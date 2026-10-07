/// Online provider templates: the providers an application offers before the
/// user configures anything, each with a default base URL.
///
/// Template ids and seeded provider ids are a compatibility contract: they are
/// derived, not generated, so fresh devices produce identical records and the
/// first sync merges them. A shipped id is never changed.
library;

import 'package:flutter/foundation.dart';

import 'provider.dart';

/// Template id of the official OpenAI API (MyTranscribe `templateId`).
const openAiTemplateId = 'openai';

/// Template id of OpenRouter (MyTranscribe `templateId`).
const openRouterTemplateId = 'openrouter';

/// Template id of a user-configured OpenAI-compatible endpoint.
const openAiCompatibleTemplateId = 'openaiCompatible';

/// Seeded record id of the OpenAI provider (MyTranscribe `provider:openai`).
const openAiProviderId = 'provider:openai';

/// Seeded record id of the OpenRouter provider (MyTranscribe
/// `provider:openrouter`).
const openRouterProviderId = 'provider:openrouter';

/// One provider template.
@immutable
class OnlineProviderTemplate {
  /// Purpose: Describe a template.
  /// Inputs: `id` — stable template id; `name`; `dialect`; `defaultBaseUrl`;
  /// `seedProviderId` — derived record id when the app seeds this template on
  /// first launch, null when it is only offered when adding a provider;
  /// `authScheme`; `headers`; `defaultModelId`; `recordsTemplateId` — whether
  /// created records carry [id] as their `templateId`.
  /// Returns: A template. Side effects: None.
  /// Notes: The custom template does not record its id, matching
  /// MyTranscribe presets whose records have no `templateId`.
  const OnlineProviderTemplate({
    required this.id,
    required this.name,
    required this.dialect,
    required this.defaultBaseUrl,
    this.seedProviderId,
    this.authScheme = OnlineAuthScheme.bearer,
    this.headers = const {},
    this.defaultModelId,
    this.recordsTemplateId = true,
  });

  /// Stable template id.
  final String id;

  /// Default provider name.
  final String name;

  /// Request shape.
  final OnlineDialect dialect;

  /// Base URL a new provider starts with; empty for a custom endpoint.
  final String defaultBaseUrl;

  /// Derived record id when seeded, or null.
  final String? seedProviderId;

  /// Default authentication.
  final OnlineAuthScheme authScheme;

  /// Default extra headers.
  final Map<String, String> headers;

  /// Default chat model id, or null.
  final String? defaultModelId;

  /// Whether created records carry [id] as `templateId`.
  final bool recordsTemplateId;

  /// Purpose: Create a provider record from this template.
  /// Inputs: `id` — record id; defaults to [seedProviderId]; `baseUrl`,
  /// `modelId`, `name` overrides.
  /// Returns: An [OnlineProvider].
  /// Side effects: None.
  /// Notes: Throws [ArgumentError] when no id is given and none is seeded.
  OnlineProvider create({
    String? id,
    String? baseUrl,
    String? modelId,
    String? name,
  }) {
    final recordId = id ?? seedProviderId;
    if (recordId == null || recordId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'required for unseeded templates');
    }
    return OnlineProvider(
      id: recordId,
      name: name ?? this.name,
      templateId: recordsTemplateId ? this.id : null,
      dialect: dialect,
      baseUrl: baseUrl ?? defaultBaseUrl,
      modelId: modelId ?? defaultModelId,
      authScheme: authScheme,
      headers: headers,
    );
  }
}

/// The official OpenAI API template, seeded as `provider:openai`.
const openAiTemplate = OnlineProviderTemplate(
  id: openAiTemplateId,
  name: 'OpenAI',
  dialect: OnlineDialect.openai,
  defaultBaseUrl: 'https://api.openai.com/v1',
  seedProviderId: openAiProviderId,
);

/// The OpenRouter template, seeded as `provider:openrouter`.
const openRouterTemplate = OnlineProviderTemplate(
  id: openRouterTemplateId,
  name: 'OpenRouter',
  dialect: OnlineDialect.openrouter,
  defaultBaseUrl: 'https://openrouter.ai/api/v1',
  seedProviderId: openRouterProviderId,
);

/// A custom OpenAI-compatible endpoint; not seeded, no default URL.
const openAiCompatibleTemplate = OnlineProviderTemplate(
  id: openAiCompatibleTemplateId,
  name: 'OpenAI-compatible',
  dialect: OnlineDialect.openaiCompatible,
  defaultBaseUrl: '',
  recordsTemplateId: false,
);

/// The templates an application registers, in display order.
class OnlineProviderTemplateRegistry {
  /// Purpose: Create a registry.
  /// Inputs: `templates` — initial templates, in order.
  /// Returns: A registry. Side effects: None.
  /// Notes: Use [OnlineProviderTemplateRegistry.builtIn] for the three
  /// shared templates.
  OnlineProviderTemplateRegistry([
    Iterable<OnlineProviderTemplate> templates = const [],
  ]) {
    templates.forEach(register);
  }

  /// Purpose: Create a registry with OpenAI, OpenRouter and custom.
  /// Inputs: None. Returns: A registry. Side effects: None.
  /// Notes: Apps may register more (for example a local-server preset).
  factory OnlineProviderTemplateRegistry.builtIn() =>
      OnlineProviderTemplateRegistry(const [
        openAiTemplate,
        openRouterTemplate,
        openAiCompatibleTemplate,
      ]);

  final Map<String, OnlineProviderTemplate> _byId = {};

  /// Purpose: Register or replace a template.
  /// Inputs: `template`.
  /// Returns: None.
  /// Side effects: Mutates the registry.
  /// Notes: Replacing keeps the original position so lists stay stable.
  void register(OnlineProviderTemplate template) =>
      _byId[template.id] = template;

  /// Purpose: Look up a template.
  /// Inputs: `id`. Returns: Template or null. Side effects: None. Notes: None.
  OnlineProviderTemplate? byId(String? id) => id == null ? null : _byId[id];

  /// Purpose: List templates in registration order.
  /// Inputs: None. Returns: Unmodifiable list. Side effects: None.
  /// Notes: None.
  List<OnlineProviderTemplate> get templates => List.unmodifiable(_byId.values);

  /// Purpose: Create the providers seeded on first launch.
  /// Inputs: None.
  /// Returns: One provider per template with a [OnlineProviderTemplate.seedProviderId].
  /// Side effects: None.
  /// Notes: The caller inserts only ids it does not already have.
  List<OnlineProvider> seedProviders() => [
    for (final t in _byId.values)
      if (t.seedProviderId != null) t.create(),
  ];
}
