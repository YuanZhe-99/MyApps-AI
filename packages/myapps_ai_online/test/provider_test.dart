import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

void main() {
  group('OnlineProvider', () {
    test('reads a MyTranscribe provider payload and preserves extras', () {
      final payload = {
        'name': 'OpenAI',
        'templateId': 'openai',
        'dialect': 'openai',
        'baseUrl': 'https://api.openai.com/v1',
        'authScheme': 'bearer',
        'extraHeaders': {'X-A': 'b'},
        'maxFileBytes': 26214400,
        'requestTimeoutSeconds': 600,
        'defaultModelId': 'model:openai:gpt-transcribe',
        'overriddenFields': ['name'],
        'templateVersion': 1,
        'futureField': {'nested': true},
      };
      final p = OnlineProvider.fromJson('provider:openai', payload);
      expect(p.dialect, OnlineDialect.openai);
      expect(p.headers, {'X-A': 'b'});
      expect(p.recipientHost, 'api.openai.com');
      expect(p.extra['maxFileBytes'], 26214400);
      expect(p.extra['futureField'], {'nested': true});
      expect(p.toJson(), payload);
    });

    test('falls back on unknown values', () {
      final p = OnlineProvider.fromJson('x', {
        'dialect': 'future',
        'authScheme': '???',
      });
      expect(p.dialect, OnlineDialect.openaiCompatible);
      expect(p.authScheme, OnlineAuthScheme.bearer);
      expect(p.name, 'x');
      expect(OnlineProvider.fromJson('y', null).baseUrl, '');
    });

    test('endpoint joining and auth headers', () {
      const p = OnlineProvider(
        id: 'p',
        dialect: OnlineDialect.openaiCompatible,
        baseUrl: 'http://127.0.0.1:8080/v1/',
        authScheme: OnlineAuthScheme.header,
        authHeaderName: 'X-Key',
      );
      expect(p.endpoint('/models'), 'http://127.0.0.1:8080/v1/models');
      expect(p.authHeaders('k'), {'X-Key': 'k'});
      expect(p.authHeaders(''), isEmpty);
    });

    test('source option readiness', () {
      final p = openAiTemplate.create(modelId: 'gpt-x');
      expect(p.toSourceOption('k').readiness, AiSourceReadiness.ready);
      expect(p.toSourceOption('k').id, 'online:provider:openai');
      expect(p.toSourceOption('k').kind, AiSourceKind.online);
      expect(
        p.toSourceOption(null).readiness,
        AiSourceReadiness.needsConfiguration,
      );
      expect(
        openAiCompatibleTemplate
            .create(id: 'provider:custom')
            .configurationGaps('k'),
        {OnlineConfigurationGap.endpoint, OnlineConfigurationGap.model},
      );
    });
  });

  group('templates', () {
    test('ids and default URLs match MyTranscribe', () {
      final registry = OnlineProviderTemplateRegistry.builtIn();
      expect(registry.templates.map((t) => t.id), [
        'openai',
        'openrouter',
        'openaiCompatible',
      ]);
      final seeded = registry.seedProviders();
      expect(seeded.map((p) => p.id), [
        'provider:openai',
        'provider:openrouter',
      ]);
      expect(seeded.map((p) => p.templateId), ['openai', 'openrouter']);
      expect(seeded.map((p) => p.baseUrl), [
        'https://api.openai.com/v1',
        'https://openrouter.ai/api/v1',
      ]);
      expect(
        registry.byId('openaiCompatible')!.create(id: 'provider:u').templateId,
        isNull,
      );
      expect(() => openAiCompatibleTemplate.create(), throwsArgumentError);
    });

    test('apps register more templates; replacing keeps order', () {
      final registry = OnlineProviderTemplateRegistry.builtIn()
        ..register(
          const OnlineProviderTemplate(
            id: 'local',
            name: 'Local server',
            dialect: OnlineDialect.openaiCompatible,
            defaultBaseUrl: 'http://127.0.0.1:8080/v1',
            authScheme: OnlineAuthScheme.none,
          ),
        )
        ..register(
          const OnlineProviderTemplate(
            id: 'openai',
            name: 'OpenAI (custom)',
            dialect: OnlineDialect.openai,
            defaultBaseUrl: 'https://api.openai.com/v1',
          ),
        );
      expect(registry.templates.first.name, 'OpenAI (custom)');
      expect(registry.templates.last.id, 'local');
      expect(
        registry.byId('local')!.create(id: 'provider:l').needsApiKey,
        isFalse,
      );
    });
  });

  group('privacy notice', () {
    test('forProvider requires a host', () {
      final p = openRouterTemplate.create();
      final notice = OnlinePrivacyNotice.forProvider(
        version: 1,
        host: p.recipientHost,
        providerName: p.name,
        sent: const [
          OnlineDataItem(OnlineDataCategory.promptText),
          OnlineDataItem(OnlineDataCategory.audio, description: 'recordings'),
        ],
      )!;
      expect(notice.recipientHost, 'openrouter.ai');
      expect(notice.categories, {
        OnlineDataCategory.promptText,
        OnlineDataCategory.audio,
      });
      expect(notice.keySync, OnlineKeySync.secureEndpointsOnly);
      expect(notice.usedOnlyWhenSelected, isTrue);
      expect(
        OnlinePrivacyNotice.forProvider(version: 1, host: null, sent: const []),
        isNull,
      );
    });

    test('acknowledgement version and host checks', () {
      expect(needsOnlinePrivacyAcknowledgement(null, 1), isTrue);
      final ack = OnlinePrivacyAcknowledgement(
        noticeVersion: 2,
        acknowledgedAt: DateTime.utc(2026),
        recipientHost: 'api.openai.com',
      );
      expect(needsOnlinePrivacyAcknowledgement(ack, 2), isFalse);
      expect(needsOnlinePrivacyAcknowledgement(ack, 1), isFalse);
      expect(needsOnlinePrivacyAcknowledgement(ack, 3), isTrue);
      expect(
        needsOnlinePrivacyAcknowledgement(
          ack,
          2,
          recipientHost: 'API.OpenAI.com',
        ),
        isFalse,
      );
      expect(
        needsOnlinePrivacyAcknowledgement(
          ack,
          2,
          recipientHost: 'openrouter.ai',
        ),
        isTrue,
      );
    });

    test('acknowledgement round trip keeps unknown fields', () {
      final json = {
        'noticeVersion': 1,
        'acknowledgedAt': '2026-01-01T00:00:00.000Z',
        'recipientHost': 'h',
        'other': 3,
      };
      expect(OnlinePrivacyAcknowledgement.tryParse(json)!.toJson(), json);
      expect(
        OnlinePrivacyAcknowledgement.tryParse({'noticeVersion': 1}),
        isNull,
      );
      expect(OnlinePrivacyAcknowledgement.tryParse('x'), isNull);
    });
  });
}
