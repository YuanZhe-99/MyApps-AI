/// Online provider templates: the providers an application offers before the
/// user configures anything, each with a default base URL.
///
/// Template ids and seeded provider ids are a compatibility contract: they are
/// derived, not generated, so fresh devices produce identical records and the
/// first sync merges them. A shipped id is never changed.
library;

import 'package:flutter/foundation.dart';

import 'provider.dart';
import 'template_catalog.dart';

export 'template_catalog.dart';

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

/// One service endpoint of a provider with several, such as an
/// international and a China site.
@immutable
class OnlineEndpointOption {
  /// Purpose: Describe an endpoint.
  /// Inputs: [url]; [label] in the provider's own wording, such as
  /// `International (Singapore)`, or null to show only the domain;
  /// [catalogId], the models.dev provider id for this endpoint.
  /// Returns: Option. Side effects: None.
  /// Notes: Applications never invent region words; see the label rule.
  const OnlineEndpointOption(this.url, {this.label, this.catalogId});

  /// Base URL.
  final String url;

  /// The provider's own name for this endpoint, or null.
  final String? label;

  /// models.dev provider id, or null.
  final String? catalogId;

  /// Purpose: The endpoint's host. Inputs: None. Returns: Host or the URL.
  /// Side effects: None. Notes: None.
  String get host => Uri.tryParse(url)?.host ?? url;
}

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
    this.authHeaderName,
    this.headers = const {},
    this.defaultModelId,
    this.recordsTemplateId = true,
    this.iconKey,
    this.catalogId,
    this.docsUrl,
    this.endpoints = const [],
    this.local = false,
  });

  /// Header carrying the key when [authScheme] is `header`, such as
  /// Azure's `api-key`.
  final String? authHeaderName;

  /// Icon of the provider in `myapps_ai_online_ui`, or null for initials.
  final String? iconKey;

  /// models.dev provider id of the default endpoint, or null.
  final String? catalogId;

  /// The provider's API documentation.
  final String? docsUrl;

  /// Alternative endpoints; empty when the provider has one.
  final List<OnlineEndpointOption> endpoints;

  /// Whether this is a server on the user's own machine or network.
  final bool local;

  /// Purpose: The models.dev id for a base URL of this template.
  /// Inputs: [baseUrl]. Returns: The matching endpoint's id, else
  /// [catalogId]. Side effects: None. Notes: None.
  String? catalogIdFor(String baseUrl) {
    for (final e in endpoints) {
      if (e.url == baseUrl) return e.catalogId ?? catalogId;
    }
    return catalogId;
  }

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
      authHeaderName: authHeaderName,
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
  iconKey: 'openai',
  catalogId: 'openai',
  docsUrl: 'https://platform.openai.com/docs/models',
);

/// The OpenRouter template, seeded as `provider:openrouter`.
const openRouterTemplate = OnlineProviderTemplate(
  id: openRouterTemplateId,
  name: 'OpenRouter',
  dialect: OnlineDialect.openrouter,
  defaultBaseUrl: 'https://openrouter.ai/api/v1',
  seedProviderId: openRouterProviderId,
  iconKey: 'openrouter',
  catalogId: 'openrouter',
  docsUrl: 'https://openrouter.ai/models',
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
  /// Chat applications use [OnlineProviderTemplateRegistry.chat].
  factory OnlineProviderTemplateRegistry.builtIn() =>
      OnlineProviderTemplateRegistry(const [
        openAiTemplate,
        openRouterTemplate,
        openAiCompatibleTemplate,
      ]);

  /// Purpose: Create a registry with every chat provider template.
  /// Inputs: None. Returns: A registry, sorted by name with the custom
  /// template last. Side effects: None.
  /// Notes: Not grouped by region; see [chatProviderTemplates].
  factory OnlineProviderTemplateRegistry.chat() =>
      OnlineProviderTemplateRegistry([
        ...[
          openAiTemplate,
          openRouterTemplate,
          ...chatProviderTemplates,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
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
