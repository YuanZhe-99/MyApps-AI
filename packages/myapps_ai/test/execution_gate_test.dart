import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// Purpose: Verify lock and obsolete-result handling. Inputs: None.
/// Returns: None. Side effects: Runs fake operations. Notes: No platform model.
void main() {
  test(
    'off refuses before body, concurrent request refuses, invalidated result drops',
    () async {
      final gate = AiExecutionGate();
      var enabled = false;
      var calls = 0;
      final reply = Completer<String>();
      Future<String> run() => gate.run(
        enabled: () => enabled,
        body: (_) {
          calls++;
          return reply.future;
        },
        cancel: () async {},
        unavailable: () => 'off',
        occupied: () => 'busy',
        cancelled: () => 'cancelled',
        timedOut: () => 'timeout',
        timeout: const Duration(seconds: 10),
      );
      await expectLater(run(), throwsA('off'));
      expect(calls, 0);
      enabled = true;
      final first = run();
      final rejected = expectLater(first, throwsA('cancelled'));
      await expectLater(run(), throwsA('busy'));
      gate.invalidate();
      reply.complete('old');
      await rejected;
      expect(gate.busy, isFalse);
    },
  );

  test(
    'timeout holds slot until cancellation completes and ignores late body',
    () async {
      final gate = AiExecutionGate();
      final reply = Completer<String>();
      final cleanup = Completer<void>();
      var cancellations = 0;
      final result = gate.run(
        enabled: () => true,
        body: (_) => reply.future,
        cancel: () {
          cancellations++;
          return cleanup.future;
        },
        unavailable: () => 'off',
        occupied: () => 'busy',
        cancelled: () => 'cancelled',
        timedOut: () => 'timeout',
        timeout: const Duration(milliseconds: 1),
      );
      final failed = expectLater(result, throwsA('timeout'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cancellations, 1);
      expect(gate.busy, isTrue);
      reply.complete('late');
      cleanup.complete();
      await failed;
      expect(gate.busy, isFalse);
    },
  );
}
