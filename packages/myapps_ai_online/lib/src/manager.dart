/// Purpose: Online sources as one object: records, keys, privacy
/// acknowledgements and model lists for the settings pages, and ready
/// backends for the router.
/// Inputs: Application storage callbacks; see [OnlineSourceManager.new].
/// Returns: [OnlineSourceManager].
/// Side effects: Reads and writes the application's configuration and
/// secret store; network only for tests, model lists and generation.
/// Notes: Replaces the `OnlineSources` class an application kept. Records
/// and acknowledgements stay device-local; keys never leave the secret store.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';

import 'catalog.dart';
import 'controller.dart';
import 'http_support.dart';
import 'llm_backend.dart';
import 'model.dart';
import 'privacy_notice.dart';
import 'provider.dart';
import 'templates.dart';

/// Configuration key of the provider records.
const onlineProvidersKey = 'aiOnlineProviders';

/// Configuration key of this device's privacy acknowledgements.
const onlineAcknowledgementsKey = 'aiOnlineAcknowledgements';

/// Online sources over an application's configuration and secret store.
class OnlineSourceManager implements OnlineSourcesController, AiOnlineSources {
  /// Purpose: Bind application storage.
  /// Inputs: [readConfig] and [writeConfig] over the whole device-local
  /// configuration; [readKey] and [writeKey] over the secret store;
  /// [notice] builds the privacy notice for a provider (the application
  /// knows what its prompts contain); [templates] (every chat template by
  /// default); [client] for HTTP (tests).
  /// Returns: Manager. Side effects: None until [initialize].
  /// Notes: Writes merge into the configuration, keeping other settings.
  OnlineSourceManager({
    required this.readConfig,
    required this.writeConfig,
    required this.readKey,
    required this.writeKey,
    required this.notice,
    OnlineProviderTemplateRegistry? templates,
    http.Client Function()? client,
  }) : templates = templates ?? OnlineProviderTemplateRegistry.chat(),
       _client = client ?? http.Client.new;

  /// Reads the device-local configuration.
  final Future<Map<String, dynamic>> Function() readConfig;

  /// Replaces the device-local configuration.
  final Future<void> Function(Map<String, dynamic>) writeConfig;

  /// Reads a provider's key.
  final Future<String?> Function(String providerId) readKey;

  /// Stores (or with null, deletes) a provider's key.
  final Future<void> Function(String providerId, String? key) writeKey;

  /// Builds the privacy notice for a provider.
  final OnlinePrivacyNotice? Function(OnlineProvider provider) notice;

  @override
  final OnlineProviderTemplateRegistry templates;

  final http.Client Function() _client;
  final _notifier = ValueNotifier<int>(0);
  List<OnlineProvider> _providers = [];
  final _keys = <String, bool>{};
  final _acks = <String, OnlinePrivacyAcknowledgement?>{};
  final _backends = <String, OpenAiCompatibleLlmBackend>{};
  final _lastResult = <String, String>{};
  Future<void>? _loading;

  @override
  Future<void> initialize() => _loading ??= _load();

  /// Purpose: Load records, key presence and acknowledgements.
  /// Inputs: None. Returns: Completion. Side effects: Storage reads.
  /// Notes: Internal.
  Future<void> _load() async {
    final config = await readConfig();
    final raw = config[onlineProvidersKey];
    _providers = [
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String)
            OnlineProvider.fromJson(e.key as String, e.value),
    ];
    final acks = config[onlineAcknowledgementsKey];
    for (final p in _providers) {
      _keys[p.id] = (await readKey(p.id))?.isNotEmpty ?? false;
      _acks[p.id] = OnlinePrivacyAcknowledgement.tryParse(
        acks is Map ? acks[p.id] : null,
      );
    }
    _notifier.value++;
  }

  @override
  List<OnlineProvider> get providers => List.unmodifiable(_providers);

  @override
  Listenable get changes => _notifier;

  @override
  String newProviderId() {
    final r = Random.secure();
    final hex = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'provider:$hex';
  }

  @override
  Future<bool> hasKey(String providerId) async =>
      (await readKey(providerId))?.isNotEmpty ?? false;

  /// Purpose: Write one map entry of the configuration.
  /// Inputs: [key], [id], [value] (null removes). Returns: Completion.
  /// Side effects: Reads then writes the configuration. Notes: Internal.
  Future<void> _writeEntry(String key, String id, Object? value) async {
    final config = Map<String, dynamic>.of(await readConfig());
    final map = Map<String, dynamic>.from(config[key] as Map? ?? {});
    if (value == null) {
      map.remove(id);
    } else {
      map[id] = value;
    }
    config[key] = map;
    await writeConfig(config);
  }

  @override
  Future<void> save(
    OnlineProvider provider, {
    String? newKey,
    bool clearKey = false,
  }) async {
    await initialize();
    if (clearKey || newKey != null) {
      await writeKey(provider.id, clearKey ? null : newKey);
      _keys[provider.id] = !clearKey && (newKey?.isNotEmpty ?? false);
    } else {
      _keys[provider.id] ??= await hasKey(provider.id);
    }
    await _writeEntry(onlineProvidersKey, provider.id, provider.toJson());
    final i = _providers.indexWhere((p) => p.id == provider.id);
    _providers = [..._providers];
    if (i < 0) {
      _providers.add(provider);
    } else {
      _providers[i] = provider;
    }
    _dropBackends(provider.id);
    _notifier.value++;
  }

  @override
  Future<void> remove(String providerId) async {
    await initialize();
    await writeKey(providerId, null);
    await _writeEntry(onlineProvidersKey, providerId, null);
    _providers = [..._providers.where((p) => p.id != providerId)];
    _keys.remove(providerId);
    _dropBackends(providerId);
    _notifier.value++;
  }

  /// Purpose: Forget cached backends of a provider. Inputs: [providerId].
  /// Returns: None. Side effects: Unloads them. Notes: Internal.
  void _dropBackends(String providerId) {
    _backends.removeWhere((key, b) {
      if (b.provider.id != providerId) return false;
      b.unload();
      return true;
    });
  }

  @override
  Future<GenAiStatusReport> testConnection(
    OnlineProvider draft,
    String? draftKey,
  ) async {
    final watch = Stopwatch()..start();
    final report = await OpenAiCompatibleLlmBackend(
      provider: draft,
      readSecret: (_) async => draftKey ?? await readKey(draft.id),
    ).testConnection();
    _lastResult[draft.id] =
        '${report.status.name}${report.detail == null ? '' : ' ${report.detail}'}'
        ' in ${watch.elapsedMilliseconds} ms';
    _notifier.value++;
    return report;
  }

  @override
  OnlinePrivacyNotice? privacyNotice(OnlineProvider provider) =>
      notice(provider);

  @override
  Future<OnlinePrivacyAcknowledgement?> acknowledgement(
    String providerId,
  ) async {
    final raw = (await readConfig())[onlineAcknowledgementsKey];
    return OnlinePrivacyAcknowledgement.tryParse(
      raw is Map ? raw[providerId] : null,
    );
  }

  @override
  Future<void> acknowledge(
    String providerId,
    OnlinePrivacyAcknowledgement record,
  ) async {
    await _writeEntry(onlineAcknowledgementsKey, providerId, record.toJson());
    _acks[providerId] = record;
    _notifier.value++;
  }

  @override
  Future<List<OnlineModelEntry>> fetchModels(
    OnlineProvider draft,
    String? draftKey,
  ) async {
    final catalogId = templates
        .byId(draft.templateId)
        ?.catalogIdFor(draft.baseUrl);
    final client = _client();
    try {
      final listed = await fetchOnlineModels(
        client,
        draft,
        apiKey: draftKey ?? await readKey(draft.id),
      );
      _lastResult[draft.id] = 'listed ${listed.length} models';
      return [
        for (final e in listed)
          switch (OnlineModelCatalog.lookup(e.id, catalogId: catalogId)) {
            final c? => e.withFallback(
              displayName: c.displayName,
              vendor: c.vendor,
              contextTokens: c.contextTokens,
              inputModalities: c.inputModalities,
            ),
            null => e,
          },
      ];
    } finally {
      client.close();
    }
  }

  @override
  List<OnlineModelEntry> catalogModels(OnlineProvider provider) {
    final id = templates
        .byId(provider.templateId)
        ?.catalogIdFor(provider.baseUrl);
    return id == null ? const [] : OnlineModelCatalog.modelsOf(id);
  }

  // ── AiOnlineSources ──

  @override
  List<AiSourceOption> get sourceOptions => [
    for (final p in _providers)
      for (final m in p.models)
        AiSourceOption(
          id: onlineModelSourceId(p.id, m.modelName),
          kind: AiSourceKind.online,
          readiness:
              p
                  .configurationGaps(
                    (_keys[p.id] ?? false) ? 'present' : null,
                    requireModel: false,
                  )
                  .isEmpty
              ? AiSourceReadiness.ready
              : AiSourceReadiness.needsConfiguration,
        ),
  ];

  /// Purpose: The provider and model a source id names.
  /// Inputs: [id]: `online:model:<p>:<m>`, or a legacy `provider:<p>` /
  /// `online:provider:<p>` meaning that source's first model.
  /// Returns: Both, or null. Side effects: None. Notes: Internal.
  (OnlineProvider, OnlineModel)? _lookup(String id) {
    for (final p in _providers) {
      for (final m in p.models) {
        if (onlineModelSourceId(p.id, m.modelName) == id) return (p, m);
      }
      if ((id == p.id || id == 'online:${p.id}') && p.models.isNotEmpty) {
        return (p, p.models.first);
      }
    }
    return null;
  }

  /// Purpose: The source holding an online model.
  /// Inputs: [sourceId], as in a selection (legacy ids included).
  /// Returns: The provider, or null. Side effects: None.
  /// Notes: For icons and labels in applications.
  OnlineProvider? providerFor(String sourceId) => _lookup(sourceId)?.$1;

  @override
  bool owns(String id) =>
      id.startsWith('online:') ||
      id.startsWith('provider:') ||
      _lookup(id) != null;

  @override
  String? sourceName(String id) {
    final hit = _lookup(id);
    if (hit == null) return null;
    final (p, m) = hit;
    return m.name(vendorHint: p.name);
  }

  @override
  String? sourceDetail(String id) => _lookup(id)?.$1.name;

  @override
  Future<GenAiBackend> resolve(String id) async {
    await initialize();
    final hit = _lookup(id);
    if (hit == null) {
      throw const GenAiException(GenAiFailure.unavailable, 'unknownSource');
    }
    final (p, m) = hit;
    final key = await readKey(p.id);
    final gaps = p.configurationGaps(key, requireModel: false);
    if (gaps.isNotEmpty) {
      throw GenAiException(
        GenAiFailure.unavailable,
        needsConfigurationDetail(gaps),
      );
    }
    final current = notice(p);
    if (current == null ||
        needsOnlinePrivacyAcknowledgement(
          await acknowledgement(p.id),
          current.version,
          recipientHost: p.recipientHost,
        )) {
      throw const GenAiException(GenAiFailure.unavailable, 'privacyNotice');
    }
    final backend = _backends[id] ??= OpenAiCompatibleLlmBackend(
      provider: p.forModel(m),
      readSecret: readKey,
    );
    return LlmGenAiBackend(backend, baseModelName: m.modelName);
  }

  @override
  Future<void> cancel() async {
    for (final b in _backends.values) {
      await b.cancel();
    }
  }

  @override
  Future<void> release() async {
    for (final b in _backends.values) {
      await b.unload();
    }
    _backends.clear();
  }

  @override
  Future<List<AiDiagnosticSection>> diagnostics() async {
    await initialize();
    if (_providers.isEmpty) {
      return const [AiDiagnosticSection('online', 'Online sources', [])];
    }
    return [
      for (final p in _providers)
        AiDiagnosticSection('online:${p.id}', p.name, [
          AiDiagnosticRow('host', p.recipientHost ?? p.baseUrl),
          AiDiagnosticRow('template', p.templateId ?? 'custom'),
          AiDiagnosticRow('auth', p.authScheme.name),
          AiDiagnosticRow(
            'keyStored',
            p.needsApiKey ? (_keys[p.id] ?? false) : 'not needed',
            severity: p.needsApiKey && !(_keys[p.id] ?? false)
                ? AiDiagnosticSeverity.warning
                : AiDiagnosticSeverity.info,
          ),
          AiDiagnosticRow(
            'privacyNotice',
            _acks[p.id] == null
                ? 'not acknowledged'
                : 'v${_acks[p.id]!.noticeVersion} for '
                      '${_acks[p.id]!.recipientHost ?? '-'}',
            severity: _acks[p.id] == null
                ? AiDiagnosticSeverity.warning
                : AiDiagnosticSeverity.info,
          ),
          AiDiagnosticRow('models', p.models.length),
          for (final m in p.models)
            AiDiagnosticRow('  ${m.modelName}', m.name()),
          if (_lastResult[p.id] case final r?) AiDiagnosticRow('lastResult', r),
        ]),
    ];
  }
}
