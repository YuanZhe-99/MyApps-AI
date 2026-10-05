import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// Controllable backend for late replies.
class DelayedBackend extends CapabilityGenAiBackend {
  Completer<GenAiStatusReport>? statusHold;
  Completer<String>? generation;
  int infoCalls = 0;
  int cancellations = 0;

  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) async =>
      statusHold?.future ?? const GenAiStatusReport(GenAiStatus.available);
  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async {
    infoCalls++;
    return null;
  }

  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async => generation?.future ?? 'ok';
  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> prewarm() async {}
  @override
  Future<bool> download({void Function(int, int)? onProgress}) async => false;
  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async => [];
}

/// Purpose: Verify capability isolation and invalidation. Inputs: None.
/// Returns: None. Side effects: Installs test channel handlers. Notes: No native model.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'independent capability states and proofreading wire protocol',
    () async {
      const channel = MethodChannel('capability-test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'status') {
              return {
                'status': call.arguments['feature'] == 'proofread'
                    ? 'available'
                    : 'unavailable',
              };
            }
            if (call.method == 'proofread') return ['直しました。'];
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final backend = MethodChannelGenAiBackend(channel);
      expect((await backend.statusReport()).status, GenAiStatus.unavailable);
      expect(
        (await backend.capabilityReport(GenAiFeature.proofread)).status,
        GenAiStatus.available,
      );
      expect(await backend.downloadCapability(GenAiFeature.proofread), isTrue);
      expect(calls.last.arguments['feature'], 'proofread');
      expect(await backend.proofread('文'), ['直しました。']);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final count = calls.length;
      expect(
        (await backend.capabilityReport(GenAiFeature.proofread)).status,
        GenAiStatus.unsupported,
      );
      expect(calls.length, count);
    },
  );

  test('disable while status waits prevents subsequent info calls', () async {
    final backend = DelayedBackend()..statusHold = Completer();
    final service = OnDeviceAiService(backend: backend);
    addTearDown(service.dispose);
    final enabling = service.setEnabled(true);
    await service.setEnabled(false);
    backend.statusHold!.complete(
      const GenAiStatusReport(GenAiStatus.available),
    );
    await enabling;
    expect(backend.infoCalls, 0);
    expect(service.report.status, GenAiStatus.unsupported);
  });

  test('late generation after disable cannot publish success', () async {
    final backend = DelayedBackend()..generation = Completer();
    final service = OnDeviceAiService(backend: backend);
    addTearDown(service.dispose);
    await service.setEnabled(true);
    final answer = service.generate(instructions: 'i', prompt: 'p');
    final rejected = expectLater(answer, throwsA(isA<GenAiException>()));
    await pumpEventQueue();
    await service.setEnabled(false);
    backend.generation!.complete('stale');
    await rejected;
    expect(backend.cancellations, 1);
  });

  test('model preference invalidates an in-flight result', () async {
    final backend = DelayedBackend()..generation = Completer();
    final service = OnDeviceAiService(backend: backend);
    addTearDown(service.dispose);
    await service.setEnabled(true);
    final answer = service.generate(instructions: 'i', prompt: 'p');
    final rejected = expectLater(answer, throwsA(isA<GenAiException>()));
    await pumpEventQueue();
    await service.setPreferFast(true);
    backend.generation!.complete('old model');
    await rejected;
    expect(backend.cancellations, 1);
  });
}
