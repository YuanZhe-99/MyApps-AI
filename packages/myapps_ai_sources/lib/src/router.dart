/// Purpose: The application's AI backend: one global source choice routed
/// to system AI, a local llama.cpp model or an online model.
/// Inputs: See [AiSourceRouter.new].
/// Returns: [AiSourceRouter].
/// Side effects: Reads and writes device-local configuration; loads models
/// only when asked to generate or prewarm.
/// Notes: Replaces the `AiSourceBackend` each application kept. Rules kept
/// from those: nothing downloads implicitly; automatic never chooses an
/// online model; switching cancels, then unloads; a local model is leased
/// while selected; proofreading always uses system AI.
library;

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';
import 'package:myapps_ai_llm_llama/myapps_ai_llm_llama.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'store.dart';

/// Version of the source routing, shown in technical details.
const myappsAiSourcesVersion = '0.6.0';

/// Routes AI requests to the selected source.
class AiSourceRouter extends CapabilityGenAiBackend
    implements
        ModelManagementController,
        AiSourceController,
        CustomModelController {
  /// Purpose: Bind application storage and backends.
  /// Inputs: [store] for device-local choices; [system], the platform
  /// backend; [models], where model files live (excluded from sync and
  /// backup by the application); [online] when the application offers online
  /// models; [catalog], the local models offered (the llama.cpp catalog by
  /// default); [appInfo], rows such as the application version for technical
  /// details; [manager] to replace the artifact manager in tests.
  /// Returns: Router. Side effects: None until [initialize].
  /// Notes: None.
  AiSourceRouter({
    required this.store,
    required this.system,
    required ModelStorageRoot models,
    this.online,
    List<ArtifactManifest>? catalog,
    this.appInfo = const {},
    ArtifactManager? manager,
    http.Client Function()? client,
  }) : builtIn = catalog ?? llamaCatalogFor(),
       _client = client ?? http.Client.new,
       manager =
           manager ??
           ArtifactManager(
             storage: models,
             downloader: ArtifactDownloader(clientFactory: http.Client.new),
           );

  /// Device-local storage of the choices.
  final AiSourceStore store;

  /// The platform's system AI.
  final CapabilityGenAiBackend system;

  /// Online models, or null when the application has none.
  final AiOnlineSources? online;

  /// Recommended local models.
  final List<ArtifactManifest> builtIn;

  /// Purpose: Every local model offered: recommended, then custom.
  /// Inputs: None. Returns: Manifests. Side effects: None. Notes: None.
  List<ArtifactManifest> get catalog => [...builtIn, ..._custom];

  final http.Client Function() _client;
  List<ArtifactManifest> _custom = const [];
  Map<String, String> _aliases = const {};

  /// Model files.
  final ArtifactManager manager;

  /// Application rows for technical details.
  final Map<String, String> appInfo;

  /// Purpose: Notifies on every change the settings show.
  /// Inputs: None. Returns: Notifier. Side effects: None.
  /// Notes: Kept for applications that listened to `AiSourceBackend`.
  final notifier = ValueNotifier<int>(0);

  final _changes = StreamController<ModelManagementState>.broadcast();
  AiSourceSelection _selection = const AiSourceSelection();
  LlmComputePreference _compute = LlmComputePreference.cpuOnly;
  late final _gpuFailures = _StoredGpuFailures(store);
  LlamaCppBackend? _local;
  LlmGenAiBackend? _localGenAi;
  String? _localId;
  ArtifactLease? _lease;
  Future<void>? _initializing;
  Future<GenAiBackend>? _resolving;

  @override
  Listenable get sourceChanges => notifier;

  @override
  AiSourceSelection get selection => _selection;

  /// Purpose: Read device-local choices and installed metadata.
  /// Inputs: None. Returns: Completion. Side effects: Local reads.
  /// Notes: Probes no backend and loads no model; retried after a failure.
  Future<void> initialize() => _initializing ??= _initialize().catchError((
    Object error,
    StackTrace stack,
  ) {
    _initializing = null;
    Error.throwWithStackTrace(error, stack);
  });

  /// Purpose: Initialize once. Inputs: None. Returns: Completion.
  /// Side effects: Reads configuration and manifests. Notes: Internal.
  Future<void> _initialize() async {
    final config = await store.read();
    _selection = AiSourceSelection.fromJson(config[aiSourceSelectionKey]);
    _compute = LlmComputePreference.parse(config[aiComputePreferenceKey]);
    _custom = [
      if (config[aiCustomModelsKey] case final List list)
        for (final m in list)
          if (m is Map) ?_tryManifest(Map<String, dynamic>.from(m)),
    ];
    _aliases = {
      if (config[aiModelAliasesKey] case final Map map)
        for (final e in map.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    final online = this.online;
    if (online != null) {
      await online.initialize();
      online.changes.addListener(_publish);
    }
    for (final m in catalog) {
      await manager.refresh(m.artifactId);
      manager.watch(m.artifactId).listen((_) => _publish());
    }
    _publish();
  }

  @override
  Future<void> select(String id) async {
    await initialize();
    if (id == _selection.global) return;
    await _resolving;
    await cancel();
    await _release();
    final next = _selection.withGlobal(id);
    await store.write({aiSourceSelectionKey: next.toJson()});
    _selection = next;
    _publish();
  }

  @override
  bool get gpuAllowed => _compute == LlmComputePreference.auto;

  @override
  Future<void> setGpuAllowed(bool allowed) async {
    await initialize();
    final next = allowed
        ? LlmComputePreference.auto
        : LlmComputePreference.cpuOnly;
    if (next == _compute) return;
    await _resolving;
    await cancel();
    await _release();
    await store.write({aiComputePreferenceKey: next.name});
    _compute = next;
    _publish();
  }

  @override
  Future<bool> gpuSelectable() async {
    if (!llamaGpuVerifiedPlatforms.contains(Platform.operatingSystem)) {
      return false;
    }
    final rows = await llamaLibraryDiagnostics();
    return rows.any((r) => r.key == 'gpuBuilt' && r.value == 'true');
  }

  @override
  List<AiSourceOption> get sourceOptions => [
    const AiSourceOption(id: 'auto', kind: AiSourceKind.auto),
    AiSourceOption(
      id: 'system',
      kind: AiSourceKind.system,
      readiness: platformMayHaveOnDeviceModel
          ? AiSourceReadiness.ready
          : AiSourceReadiness.unavailable,
    ),
    for (final m in catalog)
      AiSourceOption(
        id: m.modelId,
        kind: AiSourceKind.local,
        readiness:
            manager.statusOf(m.artifactId).state == ArtifactState.installed
            ? AiSourceReadiness.ready
            : AiSourceReadiness.needsDownload,
      ),
    ...?online?.sourceOptions,
  ];

  @override
  String? sourceName(String id) {
    for (final m in catalog) {
      if (m.modelId == id) return artifactDisplayName(m, alias: _aliases[id]);
    }
    return online?.sourceName(id);
  }

  @override
  String? sourceDetail(String id) => online?.sourceDetail(id);

  /// Purpose: Name a local model. Inputs: [modelId]; [alias], empty to
  /// clear. Returns: Completion. Side effects: Writes device-local storage.
  /// Notes: The alias wins over every generated name.
  Future<void> setModelAlias(String modelId, String alias) async {
    await initialize();
    final next = {..._aliases};
    if (alias.trim().isEmpty) {
      next.remove(modelId);
    } else {
      next[modelId] = alias.trim();
    }
    await store.write({aiModelAliasesKey: next});
    _aliases = next;
    _publish();
  }

  /// Purpose: Parse a stored manifest. Inputs: [json]. Returns: Manifest or
  /// null when unreadable. Side effects: None. Notes: Internal.
  static ArtifactManifest? _tryManifest(Map<String, dynamic> json) {
    try {
      return ArtifactManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  bool isCustom(String modelId) => _custom.any((m) => m.modelId == modelId);

  @override
  Future<HuggingFaceRepoListing> listRepository(String input) async {
    final repo = parseHuggingFaceRepo(input);
    if (repo == null) {
      throw const ArtifactListingException('invalidRepository');
    }
    final client = _client();
    try {
      return await HuggingFaceModelSource(client).list(repo);
    } finally {
      client.close();
    }
  }

  @override
  Future<CustomModelProbe> probe(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
  ) async {
    final org = listing.repo.split('/').first;
    final client = _client();
    GgufHeader? header;
    try {
      header = readGgufHeader(
        await HuggingFaceModelSource(client).head(listing, file),
      );
    } catch (_) {
      header = null;
    } finally {
      client.close();
    }
    final base = file.path
        .split('/')
        .last
        .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
    final quant = file.quantization;
    // The file name is usually the published model name; a header's
    // `general.name` can be a training run's ("Smollm2 135M 8k Lc100K
    // Mix1 Ep2"), so it names only generically named files.
    final generic = RegExp(
      r'^(ggml-)?model([-_.]|$)',
      caseSensitive: false,
    ).hasMatch(base);
    final idForName = '$org/${generic ? (header?.name ?? base) : base}'
        .replaceAll(RegExp('[-_.]?$quant\$', caseSensitive: false), '');
    final named = friendlyModelName(idForName);
    return CustomModelProbe(
      displayName: quant.isEmpty ? named : '$named (${quant.toUpperCase()})',
      architecture: header?.architecture,
      name: header?.name,
      supported: header?.architectureSupported,
      contextLength: header?.contextLength,
    );
  }

  @override
  Future<String> addCustomModel(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
    CustomModelProbe probe,
  ) async {
    await initialize();
    final colon = probe.displayName.indexOf(': ');
    final m = listing.manifestFor(
      file,
      backendId: llamaCppBackendId,
      vendor: colon > 0 ? probe.displayName.substring(0, colon) : null,
      displayName:
          (colon > 0
                  ? probe.displayName.substring(colon + 2)
                  : probe.displayName)
              .replaceAll(RegExp(r' \([^)]*\)$'), ''),
    );
    if (!isCustom(m.modelId)) {
      _custom = [..._custom, m];
      await store.write({
        aiCustomModelsKey: [for (final c in _custom) c.toJson()],
      });
      await manager.refresh(m.artifactId);
      manager.watch(m.artifactId).listen((_) => _publish());
    }
    _publish();
    unawaited(perform(m.modelId, ModelAction.download).catchError((_) {}));
    return m.modelId;
  }

  @override
  Future<void> removeCustomModel(String modelId) async {
    await initialize();
    final m = _custom.where((m) => m.modelId == modelId).firstOrNull;
    if (m == null) return;
    if (_localId == modelId) {
      await cancel();
      await _release();
    }
    manager.cancel(m.artifactId);
    if (manager.statusOf(m.artifactId).state == ArtifactState.installed) {
      await manager.remove(m.artifactId);
    }
    _custom = [..._custom.where((c) => c.modelId != modelId)];
    await store.write({
      aiCustomModelsKey: [for (final c in _custom) c.toJson()],
    });
    if (_selection.global == modelId) await select('auto');
    _publish();
  }

  /// Purpose: Notify listeners. Inputs: None. Returns: None.
  /// Side effects: Bumps [notifier], emits [changes]. Notes: Internal.
  void _publish() {
    notifier.value++;
    _changes.add(state);
  }

  @override
  ModelManagementState get state => ModelManagementState(
    entries: [
      for (final m in catalog)
        ModelCatalogEntry.forArtifact(
          manifest: m,
          status: manager.statusOf(m.artifactId),
          platform: manager.platform,
          capability: 'llm',
          leased: manager.isLeased(m.artifactId),
        ),
    ],
  );

  @override
  Stream<ModelManagementState> get changes => _changes.stream;

  @override
  Future<void> perform(String modelId, ModelAction action) async {
    await initialize();
    final m = catalog.firstWhere((m) => m.modelId == modelId);
    if (!state.entryFor(modelId)!.can(action)) {
      throw StateError('actionUnavailable');
    }
    switch (action) {
      case ModelAction.download:
        await manager.install(m);
      case ModelAction.cancel:
        manager.cancel(m.artifactId);
      case ModelAction.verify:
        await manager.verify(m.artifactId);
      case ModelAction.remove:
        await manager.remove(m.artifactId);
      case ModelAction.pauseResume:
        throw StateError('actionUnavailable');
    }
    _publish();
  }

  /// Purpose: The backend for the current selection.
  /// Inputs: None. Returns: Backend. Side effects: May lease a model.
  /// Notes: Concurrent callers share one resolution.
  Future<GenAiBackend> _resolve() =>
      _resolving ??= _resolveSelected().whenComplete(() => _resolving = null);

  /// Purpose: Resolve the selection without concurrent model allocations.
  /// Inputs: None. Returns: Backend. Side effects: Acquires a lease.
  /// Notes: Throws [GenAiException] (`unavailable`) with a detail naming
  /// why: `unknownSource`, `modelNotInstalled`, or the online reason.
  Future<GenAiBackend> _resolveSelected() async {
    await initialize();
    final id = _selection.global;
    if (id == 'auto' || id == 'system') return system;
    final online = this.online;
    if (online != null && online.owns(id)) return online.resolve(id);
    final m = catalog.where((m) => m.modelId == id).firstOrNull;
    if (m == null) {
      throw const GenAiException(GenAiFailure.unavailable, 'unknownSource');
    }
    final status = await manager.refresh(m.artifactId);
    if (status.state != ArtifactState.installed) {
      throw const GenAiException(GenAiFailure.unavailable, 'modelNotInstalled');
    }
    if (_localId != id) {
      await _release();
      _lease = manager.lease(m.artifactId);
      final local = _local = LlamaCppBackend(
        modelPath: llamaModelPath(m, await manager.artifactDir(m.artifactId))!,
        compute: _compute,
        gpuFailures: _gpuFailures,
      );
      _localGenAi = LlmGenAiBackend(local, baseModelName: id);
      _localId = id;
      _publish();
    }
    return _localGenAi!;
  }

  /// Purpose: Release the local model and online clients.
  /// Inputs: None. Returns: Completion.
  /// Side effects: Unloads native memory, releases the lease.
  /// Notes: Safe when idle.
  Future<void> _release() async {
    await online?.release();
    await _local?.dispose();
    _local = null;
    _localGenAi = null;
    _localId = null;
    _lease?.release();
    _lease = null;
  }

  /// Purpose: Read readiness of the selection.
  /// Inputs: probe preferences. Returns: Report.
  /// Side effects: Status queries. Notes: For a local or online source,
  /// `variant` and `baseModelName` hold the source id, which applications
  /// store as the identity of what they generated; the backend's own detail
  /// is kept, and a resolution failure says why in `detail`. The backend's
  /// own variant is in [diagnostics].
  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) async {
    try {
      final report = await (await _resolve()).statusReport(
        force: force,
        preferFast: preferFast,
      );
      final id = _selection.global;
      if (id == 'auto' || id == 'system') return report;
      return GenAiStatusReport(
        report.status,
        code: report.code,
        detail: report.detail,
        variant: id,
        served: report.served,
        refused: report.refused,
        baseModelName: id,
        tokenLimit: report.tokenLimit,
      );
    } on GenAiException catch (e) {
      return GenAiStatusReport(
        GenAiStatus.unavailable,
        detail: e.message ?? e.failure.name,
        variant: _selection.global,
        baseModelName: _selection.global,
      );
    }
  }

  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async {
    try {
      return await (await _resolve()).coreInfo(localeTag: localeTag);
    } on GenAiException {
      return null;
    }
  }

  @override
  Future<bool> download({void Function(int, int)? onProgress}) async =>
      (await _resolve()).download(onProgress: onProgress);

  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async => (await _resolve()).generate(
    instructions: instructions,
    prompt: prompt,
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    topK: topK,
  );

  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async => (await _resolve()).choose(
    instructions: instructions,
    prompt: prompt,
    options: options,
    maxItems: maxItems,
  );

  @override
  Future<void> prewarm() async {
    try {
      await (await _resolve()).prewarm();
    } catch (_) {
      // Advisory: the next request reports the failure.
    }
  }

  @override
  Future<void> cancel() async {
    await system.cancel();
    await _local?.cancel();
    await online?.cancel();
  }

  @override
  Future<GenAiStatusReport> capabilityReport(
    GenAiFeature feature, {
    bool force = false,
    bool preferFast = false,
  }) => feature == GenAiFeature.prompt
      ? statusReport(force: force, preferFast: preferFast)
      : system.capabilityReport(feature, force: force, preferFast: preferFast);

  @override
  Future<bool> downloadCapability(
    GenAiFeature feature, {
    void Function(int, int)? onProgress,
  }) => feature == GenAiFeature.prompt
      ? download(onProgress: onProgress)
      : system.downloadCapability(feature, onProgress: onProgress);

  @override
  Future<List<String>> proofread(String text) => system.proofread(text);

  @override
  Future<AiDiagnosticsReport> diagnostics({String? localeTag}) async {
    await initialize();
    final selected = await statusReport();
    final systemReport = await _safe(() => system.statusReport());
    final info = await _safe(() => system.coreInfo(localeTag: localeTag));
    final proofread = await _safe(
      () => system.capabilityReport(GenAiFeature.proofread),
    );
    final library = await llamaLibraryDiagnostics();
    return AiDiagnosticsReport([
      AiDiagnosticSection('app', 'App', [
        for (final e in appInfo.entries) AiDiagnosticRow(e.key, e.value),
        AiDiagnosticRow('myappsAiSources', myappsAiSourcesVersion),
        AiDiagnosticRow(
          'os',
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ),
        AiDiagnosticRow('abi', Abi.current()),
        AiDiagnosticRow('processors', Platform.numberOfProcessors),
      ]),
      AiDiagnosticSection('selection', 'Selection', [
        AiDiagnosticRow('global', _selection.global),
        for (final e in _selection.overrides.entries)
          AiDiagnosticRow('override.${e.key}', e.value),
        ..._statusRows(selected),
        AiDiagnosticRow('compute', _compute.name),
      ]),
      AiDiagnosticSection('systemAi', 'System AI', [
        if (systemReport case final r?) ..._statusRows(r),
        if (info case final i?) ...[
          AiDiagnosticRow('platform', i.platform),
          AiDiagnosticRow('installed', i.installed),
          if (i.versionName != null) AiDiagnosticRow('aicore', i.versionName),
          if (i.sdk != null) AiDiagnosticRow('sdk', i.sdk),
          if (i.device != null) AiDiagnosticRow('device', i.device),
          if (i.compatible != null) AiDiagnosticRow('compatible', i.compatible),
          if (i.osVersion != null) AiDiagnosticRow('osVersion', i.osVersion),
          if (i.localeSupported != null)
            AiDiagnosticRow('localeSupported', i.localeSupported),
        ],
        if (proofread case final r?)
          AiDiagnosticRow('proofread', '${r.status.name} (${r.code})'),
      ]),
      AiDiagnosticSection('llama.cpp', 'llama.cpp', [
        ...library,
        AiDiagnosticRow('gpuSelectable', await gpuSelectable()),
      ]),
      AiDiagnosticSection('localModels', 'Local models', [
        for (final m in catalog) ..._modelRows(m),
      ]),
      if (online case final o?)
        ...await o.diagnostics()
      else
        const AiDiagnosticSection('online', 'Online sources', []),
    ]);
  }

  /// Purpose: Rows of a status report. Inputs: [r]. Returns: Rows.
  /// Side effects: None. Notes: Internal.
  List<AiDiagnosticRow> _statusRows(GenAiStatusReport r) => [
    AiDiagnosticRow(
      'status',
      '${r.status.name} (${r.code})',
      severity: r.status == GenAiStatus.available
          ? AiDiagnosticSeverity.info
          : AiDiagnosticSeverity.warning,
    ),
    if (r.detail != null) AiDiagnosticRow('detail', r.detail),
    if (r.variant != null) AiDiagnosticRow('variant', r.variant),
    if (r.served != null) AiDiagnosticRow('served', r.served),
    if (r.refused != null) AiDiagnosticRow('refused', r.refused),
    if (r.baseModelName != null) AiDiagnosticRow('model', r.baseModelName),
    if (r.tokenLimit != null) AiDiagnosticRow('tokenLimit', r.tokenLimit),
  ];

  /// Purpose: Rows describing one local model. Inputs: [m]. Returns: Rows.
  /// Side effects: None. Notes: Internal.
  List<AiDiagnosticRow> _modelRows(ArtifactManifest m) {
    final status = manager.statusOf(m.artifactId);
    final file = m.files.first;
    final minimum = llamaMinimumBuild(m);
    return [
      AiDiagnosticRow(m.modelId, artifactDisplayName(m)),
      AiDiagnosticRow(
        '  state',
        status.state.name,
        severity: status.failure == null
            ? AiDiagnosticSeverity.info
            : AiDiagnosticSeverity.error,
      ),
      if (status.failure != null)
        AiDiagnosticRow(
          '  failure',
          '${status.failure!.name} ${status.message ?? ''}',
        ),
      AiDiagnosticRow('  bytes', file.bytes),
      AiDiagnosticRow('  sha256', '${file.sha256.substring(0, 12)}…'),
      if (minimum != null)
        AiDiagnosticRow(
          '  minimumBuild',
          'b$minimum (pinned b$llamaPinnedBuild)',
        ),
      if (_localId == m.modelId && _local != null)
        for (final r in _local!.diagnostics)
          AiDiagnosticRow('  ${r.key}', r.value, severity: r.severity),
    ];
  }

  /// Purpose: Run a status query, swallowing its failure.
  /// Inputs: [body]. Returns: Its value, or null. Side effects: [body]'s.
  /// Notes: Internal; diagnostics must render even when a backend throws.
  static Future<T?> _safe<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } catch (_) {
      return null;
    }
  }
}

/// [LlamaGpuFailures] kept in the router's device-local store.
class _StoredGpuFailures implements LlamaGpuFailures {
  /// Purpose: Bind [store]. Inputs: [store]. Returns: Value.
  /// Side effects: None. Notes: Internal.
  _StoredGpuFailures(this.store);
  final AiSourceStore store;

  @override
  Future<String?> reasonFor(String key) async {
    final map = (await store.read())[aiGpuFailuresKey];
    return map is Map && map[key] is String ? map[key] as String : null;
  }

  @override
  Future<void> record(String key, String reason) async {
    final map = (await store.read())[aiGpuFailuresKey];
    await store.write({
      aiGpuFailuresKey: {if (map is Map) ...map, key: reason},
    });
  }
}
