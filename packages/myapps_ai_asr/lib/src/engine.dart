import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'capability.dart';
import 'errors.dart';
import 'route.dart';

/// What to load, and where.
@immutable
class AsrPrepareRequest {
  /// Purpose: Route to load on.
  /// Inputs: None. Returns: [AsrRoute]. Side effects: None. Notes: None.
  final AsrRoute route;

  /// Purpose: Installed artifact's manifest.
  /// Inputs: None. Returns: [ArtifactManifest]. Side effects: None.
  /// Notes: None.
  final ArtifactManifest manifest;

  /// Purpose: Installed artifact's folder.
  /// Inputs: None. Returns: Directory. Side effects: None. Notes: None.
  final Directory artifactDir;

  /// Purpose: Job it is for, or null for a self-test.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? jobId;

  /// Purpose: Create a prepare request.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrPrepareRequest({
    required this.route,
    required this.manifest,
    required this.artifactDir,
    this.jobId,
  });
}

/// A model loaded on a processor, ready for windows.
@immutable
class AsrSession {
  /// Purpose: Identifies the session to transcribe and release.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String sessionId;

  /// Purpose: Artifact revision loaded.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String artifactRevision;

  /// Purpose: Processor asked for.
  /// Inputs: None. Returns: [ComputeDevice]. Side effects: None. Notes: None.
  final ComputeDevice requestedDevice;

  /// Purpose: Where the runtime says the model actually went.
  /// Inputs: None. Returns: [PlacementKind]. Side effects: None.
  /// Notes: Never inferred from the route's intent.
  final PlacementKind placement;

  /// Purpose: How long loading took.
  /// Inputs: None. Returns: Duration. Side effects: None. Notes: None.
  final Duration prepareTime;

  /// Purpose: Whether a compile cache made loading faster.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool usedCompileCache;

  /// Purpose: Create a session description.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrSession({
    required this.sessionId,
    required this.artifactRevision,
    required this.requestedDevice,
    required this.placement,
    this.prepareTime = Duration.zero,
    this.usedCompileCache = false,
  });
}

/// One window to transcribe.
@immutable
class AsrRequest {
  /// Purpose: Job id, echoed on every event and used to cancel.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String jobId;

  /// Purpose: Session to run on.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String sessionId;

  /// Purpose: The window: 16 kHz mono 16-bit PCM WAV.
  /// Inputs: None. Returns: File. Side effects: None.
  /// Notes: Use [readPcmWindow] to check it.
  final File pcmWindow;

  /// Purpose: Its length in seconds.
  /// Inputs: None. Returns: double. Side effects: None. Notes: None.
  final double windowSeconds;

  /// Purpose: Language hints, most likely first; empty to detect.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> languages;

  /// Purpose: Context prompt for models that take one.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? prompt;

  /// Purpose: Keyword hints for models that take them.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> keywords;

  /// Purpose: Create a transcribe request.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrRequest({
    required this.jobId,
    required this.sessionId,
    required this.pcmWindow,
    required this.windowSeconds,
    this.languages = const [],
    this.prompt,
    this.keywords = const [],
  });
}

/// One timed word, in window-local seconds.
@immutable
class AsrWord {
  /// Purpose: Start. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double startSeconds;

  /// Purpose: End. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double endSeconds;

  /// Purpose: The word. Inputs: None. Returns: String. Side effects: None.
  /// Notes: Trimmed.
  final String text;

  /// Purpose: Create a word.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrWord({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });
}

/// One timed piece of text, in window-local seconds.
@immutable
class AsrSegment {
  /// Purpose: Start. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double startSeconds;

  /// Purpose: End. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double endSeconds;

  /// Purpose: What was said. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String text;

  /// Purpose: Word times, when the route produces them.
  /// Inputs: None. Returns: List; empty when absent. Side effects: None.
  /// Notes: None.
  final List<AsrWord> words;

  /// Purpose: Window-local speaker label, when diarization assigned one.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Labels mean nothing across windows.
  final String? speaker;

  /// Purpose: Create a segment.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    this.words = const [],
    this.speaker,
  });

  /// Purpose: Return a copy with a speaker label.
  /// Inputs: [speaker]. Returns: A new segment. Side effects: None.
  /// Notes: None.
  AsrSegment withSpeaker(String? speaker) => AsrSegment(
    startSeconds: startSeconds,
    endSeconds: endSeconds,
    text: text,
    words: words,
    speaker: speaker,
  );
}

/// What an engine event says.
enum AsrEventType {
  /// Loading or compiling.
  preparing,

  /// The window started.
  started,

  /// How far through the window it is.
  progress,

  /// A finished segment.
  segment,

  /// The window finished.
  completed,

  /// The window stopped because it was cancelled.
  cancelled,

  /// The window failed.
  error,

  /// The engine moved to another route on its own and says so.
  fallback,
}

/// One event from a running window.
///
/// A single envelope for every type keeps channel-based adapters to one
/// message shape.
@immutable
class AsrEvent {
  /// Purpose: Job it belongs to. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String jobId;

  /// Purpose: Position in the window's events, from zero.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int sequence;

  /// Purpose: What it says. Inputs: None. Returns: [AsrEventType].
  /// Side effects: None. Notes: None.
  final AsrEventType type;

  /// Purpose: 0..1, for [AsrEventType.progress].
  /// Inputs: None. Returns: double or null. Side effects: None. Notes: None.
  final double? progress;

  /// Purpose: The segment, for [AsrEventType.segment].
  /// Inputs: None. Returns: [AsrSegment] or null. Side effects: None.
  /// Notes: None.
  final AsrSegment? segment;

  /// Purpose: Whether segments carry real times, for completed.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: False when one segment merely spans the window.
  final bool hasRealTimestamps;

  /// Purpose: Where the window actually ran, for completed.
  /// Inputs: None. Returns: [PlacementKind] or null. Side effects: None.
  /// Notes: Runtime-reported only.
  final PlacementKind? placement;

  /// Purpose: Language the runtime detected or used, for completed.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Null when the route does not report one.
  final String? language;

  /// Purpose: The failure, for [AsrEventType.error].
  /// Inputs: None. Returns: [AsrException] or null. Side effects: None.
  /// Notes: None.
  final AsrException? error;

  /// Purpose: A sentence, for [AsrEventType.fallback].
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? detail;

  /// Purpose: Create an event.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrEvent({
    required this.jobId,
    required this.sequence,
    required this.type,
    this.progress,
    this.segment,
    this.hasRealTimestamps = false,
    this.placement,
    this.language,
    this.error,
    this.detail,
  });
}

/// The collected outcome of one window.
@immutable
class AsrResult {
  /// Purpose: Segments in order. Inputs: None. Returns: List.
  /// Side effects: None. Notes: None.
  final List<AsrSegment> segments;

  /// Purpose: Whether segment times are real.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool hasRealTimestamps;

  /// Purpose: Detected or used language, when reported.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? language;

  /// Purpose: Where the window actually ran.
  /// Inputs: None. Returns: [PlacementKind]. Side effects: None.
  /// Notes: [PlacementKind.unknown] when the runtime said nothing.
  final PlacementKind placement;

  /// Purpose: Create a result.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrResult({
    required this.segments,
    this.hasRealTimestamps = false,
    this.language,
    this.placement = PlacementKind.unknown,
  });

  /// Purpose: Join every segment's text.
  /// Inputs: None. Returns: Trimmed texts joined by spaces.
  /// Side effects: None. Notes: None.
  String get text => [
    for (final segment in segments)
      if (segment.text.trim().isNotEmpty) segment.text.trim(),
  ].join(' ');

  /// Purpose: Collect a window's event stream into a result.
  /// Inputs: [events] from [AsrEngine.transcribe].
  /// Returns: The result.
  /// Side effects: Listens to the stream to its end.
  /// Notes: Throws the [AsrException] of an error event, or
  /// [AsrErrorCode.cancelled] for a cancelled window.
  static Future<AsrResult> collect(Stream<AsrEvent> events) async {
    final segments = <AsrSegment>[];
    AsrEvent? completed;
    await for (final event in events) {
      switch (event.type) {
        case AsrEventType.segment when event.segment != null:
          segments.add(event.segment!);
        case AsrEventType.error:
          throw event.error ??
              const AsrException(
                AsrErrorCode.deviceUnavailable,
                'The engine failed without saying why.',
              );
        case AsrEventType.cancelled:
          throw const AsrException(AsrErrorCode.cancelled, 'Cancelled.');
        case AsrEventType.completed:
          completed = event;
        default:
          break;
      }
    }
    return AsrResult(
      segments: segments,
      hasRealTimestamps: completed?.hasRealTimestamps ?? false,
      language: completed?.language,
      placement: completed?.placement ?? PlacementKind.unknown,
    );
  }
}

/// A speech recognition engine (local adapter or online client).
abstract interface class AsrEngine {
  /// Purpose: Adapter id: `whisper_cpp`, `sherpa_onnx`, `fluidaudio`, ...
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Matches [ArtifactManifest.backendId] of the artifacts it reads.
  String get adapterId;

  /// Purpose: Describe every route this adapter could run here.
  /// Inputs: Installed [manifests] for this adapter.
  /// Returns: Routes with evidence, capabilities and availability.
  /// Side effects: May load the runtime and query drivers.
  /// Notes: Health is attached by [AsrEngineRegistry], not here.
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests);

  /// Purpose: Load a model on a processor.
  /// Inputs: [request]. Returns: The session, with reported placement.
  /// Side effects: Loads native resources.
  /// Notes: Throws [AsrException].
  Future<AsrSession> prepare(AsrPrepareRequest request);

  /// Purpose: Transcribe one window.
  /// Inputs: [request].
  /// Returns: Events ending in exactly one of completed, cancelled or error.
  /// Side effects: Runs the model.
  /// Notes: The stream closes after its last event.
  Stream<AsrEvent> transcribe(AsrRequest request);

  /// Purpose: Stop a job's running window.
  /// Inputs: [jobId].
  /// Returns: A future completing after the native call has returned.
  /// Side effects: Sets the runtime's abort flag or discards the result.
  /// Notes: Releasing before this completes would free memory in use. It
  /// also waits for the window's stream to finish, so do not await it from
  /// inside that stream's own listener.
  Future<void> cancel(String jobId);

  /// Purpose: Unload a session.
  /// Inputs: [sessionId]. Returns: None. Side effects: Frees resources.
  /// Notes: Unknown ids are ignored.
  Future<void> release(String sessionId);
}

/// Purpose: Build an event emitter for one window.
/// Inputs: [jobId].
/// Returns: A function creating events with increasing sequence numbers.
/// Side effects: None until called.
/// Notes: Shared by adapters so every window starts at sequence zero.
AsrEvent Function(
  AsrEventType type, {
  double? progress,
  AsrSegment? segment,
  bool hasRealTimestamps,
  PlacementKind? placement,
  String? language,
  AsrException? error,
  String? detail,
})
asrEventSequence(String jobId) {
  var sequence = 0;
  return (
    type, {
    progress,
    segment,
    hasRealTimestamps = false,
    placement,
    language,
    error,
    detail,
  }) => AsrEvent(
    jobId: jobId,
    sequence: sequence++,
    type: type,
    progress: progress,
    segment: segment,
    hasRealTimestamps: hasRealTimestamps,
    placement: placement,
    language: language,
    error: error,
    detail: detail,
  );
}
