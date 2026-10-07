import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr_whisper/myapps_ai_asr_whisper.dart';
import 'package:myapps_ai_asr_whisper/native.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

const _host = AsrHost(
  platform: 'linux',
  deviceClass: 'linux-x64',
  osVersion: 'test',
  threads: 4,
);

ArtifactManifest _manifest(String path, {String backend = 'whisper_cpp'}) =>
    ArtifactManifest(
      artifactId: 'whisper-test',
      modelId: 'local:whisper-test',
      backendId: backend,
      format: ArtifactFormat.ggml,
      revision: 'r1',
      files: [
        ArtifactFile(
          path: path,
          sourceUrl: 'https://example.invalid/$path',
          bytes: 1,
          sha256: 'a' * 64,
        ),
      ],
      licenseId: 'MIT',
    );

void main() {
  group('route naming and grades', () {
    test('backend names do not depend on device numbering', () {
      expect(gpuBackendName('Vulkan0'), 'vulkan');
      expect(gpuBackendName('GPUOpenCL'), 'opencl');
      expect(gpuBackendName('MTL0'), 'metal');
      expect(gpuBackendName('CUDA 1'), 'cuda1');
    });

    test('a second device of one kind gets its position', () {
      const info = WhisperRuntimeInfo(
        loaded: true,
        devices: [
          WhisperDevice('CPU', 'cpu', 0),
          WhisperDevice('Vulkan0', 'GPU A', 1),
          WhisperDevice('Vulkan1', 'GPU B', 2),
        ],
      );
      expect(info.gpuBackends(), ['vulkan', 'vulkan1']);
      expect(info.cpuName, 'cpu');
    });

    test('grades follow the support matrix', () {
      expect(
        gpuEvidence('metal', deviceClass: 'macos-arm64'),
        EvidenceLevel.community,
      );
      expect(
        gpuEvidence('vulkan', deviceClass: 'windows-x64'),
        EvidenceLevel.community,
      );
      expect(
        gpuEvidence('vulkan', deviceClass: 'android'),
        EvidenceLevel.experimental,
      );
      expect(
        gpuEvidence('metal', deviceClass: 'macos-arm64', parakeet: true),
        EvidenceLevel.experimental,
      );
      expect(gpuEvidence('cuda', deviceClass: 'linux-x64'), EvidenceLevel.none);
    });

    test('the model file is the .bin entry', () {
      expect(
        whisperModelFile(_manifest('ggml-tiny.bin'))?.path,
        'ggml-tiny.bin',
      );
      expect(whisperModelFile(_manifest('model.onnx')), isNull);
    });
  });

  group('library', () {
    test('loads with at least the CPU device', () {
      expect(WhisperLibrary.load(), greaterThan(0));
      expect(WhisperLibrary.version(), isNotEmpty);
      expect(WhisperLibrary.devices().map((d) => d.type), contains(0));
    });

    test('probe offers a CPU route and fingerprints it', () async {
      final engine = WhisperCppEngine(host: _host);
      addTearDown(engine.dispose);
      final routes = await engine.probe([
        _manifest('ggml-tiny.bin'),
        _manifest('other.bin', backend: 'parakeet_cpp'),
      ]);
      final cpu = routes.singleWhere((r) => r.isCpu);
      expect(cpu.key, 'whisper_cpp:whisper-test:cpu');
      expect(cpu.available, isTrue);
      expect(cpu.fingerprint.runtimeVersion, endsWith(whisperBindingsVersion));
      expect(cpu.fingerprint.modelHash, 'a' * 64);
    });
  });

  final model = Platform.environment['LASR_TEST_MODEL'];
  test(
    'transcribes the JFK clip through the engine, and cancels',
    () async {
      final dir = await Directory.systemTemp.createTemp('whisper-live');
      addTearDown(() => dir.delete(recursive: true));
      await File(model!).copy('${dir.path}/ggml-tiny.bin');
      final manifest = _manifest('ggml-tiny.bin');
      final engine = WhisperCppEngine(host: _host);
      addTearDown(engine.dispose);
      final route = (await engine.probe([
        manifest,
      ])).singleWhere((r) => r.isCpu);
      final session = await engine.prepare(
        AsrPrepareRequest(route: route, manifest: manifest, artifactDir: dir),
      );
      expect(session.placement, PlacementKind.cpu);
      final clip = File('../myapps_ai_asr/assets/jfk.wav');
      final events = await engine
          .transcribe(
            AsrRequest(
              jobId: 'j1',
              sessionId: session.sessionId,
              pcmWindow: clip,
              windowSeconds: 11,
              languages: const ['en'],
            ),
          )
          .toList();
      final text = events
          .where((e) => e.type == AsrEventType.segment)
          .map((e) => e.segment!.text)
          .join(' ')
          .toLowerCase();
      expect(text, contains('ask not what your country can do for you'));
      final done = events.last;
      expect(done.type, AsrEventType.completed);
      expect(done.hasRealTimestamps, isTrue);
      expect(done.placement, PlacementKind.cpu);

      final stream = engine.transcribe(
        AsrRequest(
          jobId: 'j2',
          sessionId: session.sessionId,
          pcmWindow: clip,
          windowSeconds: 11,
        ),
      );
      final types = <AsrEventType>[];
      Future<void>? cancelled;
      await for (final event in stream) {
        types.add(event.type);
        // Not awaited here: cancel completes after the stream's own cleanup,
        // which needs this listener to keep reading.
        if (event.type == AsrEventType.started) {
          cancelled = engine.cancel('j2');
        }
      }
      await cancelled;
      expect(types.last, AsrEventType.cancelled);
      await engine.release(session.sessionId);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: model == null ? 'set LASR_TEST_MODEL to a GGML model' : false,
  );
}
