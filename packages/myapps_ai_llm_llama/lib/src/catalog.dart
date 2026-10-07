import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'backend.dart';
import 'native/llama.dart' show llamaUpstreamTag;

/// Purpose: Build one single-file GGUF manifest pinned to a repository commit.
/// Inputs: Identity, repository, commit, file name, size and hash, licence.
/// Returns: The manifest. Side effects: None. Notes: Internal.
ArtifactManifest _gguf({
  required String artifactId,
  required String modelId,
  required String repository,
  required String commit,
  required String file,
  required int bytes,
  required String sha256,
  required String quantization,
  required String attribution,
  required int minimumBuild,
}) => ArtifactManifest(
  artifactId: artifactId,
  modelId: modelId,
  backendId: llamaCppBackendId,
  format: ArtifactFormat.gguf,
  quantization: quantization,
  revision: commit,
  files: [
    ArtifactFile(
      path: file,
      bytes: bytes,
      sha256: sha256,
      sourceUrl: 'https://huggingface.co/$repository/resolve/$commit/$file',
    ),
  ],
  licenseId: 'Apache-2.0',
  licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
  attribution: attribution,
  extraJson: {llamaMinimumBuildKey: minimumBuild},
);

/// Manifest field holding the first llama.cpp build that loads the model's
/// architecture.
const llamaMinimumBuildKey = 'llamaMinimumBuild';

/// llama.cpp build number of the binaries this package pins.
final int llamaPinnedBuild = int.parse(llamaUpstreamTag.substring(1));

/// Purpose: Read the first llama.cpp build that supports a model.
/// Inputs: [manifest]. Returns: The build number, or null when unrecorded.
/// Side effects: None. Notes: None.
int? llamaMinimumBuild(ArtifactManifest manifest) =>
    switch (manifest.extraJson[llamaMinimumBuildKey]) {
      final int build => build,
      _ => null,
    };

/// Purpose: List the catalog models a given llama.cpp build can load.
/// Inputs: [build], default [llamaPinnedBuild].
/// Returns: Supported entries, in catalog order.
/// Side effects: None.
/// Notes: An application that pins an older llama.cpp (for example to share
/// ggml with an older whisper.cpp) offers only these; an entry with no
/// recorded minimum is excluded.
List<ArtifactManifest> llamaCatalogFor([int? build]) => [
  for (final m in llamaModelCatalog)
    if (llamaMinimumBuild(m) case final min?
        when min <= (build ?? llamaPinnedBuild))
      m,
];

/// Qwen3.5 0.8B, 4-bit (Q4_K_M).
final qwen35_08bQ4 = _gguf(
  artifactId: 'qwen3.5-0.8b-q4_k_m-gguf',
  modelId: 'local:qwen3.5-0.8b',
  repository: 'bartowski/Qwen_Qwen3.5-0.8B-GGUF',
  commit: 'f36b1ea49a332ede8fe5f389bbf5b3575ef71f48',
  file: 'Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
  bytes: 579615840,
  sha256: 'fb044e93939a70469c905781334f5de1e6c8b608ced6cbc8c9249bd4127d9526',
  quantization: 'q4_k_m',
  minimumBuild: 7990,
  attribution:
      'Qwen3.5-0.8B by the Qwen team, Alibaba Cloud, Apache-2.0; '
      'GGUF quantization by bartowski.',
);

/// Qwen3.5 2B, 4-bit (Q4_K_M).
final qwen35_2bQ4 = _gguf(
  artifactId: 'qwen3.5-2b-q4_k_m-gguf',
  modelId: 'local:qwen3.5-2b',
  repository: 'bartowski/Qwen_Qwen3.5-2B-GGUF',
  commit: '7d26695454df6de5fbcce2e58681e62dae06ce43',
  file: 'Qwen_Qwen3.5-2B-Q4_K_M.gguf',
  bytes: 1396198496,
  sha256: '57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8',
  quantization: 'q4_k_m',
  minimumBuild: 7990,
  attribution:
      'Qwen3.5-2B by the Qwen team, Alibaba Cloud, Apache-2.0; '
      'GGUF quantization by bartowski.',
);

/// Gemma 4 E2B instruction-tuned, Google's quantization-aware 4-bit (Q4_0).
final gemma4E2bQ4 = _gguf(
  artifactId: 'gemma-4-e2b-it-qat-q4_0-gguf',
  modelId: 'local:gemma-4-e2b-it',
  repository: 'google/gemma-4-E2B-it-qat-q4_0-gguf',
  commit: '675cff42a74c774d6cb76f76d8eacb49b48c9b93',
  file: 'gemma-4-E2B_q4_0-it.gguf',
  bytes: 3349516256,
  sha256: 'fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634',
  quantization: 'q4_0',
  minimumBuild: 8637,
  attribution: 'Gemma 4 E2B by Google, Apache-2.0; QAT GGUF by Google.',
);

/// The text models this package version supports, smallest first.
///
/// Changes together with `native/binaries.json`: a newer llama.cpp may add
/// architectures, and the list is reviewed whenever the binaries move. Each
/// entry records the first build carrying its architecture (Qwen3.5 `qwen35`
/// b7990, Gemma 4 `gemma4` b8637).
final List<ArtifactManifest> llamaModelCatalog = List.unmodifiable([
  qwen35_08bQ4,
  qwen35_2bQ4,
  gemma4E2bQ4,
]);
