import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// Purpose: Verify bounded fallback policy. Inputs: None. Returns: None.
/// Side effects: Runs fake generation. Notes: Business parsing supplied by consumers.
void main() {
  test('unusable primary falls back once and retains answered facts', () async {
    final calls = <String>[];
    final result = await generateWithFallback<String, List<String>>(
      primary: 'full',
      fallback: 'plain',
      generate: (facts) async {
        calls.add(facts);
        return facts == 'full' ? [] : ['ok'];
      },
      usable: (value) => value.isNotEmpty,
    );
    expect(result.$1, 'plain');
    expect(result.$2, ['ok']);
    expect(calls, ['full', 'plain']);
  });
  test(
    'quota propagates without fallback and guardrail retries only once',
    () async {
      for (final failure in [GenAiFailure.quota, GenAiFailure.guardrail]) {
        var calls = 0;
        await expectLater(
          generateWithFallback<String, String>(
            primary: 'full',
            fallback: 'plain',
            generate: (_) async {
              calls++;
              throw GenAiException(failure);
            },
            usable: (value) => value.isNotEmpty,
          ),
          throwsA(isA<GenAiException>()),
        );
        expect(calls, failure == GenAiFailure.quota ? 1 : 2);
      }
    },
  );
  test('usable primary and absent fallback do not generate twice', () async {
    var calls = 0;
    final result = await generateWithFallback<String, String>(
      primary: 'facts',
      generate: (_) async {
        calls++;
        return '';
      },
      usable: (value) => value.isNotEmpty,
    );
    expect(result, ('facts', ''));
    expect(calls, 1);
  });
}
