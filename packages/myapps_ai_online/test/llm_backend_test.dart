import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

const _provider = OnlineProvider(
  id: 'provider:test',
  name: 'Test',
  dialect: OnlineDialect.openai,
  baseUrl: 'https://api.example.com/v1/',
  modelId: 'gpt-test',
  headers: {'X-Extra': '1'},
);

const _request = LlmRequest(
  messages: [
    LlmMessage(LlmRole.system, 'be brief'),
    LlmMessage(LlmRole.user, 'hello'),
  ],
);

/// Purpose: Encode SSE events. Inputs: payloads. Returns: chunks.
/// Side effects: None. Notes: Test helper.
List<List<int>> _sse(List<String> payloads) => [
  for (final p in payloads) utf8.encode('data: $p\n\n'),
];

/// Purpose: Build one streamed delta event. Inputs: text. Returns: JSON.
/// Side effects: None. Notes: Test helper.
String _delta(String text, {String? finish}) => jsonEncode({
  'choices': [
    {
      'delta': {'content': text},
      'finish_reason': finish,
    },
  ],
});

void main() {
  late List<http.BaseRequest> sent;
  late List<String> bodies;

  setUp(() {
    sent = [];
    bodies = [];
  });

  /// Purpose: Build a backend over a streaming mock. Inputs: response factory,
  /// key. Returns: Backend. Side effects: Records requests. Notes: Helper.
  OpenAiCompatibleLlmBackend backend(
    Future<http.StreamedResponse> Function(http.BaseRequest) respond, {
    String? key = 'sk-test',
    OnlineProvider provider = _provider,
    Duration idleTimeout = const Duration(seconds: 5),
  }) => OpenAiCompatibleLlmBackend(
    provider: provider,
    readSecret: (_) async => key,
    idleTimeout: idleTimeout,
    clientFactory: () => MockClient.streaming((request, body) async {
      sent.add(request);
      bodies.add(utf8.decode(await body.toBytes()));
      return respond(request);
    }),
  );

  http.StreamedResponse sseResponse(Stream<List<int>> stream) =>
      http.StreamedResponse(
        stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );

  test('streams deltas until [DONE] and reports remote metrics', () async {
    final llm = backend(
      (_) async => sseResponse(
        Stream.fromIterable([
          utf8.encode(': keep-alive\n\n'),
          ..._sse([_delta('Hel'), _delta('lo', finish: 'stop')]),
          utf8.encode(
            'data: ${jsonEncode({
              'choices': <Object>[],
              'usage': {'prompt_tokens': 7, 'completion_tokens': 2},
            })}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
          // Anything after [DONE] is ignored.
          ..._sse([_delta('ignored')]),
        ]),
      ),
    );
    final events = await llm.generate(_request).toList();
    expect(events.whereType<LlmDelta>().map((e) => e.text), ['Hel', 'lo']);
    final done = events.last as LlmDone;
    expect(done.finish, LlmFinish.stop);
    expect(done.metrics.device, 'remote');
    expect(done.metrics.promptTokens, 7);
    expect(done.metrics.outputTokens, 2);
    expect(done.metrics.total, isNotNull);

    final request = sent.single;
    expect(
      request.url.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer sk-test');
    expect(request.headers['X-Extra'], '1');
    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(body['model'], 'gpt-test');
    expect(body['stream'], isTrue);
    expect(body['max_completion_tokens'], 256);
    expect(body['messages'], [
      {'role': 'system', 'content': 'be brief'},
      {'role': 'user', 'content': 'hello'},
    ]);
  });

  test('handles events split across chunks and length finish', () async {
    final payload =
        'data: ${_delta('abc', finish: 'length')}\n\ndata: [DONE]\n\n';
    final bytes = utf8.encode(payload);
    final llm = backend(
      (_) async => sseResponse(
        Stream.fromIterable([
          for (var i = 0; i < bytes.length; i += 5)
            bytes.sublist(i, i + 5 > bytes.length ? bytes.length : i + 5),
        ]),
      ),
    );
    final (text, done) = await collectLlm(llm.generate(_request));
    expect(text, 'abc');
    expect(done.finish, LlmFinish.length);
  });

  test('compatible dialect sends max_tokens without stream_options', () async {
    final llm = backend(
      (_) async => sseResponse(Stream.fromIterable(_sse(['[DONE]']))),
      provider: _provider.copyWith(dialect: OnlineDialect.openaiCompatible),
    );
    await llm.generate(_request).toList();
    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(body['max_tokens'], 256);
    expect(body.containsKey('stream_options'), isFalse);
  });

  test('a stream ending without [DONE] or finish fails', () async {
    final llm = backend(
      (_) async => sseResponse(Stream.fromIterable(_sse([_delta('x')]))),
    );
    expect(collectLlm(llm.generate(_request)), throwsA(isA<OnlineException>()));
  });

  test('accepts a non-streamed JSON reply', () async {
    final llm = backend(
      (_) async => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'whole'},
                  'finish_reason': 'stop',
                },
              ],
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final (text, done) = await collectLlm(llm.generate(_request));
    expect(text, 'whole');
    expect(done.metrics.device, 'remote');
  });

  test('cancel mid-stream ends with cancelled and closes the stream', () async {
    final source = StreamController<List<int>>();
    final llm = backend((_) async => sseResponse(source.stream));
    final events = <LlmEvent>[];
    final finished = Completer<void>();
    llm.generate(_request).listen(events.add, onDone: finished.complete);
    source.add(_sse([_delta('part')]).single);
    await pumpUntil(() => events.isNotEmpty);
    await llm.cancel();
    await finished.future;
    expect((events.first as LlmDelta).text, 'part');
    expect((events.last as LlmDone).finish, LlmFinish.cancelled);
    expect(source.hasListener, isFalse);
    await source.close();
  });

  test('the same backend accepts a request after cancel', () async {
    var calls = 0;
    final first = StreamController<List<int>>();
    final llm = backend(
      (_) async => calls++ == 0
          ? sseResponse(first.stream)
          : sseResponse(Stream.fromIterable(_sse([_delta('again'), '[DONE]']))),
    );
    llm.generate(_request).listen((_) {});
    await pumpUntil(() => sent.isNotEmpty);
    await llm.cancel();
    final (text, done) = await collectLlm(llm.generate(_request));
    expect(text, 'again');
    expect(done.finish, LlmFinish.stop);
    await first.close();
  });

  test('cancelling the subscription aborts the request', () async {
    final source = StreamController<List<int>>(onCancel: () {});
    final llm = backend((_) async => sseResponse(source.stream));
    final sub = llm.generate(_request).listen((_) {});
    source.add(_sse([_delta('part')]).single);
    await pumpUntil(() => source.hasListener);
    await sub.cancel();
    expect(source.hasListener, isFalse);
    // A new generation is accepted.
    final llm2 = backend(
      (_) async => sseResponse(Stream.fromIterable(_sse(['[DONE]']))),
    );
    expect((await llm2.generate(_request).toList()).last, isA<LlmDone>());
  });

  test('a second concurrent request is busy', () async {
    final source = StreamController<List<int>>();
    final llm = backend((_) async => sseResponse(source.stream));
    llm.generate(_request).listen((_) {}, onError: (_) {});
    await pumpUntil(() => sent.isNotEmpty);
    await expectLater(
      llm.generate(_request).toList(),
      throwsA(
        isA<GenAiException>().having((e) => e.failure, 'f', GenAiFailure.busy),
      ),
    );
    await llm.cancel();
    await source.close();
  });

  group('HTTP error mapping', () {
    Future<GenAiException> failWith(
      int status, {
      Map<String, String> headers = const {},
    }) async {
      final llm = backend(
        (_) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'error': {'message': 'server says $status'},
              }),
            ),
          ),
          status,
          headers: headers,
        ),
      );
      try {
        await llm.generate(_request).toList();
      } on GenAiException catch (e) {
        return e;
      }
      fail('no error');
    }

    test('401 and 403 are unavailable with auth detail', () async {
      for (final status in [401, 403]) {
        final e = await failWith(status) as OnlineException;
        expect(e.failure, GenAiFailure.unavailable);
        expect(e.kind, OnlineErrorKind.unauthorized);
        expect(e.message, startsWith('auth'));
        expect(e.message, contains('server says $status'));
      }
    });

    test('429 is quota with capped retry-after', () async {
      final e = await failWith(429, headers: {'retry-after': '600'});
      expect(e.failure, GenAiFailure.quota);
      expect((e as OnlineException).retryAfter, maxHonouredRetryAfter);
    });

    test('503 is busy, 500 failed, 400 failed', () async {
      expect((await failWith(503)).failure, GenAiFailure.busy);
      expect((await failWith(500)).failure, GenAiFailure.failed);
      expect((await failWith(400)).failure, GenAiFailure.failed);
    });

    test('a mid-stream error object fails the stream', () async {
      final llm = backend(
        (_) async => sseResponse(
          Stream.fromIterable(
            _sse([
              _delta('a'),
              jsonEncode({
                'error': {'code': 429, 'message': 'slow down'},
              }),
            ]),
          ),
        ),
      );
      await expectLater(
        llm.generate(_request).toList(),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'f',
            GenAiFailure.quota,
          ),
        ),
      );
    });
  });

  test('network failure surfaces and status reports unreachable', () async {
    final llm = OpenAiCompatibleLlmBackend(
      provider: _provider,
      readSecret: (_) async => 'k',
      clientFactory: () => MockClient.streaming(
        (_, _) async => throw http.ClientException('connection refused'),
      ),
    );
    await expectLater(
      llm.generate(_request).toList(),
      throwsA(isA<OnlineException>()),
    );
    final status = await llm.status();
    expect(status.status, GenAiStatus.unreachable);
  });

  test('timeout waiting for headers maps to timeout', () async {
    final llm = OpenAiCompatibleLlmBackend(
      provider: _provider,
      readSecret: (_) async => 'k',
      requestTimeout: const Duration(milliseconds: 20),
      clientFactory: () => MockClient.streaming(
        (_, _) => Completer<http.StreamedResponse>().future,
      ),
    );
    await expectLater(
      llm.generate(_request).toList(),
      throwsA(
        isA<GenAiException>().having(
          (e) => e.failure,
          'f',
          GenAiFailure.timeout,
        ),
      ),
    );
  });

  group('unconfigured', () {
    test('status needs configuration and nothing is sent', () async {
      final llm = backend((_) async => fail('sent'), key: null);
      final status = await llm.status();
      expect(status.status, GenAiStatus.unavailable);
      expect(status.detail, 'needsConfiguration:apiKey');
      await expectLater(
        llm.generate(_request).toList(),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'f',
            GenAiFailure.unavailable,
          ),
        ),
      );
      await expectLater(llm.load(), throwsA(isA<GenAiException>()));
      expect(sent, isEmpty);
    });

    test('missing endpoint and model are listed', () async {
      final llm = backend(
        (_) async => fail('sent'),
        provider: const OnlineProvider(
          id: 'p',
          dialect: OnlineDialect.openaiCompatible,
          baseUrl: 'not a url',
          authScheme: OnlineAuthScheme.none,
        ),
      );
      expect((await llm.status()).detail, 'needsConfiguration:endpoint,model');
      expect((await llm.testConnection()).status, GenAiStatus.unavailable);
      expect(sent, isEmpty);
    });

    test('no-auth providers need no key', () async {
      final llm = backend(
        (_) async => fail('sent'),
        key: null,
        provider: _provider.copyWith(authScheme: OnlineAuthScheme.none),
      );
      expect((await llm.status()).status, GenAiStatus.available);
      expect(sent, isEmpty);
    });
  });

  group('testConnection', () {
    test('lists models without sending content', () async {
      final llm = backend(
        (_) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'data': [
                  {'id': 'gpt-test'},
                  {'id': 'other'},
                ],
              }),
            ),
          ),
          200,
        ),
      );
      final report = await llm.testConnection();
      expect(report.status, GenAiStatus.available);
      expect(report.detail, 'models:2,modelListed');
      expect(sent.single.method, 'GET');
      expect(sent.single.url.toString(), 'https://api.example.com/v1/models');
      expect(bodies.single, isEmpty);
    });

    test('reports auth failure', () async {
      final llm = backend(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode('no')), 401),
      );
      final report = await llm.testConnection();
      expect(report.status, GenAiStatus.unavailable);
      expect(report.detail, 'auth');
      expect(report.code, 401);
    });
  });

  test('works through LlmGenAiBackend', () async {
    final llm = backend(
      (_) async => sseResponse(
        Stream.fromIterable(_sse([_delta('ok', finish: 'stop'), '[DONE]'])),
      ),
    );
    final adapter = LlmGenAiBackend(llm);
    expect(await adapter.generate(instructions: 'i', prompt: 'p'), 'ok');
    expect(llm.id, 'online:provider:test');
  });
}

/// Purpose: Pump the event loop until a condition holds.
/// Inputs: `condition`. Returns: After it holds. Side effects: Delays.
/// Notes: Fails after ~2 s.
Future<void> pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
