import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

/// A request taken apart the way MyTranscribe's fake server does.
class Recorded {
  /// Purpose: Hold one request. Inputs: all fields. Returns: Value.
  /// Side effects: None. Notes: Test helper.
  Recorded(this.request, this.fields, this.fileNames, this.json);
  final http.BaseRequest request;
  final Map<String, List<String>> fields;
  final Map<String, String> fileNames;
  final Map<String, dynamic>? json;

  /// Purpose: Read a single field. Inputs: name. Returns: value or null.
  /// Side effects: None. Notes: Test helper.
  String? field(String name) => fields[name]?.single;

  /// Purpose: Read a repeated field. Inputs: name. Returns: values.
  /// Side effects: None. Notes: Test helper.
  List<String> valuesOf(String name) => fields[name] ?? const [];
}

/// A fake transcription endpoint answering canned replies.
class FakeServer extends http.BaseClient {
  /// Purpose: Create the fake. Inputs: replies `(status, body, headers)`.
  /// Returns: Client. Side effects: None. Notes: Last reply repeats.
  FakeServer(this.replies);
  final List<(int, String, Map<String, String>)> replies;
  final requests = <Recorded>[];

  /// Purpose: Record and answer. Inputs: request. Returns: Response.
  /// Side effects: Appends to [requests]. Notes: Test helper.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final fields = <String, List<String>>{};
    final files = <String, String>{};
    Map<String, dynamic>? json;
    if (request is http.MultipartRequest) {
      for (final e in request.fields.entries) {
        fields.putIfAbsent(e.key, () => []).add(e.value);
      }
      for (final f in request.files) {
        if (f.filename == null) {
          fields
              .putIfAbsent(f.field, () => [])
              .add(utf8.decode(await f.finalize().toBytes()));
        } else {
          files[f.field] = f.filename!;
        }
      }
    } else if (request is http.Request) {
      json = jsonDecode(request.body) as Map<String, dynamic>;
    }
    requests.add(Recorded(request, fields, files, json));
    final r = replies[(requests.length - 1).clamp(0, replies.length - 1)];
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.$2)),
      r.$1,
      headers: r.$3,
    );
  }
}

void main() {
  late Directory work;
  late String audio;

  setUp(() {
    work = Directory.systemTemp.createTempSync('myapps_ai_online_');
    audio = '${work.path}/chunk_0000.mp3';
    File(audio).writeAsBytesSync(List.filled(2048, 7));
  });

  tearDown(() => work.deleteSync(recursive: true));

  OnlineProvider source(
    OnlineDialect dialect, {
    OnlineAuthScheme auth = OnlineAuthScheme.bearer,
    String? headerName,
  }) => OnlineProvider(
    id: 'provider:test',
    dialect: dialect,
    baseUrl: 'https://api.example.com/v1',
    authScheme: auth,
    authHeaderName: headerName,
  );

  OnlineTranscriptionModel model({
    OnlineCapability diarization = OnlineCapability.unsupported,
    OnlineCapability segments = OnlineCapability.unsupported,
    bool prompt = false,
    bool keywords = false,
    OnlineLanguageStyle languageStyle = OnlineLanguageStyle.language,
    List<String> formats = const ['json'],
    bool chunking = false,
    int? maxKnownSpeakers,
  }) => OnlineTranscriptionModel(
    modelName: 'test-model',
    diarization: diarization,
    segmentTimestamps: segments,
    supportsPrompt: prompt,
    supportsKeywords: keywords,
    languageStyle: languageStyle,
    responseFormats: formats,
    requiresChunkingStrategy: chunking,
    maxKnownSpeakers: maxKnownSpeakers,
  );

  Future<(Recorded, OnlineTranscriptionResult)> send(
    OnlineProvider provider,
    OnlineTranscriptionModel chosen, {
    String reply = '{"text":"hello"}',
    List<String> languages = const [],
    String? prompt,
    List<String> keywords = const [],
    bool diarize = false,
    String? apiKey = 'sk-test',
    List<OnlineKnownSpeaker> speakers = const [],
  }) async {
    final server = FakeServer([(200, reply, const {})]);
    final result =
        await OnlineTranscriptionClient(
          clientFactory: () => server,
          sleep: (_) async {},
        ).transcribe(
          request: OnlineTranscriptionRequest(
            audioPath: audio,
            languages: languages,
            prompt: prompt,
            keywords: keywords,
            diarize: diarize,
            knownSpeakers: speakers,
          ),
          provider: provider,
          model: chosen,
          apiKey: apiKey,
          audioSeconds: 600,
        );
    return (server.requests.single, result);
  }

  group('OpenAI multipart', () {
    test('file, model, format and bearer auth', () async {
      final (r, result) = await send(source(OnlineDialect.openai), model());
      expect(r.json, isNull);
      expect(
        r.request.url.toString(),
        'https://api.example.com/v1/audio/transcriptions',
      );
      expect(r.field('model'), 'test-model');
      expect(r.field('response_format'), 'json');
      expect(r.fileNames['file'], 'chunk_0000.mp3');
      expect(r.request.headers['Authorization'], 'Bearer sk-test');
      expect(result.text, 'hello');
      expect(result.segments.single.endSeconds, 600);
      expect(result.hasRealTimestamps, isFalse);
    });

    test('language list vs single code', () async {
      final (list, _) = await send(
        source(OnlineDialect.openai),
        model(languageStyle: OnlineLanguageStyle.languages),
        languages: const ['en', 'zh'],
      );
      expect(list.valuesOf('languages[]'), ['en', 'zh']);
      expect(list.field('language'), isNull);
      final (single, _) = await send(
        source(OnlineDialect.openai),
        model(),
        languages: const ['en', 'zh'],
      );
      expect(single.field('language'), 'en');
    });

    test('prompt only when supported; keywords as repeated parts', () async {
      final (r, _) = await send(
        source(OnlineDialect.openai),
        model(keywords: true),
        prompt: 'ctx',
        keywords: const ['eigenvector', 'Gram-Schmidt'],
      );
      expect(r.field('prompt'), isNull);
      expect(r.valuesOf('keywords[]'), ['eigenvector', 'Gram-Schmidt']);
      final (p, _) = await send(
        source(OnlineDialect.openai),
        model(prompt: true),
        prompt: 'ctx',
      );
      expect(p.field('prompt'), 'ctx');
    });

    test('diarized request with chunking strategy and speakers', () async {
      final sample = '${work.path}/spk.wav';
      File(sample).writeAsBytesSync([1, 2, 3, 4]);
      final (r, result) = await send(
        source(OnlineDialect.openai),
        model(
          diarization: OnlineCapability.supported,
          formats: const ['diarized_json', 'json'],
          chunking: true,
          maxKnownSpeakers: 1,
        ),
        diarize: true,
        speakers: [
          OnlineKnownSpeaker(id: 'spk_1', samplePath: sample),
          OnlineKnownSpeaker(id: 'spk_2', samplePath: sample),
        ],
        reply: jsonEncode({
          'segments': [
            {'start': 0, 'end': 5, 'text': ' hi ', 'speaker': 0},
            {'start': '5', 'end': 7, 'text': 'there', 'speaker': 'A'},
          ],
        }),
      );
      expect(r.field('response_format'), 'diarized_json');
      expect(r.field('chunking_strategy'), 'auto');
      expect(r.field('known_speaker_names[]'), 'spk_1');
      expect(
        r.field('known_speaker_references[]'),
        'data:audio/wav;base64,${base64Encode([1, 2, 3, 4])}',
      );
      expect(result.text, 'hi there');
      expect(result.segments.map((s) => s.speaker), ['S0', 'A']);
      expect(result.segments[1].startSeconds, 5);
      expect(result.hasRealTimestamps, isTrue);
      expect(result.hasSpeakers, isTrue);
    });

    test('verbose_json with segment granularity when supported', () async {
      final (r, _) = await send(
        source(OnlineDialect.openai),
        model(
          segments: OnlineCapability.supported,
          formats: const ['verbose_json', 'json'],
        ),
      );
      expect(r.field('response_format'), 'verbose_json');
      expect(r.field('timestamp_granularities[]'), 'segment');
    });
  });

  group('OpenRouter', () {
    test('multipart without prompt when no provider option', () async {
      final (r, _) = await send(
        source(OnlineDialect.openrouter),
        model(prompt: true),
        prompt: 'dropped',
        languages: const ['ja'],
      );
      expect(r.json, isNull);
      expect(r.field('prompt'), isNull);
      expect(r.field('language'), 'ja');
    });

    test('JSON body for speakers and keywords', () async {
      final (r, _) = await send(
        source(OnlineDialect.openrouter),
        model(
          diarization: OnlineCapability.supported,
          segments: OnlineCapability.supported,
          keywords: true,
          formats: const ['verbose_json', 'json'],
        ),
        diarize: true,
        keywords: const ['eigenvector'],
        languages: const ['en'],
      );
      expect(r.request.headers['Content-Type'], 'application/json');
      final json = r.json!;
      expect(json['model'], 'test-model');
      expect(json['response_format'], 'verbose_json');
      expect(json['language'], 'en');
      expect(json['timestamp_granularities'], ['segment']);
      expect(json['provider'], {
        'options': {
          'azure': {
            'diarization': {'enabled': true},
            'phraseList': {
              'phrases': ['eigenvector'],
            },
          },
        },
      });
      final input = json['input_audio'] as Map<String, dynamic>;
      expect(input['format'], 'mp3');
      expect(base64Decode(input['data'] as String), hasLength(2048));
    });
  });

  group('compatible', () {
    test('no auth header for no-auth servers', () async {
      final (r, _) = await send(
        source(OnlineDialect.openaiCompatible, auth: OnlineAuthScheme.none),
        model(segments: OnlineCapability.unknown),
        apiKey: null,
      );
      expect(r.request.headers.containsKey('Authorization'), isFalse);
      expect(r.field('response_format'), 'json');
    });

    test('custom header auth', () async {
      final (r, _) = await send(
        source(
          OnlineDialect.openaiCompatible,
          auth: OnlineAuthScheme.header,
          headerName: 'X-Api-Key',
        ),
        model(),
      );
      expect(r.request.headers['X-Api-Key'], 'sk-test');
      expect(r.request.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('failures', () {
    Future<OnlineTranscriptionException> failWith(
      List<(int, String, Map<String, String>)> replies, {
      List<Duration>? slept,
      bool diarize = false,
    }) async {
      final server = FakeServer(replies);
      try {
        await OnlineTranscriptionClient(
          clientFactory: () => server,
          sleep: (d) async => slept?.add(d),
        ).transcribe(
          request: OnlineTranscriptionRequest(
            audioPath: audio,
            diarize: diarize,
          ),
          provider: source(OnlineDialect.openai),
          model: model(),
          apiKey: 'k',
          audioSeconds: 1,
        );
      } on OnlineTranscriptionException catch (e) {
        return e;
      }
      fail('no error');
    }

    test('401 is not retried and keeps the server message', () async {
      final e = await failWith([
        (401, '{"error":{"message":"bad key"}}', const {}),
      ]);
      expect(e.kind, OnlineErrorKind.unauthorized);
      expect(e.failure, GenAiFailure.unavailable);
      expect(e.message, 'bad key');
    });

    test('429 retries honouring retry-after, then fails', () async {
      final slept = <Duration>[];
      final e = await failWith([
        (429, 'slow', const {'retry-after': '3'}),
      ], slept: slept);
      expect(e.failure, GenAiFailure.quota);
      expect(slept, [const Duration(seconds: 3), const Duration(seconds: 3)]);
    });

    test('500 then success', () async {
      final server = FakeServer([
        (500, 'oops', const {}),
        (200, 'plain text', const {}),
      ]);
      final result =
          await OnlineTranscriptionClient(
            clientFactory: () => server,
            sleep: (_) async {},
          ).transcribe(
            request: OnlineTranscriptionRequest(audioPath: audio),
            provider: source(OnlineDialect.openai),
            model: model(),
            apiKey: 'k',
            audioSeconds: 3,
          );
      expect(result.text, 'plain text');
      expect(server.requests, hasLength(2));
    });

    test('400 names the rejected feature', () async {
      final e = await failWith([
        (400, '{"error":{"message":"diarization not allowed"}}', const {}),
      ], diarize: true);
      expect(e.kind, OnlineErrorKind.rejected);
      expect(e.rejectedFeature, OnlineRejectedFeature.diarization);
    });

    test('cancel aborts the upload and is not retried', () async {
      var attempts = 0;
      late OnlineTranscriptionClient client;
      client = OnlineTranscriptionClient(
        clientFactory: () => _HangingClient(() {
          attempts++;
          client.cancel();
        }),
        sleep: (_) async {},
      );
      await expectLater(
        client.transcribe(
          request: OnlineTranscriptionRequest(audioPath: audio),
          provider: source(OnlineDialect.openai),
          model: model(),
          apiKey: 'k',
          audioSeconds: 1,
        ),
        throwsA(
          isA<OnlineTranscriptionException>()
              .having((e) => e.kind, 'kind', OnlineErrorKind.cancelled)
              .having((e) => e.failure, 'f', GenAiFailure.cancelled),
        ),
      );
      expect(attempts, 1);
    });

    test('empty reply is badResponse', () async {
      final e = await failWith([(200, '  ', const {})]);
      expect(e.kind, OnlineErrorKind.badResponse);
    });
  });
}

/// A client whose request never answers until aborted.
class _HangingClient extends http.BaseClient {
  /// Purpose: Create. Inputs: `onSend` hook. Returns: Client.
  /// Side effects: None. Notes: Test helper.
  _HangingClient(this.onSend);
  final void Function() onSend;

  /// Purpose: Wait for the abort trigger. Inputs: request.
  /// Returns: Never; throws [http.RequestAbortedException].
  /// Side effects: Calls [onSend]. Notes: Test helper.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend();
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException(request.url);
  }
}
