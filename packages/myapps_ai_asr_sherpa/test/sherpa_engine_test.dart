import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr_sherpa/myapps_ai_asr_sherpa.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

const _host = AsrHost(
  platform: 'linux',
  deviceClass: 'linux-x64',
  osVersion: 'test',
  threads: 4,
);

const _manifest = ArtifactManifest(
  artifactId: 'qwen-test',
  modelId: 'local:qwen-test',
  backendId: sherpaOnnxAdapterId,
  format: ArtifactFormat.onnx,
  revision: 'r1',
  files: [
    ArtifactFile(
      path: 'model.tar.bz2',
      bytes: 1,
      sha256: 'b',
      sourceUrl: 'https://example.invalid/model.tar.bz2',
    ),
  ],
  licenseId: 'Apache-2.0',
);

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('sherpa'));
  tearDown(() => temp.delete(recursive: true));

  void touch(String path) => File('${temp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  test('Qwen files are found at the top or one folder down', () {
    expect(findQwenFiles(temp), isNull);
    touch('pkg/encoder.int8.onnx');
    touch('pkg/decoder.int8.onnx');
    touch('pkg/conv_frontend.onnx');
    expect(findQwenFiles(temp), isNull);
    Directory('${temp.path}/pkg/tokenizer').createSync();
    expect(findQwenFiles(temp)!.encoder, endsWith('pkg/encoder.int8.onnx'));
  });

  test('diarizer models need both files', () async {
    final diarizer = SherpaDiarizer(
      models: () async => findDiarizerModels(temp),
      threads: 1,
    );
    expect(await diarizer.available(), isFalse);
    expect(
      () => diarizer.diarize('${temp.path}/none.wav'),
      throwsA(isA<AsrException>()),
    );
    touch('sherpa-onnx-pyannote-segmentation-3-0/model.onnx');
    touch('3dspeaker_campplus_sv_en_voxceleb_16k.onnx');
    final found = findDiarizerModels(temp)!;
    expect(found.segmentation, contains('segmentation'));
    expect(found.embedding, contains('campplus'));
    expect(await diarizer.available(), isTrue);
  });

  test('the prebuilt library loads and the route is CPU only', () async {
    final engine = SherpaOnnxEngine(host: _host);
    addTearDown(engine.dispose);
    expect(await engine.runtime(), sherpaVersion);
    final route = (await engine.probe([_manifest])).single;
    expect(route.key, 'sherpa_onnx:qwen-test:cpu');
    expect(route.available, isTrue);
    expect(route.maxWindowSeconds, qwenMaxWindowSeconds);
    expect(route.capabilities.segmentTimestamps, AsrCapability.unsupported);
    expect(
      route.fingerprint.runtimeVersion,
      'sherpa-onnx $sherpaVersion $sherpaBindingsVersion',
    );
    expect(route.fingerprint.deviceId, 'linux-x64');
  });

  test('preparing without the model files says what is missing', () async {
    final engine = SherpaOnnxEngine(host: _host);
    addTearDown(engine.dispose);
    final route = (await engine.probe([_manifest])).single;
    await expectLater(
      engine.prepare(
        AsrPrepareRequest(route: route, manifest: _manifest, artifactDir: temp),
      ),
      throwsA(
        isA<AsrException>().having(
          (e) => e.code,
          'code',
          AsrErrorCode.modelMissing,
        ),
      ),
    );
  });

  final qwen = Platform.environment['QWEN_TEST_DIR'];
  test(
    'Qwen3-ASR transcribes the JFK clip as one untimed segment',
    () async {
      final engine = SherpaOnnxEngine(host: _host);
      addTearDown(engine.dispose);
      final route = (await engine.probe([_manifest])).single;
      final session = await engine.prepare(
        AsrPrepareRequest(
          route: route,
          manifest: _manifest,
          artifactDir: Directory(qwen!),
        ),
      );
      final events = await engine
          .transcribe(
            AsrRequest(
              jobId: 'j',
              sessionId: session.sessionId,
              pcmWindow: File('../myapps_ai_asr/assets/jfk.wav'),
              windowSeconds: 11,
            ),
          )
          .toList();
      final segment = events
          .singleWhere((e) => e.type == AsrEventType.segment)
          .segment!;
      expect(
        segment.text.toLowerCase(),
        contains('ask not what your country can do for you'),
      );
      expect(segment.endSeconds, 11);
      expect(events.last.hasRealTimestamps, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: qwen == null ? 'set QWEN_TEST_DIR to an unpacked model' : false,
  );
}
