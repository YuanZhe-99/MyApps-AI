import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'capability.dart';
import 'engine.dart';
import 'errors.dart';
import 'route.dart';

/// How close a self-test's text must be to the expected text, 0..1.
///
/// One minus word error rate after normalising case and punctuation. 0.8
/// tolerates a spelled number or split compound and fails a different
/// sentence or nothing — what a broken GPU kernel usually produces.
const asrSelfTestMinSimilarity = 0.8;

/// Asset key of the bundled self-test clip, as consumers load it.
const asrSmokeClipAsset = 'packages/myapps_ai_asr/assets/jfk.wav';

/// What is said in the bundled clip.
///
/// The opening of President Kennedy's 1961 inaugural address (public domain),
/// as whisper.cpp ships it.
const asrSmokeClipText =
    'And so, my fellow Americans, ask not what your country can do for you, '
    'ask what you can do for your country.';

/// Length of the bundled clip in seconds.
const asrSmokeClipSeconds = 11.0;

/// The clip a self-test transcribes.
@immutable
class AsrSmokeClip {
  /// Purpose: The clip as a 16 kHz mono 16-bit WAV file.
  /// Inputs: None. Returns: File. Side effects: None. Notes: None.
  final File wav;

  /// Purpose: What is said in it.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String expectedText;

  /// Purpose: Its length in seconds.
  /// Inputs: None. Returns: double. Side effects: None. Notes: None.
  final double seconds;

  /// Purpose: Its language.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String language;

  /// Purpose: Create a clip description.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrSmokeClip({
    required this.wav,
    required this.expectedText,
    required this.seconds,
    this.language = 'en',
  });

  /// Purpose: Describe the bundled clip at a file path.
  /// Inputs: [wav]. Returns: A clip with the bundled text and length.
  /// Side effects: None.
  /// Notes: For tools and tests that read the package file directly.
  factory AsrSmokeClip.jfk(File wav) => AsrSmokeClip(
    wav: wav,
    expectedText: asrSmokeClipText,
    seconds: asrSmokeClipSeconds,
  );
}

/// Purpose: Copy the bundled clip out of the asset bundle into [directory].
/// Inputs: [directory] (e.g. the app's temporary directory), optional
/// [bundle] and [assetKey].
/// Returns: The clip, or null when the asset is missing.
/// Side effects: Writes `myapps_asr_check_clip.wav` when absent or the wrong
/// size.
/// Notes: Engines read files, not assets. No path provider dependency: the
/// application supplies the directory.
Future<AsrSmokeClip?> loadAsrSmokeClip(
  Directory directory, {
  AssetBundle? bundle,
  String assetKey = asrSmokeClipAsset,
}) async {
  final ByteData data;
  try {
    data = await (bundle ?? rootBundle).load(assetKey);
  } catch (_) {
    return null;
  }
  final file = File('${directory.path}/myapps_asr_check_clip.wav');
  if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
    await directory.create(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return AsrSmokeClip.jfk(file);
}

/// Purpose: Reduce text to comparable words.
/// Inputs: [text]. Returns: Lower-case words, punctuation removed.
/// Side effects: None.
/// Notes: Letters and digits of any script are kept.
List<String> normalizedWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}\s']", unicode: true), ' ')
    .replaceAll("'", '')
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList();

/// Purpose: Score how close [actual] is to [expected].
/// Inputs: Texts. Returns: One minus word error rate, clamped to 0..1.
/// Side effects: None.
/// Notes: Word-level edit distance; an empty expectation matches only an
/// empty result.
double textSimilarity(String expected, String actual) {
  final a = normalizedWords(expected);
  final b = normalizedWords(actual);
  if (a.isEmpty) return b.isEmpty ? 1 : 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      current[j] = [
        substitution,
        deletion,
        insertion,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return (1 - previous[b.length] / a.length).clamp(0.0, 1.0);
}

/// What one ASR self-test run produced.
@immutable
class AsrSelfTestRun {
  /// Purpose: Joined segment text.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String text;

  /// Purpose: Transcription time only, excluding model load.
  /// Inputs: None. Returns: Duration. Side effects: None.
  /// Notes: A job loads once and transcribes many windows.
  final Duration transcribeTime;

  /// Purpose: Engine error, if the window failed.
  /// Inputs: None. Returns: [AsrException] or null. Side effects: None.
  /// Notes: None.
  final AsrException? error;

  /// Purpose: Placement the runtime reported.
  /// Inputs: None. Returns: [PlacementKind]. Side effects: None.
  /// Notes: None.
  final PlacementKind placement;

  /// Purpose: Create a run.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrSelfTestRun({
    required this.text,
    required this.transcribeTime,
    this.error,
    this.placement = PlacementKind.unknown,
  });
}

/// The ASR self-test: transcribe a known clip through one route and compare.
///
/// Run with [SelfTestRunner], which writes the crash marker around it and
/// files the record under [fingerprint]. Records carry `text`, `similarity`
/// and `realTimeFactor` exactly as MyTranscribe's route check wrote them.
class AsrSelfTestFixture extends SelfTestFixture<AsrSelfTestRun> {
  /// Purpose: Create a fixture.
  /// Inputs: [engine], [route], its installed [manifest] and [artifactDir],
  /// [clip], optional [minSimilarity] and [stopwatch] factory for tests.
  /// Returns: A new fixture. Side effects: None. Notes: None.
  AsrSelfTestFixture({
    required this.engine,
    required this.route,
    required this.manifest,
    required this.artifactDir,
    required this.clip,
    this.minSimilarity = asrSelfTestMinSimilarity,
    Stopwatch Function()? stopwatch,
  }) : _stopwatch = stopwatch ?? Stopwatch.new;

  /// Purpose: Engine under test. Inputs: None. Returns: [AsrEngine].
  /// Side effects: None. Notes: None.
  final AsrEngine engine;

  /// Purpose: Route under test. Inputs: None. Returns: [AsrRoute].
  /// Side effects: None. Notes: None.
  final AsrRoute route;

  /// Purpose: Installed manifest. Inputs: None. Returns: Manifest.
  /// Side effects: None. Notes: None.
  final ArtifactManifest manifest;

  /// Purpose: Installed folder. Inputs: None. Returns: Directory.
  /// Side effects: None. Notes: None.
  final Directory artifactDir;

  /// Purpose: Clip to transcribe. Inputs: None. Returns: [AsrSmokeClip].
  /// Side effects: None. Notes: None.
  final AsrSmokeClip clip;

  /// Purpose: Pass threshold. Inputs: None. Returns: double.
  /// Side effects: None. Notes: Defaults to [asrSelfTestMinSimilarity].
  final double minSimilarity;

  final Stopwatch Function() _stopwatch;
  String? _sessionId;

  /// Job id used for self-test windows.
  static const jobId = 'smoke-test';

  @override
  String get routeKey => route.key;

  @override
  HealthFingerprint get fingerprint => route.fingerprint;

  /// Purpose: Prepare the route and transcribe the clip.
  /// Inputs: None. Returns: [AsrSelfTestRun].
  /// Side effects: Loads and runs the model.
  /// Notes: Engine errors are returned, not thrown, so their code is kept.
  @override
  Future<AsrSelfTestRun> run() async {
    try {
      final session = await engine.prepare(
        AsrPrepareRequest(
          route: route,
          manifest: manifest,
          artifactDir: artifactDir,
        ),
      );
      _sessionId = session.sessionId;
      final watch = _stopwatch()..start();
      final text = StringBuffer();
      AsrException? error;
      var placement = PlacementKind.unknown;
      await for (final event in engine.transcribe(
        AsrRequest(
          jobId: jobId,
          sessionId: session.sessionId,
          pcmWindow: clip.wav,
          windowSeconds: clip.seconds,
          languages: [clip.language],
        ),
      )) {
        if (event.type == AsrEventType.segment && event.segment != null) {
          if (text.isNotEmpty) text.write(' ');
          text.write(event.segment!.text.trim());
        } else if (event.type == AsrEventType.error) {
          error =
              event.error ??
              const AsrException(AsrErrorCode.deviceUnavailable, 'Failed.');
        } else if (event.type == AsrEventType.completed) {
          placement = event.placement ?? PlacementKind.unknown;
        }
      }
      watch.stop();
      return AsrSelfTestRun(
        text: '$text',
        transcribeTime: watch.elapsed,
        error: error,
        placement: placement,
      );
    } on AsrException catch (error) {
      return AsrSelfTestRun(
        text: '',
        transcribeTime: Duration.zero,
        error: error,
      );
    }
  }

  /// Purpose: Judge a run.
  /// Inputs: [result], [elapsed] (ignored; transcription time is used).
  /// Returns: Pass when similarity ≥ [minSimilarity].
  /// Side effects: None.
  /// Notes: Failure reasons match MyTranscribe's wording.
  @override
  SelfTestEvaluation evaluate(AsrSelfTestRun result, Duration elapsed) {
    final error = result.error;
    if (error != null) {
      return SelfTestEvaluation(
        passed: false,
        reason: '${error.code.wire}: ${error.message}',
      );
    }
    final similarity = textSimilarity(clip.expectedText, result.text);
    final passed = similarity >= minSimilarity;
    final seconds = result.transcribeTime.inMicroseconds / 1e6;
    return SelfTestEvaluation(
      passed: passed,
      score: similarity,
      output: result.text,
      reason: passed
          ? null
          : 'The check clip came back ${(similarity * 100).round()} % right; '
                '${(minSimilarity * 100).round()} % is needed.',
      metrics: {
        if (clip.seconds > 0) asrRealTimeFactorMetric: seconds / clip.seconds,
      },
    );
  }

  /// Purpose: Release the session the run prepared.
  /// Inputs: None. Returns: None. Side effects: Unloads the model.
  /// Notes: Called by the runner whatever happened.
  @override
  Future<void> release() async {
    final id = _sessionId;
    _sessionId = null;
    if (id != null) await engine.release(id);
  }
}
