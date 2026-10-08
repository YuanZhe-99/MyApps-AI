import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

ArtifactManifest _m(Map<String, dynamic> extra, {String quant = 'q4_k_m'}) =>
    ArtifactManifest(
      artifactId: 'a',
      modelId: 'local:a',
      backendId: 'llama.cpp',
      format: ArtifactFormat.gguf,
      revision: 'r',
      quantization: quant,
      files: const [
        ArtifactFile(path: 'a.gguf', bytes: 1, sha256: 'x', sourceUrl: 'u'),
      ],
      licenseId: 'MIT',
      extraJson: extra,
    );

void main() {
  test('names read Vendor: Name (QUANT), alias first', () {
    final m = _m({artifactVendorKey: 'Qwen', artifactNameKey: 'Qwen3.5 0.8B'});
    expect(artifactDisplayName(m), 'Qwen: Qwen3.5 0.8B (Q4_K_M)');
    expect(artifactDisplayName(m, alias: ' Mine '), 'Mine');
    expect(artifactDisplayName(m, alias: '  '), 'Qwen: Qwen3.5 0.8B (Q4_K_M)');
    expect(
      artifactDisplayName(
        _m({
          artifactVendorKey: 'Google',
          artifactNameKey: 'Gemma 4 E2B',
          artifactQuantizationLabelKey: 'Q4_0 QAT',
        }, quant: 'q4_0'),
      ),
      'Google: Gemma 4 E2B (Q4_0 QAT)',
    );
    expect(artifactDisplayName(_m({artifactNameKey: 'X'}, quant: '')), 'X');
    expect(artifactDisplayName(_m({})), 'local:a');
  });
}
