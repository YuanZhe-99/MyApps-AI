/// Purpose: User-facing names for model artifacts.
/// Inputs: Manifests carrying optional naming fields in `extraJson`.
/// Returns: [artifactDisplayName] and the field keys.
/// Side effects: None.
/// Notes: Names follow OpenRouter's `Vendor: Model` form, with the
/// quantization in parentheses: `Qwen: Qwen3.5 0.8B (Q4_K_M)`.
library;

import 'manifest.dart';

/// `extraJson` key: the model's maker, such as `Qwen` or `Google`.
const artifactVendorKey = 'vendor';

/// `extraJson` key: the model's name without vendor or quantization.
const artifactNameKey = 'displayName';

/// `extraJson` key: how to show the quantization, such as `Q4_0 QAT`.
const artifactQuantizationLabelKey = 'quantizationLabel';

/// Purpose: The display name of [manifest].
/// Inputs: [manifest]; [alias], a user's name for it, which wins.
/// Returns: `Vendor: Name (QUANT)`, dropping parts that are absent; the model
/// id when the manifest carries no name.
/// Side effects: None.
/// Notes: The quantization falls back to the manifest's, upper-cased.
String artifactDisplayName(ArtifactManifest manifest, {String? alias}) {
  if (alias != null && alias.trim().isNotEmpty) return alias.trim();
  final extra = manifest.extraJson;
  final name = extra[artifactNameKey];
  if (name is! String || name.isEmpty) return manifest.modelId;
  final vendor = extra[artifactVendorKey];
  final quant = switch (extra[artifactQuantizationLabelKey]) {
    final String label when label.isNotEmpty => label,
    _ => manifest.quantization.toUpperCase(),
  };
  return [
    if (vendor is String && vendor.isNotEmpty) '$vendor: $name' else name,
    if (quant.isNotEmpty) '($quant)',
  ].join(' ');
}
