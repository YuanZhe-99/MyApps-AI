import 'dart:async';
import 'dart:io';

import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';
import 'package:path/path.dart' as p;

import 'native/whisper.dart';

/// Binary set and bindings revision, part of every fingerprint.
///
/// Same value as MyTranscribe's `_bindingsVersion`, so existing self-test
/// records stay valid; bump it with any rebuilt set or regenerated bindings.
const whisperBindingsVersion = 'prebuilt3';

/// Adapter id of whisper.cpp's Whisper runtime.
const whisperCppAdapterId = 'whisper_cpp';

/// Adapter id of whisper.cpp's Parakeet runtime.
const parakeetCppAdapterId = 'parakeet_cpp';

/// Longest window Parakeet is given, in seconds.
///
/// Parakeet encodes a whole window with attention over every frame, so memory
/// grows with the square of its length; two minutes keeps that small on a
/// phone.
const parakeetMaxWindowSeconds = 120;

/// Model families whisper.cpp's libraries run.
enum GgmlFamily {
  /// Whisper, through `whisper.h`.
  whisper,

  /// Parakeet TDT, through `parakeet.h`.
  parakeet,
}

/// What the worker learned about the native library.
class WhisperRuntimeInfo {
  /// Purpose: Whether the library loaded.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool loaded;

  /// Purpose: whisper.cpp version.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String version;

  /// Purpose: whisper.cpp system-info line.
  /// Inputs: None. Returns: String. Side effects: None. Notes: Diagnostics.
  final String systemInfo;

  /// Purpose: Devices ggml found.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<WhisperDevice> devices;

  /// Purpose: Whether the binary set has the Parakeet library.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool hasParakeet;

  /// Purpose: Create a runtime description.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: Tests construct it directly.
  const WhisperRuntimeInfo({
    required this.loaded,
    this.version = '',
    this.systemInfo = '',
    this.devices = const [],
    this.hasParakeet = false,
  });

  /// Purpose: CPU device's description, for the fingerprint.
  /// Inputs: None. Returns: String; `CPU` when none is listed.
  /// Side effects: None. Notes: None.
  String get cpuName {
    for (final device in devices) {
      if (device.type == 0) return device.description;
    }
    return 'CPU';
  }

  /// Purpose: GPUs ggml found, discrete and integrated, in ggml's order.
  /// Inputs: None. Returns: List. Side effects: None.
  /// Notes: The index is whisper.cpp's `gpu_device`.
  List<WhisperDevice> get gpus => [
    for (final device in devices)
      if (device.type == 1 || device.type == 2) device,
  ];

  /// Purpose: Name each GPU's route backend.
  /// Inputs: None. Returns: One backend per [gpus] entry.
  /// Side effects: None.
  /// Notes: A second device of one kind gets its position (`vulkan1`) so
  /// route keys stay unique.
  List<String> gpuBackends() {
    final seen = <String, int>{};
    return [
      for (final device in gpus)
        if (gpuBackendName(device.name) case final name)
          switch (seen.update(name, (n) => n + 1, ifAbsent: () => 0)) {
            0 => name,
            final n => '$name$n',
          },
    ];
  }
}

/// Purpose: Name a GPU route's backend from ggml's device name.
/// Inputs: [name], e.g. `Vulkan0`, `GPUOpenCL`, `MTL0`.
/// Returns: `vulkan`, `opencl`, `metal`, or the lower-cased alphanumerics.
/// Side effects: None.
/// Notes: Part of route keys, so it must not depend on device numbering.
String gpuBackendName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('vulkan')) return 'vulkan';
  if (lower.contains('opencl')) return 'opencl';
  if (lower.startsWith('mtl') || lower.contains('metal')) return 'metal';
  return lower.replaceAll(RegExp('[^a-z0-9]'), '');
}

/// Purpose: Evidence grade of a whisper.cpp GPU route.
/// Inputs: [backend] as [gpuBackendName] spells it; [parakeet]; the
/// [deviceClass].
/// Returns: The support-matrix grade.
/// Side effects: None.
/// Notes: Metal Whisper **B**; Parakeet on any GPU **E**; Vulkan on
/// `windows-x64` **B**, elsewhere **E**; OpenCL **E**; anything else **U**.
EvidenceLevel gpuEvidence(
  String backend, {
  required String deviceClass,
  bool parakeet = false,
}) {
  if (parakeet) {
    return backend == 'metal' || backend == 'vulkan' || backend == 'opencl'
        ? EvidenceLevel.experimental
        : EvidenceLevel.none;
  }
  return switch (backend) {
    'metal' => EvidenceLevel.community,
    'vulkan' when deviceClass == 'windows-x64' => EvidenceLevel.community,
    'vulkan' || 'opencl' => EvidenceLevel.experimental,
    _ => EvidenceLevel.none,
  };
}

/// The whisper.cpp engine for one model family.
///
/// Every native call runs on a long-lived [NativeWorker] that owns each model
/// handle. Cancelling writes a flag in native memory the running call polls,
/// then waits for the call to return before anything is released.
class WhisperCppEngine implements AsrEngine {
  /// Purpose: Create the engine.
  /// Inputs: [family]; [host] (current by default); application-owned
  /// [testedRoutes]; [threads] override.
  /// Returns: A new engine; the worker starts on first use.
  /// Side effects: None.
  /// Notes: One engine per family, each with its own worker.
  WhisperCppEngine({
    this.family = GgmlFamily.whisper,
    AsrHost? host,
    this.testedRoutes = const TestedRouteTable(),
    int? threads,
  }) : host = host ?? AsrHost.current(),
       _threadsOverride = threads;

  /// Purpose: Model family this engine runs.
  /// Inputs: None. Returns: [GgmlFamily]. Side effects: None. Notes: None.
  final GgmlFamily family;

  /// Purpose: Host description used for fingerprints and grades.
  /// Inputs: None. Returns: [AsrHost]. Side effects: None. Notes: None.
  final AsrHost host;

  /// Purpose: Application-owned verified routes.
  /// Inputs: None. Returns: [TestedRouteTable]. Side effects: None.
  /// Notes: None.
  final TestedRouteTable testedRoutes;

  final int? _threadsOverride;

  bool get _isParakeet => family == GgmlFamily.parakeet;

  @override
  String get adapterId =>
      _isParakeet ? parakeetCppAdapterId : whisperCppAdapterId;

  NativeWorker? _worker;
  WhisperRuntimeInfo? _info;
  final _sessions = <String, ({int id, PlacementKind placement})>{};
  final _running = <String, ({WhisperControl control, Future<void> done})>{};

  /// Purpose: Start the worker and learn what the library has.
  /// Inputs: None. Returns: [WhisperRuntimeInfo].
  /// Side effects: Spawns the worker once; loads the library there.
  /// Notes: A library that does not load is reported, not thrown.
  Future<WhisperRuntimeInfo> runtime() async {
    final known = _info;
    if (known != null) return known;
    final worker = _worker ??= await NativeWorker.spawn(
      _whisperWorker,
      debugName: 'whisper.cpp',
    );
    final info = await worker.call(const _Info());
    return _info = info is WhisperRuntimeInfo
        ? info
        : const WhisperRuntimeInfo(loaded: false);
  }

  @override
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests) async {
    final info = await runtime();
    final routes = <AsrRoute>[];
    final capabilities = AsrCapabilities(
      segmentTimestamps: AsrCapability.supported,
      wordTimestamps: AsrCapability.unknown,
      languageDetection: _isParakeet
          ? AsrCapability.unknown
          : AsrCapability.supported,
      prompt: _isParakeet ? AsrCapability.unsupported : AsrCapability.supported,
      keywords: AsrCapability.unsupported,
      cancelsMidWindow: true,
      reportsProgress: true,
    );
    for (final manifest in manifests) {
      if (manifest.backendId != adapterId) continue;
      final model = whisperModelFile(manifest);
      final built = info.loaded && (!_isParakeet || info.hasParakeet);
      final name = _isParakeet ? 'Parakeet' : 'whisper.cpp';
      routes.add(
        testedRoutes.apply(
          AsrRoute(
            adapterId: adapterId,
            modelId: manifest.modelId,
            artifactId: manifest.artifactId,
            device: ComputeDevice.cpu,
            backend: 'cpu',
            evidence: asrCpuEvidence(host),
            available: built && model != null,
            unavailableReason: !built
                ? '$name is not built for this device.'
                : model == null
                ? 'The package has no GGML model file.'
                : null,
            capabilities: capabilities,
            maxWindowSeconds: _isParakeet ? parakeetMaxWindowSeconds : null,
            memoryBytes: manifest.minimumRamBytes,
            memorySource: manifest.ramEstimateSource,
            fingerprint: _fingerprint(info, manifest, model),
          ),
        ),
      );
      if (!built) continue;
      final backends = info.gpuBackends();
      for (var i = 0; i < backends.length; i++) {
        final gpu = info.gpus[i];
        routes.add(
          testedRoutes.apply(
            AsrRoute(
              adapterId: adapterId,
              modelId: manifest.modelId,
              artifactId: manifest.artifactId,
              device: ComputeDevice.gpu,
              backend: backends[i],
              evidence: gpuEvidence(
                gpuBackendName(gpu.name),
                deviceClass: host.deviceClass,
                parakeet: _isParakeet,
              ),
              available: model != null,
              capabilities: capabilities,
              maxWindowSeconds: _isParakeet ? parakeetMaxWindowSeconds : null,
              memoryBytes: manifest.minimumRamBytes,
              memorySource: manifest.ramEstimateSource,
              fingerprint: _fingerprint(info, manifest, model, gpu: gpu),
            ),
          ),
        );
      }
    }
    return routes;
  }

  @override
  Future<AsrSession> prepare(AsrPrepareRequest request) async {
    final info = await runtime();
    final name = _isParakeet ? 'Parakeet' : 'whisper.cpp';
    if (!info.loaded || (_isParakeet && !info.hasParakeet)) {
      throw AsrException(
        AsrErrorCode.backendNotBuilt,
        '$name is not built for this device.',
      );
    }
    final model = whisperModelFile(request.manifest);
    if (model == null) {
      throw const AsrException(
        AsrErrorCode.modelFormatMismatch,
        'The package has no GGML model file.',
      );
    }
    final path = p.join(request.artifactDir.path, model.path);
    if (!File(path).existsSync()) {
      throw AsrException(
        AsrErrorCode.modelMissing,
        'The model file is not on this device: ${model.path}.',
      );
    }
    final need = request.manifest.minimumRamBytes;
    if (need != null) {
      final free = await _worker!.call(const _Memory());
      if (free is int && free < need) {
        throw AsrException(
          AsrErrorCode.outOfMemory,
          'This model needs about ${_gb(need)} of memory; '
          '${_gb(free)} is free on this device.',
        );
      }
    }
    final useGpu = !request.route.isCpu;
    final gpuDevice = useGpu
        ? info.gpuBackends().indexOf(request.route.backend)
        : 0;
    if (useGpu && gpuDevice < 0) {
      throw AsrException(
        AsrErrorCode.deviceUnavailable,
        'The ${request.route.backend} device is no longer there.',
      );
    }
    final encoder = Directory(
      '${path.substring(0, path.length - 4)}-encoder.mlmodelc',
    );
    final watch = Stopwatch()..start();
    final id = await _worker!.call(_Load(path, useGpu, gpuDevice, _isParakeet));
    watch.stop();
    if (id is! int) {
      throw AsrException(
        AsrErrorCode.modelCorrupt,
        'The model did not load: $id',
      );
    }
    final sessionId = '${family.name}-$id';
    // Core ML encoder beside a Metal route means the encoder runs on the
    // Neural Engine and the decoder on the GPU.
    final placement = !useGpu
        ? PlacementKind.cpu
        : !_isParakeet &&
              request.route.backend == 'metal' &&
              encoder.existsSync()
        ? PlacementKind.mixed
        : PlacementKind.gpu;
    _sessions[sessionId] = (id: id, placement: placement);
    return AsrSession(
      sessionId: sessionId,
      artifactRevision: request.manifest.revision,
      requestedDevice: request.route.device,
      placement: placement,
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
    final control = WhisperControl();
    final done = Completer<void>();
    _running[request.jobId] = (control: control, done: done.future);
    yield event(AsrEventType.started);
    try {
      final call = _worker!.call(
        _Transcribe(
          session.id,
          request.pcmWindow.path,
          request.languages.isEmpty ? null : request.languages.first,
          request.prompt,
          _threadsOverride ?? host.threads,
          control.address,
        ),
      );
      // Created once: a fresh `then` per tick would pile up closures.
      final finished = call.then((_) => true);
      var last = -1;
      while (true) {
        final over = await Future.any([
          finished,
          Future<bool>.delayed(const Duration(milliseconds: 250), () => false),
        ]);
        final progress = control.progress;
        if (progress != last) {
          last = progress;
          yield event(AsrEventType.progress, progress: progress / 100);
        }
        if (over) break;
      }
      final result = await call;
      if (result is _Cancelled || control.isCancelled) {
        yield event(AsrEventType.cancelled);
        return;
      }
      if (result is! _Transcript) {
        yield event(
          AsrEventType.error,
          error: AsrException(AsrErrorCode.deviceUnavailable, '$result'),
        );
        return;
      }
      for (final segment in result.segments) {
        yield event(
          AsrEventType.segment,
          segment: AsrSegment(
            startSeconds: segment.startSeconds,
            endSeconds: segment.endSeconds,
            text: segment.text,
          ),
        );
      }
      yield event(
        AsrEventType.completed,
        hasRealTimestamps: true,
        placement: session.placement,
        language: result.language.isEmpty ? null : result.language,
      );
    } finally {
      _running.remove(request.jobId);
      done.complete();
      control.dispose();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    final running = _running[jobId];
    if (running == null) return;
    running.control.cancel();
    await running.done;
  }

  @override
  Future<void> release(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    await _worker?.call(_Release(session.id));
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
    _info = null;
  }

  /// Purpose: Build a route's fingerprint.
  /// Inputs: [info], [manifest], its [model] file, the [gpu] or null.
  /// Returns: [HealthFingerprint].
  /// Side effects: None.
  /// Notes: Encodes byte-identically to MyTranscribe's smoke key. ggml gives
  /// no driver version; the device description stands in for it.
  HealthFingerprint _fingerprint(
    WhisperRuntimeInfo info,
    ArtifactManifest manifest,
    ArtifactFile? model, {
    WhisperDevice? gpu,
  }) => HealthFingerprint(
    runtimeVersion:
        '${_isParakeet ? 'parakeet ' : ''}whisper.cpp ${info.version} '
        '$whisperBindingsVersion',
    modelHash: model?.sha256 ?? '',
    osVersion: host.osVersion,
    driverVersion: gpu?.description ?? '',
    deviceId: gpu?.description ?? info.cpuName,
    precision: manifest.quantization,
  );
}

/// Purpose: Find the GGML model file in an artifact.
/// Inputs: [manifest]. Returns: The `.bin` entry, or null.
/// Side effects: None.
/// Notes: A Core ML encoder beside it is found by whisper.cpp by name.
ArtifactFile? whisperModelFile(ArtifactManifest manifest) {
  for (final file in manifest.files) {
    if (file.path.endsWith('.bin')) return file;
  }
  return null;
}

/// Purpose: Format bytes as decimal gigabytes.
/// Inputs: [bytes]. Returns: e.g. `3.9 GB`. Side effects: None.
/// Notes: Internal.
String _gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

// ── Worker protocol ──

class _Info {
  /// Purpose: Ask for runtime info. Inputs: None. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Info();
}

class _Memory {
  /// Purpose: Ask for free memory. Inputs: None. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Memory();
}

class _Load {
  /// Purpose: Ask to load a model. Inputs: All fields. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Load(this.path, this.useGpu, this.gpuDevice, this.parakeet);
  final String path;
  final bool useGpu;
  final int gpuDevice;
  final bool parakeet;
}

class _Transcribe {
  /// Purpose: Ask to transcribe a window. Inputs: All fields.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Transcribe(
    this.session,
    this.wavPath,
    this.language,
    this.prompt,
    this.threads,
    this.control,
  );
  final int session;
  final String wavPath;
  final String? language;
  final String? prompt;
  final int threads;
  final int control;
}

class _Release {
  /// Purpose: Ask to free a model. Inputs: [session]. Returns: A request.
  /// Side effects: None. Notes: Internal.
  const _Release(this.session);
  final int session;
}

class _Cancelled {
  /// Purpose: Answer for a cancelled window. Inputs: None.
  /// Returns: A marker. Side effects: None. Notes: Internal.
  const _Cancelled();
}

class _Transcript {
  /// Purpose: Answer for a finished window. Inputs: All fields.
  /// Returns: A value. Side effects: None. Notes: Internal.
  const _Transcript(this.segments, this.language);
  final List<WhisperSegment> segments;
  final String language;
}

/// Models owned by this worker isolate (each isolate has its own copy).
final _models = <int, SpeechModel>{};
var _nextModel = 0;

/// Purpose: Worker handler.
/// Inputs: A request object. Returns: Its answer.
/// Side effects: Loads the library and models; runs inference.
/// Notes: Internal; runs on the worker isolate only.
Future<Object?> _whisperWorker(Object? request) async {
  switch (request) {
    case _Info():
      if (WhisperLibrary.load() == null) {
        return const WhisperRuntimeInfo(loaded: false);
      }
      return WhisperRuntimeInfo(
        loaded: true,
        version: WhisperLibrary.version(),
        systemInfo: WhisperLibrary.systemInfo(),
        devices: WhisperLibrary.devices(),
        hasParakeet: WhisperLibrary.hasParakeet(),
      );
    case _Memory():
      return WhisperLibrary.availableMemory();
    case _Load(:final path, :final useGpu, :final gpuDevice, :final parakeet):
      final key = _nextModel++;
      _models[key] = parakeet
          ? ParakeetModel.load(path, useGpu: useGpu, gpuDevice: gpuDevice)
          : WhisperModel.load(path, useGpu: useGpu, gpuDevice: gpuDevice);
      return key;
    case _Transcribe():
      final model = _models[request.session];
      if (model == null) return 'No such session.';
      final window = await readPcmWindow(File(request.wavPath));
      final samples = await window.readSamples();
      try {
        final segments = model.transcribe(
          samples,
          language: request.language,
          prompt: request.prompt,
          threads: request.threads,
          control: WhisperControl.fromAddress(request.control),
        );
        final language = model is WhisperModel ? model.detectedLanguage() : '';
        return _Transcript(segments, language);
      } on WhisperCancelled {
        return const _Cancelled();
      }
    case _Release(:final session):
      _models.remove(session)?.release();
      return null;
  }
  return 'Unknown request.';
}
