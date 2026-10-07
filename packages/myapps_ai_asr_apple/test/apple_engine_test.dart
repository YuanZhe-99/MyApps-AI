import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr_apple/myapps_ai_asr_apple.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

const _host = AsrHost(
  platform: 'linux',
  deviceClass: 'linux-x64',
  osVersion: 'test',
  threads: 4,
);

void main() {
  test('timed tokens are cut into sentences', () {
    final segments = appleSegments((
      text: 'Hello world. How are you?',
      tokens: [
        (piece: '▁Hello', start: 0.0, end: 0.4),
        (piece: '▁world', start: 0.4, end: 0.8),
        (piece: '.', start: 0.8, end: 0.9),
        (piece: '▁How', start: 1.2, end: 1.4),
        (piece: '▁are', start: 1.4, end: 1.5),
        (piece: '▁you', start: 1.5, end: 1.7),
        (piece: '?', start: 1.7, end: 1.8),
      ],
    ), 2);
    expect(segments.map((s) => s.text), ['Hello world.', 'How are you?']);
    expect(segments.last.startSeconds, 1.2);
  });

  test('text without times spans the window; silence gives nothing', () {
    final one = appleSegments((text: ' Hello. ', tokens: const []), 30);
    expect(one.single.text, 'Hello.');
    expect(one.single.endSeconds, 30);
    expect(appleSegments((text: '  ', tokens: const []), 30), isEmpty);
  });

  test('the system recogniser route is model-independent', () async {
    final engine = SystemRecognizerEngine(host: _host);
    addTearDown(engine.dispose);
    final route = (await engine.probe(const [])).single;
    expect(route.key, 'system:system-recognizer:speech');
    expect(route.modelIndependent, isTrue);
    expect(route.available, Platform.isMacOS || Platform.isIOS);
  });

  test('FluidAudio is unavailable where the bridge is absent', () async {
    final engine = FluidAudioEngine(host: _host);
    addTearDown(engine.dispose);
    const manifest = ArtifactManifest(
      artifactId: 'parakeet-coreml',
      modelId: 'local:parakeet',
      backendId: fluidAudioAdapterId,
      format: ArtifactFormat.coreml,
      revision: 'r1',
      files: [
        ArtifactFile(
          path: 'Encoder.mlmodelc/coremldata.bin',
          bytes: 1,
          sha256: '0123456789abcdef',
          sourceUrl: 'https://example.invalid/e',
        ),
      ],
      licenseId: 'CC-BY-4.0',
    );
    final route = (await engine.probe([manifest])).single;
    expect(route.key, 'fluidaudio:parakeet-coreml:ane');
    expect(route.device, ComputeDevice.npu);
    expect(route.fingerprint.modelHash, '01234567');
    if (!Platform.isMacOS && !Platform.isIOS) {
      expect(route.available, isFalse);
      await expectLater(
        engine.prepare(
          AsrPrepareRequest(
            route: route,
            manifest: manifest,
            artifactDir: Directory.systemTemp,
          ),
        ),
        throwsA(
          isA<AsrException>().having(
            (e) => e.code,
            'code',
            AsrErrorCode.backendNotBuilt,
          ),
        ),
      );
    }
  });
}
