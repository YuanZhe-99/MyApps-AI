import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

http.Client _json(Object body, {int status = 200}) => MockClient(
  (_) async => http.Response(
    body is String ? body : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  ),
);

OnlineProvider _provider(String url, {String? modelId}) => OnlineProvider(
  id: 'p',
  dialect: OnlineDialect.openaiCompatible,
  baseUrl: url,
  modelId: modelId,
);

void main() {
  group('OnlineModel', () {
    test('JSON round trip keeps unknown fields', () {
      final json = {
        'modelName': 'gpt-4o',
        'alias': 'Mine',
        'displayName': 'OpenAI: GPT-4o',
        'vendor': 'OpenAI',
        'contextTokens': 128000,
        'inputModalities': ['text', 'image'],
        'origin': 'fetched',
        'future': {'a': 1},
      };
      final m = OnlineModel.fromJson(json)!;
      expect(m.origin, OnlineModelOrigin.fetched);
      expect(m.extra['future'], {'a': 1});
      expect(m.toJson(), json);
    });

    test('fromJson rejects a missing or blank modelName', () {
      expect(OnlineModel.fromJson({'alias': 'x'}), isNull);
      expect(OnlineModel.fromJson({'modelName': '  '}), isNull);
      expect(OnlineModel.fromJson('text'), isNull);
    });

    test('name order', () {
      expect(
        const OnlineModel(
          modelName: 'a',
          alias: 'Alias',
          displayName: 'D',
        ).name(),
        'Alias',
      );
      expect(
        const OnlineModel(
          modelName: 'a',
          displayName: 'GPT',
          vendor: 'OpenAI',
        ).name(),
        'OpenAI: GPT',
      );
      expect(
        const OnlineModel(
          modelName: 'a',
          displayName: 'Acme: GPT',
          vendor: 'OpenAI',
        ).name(),
        'Acme: GPT',
      );
      expect(
        const OnlineModel(modelName: 'a', displayName: 'GPT').name(),
        'GPT',
      );
      expect(
        const OnlineModel(modelName: 'claude-opus-5-5').name(),
        'Anthropic: Claude Opus 5.5',
      );
    });

    test('recordId and source id', () {
      expect(const OnlineModel(modelName: 'm').recordId('p1'), 'model:p1:m');
      expect(onlineModelSourceId('p1', 'm'), 'online:model:p1:m');
    });
  });

  group('OnlineProvider models', () {
    test('legacy modelId yields one model and round trips unchanged', () {
      final legacy = {
        'name': 'X',
        'dialect': 'openai',
        'baseUrl': 'https://api.openai.com/v1',
        'authScheme': 'bearer',
        'requestTimeoutSeconds': 600,
        'modelId': 'gpt-4o',
      };
      final p = OnlineProvider.fromJson('p', legacy);
      expect(p.models.map((m) => m.modelName), ['gpt-4o']);
      final out = p.toJson();
      expect(out.containsKey('models'), isFalse);
      expect(out, legacy);
    });

    test('toJson writes models and first model as modelId', () {
      const p = OnlineProvider(
        id: 'p',
        dialect: OnlineDialect.openai,
        baseUrl: 'https://api.openai.com/v1',
        models: [
          OnlineModel(modelName: 'a'),
          OnlineModel(modelName: 'b'),
        ],
      );
      final json = p.toJson();
      expect(json['modelId'], 'a');
      expect((json['models']! as List).length, 2);
      final back = OnlineProvider.fromJson('p', json);
      expect(back.models.map((m) => m.modelName), ['a', 'b']);
    });

    test('unknown fields survive; forModel sets modelId', () {
      final p = OnlineProvider.fromJson('p', {
        'baseUrl': 'https://x.test/v1',
        'zzz': 5,
        'models': [
          {'modelName': 'a'},
          {'modelName': 'b'},
        ],
      });
      expect(p.toJson()['zzz'], 5);
      final m = p.models[1];
      expect(p.forModel(m).modelId, m.modelName);
    });
  });

  group('fetchOnlineModels', () {
    final p = _provider('https://x.test/v1');

    test('OpenAI list marks embeddings as not chat', () async {
      final list = await fetchOnlineModels(
        _json({
          'data': [
            {'id': 'gpt-4o'},
            {'id': 'text-embedding-3-small'},
          ],
        }),
        p,
      );
      expect(list.map((e) => e.id), ['gpt-4o', 'text-embedding-3-small']);
      expect(list[0].chat, isTrue);
      expect(list[1].chat, isFalse);
    });

    test('OpenRouter fields are read', () async {
      final list = await fetchOnlineModels(
        _json({
          'data': [
            {
              'id': 'acme/vision-1',
              'name': 'Acme: Vision 1',
              'context_length': 32000,
              'architecture': {
                'input_modalities': ['text', 'image'],
                'output_modalities': ['text'],
              },
            },
            {
              'id': 'acme/paint-1',
              'architecture': {
                'input_modalities': ['text'],
                'output_modalities': ['image'],
              },
            },
          ],
        }),
        p,
      );
      final vision = list.firstWhere((e) => e.id == 'acme/vision-1');
      expect(vision.displayName, 'Acme: Vision 1');
      expect(vision.contextTokens, 32000);
      expect(vision.inputModalities, ['text', 'image']);
      expect(vision.chat, isTrue);
      expect(list.firstWhere((e) => e.id == 'acme/paint-1').chat, isFalse);
    });

    test('Ollama list works', () async {
      final list = await fetchOnlineModels(
        _json({
          'models': [
            {'name': 'qwen2.5:7b'},
          ],
        }),
        p,
      );
      expect(list.single.id, 'qwen2.5:7b');
    });

    test('empty list', () async {
      expect(await fetchOnlineModels(_json({'data': []}), p), isEmpty);
    });

    test('HTTP errors and bad bodies throw OnlineException', () async {
      for (final status in [401, 404]) {
        await expectLater(
          fetchOnlineModels(_json({'error': 'no'}, status: status), p),
          throwsA(isA<OnlineException>()),
        );
      }
      await expectLater(
        fetchOnlineModels(_json('<html>not json</html>'), p),
        throwsA(isA<OnlineException>()),
      );
    });

    test('deduplicates and sorts by id', () async {
      final list = await fetchOnlineModels(
        _json({
          'data': [
            {'id': 'b'},
            {'id': 'a'},
            {'id': 'b'},
          ],
        }),
        p,
      );
      expect(list.map((e) => e.id), ['a', 'b']);
    });
  });

  group('OnlineModelCatalog', () {
    test('lookup with catalog id', () {
      final e = OnlineModelCatalog.lookup('gpt-4o-mini', catalogId: 'openai')!;
      expect(e.vendor, 'OpenAI');
      expect(e.contextTokens, isNotNull);
      expect(e.displayName, startsWith('OpenAI: '));
    });

    test('lookup strips an org prefix', () {
      final e = OnlineModelCatalog.lookup('someorg/gpt-4o-mini');
      expect(e, isNotNull);
      expect(e!.id, 'gpt-4o-mini');
    });

    test('modelsOf', () {
      expect(OnlineModelCatalog.modelsOf('nonexistent'), isEmpty);
      final ids = OnlineModelCatalog.modelsOf('openai').map((e) => e.id);
      expect(ids, isNotEmpty);
      expect(ids.toList(), [...ids]..sort());
    });
  });

  group('templates', () {
    final registry = OnlineProviderTemplateRegistry.chat();

    test('chat registry contents', () {
      final list = registry.templates;
      expect(list.length, greaterThanOrEqualTo(30));
      final ids = list.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['openai', 'openrouter', 'openaiCompatible']));
      expect(ids.last, 'openaiCompatible');
    });

    test('shipped ids are unchanged', () {
      expect(openAiTemplateId, 'openai');
      expect(openRouterTemplateId, 'openrouter');
      expect(openAiCompatibleTemplateId, 'openaiCompatible');
      expect(openAiProviderId, 'provider:openai');
      expect(openRouterProviderId, 'provider:openrouter');
    });

    test('only openai and openrouter are seeded', () {
      expect(registry.seedProviders().map((p) => p.id).toSet(), {
        'provider:openai',
        'provider:openrouter',
      });
    });

    test('dashscope endpoints', () {
      final t = registry.byId('dashscope')!;
      expect(t.endpoints.map((e) => e.label), [
        'International (Singapore)',
        'China (Beijing)',
      ]);
      expect(
        t.catalogIdFor('https://dashscope.aliyuncs.com/compatible-mode/v1'),
        'alibaba-cn',
      );
    });

    test('no region words in endpoint labels', () {
      final bad = RegExp('domestic|overseas|国内|海外', caseSensitive: false);
      for (final t in registry.templates) {
        for (final e in t.endpoints) {
          expect(e.label ?? '', isNot(matches(bad)), reason: t.id);
        }
      }
    });

    test('azureOpenai uses an api-key header', () {
      final p = registry.byId('azureOpenai')!.create(id: 'a');
      expect(p.authScheme, OnlineAuthScheme.header);
      expect(p.authHeaderName, 'api-key');
    });
  });

  group('OnlineSourceManager', () {
    late Map<String, dynamic> config;
    late Map<String, String> keys;

    OnlineSourceManager make({http.Client Function()? client}) =>
        OnlineSourceManager(
          readConfig: () async => config,
          writeConfig: (c) async => config = Map.of(c),
          readKey: (id) async => keys[id],
          writeKey: (id, k) async {
            if (k == null) {
              keys.remove(id);
            } else {
              keys[id] = k;
            }
          },
          notice: (p) => OnlinePrivacyNotice.forProvider(
            version: 1,
            host: p.recipientHost,
            providerName: p.name,
            sent: const [OnlineDataItem(OnlineDataCategory.promptText)],
          ),
          client: client,
        );

    const secret = 'sk-SECRET-123';
    final base = OnlineProvider(
      id: 'provider:t',
      name: 'Test',
      dialect: OnlineDialect.openaiCompatible,
      baseUrl: 'https://api.test.example/v1',
      models: const [
        OnlineModel(modelName: 'gpt-4o-mini'),
        OnlineModel(modelName: 'second'),
      ],
    );

    setUp(() {
      config = {'other': 1};
      keys = {};
    });

    OnlinePrivacyAcknowledgement ack([String host = 'api.test.example']) =>
        OnlinePrivacyAcknowledgement(
          noticeVersion: 1,
          acknowledgedAt: DateTime.utc(2026),
          recipientHost: host,
        );

    test('save persists, keeps other config, remove deletes', () async {
      final m = make();
      await m.save(base, newKey: secret);
      expect(config['other'], 1);
      expect(keys['provider:t'], secret);

      final fresh = make();
      await fresh.initialize();
      expect(fresh.providers.map((p) => p.id), ['provider:t']);
      expect(fresh.providers.single.models.length, 2);

      await fresh.remove('provider:t');
      expect(keys, isEmpty);
      expect((config[onlineProvidersKey] as Map), isEmpty);
      expect(config['other'], 1);
      expect(fresh.providers, isEmpty);
    });

    test('sourceOptions and readiness', () async {
      final m = make();
      await m.save(base);
      var options = m.sourceOptions;
      expect(options.map((o) => o.id), [
        onlineModelSourceId('provider:t', 'gpt-4o-mini'),
        onlineModelSourceId('provider:t', 'second'),
      ]);
      expect(
        options.every(
          (o) => o.readiness == AiSourceReadiness.needsConfiguration,
        ),
        isTrue,
      );
      await m.save(base, newKey: secret);
      options = m.sourceOptions;
      expect(
        options.every((o) => o.readiness == AiSourceReadiness.ready),
        isTrue,
      );
    });

    test('resolve checks key, notice and id', () async {
      final m = make();
      await m.save(base);
      final id = onlineModelSourceId('provider:t', 'second');

      await expectLater(
        m.resolve(id),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.message,
            'message',
            needsConfigurationDetail({OnlineConfigurationGap.apiKey}),
          ),
        ),
      );

      await m.save(base, newKey: secret);
      await expectLater(
        m.resolve(id),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.message,
            'message',
            'privacyNotice',
          ),
        ),
      );

      await m.acknowledge('provider:t', ack());
      expect(await m.resolve(id), isA<GenAiBackend>());
      expect(await m.resolve('online:provider:t'), isA<GenAiBackend>());
      expect(await m.resolve('provider:t'), isA<GenAiBackend>());

      await expectLater(
        m.resolve('online:model:nope:x'),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.message,
            'message',
            'unknownSource',
          ),
        ),
      );
    });

    test('acknowledgement for another host does not count', () async {
      final m = make();
      await m.save(base, newKey: secret);
      await m.acknowledge('provider:t', ack('other.example'));
      await expectLater(
        m.resolve(onlineModelSourceId('provider:t', 'second')),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.message,
            'message',
            'privacyNotice',
          ),
        ),
      );
    });

    test('sourceName and sourceDetail', () async {
      final m = make();
      await m.save(base);
      final id = onlineModelSourceId('provider:t', 'gpt-4o-mini');
      expect(
        m.sourceName(id),
        const OnlineModel(modelName: 'gpt-4o-mini').name(vendorHint: 'Test'),
      );
      expect(m.sourceDetail(id), 'Test');
      expect(m.sourceName('online:model:x:y'), isNull);
    });

    test('diagnostics list rows and never leak the key', () async {
      final m = make();
      await m.save(base, newKey: secret);
      await m.save(
        base.copyWith(name: 'Second', baseUrl: 'https://b.example/v1'),
      );
      final p2 = OnlineProvider(
        id: 'provider:u',
        name: 'Other',
        dialect: OnlineDialect.openaiCompatible,
        baseUrl: 'https://c.example/v1',
      );
      await m.save(p2, newKey: secret);
      final sections = await m.diagnostics();
      expect(sections.length, 2);
      for (final s in sections) {
        final keysOfRows = s.rows.map((r) => r.key);
        expect(keysOfRows, containsAll(['host', 'keyStored', 'privacyNotice']));
        for (final r in s.rows) {
          expect(r.value, isNot(contains(secret)));
          expect(r.key, isNot(contains(secret)));
        }
        expect(s.title, isNot(contains(secret)));
      }
      expect(
        sections.first.rows.firstWhere((r) => r.key == 'host').value,
        'b.example',
      );
    });

    test(
      'fetchModels enriches from the catalog and records lastResult',
      () async {
        final m = make(
          client: () => _json({
            'data': [
              {'id': 'gpt-4o-mini'},
            ],
          }),
        );
        final p = openAiTemplate.create(modelId: 'gpt-4o-mini');
        await m.save(p, newKey: secret);
        final list = await m.fetchModels(p, secret);
        expect(list.single.id, 'gpt-4o-mini');
        expect(list.single.contextTokens, isNotNull);
        expect(list.single.vendor, 'OpenAI');
        final section = (await m.diagnostics()).single;
        expect(
          section.rows.firstWhere((r) => r.key == 'lastResult').value,
          contains('listed 1'),
        );
      },
    );
  });
}
