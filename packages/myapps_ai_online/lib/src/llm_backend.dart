/// An [LlmBackend] for OpenAI-compatible `/chat/completions` endpoints with
/// server-sent-event streaming.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';

import 'http_support.dart';
import 'provider.dart';

/// Purpose: Build the HTTP client for one request.
/// Inputs: None. Returns: A client the backend closes after use.
/// Side effects: None until used.
/// Notes: Injected for tests; the default is [http.Client.new].
typedef OnlineClientFactory = http.Client Function();

/// Streams chat completions from one configured [OnlineProvider].
class OpenAiCompatibleLlmBackend implements LlmBackend {
  /// Purpose: Create a backend for one provider.
  /// Inputs: `provider` — endpoint, model and headers; `readSecret` — reads
  /// the provider's key; `clientFactory`; `requestTimeout` — wait for response
  /// headers, default the provider's `requestTimeoutSeconds`; `idleTimeout` —
  /// longest silence between streamed chunks; `testConnectionPath` — GET path
  /// for [testConnection].
  /// Returns: A backend.
  /// Side effects: None; nothing is sent until [generate] or [testConnection].
  /// Notes: Requests go only to `provider`'s base URL and never follow
  /// redirects, so content cannot be forwarded to another host.
  OpenAiCompatibleLlmBackend({
    required this.provider,
    required this.readSecret,
    OnlineClientFactory? clientFactory,
    Duration? requestTimeout,
    this.idleTimeout = const Duration(seconds: 60),
    this.testConnectionPath = 'models',
  }) : _clientFactory = clientFactory ?? http.Client.new,
       requestTimeout =
           requestTimeout ?? Duration(seconds: provider.requestTimeoutSeconds);

  /// The provider this backend talks to.
  final OnlineProvider provider;

  /// Wait for response headers.
  final Duration requestTimeout;

  /// Longest silence tolerated between streamed chunks.
  final Duration idleTimeout;

  /// GET path used by [testConnection].
  final String testConnectionPath;

  /// Reads the provider's API key.
  final OnlineSecretReader readSecret;
  final OnlineClientFactory _clientFactory;

  _Run? _active;

  /// Last transport failure, reported by [status] until the next success.
  OnlineException? _lastTransportFailure;

  /// Purpose: Identify the backend.
  /// Inputs: None. Returns: `online:<providerId>`. Side effects: None.
  /// Notes: Equals the source id from [onlineSourceId].
  @override
  String get id => onlineSourceId(provider.id);

  /// Purpose: Declare abilities.
  /// Inputs: None. Returns: `{streaming}`. Side effects: None.
  /// Notes: Tools, vision and structured output are not implemented.
  @override
  Set<LlmAbility> get abilities => const {LlmAbility.streaming};

  /// Purpose: Report readiness from configuration only.
  /// Inputs: None.
  /// Returns: `available` when endpoint, model and (if needed) key are set;
  /// `unavailable` with detail `needsConfiguration:<gaps>` otherwise;
  /// `unreachable` with detail `network` after a transport failure until the
  /// next successful request.
  /// Side effects: Reads the secret through the injected reader. Never sends
  /// a network request.
  /// Notes: Never throws; a failing secret reader reports
  /// `unavailable`/`secret`.
  @override
  Future<GenAiStatusReport> status() async {
    final String? key;
    try {
      key = await readSecret(provider.id);
    } catch (_) {
      return const GenAiStatusReport(GenAiStatus.unavailable, detail: 'secret');
    }
    final gaps = provider.configurationGaps(key);
    if (gaps.isNotEmpty) {
      return GenAiStatusReport(
        GenAiStatus.unavailable,
        detail: needsConfigurationDetail(gaps),
      );
    }
    if (_lastTransportFailure != null) {
      return GenAiStatusReport(
        GenAiStatus.unreachable,
        detail: 'network',
        baseModelName: provider.modelId,
      );
    }
    return GenAiStatusReport(
      GenAiStatus.available,
      baseModelName: provider.modelId,
    );
  }

  /// Purpose: Check that configuration is complete.
  /// Inputs: None. Returns: None.
  /// Side effects: Reads the secret; no network.
  /// Notes: Throws [GenAiException] `unavailable` when unconfigured; there is
  /// nothing to load for a remote model.
  @override
  Future<void> load() async {
    final gaps = provider.configurationGaps(await readSecret(provider.id));
    if (gaps.isNotEmpty) {
      throw GenAiException(
        GenAiFailure.unavailable,
        needsConfigurationDetail(gaps),
      );
    }
  }

  /// Purpose: Release resources.
  /// Inputs: None. Returns: None. Side effects: Cancels running work.
  /// Notes: Idempotent.
  @override
  Future<void> unload() => cancel();

  /// Purpose: Explicitly test the connection, for a user-tapped "test".
  /// Inputs: None.
  /// Returns: `available` (detail `models:<count>`, plus `,modelListed` /
  /// `,modelMissing` when a model is configured); `unavailable` with detail
  /// `needsConfiguration:…`, `auth`, `quota` or `http`; `unreachable` with
  /// detail `network` or `timeout`. `code` carries the HTTP status.
  /// Side effects: One GET to the provider's [testConnectionPath]; sends the
  /// key but no user content.
  /// Notes: Never throws. A public model list (OpenRouter) does not prove the
  /// key is valid. Never called by [status].
  Future<GenAiStatusReport> testConnection() async {
    final String? key;
    try {
      key = await readSecret(provider.id);
    } catch (_) {
      return const GenAiStatusReport(GenAiStatus.unavailable, detail: 'secret');
    }
    final gaps = provider.configurationGaps(key, requireModel: false);
    if (gaps.isNotEmpty) {
      return GenAiStatusReport(
        GenAiStatus.unavailable,
        detail: needsConfigurationDetail(gaps),
      );
    }
    final client = _clientFactory();
    try {
      final models = await fetchOnlineModels(
        client,
        provider,
        apiKey: key,
        path: testConnectionPath,
        timeout: requestTimeout,
      );
      _lastTransportFailure = null;
      final model = provider.modelId;
      final listed = model == null
          ? ''
          : models.any((m) => m.id == model)
          ? ',modelListed'
          : ',modelMissing';
      return GenAiStatusReport(
        GenAiStatus.available,
        code: 200,
        detail: 'models:${models.length}$listed',
        baseModelName: model,
      );
    } on OnlineException catch (e) {
      return _reportFor(e);
    } finally {
      client.close();
    }
  }

  /// Purpose: Stream a chat completion.
  /// Inputs: `request` — messages and sampling.
  /// Returns: [LlmDelta] events then one [LlmDone] with `device: remote`.
  /// Side effects: One POST to `<baseUrl>/chat/completions` once listened to.
  /// Notes: Unconfigured providers fail with `unavailable` before any request.
  /// A second concurrent request fails with `busy`. Cancelling the
  /// subscription aborts the request silently; [cancel] ends the stream with
  /// [LlmFinish.cancelled]. Errors arrive as [OnlineException] (a
  /// [GenAiException]) whose message starts with [OnlineException.detail],
  /// e.g. `auth: …`. Content is never logged.
  @override
  Stream<LlmEvent> generate(LlmRequest request) {
    late final StreamController<LlmEvent> controller;
    _Run? run;
    controller = StreamController<LlmEvent>(
      onListen: () {
        if (_active != null) {
          controller
            ..addError(
              const GenAiException(GenAiFailure.busy, 'request in flight'),
            )
            ..close();
          return;
        }
        run = _Run(_clientFactory());
        _active = run;
        unawaited(_execute(run!, request, controller));
      },
      onCancel: () async {
        final r = run;
        if (r == null) return;
        r.abort(emitDone: false);
        await r.exited.future;
      },
    );
    return controller.stream;
  }

  /// Purpose: Stop running generation.
  /// Inputs: None.
  /// Returns: Completes after the request has been torn down.
  /// Side effects: Aborts the HTTP request and closes its client; the stream
  /// ends with `LlmDone(cancelled)`.
  /// Notes: Safe when idle.
  @override
  Future<void> cancel() async {
    final run = _active;
    if (run == null) return;
    run.abort(emitDone: true);
    await run.exited.future;
  }

  /// Purpose: Run one request into `controller`.
  /// Inputs: `run`, `request`, `controller`.
  /// Returns: Completes when the run has exited.
  /// Side effects: Network I/O; closes `controller` and the run's client.
  /// Notes: Internal.
  Future<void> _execute(
    _Run run,
    LlmRequest request,
    StreamController<LlmEvent> controller,
  ) async {
    final started = DateTime.now();
    try {
      final String? key;
      try {
        key = await readSecret(provider.id);
      } catch (_) {
        // The reader's error is not forwarded: it may describe the secret.
        throw const GenAiException(GenAiFailure.unavailable, 'secret');
      }
      final gaps = provider.configurationGaps(key);
      if (gaps.isNotEmpty) {
        throw GenAiException(
          GenAiFailure.unavailable,
          needsConfigurationDetail(gaps),
        );
      }
      if (run.cancelled) throw const _Cancelled();
      final http.StreamedResponse response;
      try {
        response = await Future.any([
          run.client.send(_buildRequest(request, key, run)),
          run.aborted.future.then<http.StreamedResponse>(
            (_) => throw const _Cancelled(),
          ),
        ]).timeout(requestTimeout);
      } on _Cancelled {
        rethrow;
      } on Exception catch (e) {
        if (run.cancelled) throw const _Cancelled();
        throw onlineTransportFailure(e, requestTimeout);
      }
      if (run.cancelled) throw const _Cancelled();
      if (response.statusCode != 200) {
        final body = await _readBody(response, run);
        throw onlineFailureForResponse(
          response.statusCode,
          response.headers,
          body,
        );
      }
      final contentType = response.headers['content-type'] ?? '';
      final _Outcome outcome;
      if (contentType.contains('application/json')) {
        outcome = _parseWhole(await _readBody(response, run), controller);
      } else {
        outcome = await _consumeSse(response, run, controller, started);
      }
      _lastTransportFailure = null;
      final finished = DateTime.now();
      controller.add(
        LlmDone(
          outcome.finish,
          LlmMetrics(
            device: 'remote',
            promptTokens: outcome.promptTokens,
            outputTokens: outcome.outputTokens,
            firstToken: run.firstToken?.difference(started),
            total: finished.difference(started),
          ),
        ),
      );
    } on _Cancelled {
      if (run.emitDone) {
        controller.add(
          LlmDone(
            LlmFinish.cancelled,
            LlmMetrics(
              device: 'remote',
              firstToken: run.firstToken?.difference(started),
              total: DateTime.now().difference(started),
            ),
          ),
        );
      }
    } on OnlineException catch (e) {
      if (run.cancelled) {
        if (run.emitDone) {
          controller.add(
            const LlmDone(LlmFinish.cancelled, LlmMetrics(device: 'remote')),
          );
        }
      } else {
        if (e.kind == OnlineErrorKind.network ||
            e.kind == OnlineErrorKind.timeout) {
          _lastTransportFailure = e;
        }
        controller.addError(
          OnlineException(
            e.kind,
            '${e.detail}: ${e.message}',
            statusCode: e.statusCode,
            retryAfter: e.retryAfter,
          ),
        );
      }
    } on GenAiException catch (e) {
      controller.addError(e);
    } catch (e) {
      controller.addError(GenAiException(GenAiFailure.failed, '$e'));
    } finally {
      run.client.close();
      if (identical(_active, run)) _active = null;
      if (!run.exited.isCompleted) run.exited.complete();
      if (!controller.isClosed) unawaited(controller.close());
    }
  }

  /// Purpose: Build the POST request.
  /// Inputs: `request`, `key`, `run` for the abort trigger.
  /// Returns: An abortable request that does not follow redirects.
  /// Side effects: None.
  /// Notes: OpenAI uses `max_completion_tokens`; other dialects `max_tokens`.
  /// `stream_options.include_usage` is sent only to OpenAI and OpenRouter,
  /// which document it; strict compatible servers may reject unknown fields.
  /// `topK` is not part of the protocol and is not sent.
  http.BaseRequest _buildRequest(LlmRequest request, String? key, _Run run) {
    final s = request.sampling;
    final body = <String, Object?>{
      'model': provider.modelId,
      'messages': [for (final m in request.messages) m.toJson()],
      'stream': true,
      if (provider.dialect != OnlineDialect.openaiCompatible)
        'stream_options': {'include_usage': true},
      provider.dialect == OnlineDialect.openai
              ? 'max_completion_tokens'
              : 'max_tokens':
          s.maxOutputTokens,
      'temperature': s.temperature,
      if (s.topP != null) 'top_p': s.topP,
      if (s.seed != null) 'seed': s.seed,
      if (s.stop.isNotEmpty) 'stop': s.stop,
    };
    return http.AbortableRequest(
        'POST',
        Uri.parse(provider.endpoint('chat/completions')),
        abortTrigger: run.aborted.future,
      )
      ..followRedirects = false
      ..headers.addAll({
        ...provider.requestHeaders(key),
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..bodyBytes = utf8.encode(jsonEncode(body));
  }

  /// Purpose: Read a whole response body.
  /// Inputs: `response`, `run`.
  /// Returns: Decoded text.
  /// Side effects: Drains the response.
  /// Notes: Bounded by [idleTimeout]; aborts on cancel.
  Future<String> _readBody(http.StreamedResponse response, _Run run) async {
    try {
      final bytes = await Future.any([
        response.stream.toBytes().timeout(idleTimeout),
        run.aborted.future.then<List<int>>((_) => throw const _Cancelled()),
      ]);
      return utf8.decode(bytes, allowMalformed: true);
    } on _Cancelled {
      rethrow;
    } on Exception catch (e) {
      if (run.cancelled) throw const _Cancelled();
      throw onlineTransportFailure(e, idleTimeout);
    }
  }

  /// Purpose: Parse a non-streamed reply from a server that ignored `stream`.
  /// Inputs: `body`, `controller`.
  /// Returns: The outcome. Side effects: Adds one delta.
  /// Notes: Throws `badResponse` when the body is not a completion.
  _Outcome _parseWhole(String body, StreamController<LlmEvent> controller) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw OnlineException(OnlineErrorKind.badResponse, 'not JSON');
    }
    if (json is! Map) {
      throw OnlineException(OnlineErrorKind.badResponse, 'not a completion');
    }
    _throwIfError(json);
    final choice = _firstChoice(json);
    final message = choice?['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String) {
      throw OnlineException(OnlineErrorKind.badResponse, 'no message content');
    }
    if (content.isNotEmpty) controller.add(LlmDelta(content));
    final usage = _usage(json);
    return _Outcome(
      _finishFor(choice?['finish_reason']) ?? LlmFinish.stop,
      promptTokens: usage.$1,
      outputTokens: usage.$2,
    );
  }

  /// Purpose: Consume an SSE stream.
  /// Inputs: `response`, `run`, `controller`, `started`.
  /// Returns: The outcome once `[DONE]` arrives or the stream ends after a
  /// finish reason.
  /// Side effects: Adds deltas; records first-token time on `run`.
  /// Notes: `data:` lines of one event are joined with newlines; comment
  /// lines (`:`) are ignored; an `error` object in an event fails the stream;
  /// a stream ending with neither `[DONE]` nor a finish reason fails as
  /// `network`.
  Future<_Outcome> _consumeSse(
    http.StreamedResponse response,
    _Run run,
    StreamController<LlmEvent> controller,
    DateTime started,
  ) {
    final done = Completer<_Outcome>();
    final data = <String>[];
    LlmFinish? finish;
    int? promptTokens;
    int? outputTokens;

    void complete(_Outcome o) {
      if (!done.isCompleted) done.complete(o);
    }

    void fail(Object e) {
      if (!done.isCompleted) done.completeError(e);
    }

    void dispatch() {
      if (data.isEmpty) return;
      final payload = data.join('\n');
      data.clear();
      if (payload.trim() == '[DONE]') {
        complete(
          _Outcome(
            finish ?? LlmFinish.stop,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
          ),
        );
        return;
      }
      final Object? json;
      try {
        json = jsonDecode(payload);
      } on FormatException {
        fail(OnlineException(OnlineErrorKind.badResponse, 'unreadable event'));
        return;
      }
      if (json is! Map) return;
      try {
        _throwIfError(json);
      } on OnlineException catch (e) {
        fail(e);
        return;
      }
      final usage = _usage(json);
      promptTokens = usage.$1 ?? promptTokens;
      outputTokens = usage.$2 ?? outputTokens;
      final choice = _firstChoice(json);
      if (choice == null) return;
      final delta = choice['delta'];
      final content = delta is Map ? delta['content'] : null;
      if (content is String && content.isNotEmpty) {
        run.firstToken ??= DateTime.now();
        controller.add(LlmDelta(content));
      }
      finish = _finishFor(choice['finish_reason']) ?? finish;
    }

    run.subscription = response.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(idleTimeout)
        .listen(
          (line) {
            if (done.isCompleted) return;
            if (line.isEmpty) {
              dispatch();
            } else if (line.startsWith('data:')) {
              final v = line.substring(5);
              data.add(v.startsWith(' ') ? v.substring(1) : v);
            }
            // Comments (`:`) and `event:`/`id:`/`retry:` fields are ignored.
          },
          onError: (Object e) {
            if (run.cancelled) {
              fail(const _Cancelled());
            } else {
              fail(onlineTransportFailure(e, idleTimeout));
            }
          },
          onDone: () {
            dispatch();
            if (done.isCompleted) return;
            if (run.cancelled) return fail(const _Cancelled());
            final f = finish;
            if (f != null) {
              complete(
                _Outcome(
                  f,
                  promptTokens: promptTokens,
                  outputTokens: outputTokens,
                ),
              );
            } else {
              fail(
                OnlineException(OnlineErrorKind.network, 'stream ended early'),
              );
            }
          },
          cancelOnError: true,
        );
    run.onAbort = () => fail(const _Cancelled());
    return done.future.whenComplete(() => run.subscription?.cancel());
  }

  /// Purpose: Convert a test-connection failure into a status report.
  /// Inputs: `e`. Returns: Report. Side effects: Records transport failures.
  /// Notes: Internal.
  GenAiStatusReport _reportFor(OnlineException e) {
    final code = e.statusCode ?? -1;
    switch (e.kind) {
      case OnlineErrorKind.network:
      case OnlineErrorKind.timeout:
        _lastTransportFailure = e;
        return GenAiStatusReport(
          GenAiStatus.unreachable,
          code: code,
          detail: e.kind == OnlineErrorKind.timeout ? 'timeout' : 'network',
        );
      case OnlineErrorKind.unauthorized:
        return GenAiStatusReport(
          GenAiStatus.unavailable,
          code: code,
          detail: 'auth',
        );
      case OnlineErrorKind.rateLimited:
        return GenAiStatusReport(
          GenAiStatus.unavailable,
          code: code,
          detail: 'quota',
        );
      default:
        _lastTransportFailure = null;
        return GenAiStatusReport(
          GenAiStatus.unavailable,
          code: code,
          detail: 'http',
        );
    }
  }
}

/// Purpose: Format configuration gaps for a status detail.
/// Inputs: `gaps`.
/// Returns: `needsConfiguration:endpoint,model,apiKey` (present gaps only).
/// Side effects: None.
/// Notes: Settings maps this to [AiSourceReadiness.needsConfiguration].
String needsConfigurationDetail(Set<OnlineConfigurationGap> gaps) =>
    'needsConfiguration:${[for (final g in OnlineConfigurationGap.values)
      if (gaps.contains(g)) g.name].join(',')}';

/// Purpose: Throw when a payload is an error object.
/// Inputs: `json`. Returns: None. Side effects: None.
/// Notes: Mid-stream errors (OpenRouter) carry an `error` object.
void _throwIfError(Map<Object?, Object?> json) {
  final error = json['error'];
  if (error == null) return;
  final code = error is Map ? error['code'] : null;
  final message = error is Map
      ? '${error['message'] ?? 'error'}'
      : error.toString();
  if (code is int && code != 200) {
    throw onlineFailureForResponse(
      code,
      const {},
      jsonEncode({'error': error}),
    );
  }
  throw OnlineException(OnlineErrorKind.serverError, message);
}

/// Purpose: Read `choices[0]`.
/// Inputs: `json`. Returns: Map or null. Side effects: None. Notes: Internal.
Map<Object?, Object?>? _firstChoice(Map<Object?, Object?> json) {
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  return first is Map ? first : null;
}

/// Purpose: Read token usage.
/// Inputs: `json`. Returns: `(prompt, completion)`. Side effects: None.
/// Notes: Internal.
(int?, int?) _usage(Map<Object?, Object?> json) {
  final usage = json['usage'];
  if (usage is! Map) return (null, null);
  final p = usage['prompt_tokens'];
  final c = usage['completion_tokens'];
  return (p is int ? p : null, c is int ? c : null);
}

/// Purpose: Map `finish_reason`.
/// Inputs: `value`. Returns: Finish or null. Side effects: None.
/// Notes: `length` maps to [LlmFinish.length]; any other non-null reason to
/// [LlmFinish.stop].
LlmFinish? _finishFor(Object? value) => switch (value) {
  null => null,
  'length' => LlmFinish.length,
  _ => LlmFinish.stop,
};

/// Internal cancellation marker.
class _Cancelled implements Exception {
  /// Purpose: Create the marker. Inputs: None. Returns: Marker.
  /// Side effects: None. Notes: Internal.
  const _Cancelled();
}

/// Parsed end-of-stream facts.
class _Outcome {
  /// Purpose: Create an outcome. Inputs: finish, token counts.
  /// Returns: Outcome. Side effects: None. Notes: Internal.
  const _Outcome(this.finish, {this.promptTokens, this.outputTokens});
  final LlmFinish finish;
  final int? promptTokens;
  final int? outputTokens;
}

/// State of one in-flight request.
class _Run {
  /// Purpose: Track one request. Inputs: its `client`. Returns: Run.
  /// Side effects: None. Notes: Internal.
  _Run(this.client);

  final http.Client client;
  final Completer<void> aborted = Completer<void>();
  final Completer<void> exited = Completer<void>();
  StreamSubscription<String>? subscription;
  void Function()? onAbort;
  DateTime? firstToken;
  bool cancelled = false;
  bool emitDone = false;

  /// Purpose: Abort the request.
  /// Inputs: `emitDone` — whether the stream ends with `LlmDone(cancelled)`.
  /// Returns: None.
  /// Side effects: Fires the abort trigger, closes the client and the
  /// response subscription.
  /// Notes: Idempotent.
  void abort({required bool emitDone}) {
    if (cancelled) return;
    cancelled = true;
    this.emitDone = emitDone;
    if (!aborted.isCompleted) aborted.complete();
    onAbort?.call();
    unawaited(subscription?.cancel());
    client.close();
  }
}
