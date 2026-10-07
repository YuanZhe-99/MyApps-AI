import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_platform/myapps_ai_platform.dart';

/// Purpose: Verify the capability wire protocol. Inputs: None.
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
}
