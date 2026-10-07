/// Ported from MyTranscribe's engine_router_test.dart: every routing rule as a
/// pure case, with MyTranscribe's three fallback settings expressed as
/// application-supplied policies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr/testing.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// MyTranscribe's `sameModelOnCpu` setting.
const _cpuFallback = AsrFallbackPolicy([
  SameModelCpuFallback(),
], name: 'sameModelOnCpu');

/// MyTranscribe's `systemRecognizer` setting: only the system recogniser,
/// as the original switch did.
const _systemFallback = AsrFallbackPolicy([
  ModelIndependentFallback('system'),
], name: 'systemRecognizer');

const _whisper = AsrModel(
  id: 'local:whisper',
  displayName: 'Whisper',
  artifacts: {
    'whisper_cpp': ['w-ggml'],
  },
);

const _parakeet = AsrModel(
  id: 'local:parakeet',
  displayName: 'Parakeet',
  languages: ['en', 'de', 'fr'],
  artifacts: {
    'sherpa_onnx': ['p-onnx'],
  },
);

/// Purpose: A route of the Whisper model.
/// Inputs: The route's shape.
/// Returns: An [EngineRoute].
/// Side effects: None.
/// Notes: Internal helper used within this file only.
AsrRoute _w({
  ComputeDevice device = ComputeDevice.cpu,
  String? backend,
  EvidenceLevel evidence = EvidenceLevel.official,
  bool testedHere = false,
  bool available = true,
  SelfTestOutcome outcome = SelfTestOutcome.passed,
  double? rtf,
  AsrCapability segmentTimestamps = AsrCapability.supported,
}) => fakeAsrRoute(
  adapterId: 'whisper_cpp',
  modelId: _whisper.id,
  artifactId: 'w-ggml',
  device: device,
  backend: backend,
  evidence: evidence,
  testedHere: testedHere,
  available: available,
  health: RouteHealth(outcome, realTimeFactor: rtf),
  segmentTimestamps: segmentTimestamps,
);

/// Purpose: Route a Whisper job.
/// Inputs: The [routes], and the request's other parts.
/// Returns: The decision.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
AsrRouteDecision _route(
  List<AsrRoute> routes, {
  RouteRequest requested = RouteRequest.auto,
  AsrFallbackPolicy policy = _cpuFallback,
  AsrModel model = _whisper,
  Set<String> installed = const {'w-ggml', 'p-onnx'},
  List<String> languages = const [],
  bool requireSegmentTimestamps = false,
}) => AsrRouter.choose(
  AsrRoutingRequest(
    model: model,
    routes: routes,
    installedArtifacts: installed,
    requested: requested,
    fallback: policy,
    languages: languages,
    requireSegmentTimestamps: requireSegmentTimestamps,
  ),
);

void main() {
  final cpu = _w(rtf: 0.5, testedHere: true);

  group('the model', () {
    test('is refused for a language it does not transcribe', () {
      final route = fakeAsrRoute(
        adapterId: 'sherpa_onnx',
        modelId: _parakeet.id,
        artifactId: 'p-onnx',
        health: const RouteHealth(SelfTestOutcome.passed),
      );
      final decision = _route([route], model: _parakeet, languages: ['zh']);
      expect(decision.runs, isFalse);
      expect(decision.failure, AsrErrorCode.unsupportedLanguage);
      expect(_route([route], model: _parakeet, languages: ['en']).route, route);
    });

    test('is never swapped for another model', () {
      // Parakeet is installed and passing; the job asked for Whisper, which
      // has no route here. The answer is "not built", not Parakeet.
      final other = fakeAsrRoute(
        adapterId: 'sherpa_onnx',
        modelId: _parakeet.id,
        artifactId: 'p-onnx',
        health: const RouteHealth(SelfTestOutcome.passed),
      );
      final decision = _route([other]);
      expect(decision.runs, isFalse);
      expect(decision.failure, AsrErrorCode.backendNotBuilt);
    });

    test('with no package installed at all is "not downloaded" when this '
        'build could run it', () {
      // Adapters describe routes only for installed packages, so here there
      // are none; the adapters the build contains tell the two cases apart.
      final decision = AsrRouter.choose(
        const AsrRoutingRequest(
          model: _whisper,
          routes: [],
          installedArtifacts: {},
          fallback: _cpuFallback,
          builtAdapters: {'whisper_cpp'},
        ),
      );
      expect(decision.failure, AsrErrorCode.modelMissing);
      final unbuilt = AsrRouter.choose(
        const AsrRoutingRequest(
          model: _whisper,
          routes: [],
          installedArtifacts: {},
          fallback: _cpuFallback,
          builtAdapters: {'sherpa_onnx'},
        ),
      );
      expect(unbuilt.failure, AsrErrorCode.backendNotBuilt);
    });

    test('that is not downloaded says so', () {
      final decision = _route([cpu], installed: const {});
      expect(decision.failure, AsrErrorCode.modelMissing);
    });
  });

  group('the CPU, asked for by name', () {
    test('is the CPU route', () {
      final gpu = _w(device: ComputeDevice.gpu, testedHere: true, rtf: 0.1);
      expect(_route([cpu, gpu], requested: RouteRequest.cpu).route, cpu);
    });
  });

  group('a route asked for by name', () {
    final gpu = _w(
      device: ComputeDevice.gpu,
      evidence: EvidenceLevel.experimental,
    );

    test('runs when it can, even untested and experimental', () {
      final decision = _route([
        cpu,
        gpu,
      ], requested: RouteRequest.route(gpu.key));
      expect(decision.route, gpu);
      expect(decision.fallback, isNull);
    });

    test('that crashed falls back to the CPU under the default policy', () {
      final crashed = _w(
        device: ComputeDevice.gpu,
        outcome: SelfTestOutcome.crashed,
      );
      final decision = _route([
        cpu,
        crashed,
      ], requested: RouteRequest.route(crashed.key));
      expect(decision.route, cpu);
      expect(decision.fallback!.reason, AsrErrorCode.routeCrashed);
      expect(decision.fallback!.from, crashed.key);
      expect(decision.rejected[crashed.key], RouteRejection.crashed);
    });

    test('that crashed fails the job when the policy allows nothing', () {
      final crashed = _w(
        device: ComputeDevice.gpu,
        outcome: SelfTestOutcome.crashed,
      );
      final decision = _route(
        [cpu, crashed],
        requested: RouteRequest.route(crashed.key),
        policy: AsrFallbackPolicy.none,
      );
      expect(decision.runs, isFalse);
      expect(decision.failure, AsrErrorCode.routeCrashed);
    });

    test('whose driver is missing falls back with that reason', () {
      final missing = _w(device: ComputeDevice.gpu, available: false);
      final decision = _route([
        cpu,
        missing,
      ], requested: RouteRequest.route(missing.key));
      expect(decision.route, cpu);
      expect(decision.fallback!.reason, AsrErrorCode.driverMissing);
    });

    test('goes to the system recogniser only when the policy says so', () {
      final failed = _w(
        device: ComputeDevice.gpu,
        outcome: SelfTestOutcome.failed,
      );
      final system = fakeAsrRoute(
        adapterId: 'system',
        modelIndependent: true,
        modelId: '',
        artifactId: '',
        backend: 'os',
      );
      final decision = _route(
        [cpu, failed, system],
        requested: RouteRequest.route(failed.key),
        policy: _systemFallback,
      );
      expect(decision.route, system);
      expect(decision.fallback!.toRouteKey, system.key);
      expect(
        _route([
          cpu,
          failed,
          system,
        ], requested: RouteRequest.route(failed.key)).route,
        cpu,
        reason: 'the default policy stays with the same model',
      );
    });
  });

  group('Auto (D20)', () {
    test('takes an accelerator tested on this kind of device', () {
      final gpu = _w(
        device: ComputeDevice.gpu,
        evidence: EvidenceLevel.experimental,
        testedHere: true,
        rtf: 0.9,
      );
      expect(_route([cpu, gpu]).route, gpu);
    });

    test('takes an untested A or B route that passed and beat the CPU', () {
      for (final evidence in [
        EvidenceLevel.official,
        EvidenceLevel.community,
      ]) {
        final gpu = _w(device: ComputeDevice.gpu, evidence: evidence, rtf: 0.2);
        expect(_route([cpu, gpu]).route, gpu, reason: evidence.name);
      }
    });

    test('leaves an untested B route that was slower than the CPU', () {
      final gpu = _w(
        device: ComputeDevice.gpu,
        evidence: EvidenceLevel.community,
        rtf: 0.8,
      );
      final decision = _route([cpu, gpu]);
      expect(decision.route, cpu);
      expect(decision.rejected[gpu.key], RouteRejection.notFasterThanCpu);
    });

    test('never takes an untested E or U route, however fast', () {
      for (final evidence in [EvidenceLevel.experimental, EvidenceLevel.none]) {
        final gpu = _w(
          device: ComputeDevice.gpu,
          evidence: evidence,
          rtf: 0.01,
        );
        final decision = _route([cpu, gpu]);
        expect(decision.route, cpu, reason: evidence.name);
        expect(decision.rejected[gpu.key], RouteRejection.untestedForAuto);
      }
    });

    test('does not count an unknown speed as a win', () {
      final unmeasured = _w(testedHere: true);
      final gpu = _w(device: ComputeDevice.gpu, rtf: 0.1);
      final decision = _route([unmeasured, gpu]);
      expect(decision.route, unmeasured);
      expect(decision.rejected[gpu.key], RouteRejection.notFasterThanCpu);
    });

    test('waits for an accelerator to pass its check', () {
      final gpu = _w(
        device: ComputeDevice.gpu,
        testedHere: true,
        outcome: SelfTestOutcome.notRun,
      );
      final decision = _route([cpu, gpu]);
      expect(decision.route, cpu);
      expect(decision.rejected[gpu.key], RouteRejection.notChecked);
    });

    test('prefers a route tested here over a faster untested one', () {
      final tested = _w(
        device: ComputeDevice.gpu,
        backend: 'opencl',
        testedHere: true,
        rtf: 0.4,
      );
      final untested = _w(device: ComputeDevice.npu, backend: 'qnn', rtf: 0.1);
      expect(_route([cpu, tested, untested]).route, tested);
    });

    test('runs an unchecked CPU route after its check', () {
      final unchecked = _w(outcome: SelfTestOutcome.notRun);
      final decision = _route([unchecked]);
      expect(decision.route, unchecked);
      expect(decision.needsSelfTest, isTrue);
    });

    test('fails rather than fall to an untested E route without a CPU', () {
      final broken = _w(outcome: SelfTestOutcome.failed);
      final gpu = _w(
        device: ComputeDevice.gpu,
        evidence: EvidenceLevel.experimental,
        rtf: 0.1,
      );
      final decision = _route([broken, gpu]);
      expect(decision.runs, isFalse);
      expect(decision.rejected[broken.key], RouteRejection.checkFailed);
      expect(decision.rejected[gpu.key], RouteRejection.untestedForAuto);
    });

    test('passes over a route without the timestamps the job needs', () {
      final bare = _w(
        backend: 'cpu-bare',
        segmentTimestamps: AsrCapability.unsupported,
      );
      final decision = _route([bare], requireSegmentTimestamps: true);
      expect(decision.runs, isFalse);
      expect(decision.failure, AsrErrorCode.unsupportedFeature);
      expect(decision.rejected[bare.key], RouteRejection.lacksTimestamps);
    });
  });

  group('a route that fails mid-job', () {
    final gpu = _w(device: ComputeDevice.gpu, testedHere: true, rtf: 0.1);
    AsrRoutingRequest request(AsrFallbackPolicy policy) => AsrRoutingRequest(
      model: _whisper,
      routes: [cpu, gpu],
      installedArtifacts: const {'w-ggml'},
      fallback: policy,
    );

    test('moves to the CPU when the device is lost', () {
      final decision = AsrRouter.fallbackAfter(
        request(_cpuFallback),
        gpu,
        AsrErrorCode.deviceLost,
      );
      expect(decision.route, cpu);
      expect(decision.fallback!.reason, AsrErrorCode.deviceLost);
    });

    test('fails when the policy allows nothing', () {
      final decision = AsrRouter.fallbackAfter(
        request(AsrFallbackPolicy.none),
        gpu,
        AsrErrorCode.deviceLost,
      );
      expect(decision.failure, AsrErrorCode.deviceLost);
    });

    test('fails for a problem the CPU would have too', () {
      final decision = AsrRouter.fallbackAfter(
        request(_cpuFallback),
        gpu,
        AsrErrorCode.modelCorrupt,
      );
      expect(decision.failure, AsrErrorCode.modelCorrupt);
    });

    test('has nowhere to go from the CPU', () {
      final decision = AsrRouter.fallbackAfter(
        request(_cpuFallback),
        cpu,
        AsrErrorCode.outOfMemory,
      );
      expect(decision.failure, AsrErrorCode.outOfMemory);
    });
  });

  test('error codes have the wire spelling the docs use', () {
    expect(AsrErrorCode.modelMissing.wire, 'MODEL_MISSING');
    expect(AsrErrorCode.routeCrashed.wire, 'ROUTE_CRASHED');
    expect(AsrErrorCode.parse('OUT_OF_MEMORY'), AsrErrorCode.outOfMemory);
    expect(EvidenceLevel.parse('bogus'), EvidenceLevel.none);
    expect(EvidenceLevel.community.letter, 'B');
  });
}
