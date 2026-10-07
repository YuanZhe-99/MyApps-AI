/// Online provider configuration: where requests go and how they authenticate.
///
/// The record holds no API key. Keys are read through an injected
/// [OnlineSecretReader], so storage and sync stay with the application's
/// secret channel.
library;

import 'package:flutter/foundation.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Purpose: Read the API key for one provider.
/// Inputs: `providerId` — the [OnlineProvider.id].
/// Returns: The key, or null when none is stored.
/// Side effects: Implementations read the application's secret store.
/// Notes: Supplied by the application; this package never stores keys.
typedef OnlineSecretReader = Future<String?> Function(String providerId);

/// How requests to a provider are shaped.
///
/// Persisted by [Enum.name]; the names match the MyTranscribe `dialect` field.
enum OnlineDialect {
  /// The official OpenAI API.
  openai,

  /// OpenRouter, which needs a JSON body for provider-specific options.
  openrouter,

  /// Any other server speaking the OpenAI protocol.
  openaiCompatible,
}

/// How a request proves who it is.
enum OnlineAuthScheme {
  /// `Authorization: Bearer <key>`.
  bearer,

  /// No credential; typical for a server on the user's own machine.
  none,

  /// The key sent as-is in a header named by [OnlineProvider.authHeaderName].
  header,
}

/// What an online source is missing before it can be used.
enum OnlineConfigurationGap {
  /// The base URL is empty or not an absolute http(s) URL.
  endpoint,

  /// No model id is configured.
  model,

  /// The provider needs a key and none is stored.
  apiKey,
}

/// Keys modelled by [OnlineProvider]; everything else is preserved in
/// [OnlineProvider.extra].
const _knownKeys = {
  'name',
  'templateId',
  'dialect',
  'baseUrl',
  'authScheme',
  'authHeaderName',
  'extraHeaders',
  'requestTimeoutSeconds',
  'modelId',
};

/// One configured online provider.
@immutable
class OnlineProvider {
  /// Purpose: Create a provider configuration.
  /// Inputs: `id` — stable record id such as `provider:openai`; `name`;
  /// `dialect`; `baseUrl` — API root such as `https://api.openai.com/v1`;
  /// `templateId` — the template it came from, null when user-built;
  /// `modelId` — the model sent as `model` by the LLM backend; auth fields;
  /// `headers` — extra headers; `requestTimeoutSeconds`; `extra` — unknown
  /// JSON fields preserved on write.
  /// Returns: A new value.
  /// Side effects: None.
  /// Notes: No API key field exists by design.
  const OnlineProvider({
    required this.id,
    required this.dialect,
    required this.baseUrl,
    this.name = '',
    this.templateId,
    this.modelId,
    this.authScheme = OnlineAuthScheme.bearer,
    this.authHeaderName,
    this.headers = const {},
    this.requestTimeoutSeconds = 600,
    this.extra = const {},
  });

  /// Stable record id.
  final String id;

  /// User-visible name.
  final String name;

  /// Template id this record was created from, or null.
  final String? templateId;

  /// Request shape.
  final OnlineDialect dialect;

  /// API root without the endpoint path.
  final String baseUrl;

  /// Model id for chat completions, or null when not configured.
  final String? modelId;

  /// Authentication scheme.
  final OnlineAuthScheme authScheme;

  /// Header name for [OnlineAuthScheme.header].
  final String? authHeaderName;

  /// Extra headers sent with every request.
  final Map<String, String> headers;

  /// Seconds to wait for response headers.
  final int requestTimeoutSeconds;

  /// Unknown JSON fields, written back unchanged.
  final Map<String, Object?> extra;

  /// Purpose: Report whether the provider needs an API key.
  /// Inputs: None. Returns: `bool`. Side effects: None.
  /// Notes: False only for [OnlineAuthScheme.none].
  bool get needsApiKey => authScheme != OnlineAuthScheme.none;

  /// Purpose: Parse [baseUrl] as an absolute http(s) URL.
  /// Inputs: None.
  /// Returns: The URI, or null when unusable.
  /// Side effects: None.
  /// Notes: Requires a host so a typo never resolves to a relative request.
  Uri? get baseUri {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }

  /// Purpose: Name the host requests are sent to.
  /// Inputs: None.
  /// Returns: The host, or null when [baseUrl] is unusable.
  /// Side effects: None.
  /// Notes: Shown in privacy notices.
  String? get recipientHost => baseUri?.host;

  /// Purpose: Build the URL for one endpoint under this provider.
  /// Inputs: `path` such as `chat/completions`, optionally with a query.
  /// Returns: Absolute URL string.
  /// Side effects: None.
  /// Notes: Tolerates a trailing slash on [baseUrl] and a leading slash on
  /// `path`, matching MyTranscribe.
  String endpoint(String path) {
    final trimmed = baseUrl.trim();
    final base = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final suffix = path.startsWith('/') ? path.substring(1) : path;
    return '$base/$suffix';
  }

  /// Purpose: Build the authentication headers.
  /// Inputs: `apiKey` — may be null or empty.
  /// Returns: Headers, empty when no key or no auth is needed.
  /// Side effects: None.
  /// Notes: Same rules as MyTranscribe's `authHeaders`.
  Map<String, String> authHeaders(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) return const {};
    return switch (authScheme) {
      OnlineAuthScheme.none => const {},
      OnlineAuthScheme.bearer => {'Authorization': 'Bearer $apiKey'},
      OnlineAuthScheme.header => {(authHeaderName ?? 'Authorization'): apiKey},
    };
  }

  /// Purpose: Build every header for a request.
  /// Inputs: `apiKey`.
  /// Returns: [headers] followed by [authHeaders], auth winning collisions.
  /// Side effects: None.
  /// Notes: None.
  Map<String, String> requestHeaders(String? apiKey) => {
    ...headers,
    ...authHeaders(apiKey),
  };

  /// Purpose: List what is missing before the provider can be used.
  /// Inputs: `apiKey` — the stored key; `requireModel` — whether [modelId]
  /// must be set (true for chat, false when models are app-owned records).
  /// Returns: The gaps, empty when ready.
  /// Side effects: None.
  /// Notes: Never contacts the network.
  Set<OnlineConfigurationGap> configurationGaps(
    String? apiKey, {
    bool requireModel = true,
  }) => {
    if (baseUri == null) OnlineConfigurationGap.endpoint,
    if (requireModel && (modelId == null || modelId!.trim().isEmpty))
      OnlineConfigurationGap.model,
    if (needsApiKey && (apiKey == null || apiKey.isEmpty))
      OnlineConfigurationGap.apiKey,
  };

  /// Purpose: Describe this provider as a selectable AI source.
  /// Inputs: `apiKey`; `features` — feature ids it serves, empty for all;
  /// `requireModel` as in [configurationGaps].
  /// Returns: An [AiSourceOption] of kind [AiSourceKind.online] with id
  /// [onlineSourceId].
  /// Side effects: None.
  /// Notes: Unconfigured providers are listed as
  /// [AiSourceReadiness.needsConfiguration] so settings can deep-link.
  AiSourceOption toSourceOption(
    String? apiKey, {
    Set<String> features = const {},
    bool requireModel = true,
  }) => AiSourceOption(
    id: onlineSourceId(id),
    kind: AiSourceKind.online,
    readiness: configurationGaps(apiKey, requireModel: requireModel).isEmpty
        ? AiSourceReadiness.ready
        : AiSourceReadiness.needsConfiguration,
    features: features,
  );

  /// Purpose: Return a copy with some fields replaced.
  /// Inputs: Fields to replace; `clearModelId` to unset [modelId].
  /// Returns: A new provider.
  /// Side effects: None.
  /// Notes: [id], [templateId] and [extra] are kept.
  OnlineProvider copyWith({
    String? name,
    OnlineDialect? dialect,
    String? baseUrl,
    String? modelId,
    bool clearModelId = false,
    OnlineAuthScheme? authScheme,
    String? authHeaderName,
    Map<String, String>? headers,
    int? requestTimeoutSeconds,
  }) => OnlineProvider(
    id: id,
    name: name ?? this.name,
    templateId: templateId,
    dialect: dialect ?? this.dialect,
    baseUrl: baseUrl ?? this.baseUrl,
    modelId: clearModelId ? null : (modelId ?? this.modelId),
    authScheme: authScheme ?? this.authScheme,
    authHeaderName: authHeaderName ?? this.authHeaderName,
    headers: headers ?? this.headers,
    requestTimeoutSeconds: requestTimeoutSeconds ?? this.requestTimeoutSeconds,
    extra: extra,
  );

  /// Purpose: Serialize as a record payload.
  /// Inputs: None.
  /// Returns: JSON map without the id.
  /// Side effects: None.
  /// Notes: Field names match MyTranscribe's provider payload; unknown fields
  /// are written first so known keys win. Null optionals are omitted.
  Map<String, Object?> toJson() => {
    ...extra,
    'name': name,
    if (templateId != null) 'templateId': templateId,
    'dialect': dialect.name,
    'baseUrl': baseUrl,
    'authScheme': authScheme.name,
    if (authHeaderName != null) 'authHeaderName': authHeaderName,
    if (headers.isNotEmpty) 'extraHeaders': headers,
    'requestTimeoutSeconds': requestTimeoutSeconds,
    if (modelId != null) 'modelId': modelId,
  };

  /// Purpose: Read a record payload.
  /// Inputs: `id` — record id; `json` — payload, may be malformed.
  /// Returns: A provider; every field falls back rather than throwing.
  /// Side effects: None.
  /// Notes: Reads MyTranscribe provider payloads unchanged; fields this type
  /// does not model (limits, overrides, template version) land in [extra]
  /// and survive a round trip. Unknown dialects read as
  /// [OnlineDialect.openaiCompatible], unknown auth as bearer.
  static OnlineProvider fromJson(String id, Object? json) {
    final map = json is Map ? json : const {};
    return OnlineProvider(
      id: id,
      name: _string(map['name']) ?? id,
      templateId: _string(map['templateId']),
      dialect: OnlineDialect.values.firstWhere(
        (d) => d.name == map['dialect'],
        orElse: () => OnlineDialect.openaiCompatible,
      ),
      baseUrl: _string(map['baseUrl']) ?? '',
      modelId: _string(map['modelId']),
      authScheme: OnlineAuthScheme.values.firstWhere(
        (a) => a.name == map['authScheme'],
        orElse: () => OnlineAuthScheme.bearer,
      ),
      authHeaderName: _string(map['authHeaderName']),
      headers: {
        if (map['extraHeaders'] case final Map h)
          for (final e in h.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      requestTimeoutSeconds: _positiveInt(map['requestTimeoutSeconds']) ?? 600,
      extra: {
        for (final e in map.entries)
          if (e.key is String && !_knownKeys.contains(e.key))
            e.key as String: e.value,
      },
    );
  }
}

/// Purpose: Derive the [AiSourceSelection] id for an online provider.
/// Inputs: `providerId`.
/// Returns: `online:<providerId>`.
/// Side effects: None.
/// Notes: Also the [OpenAiCompatibleLlmBackend.id]; stable for cache keys.
String onlineSourceId(String providerId) => 'online:$providerId';

/// Purpose: Read a non-empty trimmed string.
/// Inputs: `value`. Returns: String or null. Side effects: None.
/// Notes: Internal helper.
String? _string(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// Purpose: Read a positive integer.
/// Inputs: `value`. Returns: int or null. Side effects: None.
/// Notes: Internal helper; zero and negatives read as unset.
int? _positiveInt(Object? value) {
  final n = switch (value) {
    final int i => i,
    final num d => d.round(),
    final String s => int.tryParse(s),
    _ => null,
  };
  return n != null && n > 0 ? n : null;
}
