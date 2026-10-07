import 'dart:async';
import 'dart:io';

import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'native/sherpa.dart';

/// Binary set and bindings revision, part of every fingerprint.
///
/// Same value as MyTranscribe's `_bindingsVersion`, so existing self-test
/// records stay valid; bump it with any rebuilt set or regenerated bindings.
const sherpaBindingsVersion = 'prebuilt1';

/// Adapter id of the sherpa-onnx runtime.
const sherpaOnnxAdapterId = 'sherpa_onnx';

/// Longest window Qwen3-ASR is given, in seconds.
///
/// sherpa-onnx's exported decoder takes 512 tokens, audio and text together;
/// 33 seconds came back whole and 55 seconds as one word when measured.
const qwenMaxWindowSeconds = 30;

/// The sherpa-onnx engine: Qwen3-ASR on the CPU.
///
/// The C API decodes a window in one call with no abort hook and no progress,
/// so a cancel takes effect when the window ends, and Qwen3-ASR gives no
/// timestamps: each window comes back as one segment spanning it, marked as
/// not really timed.
class SherpaOnnxEngine implements AsrEngine {
  /// Purpose: Create the engine.
  /// Inputs: [host] (current by default); application-owned [testedRoutes];
  /// [threads] override.
  /// Returns: A new engine; the worker starts on first use.
  /// Side effects: None.
  /// Notes: Apps keep one engine for their lifetime.
  SherpaOnnxEngine({
    AsrHost? host,
    this.testedRoutes = const TestedRouteTable(),
    int? threads,
  }) : host = host ?? AsrHost.current(),
       _threadsOverride = threads;

  /// Purpose: Host description used for fingerprints and grades.
  /// Inputs: None. Returns: [AsrHost]. Side effects: None. Notes: None.
  final AsrHost host;

  /// Purpose: Application-owned verified routes.
  /// Inputs: None. Returns: [TestedRouteTable]. Side effects: None.
  /// Notes: None.
  final TestedRouteTable testedRoutes;

  final int? _threadsOverride;

  @override
  String get adapterId => sherpaOnnxAdapterId;

  NativeWorker? _worker;
  String? _version;
  var _probed = false;
  final _sessions = <String, int>{};
  final _running = <String, Future<void>>{};
  final _cancelled = <String>{};

  /// Purpose: Start the worker and learn whether the library loads.
  /// Inputs: None.
  /// Returns: The library version, or null when this build has none or it
  /// does not match the bindings.
  /// Side effects: Spawns the worker isolate once.
  /// Notes: A library that does not load is reported, not thrown.
  Future<String?> runtime() async {
    if (_probed) return _version;
    final worker = _worker ??= await NativeWorker.spawn(
      _sherpaWorker,
      debugName: 'sherpa-onnx',
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
              device: ComputeDevice.cpu,
              backend: 'cpu',
              evidence: asrCpuEvidence(host),
              available: version != null,
              unavailableReason: version == null
                  ? 'sherpa-onnx is not built for this device.'
                  : null,
              capabilities: const AsrCapabilities(
                segmentTimestamps: AsrCapability.unsupported,
                wordTimestamps: AsrCapability.unsupported,
                languageDetection: AsrCapability.unknown,
                prompt: AsrCapability.unsupported,
                keywords: AsrCapability.supported,
              ),
              maxWindowSeconds: qwenMaxWindowSeconds,
              memoryBytes: manifest.minimumRamBytes,
              memorySource: manifest.ramEstimateSource,
              fingerprint: HealthFingerprint(
                runtimeVersion:
                    'sherpa-onnx ${version ?? ''} $sherpaBindingsVersion',
                modelHash: manifest.files.isEmpty
                    ? ''
                    : manifest.files.first.sha256,
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
        'sherpa-onnx is not built for this device.',
      );
    }
    final files = findQwenFiles(request.artifactDir);
    if (files == null) {
      throw const AsrException(
        AsrErrorCode.modelMissing,
        'The Qwen3-ASR files are not on this device.',
      );
    }
    final watch = Stopwatch()..start();
    final id = await _worker!.call(
      _Load(files, _threadsOverride ?? host.threads, const []),
    );
    watch.stop();
    if (id is! int) {
      throw AsrException(
        AsrErrorCode.modelCorrupt,
        'The model did not load: $id',
      );
    }
    final sessionId = 'qwen-$id';
    _sessions[sessionId] = id;
    return AsrSession(
      sessionId: sessionId,
      artifactRevision: request.manifest.revision,
      requestedDevice: request.route.device,
      placement: PlacementKind.cpu,
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
        _Transcribe(session, request.pcmWindow.path, request.keywords),
      );
      if (_cancelled.remove(request.jobId)) {
        yield event(AsrEventType.cancelled);
        return;
      }
      if (result is! String) {
        yield event(
          AsrEventType.error,
          error: AsrException(AsrErrorCode.deviceUnavailable, '$result'),
        );
        return;
      }
      if (result.isNotEmpty) {
        yield event(
          AsrEventType.segment,
          segment: AsrSegment(
            startSeconds: 0,
            endSeconds: request.windowSeconds,
            text: result,
          ),
        );
      }
      yield event(AsrEventType.completed, placement: PlacementKind.cpu);
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
    // The C API cannot stop a window midway: it finishes and is discarded.
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
  /// Notes: For tests and tools; apps keep one engine for their lifetime.
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

/// Purpose: Find a Qwen3-ASR package's files under its folder.
/// Inputs: The package [dir].
/// Returns: The files, or null when any is missing.
/// Side effects: Lists the folder.
/// Notes: sherpa-onnx's archive unpacks into a folder of its own name, so the
/// files are looked for at the top and one level down.
QwenAsrFiles? findQwenFiles(Directory dir) {
  if (!dir.existsSync()) return null;
  for (final candidate in [dir, ...dir.listSync().whereType<Directory>()]) {
    String at(String name) => '${candidate.path}${Platform.pathSeparator}$name';
    if (File(at('encoder.int8.onnx')).existsSync() &&
        File(at('decoder.int8.onnx')).existsSync() &&
        File(at('conv_frontend.onnx')).existsSync() &&
        Directory(at('tokenizer')).existsSync()) {
      return QwenAsrFiles(
        convFrontend: at('conv_frontend.onnx'),
        encoder: at('encoder.int8.onnx'),
        decoder: at('decoder.int8.onnx'),
        tokenizer: at('tokenizer'),
      );
    }
  }
  return null;
}

// ── Worker protocol ──

class _Info {
  /// Purpose: Ask for the library version. Inputs: None.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Info();
}

class _Load {
  /// Purpose: Ask to load a model. Inputs: All fields. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Load(this.files, this.threads, this.hotwords);
  final QwenAsrFiles files;
  final int threads;
  final List<String> hotwords;
}

class _Transcribe {
  /// Purpose: Ask to transcribe a window. Inputs: All fields.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Transcribe(this.session, this.wavPath, this.hotwords);
  final int session;
  final String wavPath;
  final List<String> hotwords;
}

class _Release {
  /// Purpose: Ask to free a model. Inputs: [session]. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Release(this.session);
  final int session;
}

class _Loaded {
  /// Purpose: One loaded model with what it was loaded with.
  /// Inputs: All fields. Returns: A value. Side effects: None.
  /// Notes: Internal; lives on the worker isolate.
  _Loaded(this.model, this.files, this.threads, this.hotwords);
  QwenAsrModel model;
  final QwenAsrFiles files;
  final int threads;
  List<String> hotwords;
}

/// Models owned by this worker isolate (each isolate has its own copy).
final _models = <int, _Loaded>{};
var _nextModel = 0;

/// Purpose: Worker handler.
/// Inputs: A request object. Returns: Its answer.
/// Side effects: Loads the library and models; runs inference.
/// Notes: Internal; runs on the worker isolate only. Qwen3-ASR takes its
/// hotwords at load, so a window with other keywords than the loaded model
/// reloads it first — once per job, since a job's windows share keywords. A
/// version mismatch answers an empty version, treated as not built.
Future<Object?> _sherpaWorker(Object? request) async {
  switch (request) {
    case _Info():
      try {
        return SherpaLibrary.load() ?? '';
      } on SherpaException {
        return '';
      }
    case _Load(:final files, :final threads, :final hotwords):
      final key = _nextModel++;
      _models[key] = _Loaded(
        QwenAsrModel.load(files, threads: threads, hotwords: hotwords),
        files,
        threads,
        hotwords,
      );
      return key;
    case _Transcribe(:final session, :final wavPath, :final hotwords):
      final loaded = _models[session];
      if (loaded == null) return const NativeWorkerFailure('No such session.');
      if (!_sameWords(loaded.hotwords, hotwords)) {
        loaded.model.release();
        loaded.model = QwenAsrModel.load(
          loaded.files,
          threads: loaded.threads,
          hotwords: hotwords,
        );
        loaded.hotwords = hotwords;
      }
      final window = await readPcmWindow(File(wavPath));
      return loaded.model.transcribe(await window.readSamples());
    case _Release(:final session):
      _models.remove(session)?.model.release();
      return null;
  }
  return const NativeWorkerFailure('Unknown request.');
}

/// Purpose: Compare two keyword lists.
/// Inputs: [a] and [b].
/// Returns: Whether they hold the same words in the same order.
/// Side effects: None. Notes: Internal.
bool _sameWords(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
