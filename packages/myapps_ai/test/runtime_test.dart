import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// A backend that records every call and answers from fields.
class FakeBackend extends GenAiBackend {
  final calls = <String>[];
  GenAiStatusReport status = const GenAiStatusReport(GenAiStatus.available);
  final generateReplies = <Object>[];
  Completer<String>? hold;

  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) async {
    calls.add('status');
    return status;
  }

  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async {
    calls.add('info');
    return const GenAiCoreInfo(platform: 'android', installed: true);
  }

  @override
  Future<bool> download({
    void Function(int bytes, int total)? onProgress,
  }) async {
    calls.add('download');
    onProgress?.call(10, 100);
    status = const GenAiStatusReport(GenAiStatus.available);
    return true;
  }

  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async {
    calls.add('generate:$prompt');
    if (hold != null) return hold!.future;
    final next = generateReplies.isEmpty ? 'ok' : generateReplies.removeAt(0);
    if (next is GenAiException) throw next;
    return next as String;
  }

  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async {
    calls.add('choose:$prompt');
    return [options.first];
  }

  @override
  Future<void> prewarm() async => calls.add('prewarm');

  @override
  Future<void> cancel() async => calls.add('cancel');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnDeviceAiService', () {
    late FakeBackend backend;
    late DateTime now;
    late OnDeviceAiService service;

    setUp(() {
      backend = FakeBackend();
      now = DateTime(2026, 9, 24, 12);
      service = OnDeviceAiService(backend: backend, now: () => now);
    });

    test('with the switch off the backend is never called', () async {
      await service.refreshStatus();
      await service.prewarm();
      expect(await service.download(), isFalse);
      await expectLater(
        service.generate(instructions: 'i', prompt: 'p'),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'failure',
            GenAiFailure.unavailable,
          ),
        ),
      );
      await expectLater(
        service.choose(instructions: 'i', prompt: 'p', options: ['a']),
        throwsA(isA<GenAiException>()),
      );
      expect(backend.calls, isEmpty);
    });

    test('turning it on asks for status once, forced', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      expect(backend.calls, ['status', 'info']);
      expect(service.canGenerate, isTrue);
    });

    test('status is re-checked before every request', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      backend.calls.clear();
      expect(await service.generate(instructions: 'i', prompt: 'a'), 'ok');
      expect(backend.calls, ['status', 'generate:a']);
      backend.status = const GenAiStatusReport(GenAiStatus.downloadable);
      await expectLater(
        service.generate(instructions: 'i', prompt: 'b'),
        throwsA(isA<GenAiException>()),
      );
      expect(backend.calls.last, 'status');
    });

    test('interactive requests jump ahead of background ones', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      backend.calls.clear();
      final order = <String>[];
      final futures = [
        service
            .generate(
              instructions: 'i',
              prompt: 'bg1',
              priority: AiPriority.background,
            )
            .then(order.add),
        service
            .generate(
              instructions: 'i',
              prompt: 'bg2',
              priority: AiPriority.background,
            )
            .then(order.add),
        service.generate(instructions: 'i', prompt: 'fg').then(order.add),
      ];
      backend.generateReplies.addAll(['r1', 'r2', 'r3']);
      await Future.wait(futures);
      final generated = [
        for (final c in backend.calls)
          if (c.startsWith('generate:')) c.substring(9),
      ];
      expect(generated, ['fg', 'bg1', 'bg2']);
    });

    test('nothing runs while the app is in the background', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      backend.calls.clear();
      service.handleLifecycle(AppLifecycleState.paused);
      var done = false;
      final f = service
          .generate(
            instructions: 'i',
            prompt: 'x',
            priority: AiPriority.background,
          )
          .then((_) => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      expect(backend.calls, isEmpty);
      service.handleLifecycle(AppLifecycleState.resumed);
      await f;
      expect(done, isTrue);
    });

    test('a background refusal waits for the next resume', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      backend.generateReplies.add(
        const GenAiException(GenAiFailure.background),
      );
      await expectLater(
        service.generate(instructions: 'i', prompt: 'x'),
        throwsA(isA<GenAiException>()),
      );
      backend.calls.clear();
      var done = false;
      final f = service
          .generate(instructions: 'i', prompt: 'y')
          .then((_) => done = true);
      await pumpEventQueue();
      expect(done, isFalse);
      service.handleLifecycle(AppLifecycleState.resumed);
      await f;
      expect(done, isTrue);
    });

    test(
      'busy backs off background work, doubling up to five minutes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await service.setEnabled(true);
        backend.generateReplies.add(const GenAiException(GenAiFailure.busy));
        await expectLater(
          service.generate(
            instructions: 'i',
            prompt: 'x',
            priority: AiPriority.background,
          ),
          throwsA(isA<GenAiException>()),
        );
        expect(service.pausedUntil, now.add(OnDeviceAiService.initialBackoff));

        // A background job queued during the backoff does not run yet...
        backend.calls.clear();
        var done = false;
        unawaited(
          service
              .generate(
                instructions: 'i',
                prompt: 'y',
                priority: AiPriority.background,
              )
              .then((_) => done = true, onError: (_) => false),
        );
        await pumpEventQueue();
        expect(done, isFalse);
        expect(backend.calls, isEmpty);
        // ...but an interactive one still does.
        expect(await service.generate(instructions: 'i', prompt: 'z'), 'ok');
        await service.cancelBackground();
      },
    );

    test('quota stops background work for the rest of the day', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      backend.generateReplies.add(const GenAiException(GenAiFailure.quota));
      await expectLater(
        service.generate(
          instructions: 'i',
          prompt: 'x',
          priority: AiPriority.background,
        ),
        throwsA(isA<GenAiException>()),
      );
      expect(service.quotaReachedToday, isTrue);
      await expectLater(
        service.generate(
          instructions: 'i',
          prompt: 'y',
          priority: AiPriority.background,
        ),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'failure',
            GenAiFailure.quota,
          ),
        ),
      );
      now = now.add(const Duration(days: 1));
      expect(service.quotaReachedToday, isFalse);
    });

    test('a request that never answers times out', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      fakeAsync((async) {
        service.setEnabled(true);
        async.flushMicrotasks();
        backend.hold = Completer<String>();
        Object? error;
        service.generate(instructions: 'i', prompt: 'x').catchError((Object e) {
          error = e;
          return '';
        });
        async.elapse(OnDeviceAiService.timeout + const Duration(seconds: 1));
        expect(
          error,
          isA<GenAiException>().having(
            (e) => e.failure,
            'failure',
            GenAiFailure.timeout,
          ),
        );
      });
    });

    test('switching off fails queued work and cancels', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      service.handleLifecycle(AppLifecycleState.paused);
      final f = service.generate(instructions: 'i', prompt: 'x');
      final failed = expectLater(f, throwsA(isA<GenAiException>()));
      await service.setEnabled(false);
      await failed;
      expect(service.report.status, GenAiStatus.unsupported);
    });

    test('Windows never touches the backend even when enabled', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await service.setEnabled(true);
      expect(backend.calls, isEmpty);
      expect(service.report.status, GenAiStatus.unsupported);
    });

    test('download reports progress and re-reads the status', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      backend.status = const GenAiStatusReport(GenAiStatus.downloadable);
      await service.setEnabled(true);
      expect(service.canGenerate, isFalse);
      expect(await service.download(), isTrue);
      expect(service.canGenerate, isTrue);
      expect(backend.calls, contains('download'));
    });
  });
}
