import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';

/// A scripted backend recording requests.
class ScriptedLlm implements LlmBackend {
  final requests = <LlmRequest>[];
  List<LlmEvent> script = const [LlmDelta('ok'), LlmDone(LlmFinish.stop)];
  int loads = 0;
  int cancels = 0;

  @override
  String get id => 'test';

  @override
  Set<LlmAbility> get abilities => {LlmAbility.streaming};

  @override
  Future<GenAiStatusReport> status() async =>
      const GenAiStatusReport(GenAiStatus.available);

  @override
  Future<void> load() async {
    loads++;
    throw const GenAiException(GenAiFailure.unavailable);
  }

  @override
  Future<void> unload() async {}

  @override
  Stream<LlmEvent> generate(LlmRequest request) {
    requests.add(request);
    return Stream.fromIterable(script);
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// Purpose: Verify streaming collection and prompt adaptation.
/// Inputs: None. Returns: None. Side effects: None. Notes: No model.
void main() {
  test('adapter maps instructions to system message and sampling', () async {
    final llm = ScriptedLlm()
      ..script = const [
        LlmDelta('Hel'),
        LlmDelta('lo'),
        LlmDone(LlmFinish.stop),
      ];
    final backend = LlmGenAiBackend(llm);
    expect(
      await backend.generate(
        instructions: 'be brief',
        prompt: 'hi',
        maxOutputTokens: 12,
      ),
      'Hello',
    );
    final r = llm.requests.single;
    expect(r.messages.map((m) => m.role), [LlmRole.system, LlmRole.user]);
    expect(r.sampling.maxOutputTokens, 12);
    expect(r.messages.first.toJson(), {
      'role': 'system',
      'content': 'be brief',
    });
  });

  test('choose validates replies and proofreading stays unsupported', () async {
    final llm = ScriptedLlm()
      ..script = const [LlmDelta('romance, x'), LlmDone(LlmFinish.stop)];
    final backend = LlmGenAiBackend(llm);
    expect(
      await backend.choose(
        instructions: '',
        prompt: 'p',
        options: const ['romance', 'school'],
      ),
      ['romance'],
    );
    llm.script = const [LlmDelta('a love story'), LlmDone(LlmFinish.stop)];
    await expectLater(
      backend.choose(instructions: '', prompt: 'p', options: const ['romance']),
      throwsA(isA<GenAiException>()),
    );
    expect(
      (await backend.capabilityReport(GenAiFeature.proofread)).status,
      GenAiStatus.unsupported,
    );
    await expectLater(backend.download(), throwsA(isA<GenAiException>()));
  });

  test('stream without done fails; prewarm swallows load errors', () async {
    await expectLater(
      collectLlm(Stream.fromIterable(const [LlmDelta('x')])),
      throwsA(isA<GenAiException>()),
    );
    final llm = ScriptedLlm();
    await LlmGenAiBackend(llm).prewarm();
    expect(llm.loads, 1);
    await LlmGenAiBackend(llm).cancel();
    expect(llm.cancels, 1);
  });

  test('metrics compute throughput only when measured', () {
    expect(const LlmMetrics().tokensPerSecond, isNull);
    expect(
      const LlmMetrics(
        outputTokens: 20,
        total: Duration(seconds: 2),
      ).tokensPerSecond,
      10,
    );
    unawaited(Future.value());
  });
}
