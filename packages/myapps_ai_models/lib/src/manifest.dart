import 'dart:ffi' show Abi;

import 'package:flutter/foundation.dart';

/// The platform and processor ABI that manifest filters are evaluated against.
@immutable
class ModelPlatform {
  /// Purpose: Platform id as manifests spell it.
  /// Inputs: None. Returns: `android`, `ios`, `macos`, `windows`, `linux`,
  /// `fuchsia` or `web`. Side effects: None.
  /// Notes: Same spelling as MyTranscribe's `platformId`.
  final String platform;

  /// Purpose: Processor ABI as manifests spell it.
  /// Inputs: None. Returns: `arm64`, `x64`, `arm`, `ia32`, `riscv64`, or
  /// another lower-case name; empty when unknown. Side effects: None.
  /// Notes: An empty ABI matches only files without an ABI filter.
  final String abi;

  /// Purpose: Create a platform description.
  /// Inputs: [platform], optional [abi]. Returns: A new immutable value.
  /// Side effects: None. Notes: Tests construct any combination.
  const ModelPlatform(this.platform, {this.abi = ''});

  /// Purpose: Describe the running process.
  /// Inputs: None. Returns: The current [ModelPlatform].
  /// Side effects: Reads `defaultTargetPlatform` and `Abi.current()`.
  /// Notes: `defaultTargetPlatform` lets widget tests override the platform.
  /// Not available on web; callers there supply a value explicitly.
  factory ModelPlatform.current() =>
      ModelPlatform(switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.windows => 'windows',
        TargetPlatform.linux => 'linux',
        TargetPlatform.fuchsia => 'fuchsia',
      }, abi: abiName(Abi.current()));

  /// Purpose: Spell a Dart ABI as manifests do.
  /// Inputs: [abi]. Returns: The architecture part, e.g. `arm64`.
  /// Side effects: None.
  /// Notes: `Abi.toString()` is `<os>_<arch>`; only the architecture is kept.
  static String abiName(Abi abi) {
    final text = abi.toString();
    final index = text.indexOf('_');
    return index < 0 ? text : text.substring(index + 1);
  }

  /// Purpose: Compare by value.
  /// Inputs: [other]. Returns: bool. Side effects: None. Notes: None.
  @override
  bool operator ==(Object other) =>
      other is ModelPlatform && other.platform == platform && other.abi == abi;

  /// Purpose: Hash by value.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  @override
  int get hashCode => Object.hash(platform, abi);

  /// Purpose: Render for diagnostics.
  /// Inputs: None. Returns: `platform/abi`. Side effects: None. Notes: None.
  @override
  String toString() => abi.isEmpty ? platform : '$platform/$abi';
}

/// Purpose: Report whether a platform/ABI filter admits [target].
/// Inputs: [platforms], [abis] (empty means all), [target].
/// Returns: bool. Side effects: None.
/// Notes: Shared by file-level and manifest-level filters.
bool _admits(List<String> platforms, List<String> abis, ModelPlatform target) =>
    (platforms.isEmpty || platforms.contains(target.platform)) &&
    (abis.isEmpty || abis.contains(target.abi));

/// Purpose: Read a JSON list of strings, dropping other values.
/// Inputs: [value]. Returns: List of strings. Side effects: None.
/// Notes: Tolerant parsing matches MyTranscribe.
List<String> _strings(Object? value) => [
  for (final item in (value is List ? value : const []))
    if (item is String) item,
];

/// Purpose: Collect keys not in [known] for round-tripping.
/// Inputs: [json], [known]. Returns: The unknown entries. Side effects: None.
/// Notes: Serialisers spread these first so known keys win collisions.
Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> known) => {
  for (final e in json.entries)
    if (!known.contains(e.key)) e.key: e.value,
};

/// The on-disk format of an artifact as its runtime reads it.
///
/// Kept as an open string so formats this build does not know (for example a
/// newer LLM format) round-trip unchanged, unlike MyTranscribe's enum which
/// collapsed them to `unknown`.
@immutable
class ArtifactFormat {
  /// Purpose: The persisted format name.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Empty reads as [unknown].
  final String value;

  /// Purpose: Create a format from its persisted name.
  /// Inputs: [value]. Returns: A new value. Side effects: None.
  /// Notes: Any string is accepted.
  const ArtifactFormat(this.value);

  /// whisper.cpp GGML.
  static const ggml = ArtifactFormat('ggml');

  /// llama.cpp GGUF.
  static const gguf = ArtifactFormat('gguf');

  /// ONNX models.
  static const onnx = ArtifactFormat('onnx');

  /// Compiled Core ML model.
  static const coreml = ArtifactFormat('coreml');

  /// Qualcomm context binary wrapped in ONNX.
  static const qnn = ArtifactFormat('qnn');

  /// MLX weights.
  static const mlx = ArtifactFormat('mlx');

  /// OpenVINO IR.
  static const openvino = ArtifactFormat('openvino');

  /// FastFlowLM package.
  static const flm = ArtifactFormat('flm');

  /// No format recorded.
  static const unknown = ArtifactFormat('unknown');

  /// Purpose: Parse a persisted format.
  /// Inputs: [value]. Returns: The format; non-strings and empty read as
  /// [unknown]. Side effects: None.
  /// Notes: Unrecognised strings are kept verbatim.
  static ArtifactFormat parse(Object? value) =>
      value is String && value.isNotEmpty ? ArtifactFormat(value) : unknown;

  /// Purpose: Compare by value.
  /// Inputs: [other]. Returns: bool. Side effects: None. Notes: None.
  @override
  bool operator ==(Object other) =>
      other is ArtifactFormat && other.value == value;

  /// Purpose: Hash by value.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  @override
  int get hashCode => value.hashCode;

  /// Purpose: Render the persisted name.
  /// Inputs: None. Returns: [value]. Side effects: None. Notes: None.
  @override
  String toString() => value;
}

/// Whether a downloaded file is an archive to unpack.
enum ArchiveKind {
  /// Installed as it is.
  none,

  /// A ZIP, unpacked in place.
  zip,

  /// A bzip2-compressed tar.
  tarBz2;

  /// Purpose: Parse a persisted archive kind.
  /// Inputs: [value]. Returns: The kind; anything unrecognised reads as [none].
  /// Side effects: None. Notes: Matches MyTranscribe.
  static ArchiveKind parse(Object? value) {
    for (final kind in ArchiveKind.values) {
      if (kind.name == value) return kind;
    }
    return none;
  }
}

/// Where a memory estimate came from.
enum EstimateSource {
  /// Measured on a device of this kind.
  measured,

  /// Stated by the runtime or the artifact's publisher.
  documented,

  /// Nobody has said.
  unknown;

  /// Purpose: Parse a persisted estimate source.
  /// Inputs: [value]. Returns: The source; unrecognised reads as [unknown].
  /// Side effects: None. Notes: Matches MyTranscribe.
  static EstimateSource parse(Object? value) {
    for (final source in EstimateSource.values) {
      if (source.name == value) return source;
    }
    return unknown;
  }
}

const _fileKeys = {
  'path',
  'bytes',
  'sha256',
  'sourceUrl',
  'platforms',
  'abis',
  'unpack',
  'unpackedBytes',
};

/// One file to download.
@immutable
class ArtifactFile {
  /// Purpose: Relative path inside the artifact folder, forward slashes.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Absolute paths and `..` are refused at install time.
  final String path;

  /// Purpose: Exact size in bytes.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int bytes;

  /// Purpose: SHA-256 of the file, lower-case hex.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String sha256;

  /// Purpose: The single URL the file may be fetched from.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Pinned to a revision; no other host is ever contacted.
  final String sourceUrl;

  /// Purpose: Platforms that need the file; empty means all.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> platforms;

  /// Purpose: ABIs that need the file; empty means all.
  /// Inputs: None. Returns: List. Side effects: None.
  /// Notes: New field; MyTranscribe manifests omit it.
  final List<String> abis;

  /// Purpose: Whether the file is an archive to unpack.
  /// Inputs: None. Returns: [ArchiveKind]. Side effects: None. Notes: None.
  final ArchiveKind unpack;

  /// Purpose: Size of the unpacked contents, when known.
  /// Inputs: None. Returns: int or null. Side effects: None.
  /// Notes: Counted separately in the space budget.
  final int? unpackedBytes;

  /// Purpose: Fields this build does not know, kept for round-tripping.
  /// Inputs: None. Returns: Map. Side effects: None. Notes: None.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create a file entry.
  /// Inputs: All fields; the first four are required.
  /// Returns: A new immutable value. Side effects: None. Notes: None.
  const ArtifactFile({
    required this.path,
    required this.bytes,
    required this.sha256,
    required this.sourceUrl,
    this.platforms = const [],
    this.abis = const [],
    this.unpack = ArchiveKind.none,
    this.unpackedBytes,
    this.extraJson = const {},
  });

  /// Purpose: Report whether [target] needs the file.
  /// Inputs: [target]. Returns: bool. Side effects: None. Notes: None.
  bool appliesTo(ModelPlatform target) => _admits(platforms, abis, target);

  /// Purpose: Parse a file entry.
  /// Inputs: [json]. Returns: [ArtifactFile]. Side effects: None.
  /// Notes: The hash is lower-cased, as in MyTranscribe.
  factory ArtifactFile.fromJson(Map<String, dynamic> json) => ArtifactFile(
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    sha256: (json['sha256'] as String? ?? '').toLowerCase(),
    sourceUrl: json['sourceUrl'] as String? ?? '',
    platforms: _strings(json['platforms']),
    abis: _strings(json['abis']),
    unpack: ArchiveKind.parse(json['unpack']),
    unpackedBytes: (json['unpackedBytes'] as num?)?.toInt(),
    extraJson: _extra(json, _fileKeys),
  );

  /// Purpose: Serialize a file entry.
  /// Inputs: None. Returns: JSON map. Side effects: None.
  /// Notes: Optional fields are omitted at their defaults, as before.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'path': path,
    'bytes': bytes,
    'sha256': sha256,
    'sourceUrl': sourceUrl,
    if (platforms.isNotEmpty) 'platforms': platforms,
    if (abis.isNotEmpty) 'abis': abis,
    if (unpack != ArchiveKind.none) 'unpack': unpack.name,
    if (unpackedBytes != null) 'unpackedBytes': unpackedBytes,
  };
}

const _installedKeys = {'path', 'bytes', 'sha256'};

/// One file as it was installed on this device.
@immutable
class InstalledFile {
  /// Purpose: Relative path inside the artifact folder, forward slashes.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String path;

  /// Purpose: Size in bytes.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int bytes;

  /// Purpose: SHA-256 measured on this device after unpacking.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String sha256;

  /// Purpose: Fields this build does not know.
  /// Inputs: None. Returns: Map. Side effects: None. Notes: None.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create an installed-file entry.
  /// Inputs: [path], [bytes], [sha256]. Returns: A new immutable value.
  /// Side effects: None. Notes: None.
  const InstalledFile({
    required this.path,
    required this.bytes,
    required this.sha256,
    this.extraJson = const {},
  });

  /// Purpose: Parse an installed-file entry.
  /// Inputs: [json]. Returns: [InstalledFile]. Side effects: None.
  /// Notes: None.
  factory InstalledFile.fromJson(Map<String, dynamic> json) => InstalledFile(
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    sha256: json['sha256'] as String? ?? '',
    extraJson: _extra(json, _installedKeys),
  );

  /// Purpose: Serialize an installed-file entry.
  /// Inputs: None. Returns: JSON map. Side effects: None. Notes: None.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'path': path,
    'bytes': bytes,
    'sha256': sha256,
  };
}

const _manifestKeys = {
  'artifactId',
  'modelId',
  'adapterId',
  'format',
  'quantization',
  'revision',
  'files',
  'licenseId',
  'licenseUrl',
  'attribution',
  'minimumRamBytes',
  'ramEstimateSource',
  'installedAt',
  'installed',
  'compatibleRuntimes',
  'platforms',
  'abis',
};

/// One downloadable model artifact, for any capability (ASR, LLM, ...).
///
/// JSON field names are MyTranscribe's, so its built-in templates and the
/// `models/<artifactId>/manifest.json` files already on devices parse as-is.
@immutable
class ArtifactManifest {
  /// Purpose: Artifact id, and the name of its folder under the models root.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Must be a safe folder name to install.
  final String artifactId;

  /// Purpose: The logical model this artifact serves.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Several artifacts (formats, quantizations) may share one model.
  final String modelId;

  /// Purpose: The backend (adapter) that loads it.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Persisted as `adapterId` for compatibility.
  final String backendId;

  /// Purpose: The artifact's format.
  /// Inputs: None. Returns: [ArtifactFormat]. Side effects: None. Notes: None.
  final ArtifactFormat format;

  /// Purpose: Quantization, e.g. `f16`, `q5_0`, `int8`, `q4_k_m`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String quantization;

  /// Purpose: Upstream revision the URLs are pinned to.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Include in cache keys and plan fingerprints.
  final String revision;

  /// Purpose: Files to download.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<ArtifactFile> files;

  /// Purpose: SPDX licence id.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String licenseId;

  /// Purpose: Where the licence text is published.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String licenseUrl;

  /// Purpose: Attribution the licence asks for.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String attribution;

  /// Purpose: Memory a loaded session needs, when known.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  final int? minimumRamBytes;

  /// Purpose: Where [minimumRamBytes] came from.
  /// Inputs: None. Returns: [EstimateSource]. Side effects: None. Notes: None.
  final EstimateSource ramEstimateSource;

  /// Purpose: Runtime ids able to load this artifact.
  /// Inputs: None. Returns: List; empty means only [backendId].
  /// Side effects: None.
  /// Notes: New field. Formats are never assumed interchangeable.
  final List<String> compatibleRuntimes;

  /// Purpose: Platforms the whole artifact supports; empty means all.
  /// Inputs: None. Returns: List. Side effects: None. Notes: New field.
  final List<String> platforms;

  /// Purpose: ABIs the whole artifact supports; empty means all.
  /// Inputs: None. Returns: List. Side effects: None. Notes: New field.
  final List<String> abis;

  /// Purpose: When it was installed here, UTC; null in a template.
  /// Inputs: None. Returns: DateTime or null. Side effects: None. Notes: None.
  final DateTime? installedAt;

  /// Purpose: What was actually installed, hashed here; empty in a template.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<InstalledFile> installed;

  /// Purpose: Fields written by a build this one does not know.
  /// Inputs: None. Returns: Map. Side effects: None.
  /// Notes: Capability packages may store their own fields here (for example
  /// an LLM chat template or context length) without changing this type.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create a manifest.
  /// Inputs: All fields; identity fields are required.
  /// Returns: A new immutable value. Side effects: None. Notes: None.
  const ArtifactManifest({
    required this.artifactId,
    required this.modelId,
    required this.backendId,
    required this.format,
    required this.revision,
    required this.files,
    required this.licenseId,
    this.quantization = '',
    this.licenseUrl = '',
    this.attribution = '',
    this.minimumRamBytes,
    this.ramEstimateSource = EstimateSource.unknown,
    this.compatibleRuntimes = const [],
    this.platforms = const [],
    this.abis = const [],
    this.installedAt,
    this.installed = const [],
    this.extraJson = const {},
  });

  /// Purpose: Report whether the artifact as a whole supports [target].
  /// Inputs: [target]. Returns: bool. Side effects: None.
  /// Notes: Also false when no file applies to [target].
  bool supports(ModelPlatform target) =>
      _admits(platforms, abis, target) && filesFor(target).isNotEmpty;

  /// Purpose: Report whether [runtimeId] may load this artifact.
  /// Inputs: [runtimeId]. Returns: bool. Side effects: None.
  /// Notes: Explicit compatibility only.
  bool loadableBy(String runtimeId) => compatibleRuntimes.isEmpty
      ? runtimeId == backendId
      : compatibleRuntimes.contains(runtimeId);

  /// Purpose: List the files [target] downloads.
  /// Inputs: [target]. Returns: Applicable [files]. Side effects: None.
  /// Notes: None.
  List<ArtifactFile> filesFor(ModelPlatform target) => [
    for (final file in files)
      if (file.appliesTo(target)) file,
  ];

  /// Purpose: Add up what [target] downloads.
  /// Inputs: [target]. Returns: Bytes. Side effects: None. Notes: None.
  int downloadBytesFor(ModelPlatform target) =>
      filesFor(target).fold(0, (sum, file) => sum + file.bytes);

  /// Purpose: Add up what is installed.
  /// Inputs: None. Returns: Bytes recorded in [installed]. Side effects: None.
  /// Notes: Zero for a template.
  int get installedBytes => installed.fold(0, (sum, file) => sum + file.bytes);

  /// Purpose: Return a copy recording what was installed.
  /// Inputs: [installed], [installedAt]. Returns: A new manifest.
  /// Side effects: None. Notes: [installedAt] is stored in UTC.
  ArtifactManifest asInstalled(
    List<InstalledFile> installed,
    DateTime installedAt,
  ) => ArtifactManifest(
    artifactId: artifactId,
    modelId: modelId,
    backendId: backendId,
    format: format,
    revision: revision,
    files: files,
    licenseId: licenseId,
    quantization: quantization,
    licenseUrl: licenseUrl,
    attribution: attribution,
    minimumRamBytes: minimumRamBytes,
    ramEstimateSource: ramEstimateSource,
    compatibleRuntimes: compatibleRuntimes,
    platforms: platforms,
    abis: abis,
    installedAt: installedAt.toUtc(),
    installed: installed,
    extraJson: extraJson,
  );

  /// Purpose: Parse a manifest.
  /// Inputs: [json]. Returns: [ArtifactManifest]. Side effects: None.
  /// Notes: Unknown fields are kept, so a newer build's manifest is rewritten
  /// intact.
  factory ArtifactManifest.fromJson(Map<String, dynamic> json) =>
      ArtifactManifest(
        artifactId: json['artifactId'] as String? ?? '',
        modelId: json['modelId'] as String? ?? '',
        backendId: json['adapterId'] as String? ?? '',
        format: ArtifactFormat.parse(json['format']),
        quantization: json['quantization'] as String? ?? '',
        revision: json['revision'] as String? ?? '',
        files: [
          for (final item in (json['files'] as List?) ?? const [])
            if (item is Map<String, dynamic>) ArtifactFile.fromJson(item),
        ],
        licenseId: json['licenseId'] as String? ?? '',
        licenseUrl: json['licenseUrl'] as String? ?? '',
        attribution: json['attribution'] as String? ?? '',
        minimumRamBytes: (json['minimumRamBytes'] as num?)?.toInt(),
        ramEstimateSource: EstimateSource.parse(json['ramEstimateSource']),
        compatibleRuntimes: _strings(json['compatibleRuntimes']),
        platforms: _strings(json['platforms']),
        abis: _strings(json['abis']),
        installedAt: DateTime.tryParse('${json['installedAt']}')?.toUtc(),
        installed: [
          for (final item in (json['installed'] as List?) ?? const [])
            if (item is Map<String, dynamic>) InstalledFile.fromJson(item),
        ],
        extraJson: _extra(json, _manifestKeys),
      );

  /// Purpose: Serialize a manifest.
  /// Inputs: None. Returns: JSON map. Side effects: None.
  /// Notes: Unknown fields first so a known key wins a collision; new
  /// optional fields are omitted when empty so old manifests rewrite
  /// byte-identically.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'artifactId': artifactId,
    'modelId': modelId,
    'adapterId': backendId,
    'format': format.value,
    if (quantization.isNotEmpty) 'quantization': quantization,
    'revision': revision,
    'files': [for (final file in files) file.toJson()],
    'licenseId': licenseId,
    if (licenseUrl.isNotEmpty) 'licenseUrl': licenseUrl,
    if (attribution.isNotEmpty) 'attribution': attribution,
    if (minimumRamBytes != null) 'minimumRamBytes': minimumRamBytes,
    'ramEstimateSource': ramEstimateSource.name,
    if (compatibleRuntimes.isNotEmpty) 'compatibleRuntimes': compatibleRuntimes,
    if (platforms.isNotEmpty) 'platforms': platforms,
    if (abis.isNotEmpty) 'abis': abis,
    if (installedAt != null) 'installedAt': installedAt!.toIso8601String(),
    if (installed.isNotEmpty)
      'installed': [for (final file in installed) file.toJson()],
  };
}
