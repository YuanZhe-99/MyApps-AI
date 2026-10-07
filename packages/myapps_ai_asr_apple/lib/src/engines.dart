import 'dart:async';
import 'dart:io';

import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'native/apple.dart';

/// Adapter id of FluidAudio's Parakeet on the Neural Engine.
const fluidAudioAdapterId = 'fluidaudio';

/// Adapter id of the operating system's on-device recogniser.
const systemRecognizerAdapterId = 'system';

/// Longest window the system recogniser is given, in seconds.
///
/// Apple documents no limit for on-device recognition; a minute keeps each
/// call short.
const systemRecognizerMaxWindowSeconds = 60;

/// The artifact the system recogniser's route stands for: nothing to
/// download.
///
/// Never installed; the ids match MyTranscribe's so stored route keys keep
/// matching. Hand it to [AsrPrepareRequest] where another route would get
/// its installed manifest.
const systemRecognizerManifest = ArtifactManifest(
  artifactId: 'system-recognizer',
  modelId: 'system',
  backendId: systemRecognizerAdapterId,
  format: ArtifactFormat.unknown,
  revision: 'os',
  files: [],
  licenseId: 'OS',
);

/// Purpose: Turn a bridge result into segments.
/// Inputs: The [result]'s text and timed tokens, the window's [seconds].
/// Returns: Sentences cut from the token times, or one segment spanning the
/// window when the bridge gave no times.
/// Side effects: None.
/// Notes: FluidAudio's tokens are Parakeet SentencePiece pieces, so the same
/// grouping as whisper.cpp's Parakeet applies.
List<AsrSegment> appleSegments(
  ({String text, List<AppleToken> tokens}) result,
  double seconds,
) => segmentsFromTimedText(result.text, [
  for (final token in result.tokens)
    TimedToken(token.piece, token.start, token.end),
], seconds);

/// FluidAudio's Parakeet on the Apple Neural Engine.
///
/// The bridge exists on macOS and iOS only; register this engine there. Core
/// ML does not say where each operation ran, so placement is `mixed`, never
/// "all on the Neural Engine". The bridge has no abort, so a cancel waits for
/// the window to finish and discards it.
class FluidAudioEngine implements AsrEngine {
  /// Purpose: Create the engine.
  /// Inputs: [host] (current by default); application-owned [testedRoutes].
  /// Returns: A new engine; the worker starts on first use.
  /// Side effects: None.
  /// Notes: Apps keep one engine for their lifetime.
  FluidAudioEngine({
    AsrHost? host,
    this.testedRoutes = const TestedRouteTable(),
  }) : host = host ?? AsrHost.current();

  /// Purpose: Host description used for fingerprints.
  /// Inputs: None. Returns: [AsrHost]. Side effects: None. Notes: None.
  final AsrHost host;

  /// Purpose: Application-owned verified routes.
  /// Inputs: None. Returns: [TestedRouteTable]. Side effects: None.
  /// Notes: None.
  final TestedRouteTable testedRoutes;

  @override
  String get adapterId => fluidAudioAdapterId;

  NativeWorker? _worker;
  String? _version;
  var _probed = false;
  final _sessions = <String, int>{};
  final _running = <String, Future<void>>{};
  final _cancelled = <String>{};

  /// Purpose: Start the worker and learn whether the bridge loads.
  /// Inputs: None.
  /// Returns: The bridge version, or null when this build has none.
  /// Side effects: Spawns the worker isolate once.
  /// Notes: A bridge that does not load is reported, not thrown.
  Future<String?> runtime() async {
    if (_probed) return _version;
    final worker = _worker ??= await NativeWorker.spawn(
      _fluidWorker,
      debugName: 'fluidaudio',
    );
    final answer = await worker.call(const _Info());
    _probed = true;
    return _version = answer is String && answer.isNotEmpty ? answer : null;
  }

  @override
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests) async {
    final version = await runtime();
    return [
      for (final manifest in manifests)
        if (manifest.backendId == adapterId)
          testedRoutes.apply(
            AsrRoute(
              adapterId: adapterId,
              modelId: manifest.modelId,
              artifactId: manifest.artifactId,
              device: ComputeDevice.npu,
              backend: 'ane',
              evidence: EvidenceLevel.community,
              available: version != null,
              unavailableReason: version == null
                  ? 'The Neural Engine bridge is not built for this device.'
                  : null,
              capabilities: const AsrCapabilities(
                segmentTimestamps: AsrCapability.supported,
                wordTimestamps: AsrCapability.unknown,
                prompt: AsrCapability.unsupported,
                keywords: AsrCapability.unsupported,
              ),
              memoryBytes: manifest.minimumRamBytes,
              memorySource: manifest.ramEstimateSource,
              fingerprint: HealthFingerprint(
                runtimeVersion: version ?? '',
                modelHash: manifest.files
                    .map((f) => f.sha256.substring(0, 8))
                    .join(),
                osVersion: host.osVersion,
                driverVersion: '',
                deviceId: host.deviceClass,
                precision: manifest.quantization,
              ),
            ),
          ),
    ];
  }

  @override
  Future<AsrSession> prepare(AsrPrepareRequest request) async {
    if (await runtime() == null) {
      throw const AsrException(
        AsrErrorCode.backendNotBuilt,
        'The Neural Engine bridge is not built for this device.',
      );
    }
    final folder = request.artifactDir;
    if (!Directory('${folder.path}/Encoder.mlmodelc').existsSync()) {
      throw const AsrException(
        AsrErrorCode.modelMissing,
        'The Core ML files are not on this device.',
      );
    }
    final watch = Stopwatch()..start();
    final id = await _worker!.call(_Load(folder.path));
    watch.stop();
    if (id is! int) {
      throw AsrException(
        AsrErrorCode.modelCorrupt,
        'The model did not load: $id',
      );
    }
    final sessionId = 'ane-$id';
    _sessions[sessionId] = id;
    return AsrSession(
      sessionId: sessionId,
      artifactRevision: request.manifest.revision,
      requestedDevice: request.route.device,
      placement: PlacementKind.mixed,
      prepareTime: watch.elapsed,
    );
  }

  @override
  Stream<AsrEvent> transcribe(AsrRequest request) async* {
    final session = _sessions[request.sessionId];
    final event = asrEventSequence(request.jobId);
    if (session == null) {
      yield event(
        AsrEventType.error,
        error: const AsrException(
          AsrErrorCode.modelMissing,
          'No model is loaded for this session.',
        ),
      );
      return;
    }
    final done = Completer<void>();
    _running[request.jobId] = done.future;
    yield event(AsrEventType.started);
    try {
      final result = await _worker!.call(
        _Transcribe(session, request.pcmWindow.path),
      );
      if (_cancelled.remove(request.jobId)) {
        yield event(AsrEventType.cancelled);
        return;
      }
      if (result is! _Segments) {
        yield event(
          AsrEventType.error,
          error: AsrException(AsrErrorCode.deviceUnavailable, '$result'),
        );
        return;
      }
      for (final segment in result.segments) {
        yield event(AsrEventType.segment, segment: segment);
      }
      yield event(
        AsrEventType.completed,
        placement: PlacementKind.mixed,
        hasRealTimestamps: result.timed,
      );
    } finally {
      _running.remove(request.jobId);
      _cancelled.remove(request.jobId);
      done.complete();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    final running = _running[jobId];
    if (running == null) return;
    _cancelled.add(jobId);
    await running;
  }

  @override
  Future<void> release(String sessionId) async {
    final id = _sessions.remove(sessionId);
    if (id == null) return;
    await _worker?.call(_Release(id));
  }

  /// Purpose: Stop the worker.
  /// Inputs: None. Returns: None.
  /// Side effects: Frees every loaded model; kills the isolate.
  /// Notes: For tests and tools.
  Future<void> dispose() async {
    for (final id in _sessions.keys.toList()) {
      await release(id);
    }
    _worker?.close();
    _worker = null;
    _probed = false;
    _version = null;
  }
}

/// The operating system's on-device recogniser (`SFSpeechRecognizer` with
/// on-device recognition required, so audio never leaves the device).
///
/// Its one route serves no particular model; routers offer it only as a
/// fallback the application's policy names. Permission is asked the first
/// time it transcribes, which is only after the user chose it.
class SystemRecognizerEngine implements AsrEngine {
  /// Purpose: Create the engine.
  /// Inputs: [host] (current by default).
  /// Returns: A new engine; the worker starts on first use.
  /// Side effects: None.
  /// Notes: Register on iOS and macOS only.
  SystemRecognizerEngine({AsrHost? host}) : host = host ?? AsrHost.current();

  /// Purpose: Host description used for fingerprints.
  /// Inputs: None. Returns: [AsrHost]. Side effects: None. Notes: None.
  final AsrHost host;

  @override
  String get adapterId => systemRecognizerAdapterId;

  NativeWorker? _worker;
  bool? _available;
  final _running = <String, Future<void>>{};
  final _cancelled = <String>{};

  /// Purpose: Learn whether the device language has an on-device recogniser.
  /// Inputs: None. Returns: bool.
  /// Side effects: Spawns the worker isolate once.
  /// Notes: Asks for no permission.
  Future<bool> runtime() async {
    final known = _available;
    if (known != null) return known;
    final worker = _worker ??= await NativeWorker.spawn(
      _speechWorker,
      debugName: 'system-recogniser',
    );
    return _available = await worker.call(const _Info()) == true;
  }

  @override
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests) async {
    final available = await runtime();
    return [
      AsrRoute(
        adapterId: adapterId,
        modelId: systemRecognizerManifest.modelId,
        artifactId: systemRecognizerManifest.artifactId,
        device: ComputeDevice.cpu,
        backend: 'speech',
        evidence: EvidenceLevel.official,
        available: available,
        unavailableReason: available
            ? null
            : 'This device has no on-device recogniser for its language.',
        capabilities: const AsrCapabilities(
          segmentTimestamps: AsrCapability.supported,
          wordTimestamps: AsrCapability.supported,
          prompt: AsrCapability.unsupported,
          keywords: AsrCapability.unsupported,
        ),
        maxWindowSeconds: systemRecognizerMaxWindowSeconds,
        modelIndependent: true,
        fingerprint: HealthFingerprint(
          runtimeVersion: 'SFSpeechRecognizer',
          modelHash: '',
          osVersion: host.osVersion,
          driverVersion: '',
          deviceId: 'os',
          precision: '',
        ),
      ),
    ];
  }

  @override
  Future<AsrSession> prepare(AsrPrepareRequest request) async {
    if (!await runtime()) {
      throw const AsrException(
        AsrErrorCode.backendNotBuilt,
        'This device has no on-device recogniser for its language.',
      );
    }
    return AsrSession(
      sessionId: 'system',
      artifactRevision: systemRecognizerManifest.revision,
      requestedDevice: request.route.device,
      placement: PlacementKind.unknown,
      prepareTime: Duration.zero,
    );
  }

  @override
  Stream<AsrEvent> transcribe(AsrRequest request) async* {
    final event = asrEventSequence(request.jobId);
    if (_worker == null && !await runtime()) {
      yield event(
        AsrEventType.error,
        error: const AsrException(
          AsrErrorCode.backendNotBuilt,
          'This device has no on-device recogniser for its language.',
        ),
      );
      return;
    }
    final done = Completer<void>();
    _running[request.jobId] = done.future;
    yield event(AsrEventType.started);
    try {
      final result = await _worker!.call(
        _Speech(
          request.pcmWindow.path,
          request.languages.isEmpty ? null : request.languages.first,
        ),
      );
      if (_cancelled.remove(request.jobId)) {
        yield event(AsrEventType.cancelled);
        return;
      }
      if (result is! _Segments) {
        yield event(
          AsrEventType.error,
          error: AsrException(AsrErrorCode.deviceUnavailable, '$result'),
        );
        return;
      }
      for (final segment in result.segments) {
        yield event(AsrEventType.segment, segment: segment);
      }
      // The recogniser says nothing about where it ran.
      yield event(
        AsrEventType.completed,
        placement: PlacementKind.unknown,
        hasRealTimestamps: result.timed,
      );
    } finally {
      _running.remove(request.jobId);
      _cancelled.remove(request.jobId);
      done.complete();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    final running = _running[jobId];
    if (running == null) return;
    _cancelled.add(jobId);
    await running;
  }

  @override
  Future<void> release(String sessionId) async {}

  /// Purpose: Stop the worker.
  /// Inputs: None. Returns: None.
  /// Side effects: Kills the isolate.
  /// Notes: For tests and tools.
  void dispose() {
    _worker?.close();
    _worker = null;
    _available = null;
  }
}

// ── Worker protocol ──

class _Info {
  /// Purpose: Ask whether the bridge works. Inputs: None.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Info();
}

class _Load {
  /// Purpose: Ask to load a Core ML folder. Inputs: [folder].
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Load(this.folder);
  final String folder;
}

class _Transcribe {
  /// Purpose: Ask to transcribe a window. Inputs: All fields.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Transcribe(this.session, this.wavPath);
  final int session;
  final String wavPath;
}

class _Speech {
  /// Purpose: Ask the system recogniser for a window. Inputs: All fields.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Speech(this.wavPath, this.language);
  final String wavPath;
  final String? language;
}

class _Release {
  /// Purpose: Ask to free a model. Inputs: [session]. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Release(this.session);
  final int session;
}

class _Segments {
  /// Purpose: Answer for a finished window. Inputs: All fields.
  /// Returns: A value. Side effects: None.
  /// Notes: [timed] is false when the bridge gave no token times.
  const _Segments(this.segments, this.timed);
  final List<AsrSegment> segments;
  final bool timed;
}

/// Models owned by the FluidAudio worker isolate.
final _models = <int, AppleParakeetModel>{};
var _nextModel = 0;

/// Purpose: FluidAudio worker handler.
/// Inputs: A request object. Returns: Its answer.
/// Side effects: Loads the bridge and models; runs inference.
/// Notes: Internal; runs on the worker isolate only.
Future<Object?> _fluidWorker(Object? request) async {
  switch (request) {
    case _Info():
      return AppleAsrLibrary.version() ?? '';
    case _Load(:final folder):
      final key = _nextModel++;
      _models[key] = AppleParakeetModel.load(folder);
      return key;
    case _Transcribe(:final session, :final wavPath):
      final model = _models[session];
      if (model == null) return const NativeWorkerFailure('No such session.');
      final window = await readPcmWindow(File(wavPath));
      final samples = await window.readSamples();
      final result = model.transcribe(samples);
      return _Segments(
        appleSegments(result, samples.length / 16000),
        result.tokens.isNotEmpty,
      );
    case _Release(:final session):
      _models.remove(session)?.release();
      return null;
  }
  return const NativeWorkerFailure('Unknown request.');
}

/// Purpose: System recogniser worker handler.
/// Inputs: A request object. Returns: Its answer.
/// Side effects: Calls the bridge; may prompt for permission.
/// Notes: Internal; runs on the worker isolate only.
Future<Object?> _speechWorker(Object? request) async {
  switch (request) {
    case _Info():
      return AppleSpeech.available();
    case _Speech(:final wavPath, :final language):
      final window = await readPcmWindow(File(wavPath));
      final samples = await window.readSamples();
      final result = AppleSpeech.transcribe(samples, language: language);
      return _Segments(
        appleSegments(result, samples.length / 16000),
        result.tokens.isNotEmpty,
      );
  }
  return const NativeWorkerFailure('Unknown request.');
}
