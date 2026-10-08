/// Shared HTTP failure classification for online clients.
library;

import 'dart:async';
import 'dart:convert';

import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:http/http.dart' as http;

import 'provider.dart';

/// What went wrong talking to an online provider.
enum OnlineErrorKind {
  /// 401/403: missing or wrong key.
  unauthorized,

  /// 413: the upload exceeded the endpoint's limit.
  tooLarge,

  /// 429: rate limited or out of quota.
  rateLimited,

  /// Another 4xx: the endpoint refused something in the request.
  rejected,

  /// 5xx: the endpoint had a problem of its own.
  serverError,

  /// The request never arrived or never came back.
  network,

  /// No response headers within the configured timeout.
  timeout,

  /// The reply could not be read.
  badResponse,

  /// The caller cancelled.
  cancelled,
}

/// The longest server-requested wait that is honoured.
///
/// Matches MyTranscribe: a longer `Retry-After` is capped so a job fails with
/// the server's message instead of looking hung.
const maxHonouredRetryAfter = Duration(seconds: 60);

/// A failed online request, carrying the [GenAiFailure] the UI words.
class OnlineException extends GenAiException {
  /// Purpose: Create an online failure.
  /// Inputs: `kind`; `message` — the server's own words when it gave any;
  /// `statusCode`; `retryAfter` — capped server-requested wait.
  /// Returns: Exception whose [failure] derives from `kind` and `statusCode`.
  /// Side effects: None.
  /// Notes: `message` may contain server text but never request content or
  /// keys; it is for logs and the existing "server said" line only.
  OnlineException(this.kind, String message, {this.statusCode, this.retryAfter})
    : super(failureFor(kind, statusCode), message);

  /// What went wrong.
  final OnlineErrorKind kind;

  /// HTTP status, when there was one.
  final int? statusCode;

  /// How long the server asked the caller to wait.
  final Duration? retryAfter;

  /// Purpose: Say whether retrying the same request could work.
  /// Inputs: None. Returns: `bool`. Side effects: None.
  /// Notes: Network, timeout, 5xx and 429, as in MyTranscribe.
  bool get isRetryable =>
      kind == OnlineErrorKind.network ||
      kind == OnlineErrorKind.timeout ||
      kind == OnlineErrorKind.serverError ||
      kind == OnlineErrorKind.rateLimited;

  /// Purpose: Name the failure for diagnostics.
  /// Inputs: None.
  /// Returns: `auth`, `tooLarge`, `quota`, `busy`, `server`, `rejected`,
  /// `network`, `timeout`, `badResponse` or `cancelled`.
  /// Side effects: None.
  /// Notes: Untranslated identifier, like [GenAiStatusReport.detail].
  String get detail => switch (kind) {
    OnlineErrorKind.unauthorized => 'auth',
    OnlineErrorKind.tooLarge => 'tooLarge',
    OnlineErrorKind.rateLimited => 'quota',
    OnlineErrorKind.serverError =>
      failure == GenAiFailure.busy ? 'busy' : 'server',
    OnlineErrorKind.rejected => 'rejected',
    OnlineErrorKind.network => 'network',
    OnlineErrorKind.timeout => 'timeout',
    OnlineErrorKind.badResponse => 'badResponse',
    OnlineErrorKind.cancelled => 'cancelled',
  };

  /// Purpose: Map a kind to the shared failure vocabulary.
  /// Inputs: `kind`, `statusCode`.
  /// Returns: [GenAiFailure].
  /// Side effects: None.
  /// Notes: Auth → unavailable (message starts with `auth`), 429 → quota,
  /// 503/529 → busy, other 5xx → failed, 413 → tooLong, timeout → timeout,
  /// network → failed (status reports unreachable).
  static GenAiFailure failureFor(OnlineErrorKind kind, int? statusCode) =>
      switch (kind) {
        OnlineErrorKind.unauthorized => GenAiFailure.unavailable,
        OnlineErrorKind.tooLarge => GenAiFailure.tooLong,
        OnlineErrorKind.rateLimited => GenAiFailure.quota,
        OnlineErrorKind.serverError =>
          statusCode == 503 || statusCode == 529
              ? GenAiFailure.busy
              : GenAiFailure.failed,
        OnlineErrorKind.timeout => GenAiFailure.timeout,
        OnlineErrorKind.cancelled => GenAiFailure.cancelled,
        OnlineErrorKind.rejected ||
        OnlineErrorKind.network ||
        OnlineErrorKind.badResponse => GenAiFailure.failed,
      };

  /// Purpose: Describe for logs.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  @override
  String toString() =>
      'OnlineException(${kind.name}${statusCode == null ? '' : ' $statusCode'}'
      '): $message';
}

/// Purpose: Classify an unsuccessful HTTP response.
/// Inputs: `status`, response `headers`, `body`.
/// Returns: An [OnlineException] carrying the server's own message.
/// Side effects: None.
/// Notes: Same status mapping as MyTranscribe's transcription client.
OnlineException onlineFailureForResponse(
  int status,
  Map<String, String> headers,
  String body,
) {
  final message = serverMessage(body) ?? 'The source answered with $status.';
  if (status == 401 || status == 403) {
    return OnlineException(
      OnlineErrorKind.unauthorized,
      message,
      statusCode: status,
    );
  }
  if (status == 413) {
    return OnlineException(
      OnlineErrorKind.tooLarge,
      message,
      statusCode: status,
    );
  }
  if (status == 429) {
    return OnlineException(
      OnlineErrorKind.rateLimited,
      message,
      statusCode: status,
      retryAfter: retryAfterFrom(headers),
    );
  }
  if (status >= 500) {
    return OnlineException(
      OnlineErrorKind.serverError,
      message,
      statusCode: status,
    );
  }
  return OnlineException(OnlineErrorKind.rejected, message, statusCode: status);
}

/// Purpose: Read a `Retry-After` header in seconds.
/// Inputs: `headers` (lower-case keys, as package:http provides).
/// Returns: Capped delay, or null when absent or not positive seconds.
/// Side effects: None.
/// Notes: The HTTP-date form is ignored, as in MyTranscribe.
Duration? retryAfterFrom(Map<String, String> headers) {
  final value = headers['retry-after'];
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds == null || seconds <= 0) return null;
  final delay = Duration(seconds: seconds);
  return delay > maxHonouredRetryAfter ? maxHonouredRetryAfter : delay;
}

/// Purpose: Extract the human-readable message from an error body.
/// Inputs: `body`.
/// Returns: `error.message`, a string `error`, top-level `message`, or a
/// short plain-text body; null otherwise.
/// Side effects: None.
/// Notes: Bodies over 300 characters (HTML pages) are dropped.
String? serverMessage(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (error is String) return error;
      if (decoded['message'] is String) return decoded['message'] as String;
    }
  } catch (_) {
    // Not JSON; fall through to the plain-text case.
  }
  return trimmed.length <= 300 ? trimmed : null;
}

/// One entry of a provider's model list.
class OnlineModelEntry {
  /// Purpose: Create an entry.
  /// Inputs: `id` — sent as `model`; `displayName` when distinct; `vendor`;
  /// `contextTokens`; `inputModalities`; `chat` — false for embedding,
  /// speech, image and moderation models.
  /// Returns: Entry. Side effects: None. Notes: None.
  const OnlineModelEntry(
    this.id, {
    this.displayName,
    this.vendor,
    this.contextTokens,
    this.inputModalities = const [],
    this.chat = true,
  });

  /// Model id.
  final String id;

  /// Friendlier name, or null.
  final String? displayName;

  /// Maker, when a catalog knows it.
  final String? vendor;

  /// Context length, when listed.
  final int? contextTokens;

  /// Accepted inputs such as `text` and `image`, when listed.
  final List<String> inputModalities;

  /// Whether this is a text chat model.
  final bool chat;

  /// Purpose: Copy with catalog facts filled in where missing.
  /// Inputs: Facts. Returns: Entry. Side effects: None. Notes: Listed facts
  /// win over the catalog's.
  OnlineModelEntry withFallback({
    String? displayName,
    String? vendor,
    int? contextTokens,
    List<String>? inputModalities,
  }) => OnlineModelEntry(
    id,
    displayName: this.displayName ?? displayName,
    vendor: this.vendor ?? vendor,
    contextTokens: this.contextTokens ?? contextTokens,
    inputModalities: this.inputModalities.isNotEmpty
        ? this.inputModalities
        : (inputModalities ?? const []),
    chat: chat,
  );
}

/// Model ids that are not chat models, by name.
final _notChat = RegExp(
  r'(embed|embedding|tts|whisper|transcri|dall-e|imagen|image-|moderation|'
  r'rerank|realtime|speech|audio|davinci-002|babbage|sora|veo|lyria)',
  caseSensitive: false,
);

/// Purpose: Whether a listed model is a text chat model.
/// Inputs: [id]; [outputModalities] when listed. Returns: bool.
/// Side effects: None. Notes: Listed outputs win; otherwise the id decides.
bool isChatModel(String id, {List<String>? outputModalities}) {
  if (outputModalities != null && outputModalities.isNotEmpty) {
    return outputModalities.contains('text') && !_notChat.hasMatch(id);
  }
  return !_notChat.hasMatch(id);
}

/// Purpose: Fetch a provider's model list.
/// Inputs: `client`; `provider`; `apiKey`; `path` — `models` by default,
/// `models?output_modalities=transcription` for OpenRouter transcription;
/// `timeout` — defaults to the provider's `requestTimeoutSeconds`.
/// Returns: Entries sorted by id, deduplicated.
/// Side effects: One HTTP GET to the provider's own endpoint.
/// Notes: Accepts `{"data": [...]}` (OpenAI, OpenRouter), `{"models": [...]}`
/// (Ollama's `/api/tags`) or a bare list, entries keyed by `id`, `name` or
/// `model`, as MyTranscribe's catalog fetcher; reads OpenRouter's `name`,
/// `context_length` and `architecture` modalities. Throws
/// [OnlineException]. Does not close `client`.
Future<List<OnlineModelEntry>> fetchOnlineModels(
  http.Client client,
  OnlineProvider provider, {
  String? apiKey,
  String path = 'models',
  Duration? timeout,
}) async {
  if (provider.baseUri == null) {
    throw OnlineException(
      OnlineErrorKind.rejected,
      'That address could not be read as a URL.',
    );
  }
  final uri = Uri.parse(provider.endpoint(path));
  final wait = timeout ?? Duration(seconds: provider.requestTimeoutSeconds);
  final http.Response response;
  try {
    response = await client
        .get(uri, headers: provider.requestHeaders(apiKey))
        .timeout(wait);
  } on Exception catch (error) {
    throw onlineTransportFailure(error, wait);
  }
  final body = utf8.decode(response.bodyBytes, allowMalformed: true);
  if (response.statusCode != 200) {
    throw onlineFailureForResponse(response.statusCode, response.headers, body);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw OnlineException(
      OnlineErrorKind.badResponse,
      'The source returned something that is not a model list.',
    );
  }
  final items = switch (decoded) {
    {'data': final List list} => list,
    {'models': final List list} => list,
    final List list => list,
    _ => throw OnlineException(
      OnlineErrorKind.badResponse,
      'The source returned something that is not a model list.',
    ),
  };
  final seen = <String>{};
  final entries = <OnlineModelEntry>[];
  for (final item in items) {
    if (item is! Map) continue;
    final id = item['id'] ?? item['name'] ?? item['model'];
    if (id is! String || id.trim().isEmpty || !seen.add(id)) continue;
    final name = item['name'];
    final architecture = item['architecture'];
    List<String> strings(Object? v) => [
      if (v is List)
        for (final s in v)
          if (s is String) s,
    ];
    final inputs = architecture is Map
        ? strings(architecture['input_modalities'])
        : strings(item['input_modalities']);
    final outputs = architecture is Map
        ? strings(architecture['output_modalities'])
        : strings(item['output_modalities']);
    final context = item['context_length'] ?? item['context_window'];
    entries.add(
      OnlineModelEntry(
        id,
        displayName: name is String && name != id ? name : null,
        contextTokens: context is int && context > 0 ? context : null,
        inputModalities: inputs,
        chat: isChatModel(id, outputModalities: outputs),
      ),
    );
  }
  entries.sort((a, b) => a.id.compareTo(b.id));
  return entries;
}

/// Purpose: Classify a transport-level error.
/// Inputs: `error`; `timeout` used, for the message.
/// Returns: [OnlineException] of kind timeout, cancelled or network.
/// Side effects: None.
/// Notes: Aborted requests map to cancelled.
OnlineException onlineTransportFailure(Object error, Duration timeout) {
  if (error is OnlineException) return error;
  if (error is http.RequestAbortedException) {
    return OnlineException(OnlineErrorKind.cancelled, 'cancelled');
  }
  if (error is TimeoutException) {
    return OnlineException(
      OnlineErrorKind.timeout,
      'The source did not answer within ${timeout.inSeconds} seconds.',
    );
  }
  return OnlineException(
    OnlineErrorKind.network,
    'The request could not be completed: $error',
  );
}
