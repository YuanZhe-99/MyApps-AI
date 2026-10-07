import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_platform/myapps_ai_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelGenAiBackend', () {
    const channel = MethodChannel(MethodChannelGenAiBackend.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('maps every status reply shape', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Object? reply;
      messenger.setMockMethodCallHandler(channel, (call) async => reply);
      final backend = MethodChannelGenAiBackend();
      Future<GenAiStatus> statusFor(Object? r) async {
        reply = r;
        return (await backend.statusReport()).status;
      }

      expect(await statusFor({'status': 'available'}), GenAiStatus.available);
      expect(
        await statusFor({'status': 'downloadable'}),
        GenAiStatus.downloadable,
      );
      expect(await statusFor({'status': 'notEnabled'}), GenAiStatus.notEnabled);
      expect(
        await statusFor({'status': 'unsupported'}),
        GenAiStatus.unsupported,
      );
      expect(await statusFor({'status': 'someday'}), GenAiStatus.unknown);
      expect(await statusFor({'status': 3}), GenAiStatus.unavailable);
      expect(await statusFor({}), GenAiStatus.unavailable);
      expect(await statusFor(null), GenAiStatus.unavailable);

      reply = {
        'status': 'available',
        'code': 3,
        'variant': 'stable/fast',
        'served': 'stable/full, stable/fast',
        'tokenLimit': 4000,
      };
      final report = await backend.statusReport();
      expect(report.code, 3);
      expect(report.variant, 'stable/fast');
      expect(report.hasSizeChoice, isTrue);
      expect(report.tokenLimit, 4000);
    });

    test('a platform error is unreachable, not unavailable', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom', message: 'x'),
      );
      final report = await MethodChannelGenAiBackend().statusReport();
      expect(report.status, GenAiStatus.unreachable);
      expect(report.detail, 'boom: x');
    });

    test('an unregistered channel on iOS is unreachable', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final report = await MethodChannelGenAiBackend().statusReport();
      expect(report.status, GenAiStatus.unreachable);
      expect(report.detail, 'channel not registered');
    });

    test('unsupported platforms never call the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return null;
      });
      final backend = MethodChannelGenAiBackend();
      expect((await backend.statusReport()).status, GenAiStatus.unsupported);
      expect(await backend.coreInfo(), isNull);
      expect(called, isFalse);
    });

    test('error codes map to failures', () {
      expect(
        MethodChannelGenAiBackend.failureForCode('background'),
        GenAiFailure.background,
      );
      expect(
        MethodChannelGenAiBackend.failureForCode('quota'),
        GenAiFailure.quota,
      );
      expect(
        MethodChannelGenAiBackend.failureForCode('guardrail'),
        GenAiFailure.guardrail,
      );
      expect(
        MethodChannelGenAiBackend.failureForCode('unsupportedLanguage'),
        GenAiFailure.unsupportedLanguage,
      );
      expect(
        MethodChannelGenAiBackend.failureForCode('whatever'),
        GenAiFailure.failed,
      );
    });

    test('Android choose is generate plus the line parser', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final methods = <String>[];
      Object? reply = 'romance, school';
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return reply;
      });
      final backend = MethodChannelGenAiBackend();
      final ids = await backend.choose(
        instructions: 'i',
        prompt: 'p',
        options: const ['romance', 'school', 'comedy'],
      );
      expect(ids, ['romance', 'school']);
      expect(methods, ['generate']);
      reply = 'I think it is a love story.';
      await expectLater(
        backend.choose(
          instructions: 'i',
          prompt: 'p',
          options: const ['romance'],
        ),
        throwsA(isA<GenAiException>()),
      );
    });

    test('Apple choose is native', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'choose');
        return ['comedy', 42];
      });
      final ids = await MethodChannelGenAiBackend().choose(
        instructions: 'i',
        prompt: 'p',
        options: const ['comedy'],
      );
      expect(ids, ['comedy']);
    });
  });
}
