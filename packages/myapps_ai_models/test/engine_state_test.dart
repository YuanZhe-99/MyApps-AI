import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// A state file as MyTranscribe writes it, with app and future fields.
const _legacy = '''
{
  "futureField": {"keep": true},
  "smokeTests": {
    "whisper_cpp@1.8|abc|15|drv|Adreno|f16": {
      "routeKey": "whisper_cpp:base:vulkan",
      "outcome": "passed",
      "checkedAt": "2026-03-01T10:00:00.000Z",
      "text": "and so my fellow americans",
      "similarity": 0.95,
      "realTimeFactor": 0.4
    }
  },
  "routeChoices": {"local:whisper-base": "cpu"},
  "fallbackPolicy": "none",
  "allowServerSpeechRecognition": true
}
''';

const _fp = HealthFingerprint(
  runtimeVersion: 'whisper_cpp@1.8',
  modelHash: 'abc',
  osVersion: '15',
  driverVersion: 'drv',
  deviceId: 'Adreno',
  precision: 'f16',
);

/// A scripted fixture.
class _Fixture extends SelfTestFixture<String> {
  /// Purpose: Create a fixture. Inputs: [answer], [fingerprint], [error].
  /// Returns: Fixture. Side effects: None. Notes: None.
  _Fixture(this.answer, this.fingerprint, {this.error});

  /// Purpose: Scripted answer. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String answer;

  /// Purpose: Scripted error. Inputs: None. Returns: Object or null.
  /// Side effects: None. Notes: None.
  final Object? error;

  /// Purpose: Count runs. Inputs: None. Returns: int. Side effects: None.
  /// Notes: None.
  int runs = 0;

  /// Purpose: Count releases. Inputs: None. Returns: int. Side effects: None.
  /// Notes: None.
  int releases = 0;

  /// Purpose: Fingerprint. Inputs: None. Returns: Fingerprint.
  /// Side effects: None. Notes: None.
  @override
  final HealthFingerprint fingerprint;

  /// Purpose: Route. Inputs: None. Returns: String. Side effects: None.
  /// Notes: None.
  @override
  String get routeKey => 'llama_cpp:qwen:cpu';

  /// Purpose: Run. Inputs: None. Returns: Answer. Side effects: Counts.
  /// Notes: Throws [error] when set.
  @override
  Future<String> run() async {
    runs++;
    if (error != null) throw error!;
    return answer;
  }

  /// Purpose: Judge. Inputs: [result], [elapsed]. Returns: Evaluation.
  /// Side effects: None. Notes: Passes on exact "4".
  @override
  SelfTestEvaluation evaluate(String result, Duration elapsed) =>
      SelfTestEvaluation(
        passed: result.trim() == '4',
        score: result.trim() == '4' ? 1 : 0,
        output: result,
        reason: 'expected 4',
        metrics: const {'tokensPerSecond': 12.5},
      );

  /// Purpose: Release. Inputs: None. Returns: None. Side effects: Counts.
  /// Notes: None.
  @override
  Future<void> release() async => releases++;
}

/// Purpose: Verify state persistence, crash recovery and self-tests.
/// Inputs: None. Returns: None. Side effects: Temp files. Notes: None.
void main() {
  late Directory temp;
  late File file;
  late LocalEngineStateStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('models_state_');
    file = File('${temp.path}/local_engine_state.json');
    store = LocalEngineStateStore(
      file: () async => file,
      clock: () => DateTime.utc(2026, 10, 6, 12),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  test('MyTranscribe state parses; app and unknown fields survive', () async {
    await file.writeAsString(_legacy);
    final state = await store.load();
    final record = state.selfTestFor(_fp)!;
    expect(record.outcome, SelfTestOutcome.passed);
    expect(record.score, 0.95);
    expect(record.metric('realTimeFactor'), 0.4);
    expect(_fp.encode(), 'whisper_cpp@1.8|abc|15|drv|Adreno|f16');

    await store.recordSelfTest(
      _fp.copyForTest(precision: 'q8'),
      SelfTestRecord(
        routeKey: 'r',
        outcome: SelfTestOutcome.failed,
        checkedAt: DateTime.utc(2026),
      ),
    );
    final written = jsonDecode(await file.readAsString());
    expect(written['futureField'], {'keep': true});
    expect(written['routeChoices'], {'local:whisper-base': 'cpu'});
    expect(written['fallbackPolicy'], 'none');
    expect(written['allowServerSpeechRecognition'], true);
    final kept = written['smokeTests'][_fp.encode()];
    expect(kept['realTimeFactor'], 0.4);
    expect(kept['text'], 'and so my fellow americans');
    expect(await file.readAsString(), contains('\n  "'));
  });

  test('corrupt state file is set aside on write, not overwritten', () async {
    await file.writeAsString('{not json');
    expect((await store.read()).unreadable, isTrue);
    expect((await store.load()).selfTests, isEmpty);
    // Lenient read renames nothing.
    expect(await file.readAsString(), '{not json');

    await store.clearInFlight();
    final aside = File(store.lastSetAsidePath!);
    expect(aside.path, contains('local_engine_state.json.unreadable-'));
    expect(aside.path, isNot(contains(':')));
    expect(await aside.readAsString(), '{not json');
    expect((await store.read()).unreadable, isFalse);
  });

  test('non-object JSON is unreadable; blank is empty', () async {
    await file.writeAsString('[1]');
    expect((await store.read()).unreadable, isTrue);
    await file.writeAsString('  ');
    expect((await store.read()).unreadable, isFalse);
  });

  test('in-flight marker becomes a crashed record at next start', () async {
    await store.markInFlight(routeKey: 'gpu-route', fingerprint: _fp);
    final raw = jsonDecode(await file.readAsString());
    expect(raw['inFlight']['smokeKey'], _fp.encode());

    final marker = await store.recoverFromCrash();
    expect(marker?.routeKey, 'gpu-route');
    final state = await store.load();
    expect(state.inFlight, isNull);
    expect(state.outcomeFor(_fp), SelfTestOutcome.crashed);
    expect(state.outcomeFor(_fp).allowsUse, isFalse);
    expect(await store.recoverFromCrash(), isNull);
  });

  test('concurrent updates do not lose writes', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++)
        store.recordSelfTest(
          _fp.copyForTest(precision: 'p$i'),
          SelfTestRecord(
            routeKey: 'r$i',
            outcome: SelfTestOutcome.passed,
            checkedAt: DateTime.utc(2026),
          ),
        ),
    ]);
    expect((await store.load()).selfTests, hasLength(10));
  });

  test('runner reuses only a matching fingerprint', () async {
    final runner = SelfTestRunner(store: store);
    final first = _Fixture('4', _fp);
    final record = await runner.ensure(first);
    expect(record.outcome, SelfTestOutcome.passed);
    expect(record.metric('tokensPerSecond'), 12.5);
    expect(first.runs, 1);
    expect(first.releases, 1);
    expect((await store.load()).inFlight, isNull);

    final same = _Fixture('4', _fp);
    await runner.ensure(same);
    expect(same.runs, 0);

    final newDriver = _fp.copyForTest(driverVersion: 'drv2');
    final changed = _Fixture('5', newDriver);
    final rerun = await runner.ensure(changed);
    expect(changed.runs, 1);
    expect(rerun.outcome, SelfTestOutcome.failed);
    expect(rerun.reason, 'expected 4');
    final state = await store.load();
    expect(state.outcomeFor(_fp), SelfTestOutcome.passed);
    expect(state.staleFor('llama_cpp:qwen:cpu', newDriver), [_fp.encode()]);
  });

  test('a throwing fixture is a failed record, never an exception', () async {
    final runner = SelfTestRunner(store: store);
    final fixture = _Fixture('', _fp, error: StateError('load failed'));
    final record = await runner.run(fixture);
    expect(record.outcome, SelfTestOutcome.failed);
    expect(record.reason, contains('load failed'));
    expect(fixture.releases, 1);
    expect((await store.load()).inFlight, isNull);
  });
}

/// Test-only fingerprint variation.
extension on HealthFingerprint {
  /// Purpose: Copy with one part changed. Inputs: Parts. Returns: Copy.
  /// Side effects: None. Notes: Test helper.
  HealthFingerprint copyForTest({String? precision, String? driverVersion}) =>
      HealthFingerprint(
        runtimeVersion: runtimeVersion,
        modelHash: modelHash,
        osVersion: osVersion,
        driverVersion: driverVersion ?? this.driverVersion,
        deviceId: deviceId,
        precision: precision ?? this.precision,
      );
}
