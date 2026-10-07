/// Ported from MyTranscribe's route-check tests: the ASR fixture run through
/// myapps_ai_models' SelfTestRunner, with the fake engine. Also covers the
/// registry, crash guard and record compatibility.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr/testing.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';
import 'package:path/path.dart' as p;

void main() {
  const expected = 'and so my fellow americans ask not what your country';
  late Directory root;
  late LocalEngineStateStore state;
  late AsrSmokeClip clip;
  final route = fakeAsrRoute(
    adapterId: 'whisper_cpp',
    modelId: 'local:w',
    artifactId: 'w',
    device: ComputeDevice.gpu,
  );
  const manifest = ArtifactManifest(
    artifactId: 'w',
    modelId: 'local:w',
    backendId: 'whisper_cpp',
    format: ArtifactFormat.ggml,
    revision: 'r',
    files: [],
    licenseId: 'MIT',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('myapps_asr_selftest_');
    state = LocalEngineStateStore(
      file: () async => File(p.join(root.path, 'state.json')),
    );
    clip = AsrSmokeClip(
      wav: File('assets/jfk.wav'),
      expectedText: expected,
      seconds: 10,
    );
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<SelfTestRecord> check(FakeAsrWindow window) async {
    final engine = FakeAsrEngine(
      adapterId: 'whisper_cpp',
      routes: [route],
      script: (_, _) => window,
    );
    final record = await SelfTestRunner(store: state).run(
      AsrSelfTestFixture(
        engine: engine,
        route: route,
        manifest: manifest,
        artifactDir: root,
        clip: clip,
      ),
    );
    expect(engine.released, hasLength(1), reason: 'always released');
    final loaded = await state.load();
    expect(loaded.inFlight, isNull, reason: 'marker cleared');
    expect(loaded.outcomeFor(route.fingerprint), record.outcome);
    return record;
  }

  test('passes a route that says the right words', () async {
    final record = await check(
      FakeAsrWindow.text(
        'And so, my fellow Americans, ask not what your country',
      ),
    );
    expect(record.outcome, SelfTestOutcome.passed);
    expect(record.score, 1);
    expect(record.metric(asrRealTimeFactorMetric), isNotNull);
    // Same JSON keys as MyTranscribe's SmokeTestRecord.
    final json = record.toJson();
    expect(json.keys, containsAll(['text', 'similarity', 'realTimeFactor']));
  });

  test('fails a route that says something else', () async {
    final record = await check(FakeAsrWindow.text('the the the the'));
    expect(record.outcome, SelfTestOutcome.failed);
    expect(record.reason, contains('%'));
  });

  test('fails a route that errors, with its code', () async {
    final record = await check(
      const FakeAsrWindow(
        error: AsrException(AsrErrorCode.deviceLost, 'driver timeout'),
      ),
    );
    expect(record.outcome, SelfTestOutcome.failed);
    expect(record.reason, startsWith('DEVICE_LOST'));
  });

  test(
    'fails a route whose prepare throws, still clearing the marker',
    () async {
      final engine = FakeAsrEngine(adapterId: 'whisper_cpp', routes: [route]);
      engine.prepareError[route.key] = const AsrException(
        AsrErrorCode.outOfMemory,
        'too big',
      );
      final record = await SelfTestRunner(store: state).run(
        AsrSelfTestFixture(
          engine: engine,
          route: route,
          manifest: manifest,
          artifactDir: root,
          clip: clip,
        ),
      );
      expect(record.reason, startsWith('OUT_OF_MEMORY'));
      expect((await state.load()).inFlight, isNull);
    },
  );

  test('the registry attaches health and skips a throwing adapter', () async {
    await check(FakeAsrWindow.text(expected));
    final registry = AsrEngineRegistry(
      engines: [
        FakeAsrEngine(adapterId: 'whisper_cpp', routes: [route]),
        _ThrowingEngine(),
      ],
      artifacts: AsrArtifactSource.fixed(const [manifest]),
      state: state,
    );
    final routes = await registry.routes();
    expect(routes.single.health.outcome, SelfTestOutcome.passed);
    expect(routes.single.health.realTimeFactor, isNotNull);
    expect(registry.builtAdapters, {'whisper_cpp', 'broken'});
    expect(registry.engine('broken'), isA<_ThrowingEngine>());
  });

  test('a crash inside the guard is recovered as crashed', () async {
    final guard = AsrCrashGuard(state);
    // Simulate a process that died: the marker is written, never cleared.
    await state.markInFlight(
      routeKey: route.key,
      fingerprint: route.fingerprint,
      jobId: 'job',
    );
    final marker = await guard.recover();
    expect(marker!.jobId, 'job');
    expect(
      (await state.load()).outcomeFor(route.fingerprint),
      SelfTestOutcome.crashed,
    );
    // A normal call clears its marker even when it throws.
    await expectLater(
      guard.run(route, () async => throw StateError('x')),
      throwsStateError,
    );
    expect((await state.load()).inFlight, isNull);
  });

  test('MyTranscribe state files keep their app fields and speeds', () async {
    final file = File(p.join(root.path, 'state.json'));
    await file.writeAsString(
      jsonEncode({
        'smokeTests': {
          route.fingerprint.encode(): {
            'routeKey': route.key,
            'outcome': 'passed',
            'checkedAt': '2026-03-01T10:00:00.000Z',
            'similarity': 0.95,
            'realTimeFactor': 0.4,
          },
        },
        'routeChoices': {'local:w': 'cpu'},
        'fallbackPolicy': 'none',
      }),
    );
    final health = RouteHealth.fromRecord(
      (await state.load()).selfTestFor(route.fingerprint),
    );
    expect(health.outcome, SelfTestOutcome.passed);
    expect(health.realTimeFactor, 0.4);
    await state.clearInFlight();
    final written = jsonDecode(await file.readAsString()) as Map;
    expect(written['routeChoices'], {'local:w': 'cpu'});
    expect(written['fallbackPolicy'], 'none');
  });
}

class _ThrowingEngine implements AsrEngine {
  @override
  String get adapterId => 'broken';

  @override
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests) =>
      throw StateError('broken');

  @override
  Future<void> cancel(String jobId) async {}

  @override
  Future<AsrSession> prepare(AsrPrepareRequest request) =>
      throw UnimplementedError();

  @override
  Future<void> release(String sessionId) async {}

  @override
  Stream<AsrEvent> transcribe(AsrRequest request) => throw UnimplementedError();
}
