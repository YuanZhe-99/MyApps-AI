import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// A manifest in MyTranscribe's written form, with fields from a newer build.
const _legacy = '''
{
  "futureTop": {"nested": [1, 2]},
  "artifactId": "whisper-base-q5_1",
  "modelId": "local:whisper-base",
  "adapterId": "whisper_cpp",
  "format": "ggml",
  "quantization": "q5_1",
  "revision": "abc123",
  "files": [
    {
      "path": "ggml-base-q5_1.bin",
      "bytes": 10,
      "sha256": "ABCDEF",
      "sourceUrl": "https://huggingface.co/x",
      "futureFile": true
    },
    {
      "path": "encoder.mlmodelc.zip",
      "bytes": 5,
      "sha256": "00",
      "sourceUrl": "https://huggingface.co/y",
      "platforms": ["ios", "macos"],
      "unpack": "zip",
      "unpackedBytes": 9
    }
  ],
  "licenseId": "MIT",
  "licenseUrl": "https://l",
  "attribution": "OpenAI",
  "minimumRamBytes": 1000,
  "ramEstimateSource": "documented",
  "installedAt": "2026-01-01T00:00:00.000Z",
  "installed": [{"path": "ggml-base-q5_1.bin", "bytes": 10, "sha256": "abcdef"}]
}
''';

/// Purpose: Verify manifest compatibility and filters. Inputs: None.
/// Returns: None. Side effects: None. Notes: Pure value tests.
void main() {
  test('MyTranscribe manifest parses and round-trips with unknown fields', () {
    final json = jsonDecode(_legacy) as Map<String, dynamic>;
    final manifest = ArtifactManifest.fromJson(json);
    expect(manifest.backendId, 'whisper_cpp');
    expect(manifest.format, ArtifactFormat.ggml);
    expect(manifest.files.first.sha256, 'abcdef');
    expect(manifest.files.last.unpack, ArchiveKind.zip);
    expect(manifest.ramEstimateSource, EstimateSource.documented);
    expect(manifest.installedBytes, 10);
    expect(manifest.installedAt, DateTime.utc(2026));

    final written = manifest.toJson();
    expect(written['futureTop'], {
      'nested': [1, 2],
    });
    expect((written['files'] as List).first['futureFile'], true);
    expect(written.containsKey('compatibleRuntimes'), isFalse);
    expect(written.containsKey('abis'), isFalse);
    // Re-encoding is stable apart from the lower-cased hash.
    final again = ArtifactManifest.fromJson(
      jsonDecode(jsonEncode(written)) as Map<String, dynamic>,
    ).toJson();
    expect(jsonEncode(again), jsonEncode(written));
  });

  test('unknown format string round-trips instead of collapsing', () {
    final manifest = ArtifactManifest.fromJson({
      'artifactId': 'a',
      'format': 'exotic-v9',
      'files': const [],
    });
    expect(manifest.format.value, 'exotic-v9');
    expect(manifest.toJson()['format'], 'exotic-v9');
    expect(ArtifactFormat.parse(null), ArtifactFormat.unknown);
  });

  test('platform and ABI filters select files', () {
    const file = ArtifactFile(
      path: 'a',
      bytes: 3,
      sha256: '',
      sourceUrl: '',
      platforms: ['android'],
      abis: ['arm64'],
    );
    const common = ArtifactFile(path: 'b', bytes: 4, sha256: '', sourceUrl: '');
    const manifest = ArtifactManifest(
      artifactId: 'x',
      modelId: 'm',
      backendId: 'llama_cpp',
      format: ArtifactFormat.gguf,
      revision: 'r',
      files: [file, common],
      licenseId: 'MIT',
      compatibleRuntimes: ['llama_cpp', 'llama_cpp_vulkan'],
      platforms: ['android', 'linux'],
    );
    const phone = ModelPlatform('android', abi: 'arm64');
    const x86Phone = ModelPlatform('android', abi: 'x64');
    expect(manifest.downloadBytesFor(phone), 7);
    expect(manifest.downloadBytesFor(x86Phone), 4);
    expect(manifest.supports(const ModelPlatform('ios')), isFalse);
    expect(manifest.loadableBy('llama_cpp_vulkan'), isTrue);
    expect(manifest.loadableBy('mlx'), isFalse);
    expect(manifest.toJson()['platforms'], ['android', 'linux']);
  });

  test('ABI names drop the OS part', () {
    expect(ModelPlatform.current().platform, isNotEmpty);
    expect(ModelPlatform.current().abi, isNot(contains('_')));
  });
}
