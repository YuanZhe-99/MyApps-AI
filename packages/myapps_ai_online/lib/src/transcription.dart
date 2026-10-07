/// Online speech-to-text over the OpenAI `audio/transcriptions` protocol, with
/// the OpenAI, OpenRouter and OpenAI-compatible request shapes.
///
/// Extracted from MyTranscribe's transcription client, dialects and response
/// parsers; wire formats are unchanged. Application concerns (windows, jobs,
/// speaker unification) stay with the caller.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_support.dart';
import 'llm_backend.dart' show OnlineClientFactory;
import 'provider.dart';

/// The path every supported endpoint exposes.
const transcriptionPath = 'audio/transcriptions';

/// Whether a model can do something; unknown is a real answer.
///
/// Persisted names match MyTranscribe's `Capability`.
enum OnlineCapability {
  /// The model does this.
  supported,

  /// The model does not.
  unsupported,

  /// Nobody has established either way.
  unknown;

  /// Purpose: Parse a persisted name.
  /// Inputs: `value`. Returns: Capability; unrecognised reads as [unknown].
  /// Side effects: None. Notes: None.
  static OnlineCapability parse(Object? value) => OnlineCapability.values
      .firstWhere((c) => c.name == value, orElse: () => unknown);
}

/// How a model takes a language hint; names match MyTranscribe.
enum OnlineLanguageStyle {
  /// Repeated `languages[]` parts.
  languages,

  /// One `language` field.
  language,

  /// No hint.
  none,
}

/// The model facts that shape a transcription request.
///
/// A neutral subset of MyTranscribe's `ModelConfig`; limits used for window
/// planning stay with the application.
@immutable
class OnlineTranscriptionModel {
  /// Purpose: Describe a model.
  /// Inputs: `modelName` — sent as `model`; capability fields; `responseFormats`
  /// best first; `maxKnownSpeakers`; `requiresChunkingStrategy`.
  /// Returns: A value. Side effects: None.
  /// Notes: Defaults match MyTranscribe's `ModelConfig` defaults.
  const OnlineTranscriptionModel({
    required this.modelName,
    this.diarization = OnlineCapability.unknown,
    this.segmentTimestamps = OnlineCapability.unknown,
    this.supportsPrompt = false,
    this.supportsKeywords = false,
    this.languageStyle = OnlineLanguageStyle.language,
    this.responseFormats = const ['json'],
    this.maxKnownSpeakers,
    this.requiresChunkingStrategy = false,
  });

  /// Wire model id.
  final String modelName;

  /// Speaker labels.
  final OnlineCapability diarization;

  /// Per-segment times.
  final OnlineCapability segmentTimestamps;

  /// Whether free-text context is sent.
  final bool supportsPrompt;

  /// Whether keyword lists are sent.
  final bool supportsKeywords;

  /// Language hint style.
  final OnlineLanguageStyle languageStyle;

  /// Accepted reply formats, most preferred first.
  final List<String> responseFormats;

  /// Known speaker references accepted per request.
  final int? maxKnownSpeakers;

  /// Whether a diarizing request must send `chunking_strategy`.
  final bool requiresChunkingStrategy;

  /// Purpose: Pick a reply format.
  /// Inputs: `wanted`, best first.
  /// Returns: First accepted, else the model's first, else `json`.
  /// Side effects: None. Notes: Same as MyTranscribe.
  String chooseResponseFormat(List<String> wanted) {
    for (final f in wanted) {
      if (responseFormats.contains(f)) return f;
    }
    return responseFormats.isEmpty ? 'json' : responseFormats.first;
  }
}

/// A speaker whose voice sample the request carries.
@immutable
class OnlineKnownSpeaker {
  /// Purpose: Describe a reference. Inputs: `id` — label to send and expect;
  /// `samplePath` — short WAV clip. Returns: Value. Side effects: None.
  /// Notes: Sent only by the OpenAI dialect for diarized formats.
  const OnlineKnownSpeaker({required this.id, required this.samplePath});

  /// Label sent as `known_speaker_names[]`.
  final String id;

  /// Path of the WAV sample.
  final String samplePath;
}

/// One transcription request, before any endpoint shape is applied.
@immutable
class OnlineTranscriptionRequest {
  /// Purpose: Describe the audio to transcribe.
  /// Inputs: `audioPath`; `languages` most likely first; `prompt`;
  /// `keywords`; `diarize`; `wantTimestamps`; `knownSpeakers`.
  /// Returns: Value. Side effects: None.
  /// Notes: Content (audio, prompt, keywords) is never logged.
  const OnlineTranscriptionRequest({
    required this.audioPath,
    this.languages = const [],
    this.prompt,
    this.keywords = const [],
    this.diarize = false,
    this.wantTimestamps = true,
    this.knownSpeakers = const [],
  });

  /// Audio file path; its base name is sent as the upload filename.
  final String audioPath;

  /// Language hints.
  final List<String> languages;

  /// Optional context.
  final String? prompt;

  /// Terms to bias towards.
  final List<String> keywords;

  /// Whether to ask for speaker labels.
  final bool diarize;

  /// Whether to ask for per-segment times.
  final bool wantTimestamps;

  /// Voice references.
  final List<OnlineKnownSpeaker> knownSpeakers;
}

/// One piece of transcript.
@immutable
class OnlineTranscriptSegment {
  /// Purpose: Create a segment. Inputs: times in seconds, `text`, `speaker`.
  /// Returns: Value. Side effects: None.
  /// Notes: Speaker labels are request-local; integers become `S<n>`.
  const OnlineTranscriptSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    this.speaker,
  });

  /// Start within the uploaded audio.
  final double startSeconds;

  /// End within the uploaded audio.
  final double endSeconds;

  /// Text.
  final String text;

  /// Speaker label, or null.
  final String? speaker;
}

/// A transcription reply.
@immutable
class OnlineTranscriptionResult {
  /// Purpose: Create a result. Inputs: `text`, `segments`, flags.
  /// Returns: Value. Side effects: None.
  /// Notes: Text-only replies yield one segment spanning the audio with
  /// [hasRealTimestamps] false.
  const OnlineTranscriptionResult({
    required this.text,
    this.segments = const [],
    this.hasRealTimestamps = false,
    this.hasSpeakers = false,
  });

  /// Whole text.
  final String text;

  /// Segments.
  final List<OnlineTranscriptSegment> segments;

  /// Whether segment times came from the endpoint.
  final bool hasRealTimestamps;

  /// Whether any segment has a speaker.
  final bool hasSpeakers;
}

/// A feature a rejection named, so the caller can offer to retry without it.
enum OnlineRejectedFeature { diarization, keywords, timestamps, prompt }

/// A failed transcription request.
class OnlineTranscriptionException extends OnlineException {
  /// Purpose: Create a failure.
  /// Inputs: as [OnlineException], plus `rejectedFeature`.
  /// Returns: Exception. Side effects: None.
  /// Notes: `rejectedFeature` is a suggestion only; nothing is dropped
  /// automatically.
  OnlineTranscriptionException(
    super.kind,
    super.message, {
    super.statusCode,
    super.retryAfter,
    this.rejectedFeature,
  });

  /// Purpose: Wrap a generic online failure.
  /// Inputs: `e`, `rejectedFeature`. Returns: Exception. Side effects: None.
  /// Notes: None.
  factory OnlineTranscriptionException.from(
    OnlineException e, {
    OnlineRejectedFeature? rejectedFeature,
  }) => e is OnlineTranscriptionException
      ? e
      : OnlineTranscriptionException(
          e.kind,
          e.message ?? '',
          statusCode: e.statusCode,
          retryAfter: e.retryAfter,
          rejectedFeature: rejectedFeature,
        );

  /// The refused feature, when the message named one.
  final OnlineRejectedFeature? rejectedFeature;
}

/// Retry attempts after the first, as in MyTranscribe.
const maxTranscriptionRetries = 2;

/// Delays before each retry, as in MyTranscribe.
const transcriptionRetryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

/// Sends transcription requests to configured providers.
class OnlineTranscriptionClient {
  /// Purpose: Create a client.
  /// Inputs: `clientFactory`; `sleep` between retries (injectable for tests);
  /// `maxRetries`.
  /// Returns: A client. Side effects: None.
  /// Notes: Requests go only to the given provider's base URL.
  OnlineTranscriptionClient({
    OnlineClientFactory? clientFactory,
    Future<void> Function(Duration)? sleep,
    this.maxRetries = maxTranscriptionRetries,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _sleep = sleep ?? Future<void>.delayed;

  final OnlineClientFactory _clientFactory;
  final Future<void> Function(Duration) _sleep;

  /// Retry attempts after the first.
  final int maxRetries;

  http.Client? _inFlight;
  Completer<void>? _abort;
  bool _cancelled = false;

  /// Purpose: Transcribe one audio file.
  /// Inputs: `request`; `provider`; `model`; `apiKey` (null for no-auth
  /// providers); `audioSeconds` — duration covered, for text-only replies.
  /// Returns: [OnlineTranscriptionResult].
  /// Side effects: One or more HTTP requests; reads the audio file.
  /// Notes: Retries network, timeout, 5xx and 429 failures up to
  /// [maxRetries], honouring a capped `Retry-After`. Throws
  /// [OnlineTranscriptionException]; after [cancel] it throws kind
  /// `cancelled` and does not retry.
  Future<OnlineTranscriptionResult> transcribe({
    required OnlineTranscriptionRequest request,
    required OnlineProvider provider,
    required OnlineTranscriptionModel model,
    required String? apiKey,
    required double audioSeconds,
  }) async {
    _cancelled = false;
    OnlineTranscriptionException? last;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final i = (attempt - 1).clamp(0, transcriptionRetryDelays.length - 1);
        await _sleep(last?.retryAfter ?? transcriptionRetryDelays[i]);
        if (_cancelled) throw _cancelledFailure();
      }
      try {
        return await _send(request, provider, model, apiKey, audioSeconds);
      } on OnlineTranscriptionException catch (e) {
        if (_cancelled) throw _cancelledFailure();
        if (!e.isRetryable) rethrow;
        last = e;
      }
    }
    throw last ??
        OnlineTranscriptionException(
          OnlineErrorKind.network,
          'The request could not be completed.',
        );
  }

  /// Purpose: Abort the request in flight.
  /// Inputs: None. Returns: None.
  /// Side effects: Fires the abort trigger and closes the HTTP client.
  /// Notes: The pending [transcribe] fails with kind `cancelled`.
  void cancel() {
    _cancelled = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _inFlight?.close();
    _inFlight = null;
  }

  /// Purpose: Make one attempt.
  /// Inputs: as [transcribe]. Returns: Result. Side effects: One request.
  /// Notes: Internal.
  Future<OnlineTranscriptionResult> _send(
    OnlineTranscriptionRequest request,
    OnlineProvider provider,
    OnlineTranscriptionModel model,
    String? apiKey,
    double audioSeconds,
  ) async {
    final client = _clientFactory();
    final abort = Completer<void>();
    _inFlight = client;
    _abort = abort;
    final timeout = Duration(seconds: provider.requestTimeoutSeconds);
    try {
      if (provider.baseUri == null) {
        throw OnlineTranscriptionException(
          OnlineErrorKind.rejected,
          'That address could not be read as a URL.',
        );
      }
      final built = await buildTranscriptionRequest(
        request,
        provider,
        model,
        apiKey,
        abortTrigger: abort.future,
      );
      final streamed = await client.send(built).timeout(timeout);
      final body = utf8.decode(
        await streamed.stream.toBytes(),
        allowMalformed: true,
      );
      if (streamed.statusCode != 200) {
        final e = onlineFailureForResponse(
          streamed.statusCode,
          streamed.headers,
          body,
        );
        throw OnlineTranscriptionException.from(
          e,
          rejectedFeature: e.kind == OnlineErrorKind.rejected
              ? _rejectedFeature(e.message ?? '', request)
              : null,
        );
      }
      return parseTranscriptionBody(body, audioSeconds);
    } on OnlineTranscriptionException {
      rethrow;
    } on OnlineException catch (e) {
      throw OnlineTranscriptionException.from(e);
    } catch (e) {
      if (_cancelled) throw _cancelledFailure();
      throw OnlineTranscriptionException.from(
        onlineTransportFailure(e, timeout),
      );
    } finally {
      if (identical(_inFlight, client)) _inFlight = null;
      if (identical(_abort, abort)) _abort = null;
      client.close();
    }
  }

  /// Purpose: Build the cancellation failure.
  /// Inputs: None. Returns: Exception. Side effects: None. Notes: Internal.
  OnlineTranscriptionException _cancelledFailure() =>
      OnlineTranscriptionException(OnlineErrorKind.cancelled, 'cancelled');
}

/// Purpose: Choose the reply format for a request.
/// Inputs: `dialect`, `request`, `model`.
/// Returns: Format name.
/// Side effects: None.
/// Notes: OpenAI: `diarized_json` when diarizing a model not known to lack
/// it, `verbose_json` when times are wanted and supported. OpenRouter:
/// `verbose_json` when diarizing or when times are not known unsupported.
/// Compatible: `verbose_json` only when times are known supported.
String transcriptionResponseFormat(
  OnlineDialect dialect,
  OnlineTranscriptionRequest request,
  OnlineTranscriptionModel model,
) {
  switch (dialect) {
    case OnlineDialect.openai:
      if (request.diarize &&
          model.diarization != OnlineCapability.unsupported) {
        return model.chooseResponseFormat(const ['diarized_json', 'json']);
      }
      if (request.wantTimestamps &&
          model.segmentTimestamps == OnlineCapability.supported) {
        return model.chooseResponseFormat(const ['verbose_json', 'json']);
      }
      return model.chooseResponseFormat(const ['json']);
    case OnlineDialect.openrouter:
      final detail =
          request.diarize ||
          (request.wantTimestamps &&
              model.segmentTimestamps != OnlineCapability.unsupported);
      return detail
          ? model.chooseResponseFormat(const ['verbose_json', 'json'])
          : model.chooseResponseFormat(const ['json']);
    case OnlineDialect.openaiCompatible:
      if (request.wantTimestamps &&
          model.segmentTimestamps == OnlineCapability.supported) {
        return model.chooseResponseFormat(const ['verbose_json', 'json']);
      }
      return model.chooseResponseFormat(const ['json']);
  }
}

/// Purpose: Say whether a request travels as JSON (base64 audio).
/// Inputs: `dialect`, `request`, `model`.
/// Returns: `bool`.
/// Side effects: None.
/// Notes: Only OpenRouter, when speaker labels or keywords are requested;
/// planners use it to shrink the byte budget.
bool transcriptionNeedsJsonBody(
  OnlineDialect dialect,
  OnlineTranscriptionRequest request,
  OnlineTranscriptionModel model,
) =>
    dialect == OnlineDialect.openrouter &&
    ((request.diarize && model.diarization != OnlineCapability.unsupported) ||
        (model.supportsKeywords && request.keywords.isNotEmpty));

/// Purpose: Build the HTTP request for one transcription.
/// Inputs: `request`, `provider`, `model`, `apiKey`, optional `abortTrigger`.
/// Returns: A multipart or JSON request to `<baseUrl>/audio/transcriptions`.
/// Side effects: Opens the audio file (streamed for multipart, read fully for
/// JSON) and reads speaker samples.
/// Notes: Byte-for-byte the MyTranscribe dialect shapes: repeated
/// `languages[]`/`keywords[]` parts, `chunking_strategy=auto`, speaker data
/// URLs, `timestamp_granularities[]=segment`, OpenRouter `input_audio` and
/// `provider.options.azure`. OpenRouter never receives a prompt.
Future<http.BaseRequest> buildTranscriptionRequest(
  OnlineTranscriptionRequest request,
  OnlineProvider provider,
  OnlineTranscriptionModel model,
  String? apiKey, {
  Future<void>? abortTrigger,
}) async {
  final uri = Uri.parse(provider.endpoint(transcriptionPath));
  final headers = provider.requestHeaders(apiKey);
  final format = transcriptionResponseFormat(provider.dialect, request, model);
  final fileName = _fileName(request.audioPath);

  if (transcriptionNeedsJsonBody(provider.dialect, request, model)) {
    final options = <String, Object?>{
      if (request.diarize && model.diarization != OnlineCapability.unsupported)
        'diarization': {'enabled': true},
      if (model.supportsKeywords && request.keywords.isNotEmpty)
        'phraseList': {'phrases': request.keywords},
    };
    final body = <String, Object?>{
      'model': model.modelName,
      'input_audio': {
        'data': base64Encode(await File(request.audioPath).readAsBytes()),
        'format': audioFormatForPath(request.audioPath),
      },
      'response_format': format,
      if (request.languages.isNotEmpty) 'language': request.languages.first,
      if (format == 'verbose_json') 'timestamp_granularities': ['segment'],
      if (options.isNotEmpty)
        'provider': {
          'options': {'azure': options},
        },
    };
    return http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
      ..headers.addAll({...headers, 'Content-Type': 'application/json'})
      ..bodyBytes = utf8.encode(jsonEncode(body));
  }

  final multipart =
      http.AbortableMultipartRequest('POST', uri, abortTrigger: abortTrigger)
        ..headers.addAll(headers)
        ..fields['model'] = model.modelName
        ..fields['response_format'] = format;

  switch (provider.dialect) {
    case OnlineDialect.openai:
      if (model.supportsPrompt && (request.prompt?.isNotEmpty ?? false)) {
        multipart.fields['prompt'] = request.prompt!;
      }
      if (model.supportsKeywords) {
        for (final k in request.keywords) {
          multipart.files.add(http.MultipartFile.fromString('keywords[]', k));
        }
      }
      _addLanguage(multipart, request, model);
      if (format == 'diarized_json') {
        if (model.requiresChunkingStrategy) {
          multipart.fields['chunking_strategy'] = 'auto';
        }
        for (final s in request.knownSpeakers.take(
          model.maxKnownSpeakers ?? 0,
        )) {
          // A map holds one value per name, so — as in MyTranscribe — only
          // the last reference survives; kept for wire compatibility.
          multipart.fields['known_speaker_names[]'] = s.id;
          final bytes = await File(s.samplePath).readAsBytes();
          multipart.fields['known_speaker_references[]'] =
              'data:audio/wav;base64,${base64Encode(bytes)}';
        }
      } else if (request.wantTimestamps &&
          model.segmentTimestamps == OnlineCapability.supported &&
          format == 'verbose_json') {
        multipart.fields['timestamp_granularities[]'] = 'segment';
      }
    case OnlineDialect.openrouter:
      if (request.languages.isNotEmpty) {
        multipart.fields['language'] = request.languages.first;
      }
      if (format == 'verbose_json') {
        multipart.fields['timestamp_granularities[]'] = 'segment';
      }
    case OnlineDialect.openaiCompatible:
      if (model.supportsPrompt && (request.prompt?.isNotEmpty ?? false)) {
        multipart.fields['prompt'] = request.prompt!;
      }
      _addLanguage(multipart, request, model);
  }

  multipart.files.add(
    await http.MultipartFile.fromPath(
      'file',
      request.audioPath,
      filename: fileName,
    ),
  );
  return multipart;
}

/// Purpose: Parse a transcription reply.
/// Inputs: `body`; `audioSeconds` for text-only replies.
/// Returns: Result.
/// Side effects: None.
/// Notes: Same rules as MyTranscribe's `parseTranscriptionBody`: plain text
/// becomes one segment; a JSON object is read whatever format was asked;
/// `segments[].speaker` strings are kept, numbers become `S<n>`; empty or
/// unreadable replies throw kind `badResponse`.
OnlineTranscriptionResult parseTranscriptionBody(
  String body,
  double audioSeconds,
) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw OnlineTranscriptionException(
      OnlineErrorKind.badResponse,
      'The source returned an empty reply.',
    );
  }
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return OnlineTranscriptionResult(
      text: trimmed,
      segments: [
        OnlineTranscriptSegment(
          startSeconds: 0,
          endSeconds: audioSeconds,
          text: trimmed,
        ),
      ],
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException catch (e) {
    throw OnlineTranscriptionException(
      OnlineErrorKind.badResponse,
      'The reply could not be read: ${e.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw OnlineTranscriptionException(
      OnlineErrorKind.badResponse,
      'The reply was not a transcription object.',
    );
  }
  final segments = <OnlineTranscriptSegment>[];
  if (decoded['segments'] case final List raw) {
    for (final item in raw) {
      if (item is! Map) continue;
      final text = item['text'];
      if (text is! String || text.trim().isEmpty) continue;
      final start = _toDouble(item['start']);
      segments.add(
        OnlineTranscriptSegment(
          startSeconds: start ?? 0,
          endSeconds: _toDouble(item['end']) ?? start ?? 0,
          text: text.trim(),
          speaker: _readSpeaker(item['speaker']),
        ),
      );
    }
  }
  final top = decoded['text'];
  final text = top is String && top.trim().isNotEmpty
      ? top.trim()
      : segments.map((s) => s.text).join(' ').trim();
  if (segments.isEmpty) {
    if (text.isEmpty) {
      throw OnlineTranscriptionException(
        OnlineErrorKind.badResponse,
        'The reply carried no transcript.',
      );
    }
    return OnlineTranscriptionResult(
      text: text,
      segments: [
        OnlineTranscriptSegment(
          startSeconds: 0,
          endSeconds: audioSeconds,
          text: text,
        ),
      ],
    );
  }
  return OnlineTranscriptionResult(
    text: text,
    segments: segments,
    hasRealTimestamps: true,
    hasSpeakers: segments.any((s) => s.speaker != null),
  );
}

/// Purpose: Name the audio format for a JSON body.
/// Inputs: `path`. Returns: Short format name. Side effects: None.
/// Notes: Same table as MyTranscribe.
String audioFormatForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mpga' || 'mpeg' => 'mp3',
    'oga' => 'ogg',
    _ => ext.isEmpty ? 'mp3' : ext,
  };
}

/// Purpose: Guess an audio media type from a file extension.
/// Inputs: `path`. Returns: Media type, default `application/octet-stream`.
/// Side effects: None. Notes: Same table as MyTranscribe.
String audioMimeTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp3' || 'mpga' || 'mpeg' => 'audio/mpeg',
    'm4a' || 'mp4' => 'audio/mp4',
    'wav' => 'audio/wav',
    'webm' => 'audio/webm',
    'flac' => 'audio/flac',
    'ogg' || 'oga' => 'audio/ogg',
    'aac' => 'audio/aac',
    _ => 'application/octet-stream',
  };
}

/// Purpose: Add the language hint in the model's style.
/// Inputs: `multipart`, `request`, `model`. Returns: None.
/// Side effects: Adds fields or parts. Notes: Internal.
void _addLanguage(
  http.MultipartRequest multipart,
  OnlineTranscriptionRequest request,
  OnlineTranscriptionModel model,
) {
  if (request.languages.isEmpty) return;
  switch (model.languageStyle) {
    case OnlineLanguageStyle.languages:
      for (final l in request.languages) {
        multipart.files.add(http.MultipartFile.fromString('languages[]', l));
      }
    case OnlineLanguageStyle.language:
      multipart.fields['language'] = request.languages.first;
    case OnlineLanguageStyle.none:
      break;
  }
}

/// Purpose: Guess which feature a rejection named.
/// Inputs: server `message`, `request`. Returns: Feature or null.
/// Side effects: None. Notes: Same heuristics as MyTranscribe.
OnlineRejectedFeature? _rejectedFeature(
  String message,
  OnlineTranscriptionRequest request,
) {
  final lower = message.toLowerCase();
  if (request.diarize &&
      (lower.contains('diariz') ||
          lower.contains('speaker') ||
          lower.contains('chunking_strategy'))) {
    return OnlineRejectedFeature.diarization;
  }
  if (request.keywords.isNotEmpty && lower.contains('keyword')) {
    return OnlineRejectedFeature.keywords;
  }
  if (lower.contains('timestamp') || lower.contains('verbose_json')) {
    return OnlineRejectedFeature.timestamps;
  }
  if ((request.prompt?.isNotEmpty ?? false) && lower.contains('prompt')) {
    return OnlineRejectedFeature.prompt;
  }
  return null;
}

/// Purpose: Base name of a path. Inputs: `path`. Returns: Name.
/// Side effects: None. Notes: Handles `\` separators.
String _fileName(String path) {
  final p = path.replaceAll('\\', '/');
  final slash = p.lastIndexOf('/');
  return slash < 0 ? p : p.substring(slash + 1);
}

/// Purpose: Normalize a speaker label. Inputs: `value`.
/// Returns: Label or null. Side effects: None. Notes: Numbers → `S<n>`.
String? _readSpeaker(Object? value) => switch (value) {
  final String s when s.trim().isNotEmpty => s.trim(),
  final int n => 'S$n',
  final num n => 'S${n.round()}',
  _ => null,
};

/// Purpose: Read a number possibly sent as a string. Inputs: `value`.
/// Returns: double or null. Side effects: None. Notes: Internal.
double? _toDouble(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
