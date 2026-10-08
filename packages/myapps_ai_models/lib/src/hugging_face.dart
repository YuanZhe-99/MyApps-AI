/// Purpose: Let a user pick a model file from a Hugging Face repository.
/// Inputs: A repository the user typed, an HTTP client.
/// Returns: [HuggingFaceModelSource], [HuggingFaceRepoListing],
/// [HuggingFaceFile], [parseHuggingFaceRepo].
/// Side effects: HTTP requests to huggingface.co, only when the user asks.
/// Notes: Listings are pinned to the repository's current commit, and every
/// file carries its LFS SHA-256, so the download is verified exactly as for
/// the recommended models. Nothing here downloads a model.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'manifest.dart';
import 'naming.dart';

/// `extraJson` key marking a manifest the user added.
const artifactCustomKey = 'custom';

/// Purpose: The `owner/name` of a repository the user typed.
/// Inputs: [input]: `owner/name`, or a huggingface.co URL to the repository
/// or one of its files. Returns: `owner/name`, or null when unreadable.
/// Side effects: None. Notes: None.
String? parseHuggingFaceRepo(String input) {
  var s = input.trim();
  final uri = Uri.tryParse(s);
  if (uri != null && uri.host.endsWith('huggingface.co')) {
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    s = '${parts[0]}/${parts[1]}';
  }
  final ok = RegExp(r'^[A-Za-z0-9][\w.-]*/[\w.-]+$').hasMatch(s);
  return ok ? s : null;
}

/// One file in a repository.
class HuggingFaceFile {
  /// Purpose: Describe a file. Inputs: [path], [bytes], [sha256] (LFS).
  /// Returns: File. Side effects: None. Notes: None.
  const HuggingFaceFile(this.path, this.bytes, this.sha256);

  /// Path inside the repository.
  final String path;

  /// Size in bytes.
  final int bytes;

  /// SHA-256 from the LFS pointer.
  final String sha256;

  /// Purpose: Whether this is one part of a split model, which is not
  /// supported. Inputs: None. Returns: bool. Side effects: None.
  /// Notes: Split files are named `…-00001-of-00003.gguf`.
  bool get split => RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(path);

  /// Purpose: The quantization in the file name, such as `q4_k_m`.
  /// Inputs: None. Returns: Lower-case text, or empty. Side effects: None.
  /// Notes: None.
  String get quantization =>
      RegExp(
        r'(i?q\d(?:_[0-9a-z]+)*|bf16|f16|f32)(?=\.gguf$)',
        caseSensitive: false,
      ).firstMatch(path)?.group(1)?.toLowerCase() ??
      '';
}

/// A repository's GGUF files at one commit.
class HuggingFaceRepoListing {
  /// Purpose: Create a listing. Inputs: [repo]; [commit]; [license], the
  /// model card's id; [files], GGUF files only. Returns: Listing.
  /// Side effects: None. Notes: None.
  const HuggingFaceRepoListing({
    required this.repo,
    required this.commit,
    required this.files,
    this.license,
  });

  final String repo;
  final String commit;
  final String? license;
  final List<HuggingFaceFile> files;

  /// Purpose: A manifest for one file of this listing.
  /// Inputs: [file]; [backendId] that loads it; [displayName] and [vendor]
  /// for its name. Returns: Manifest marked custom.
  /// Side effects: None.
  /// Notes: Ids derive from repository and file, so adding the same file
  /// twice yields the same record.
  ArtifactManifest manifestFor(
    HuggingFaceFile file, {
    required String backendId,
    String? displayName,
    String? vendor,
  }) {
    final slug = '$repo/${file.path}'.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]+'),
      '-',
    );
    return ArtifactManifest(
      artifactId: 'hf-$slug',
      modelId: 'local:hf:$repo/${file.path}',
      backendId: backendId,
      format: ArtifactFormat.gguf,
      revision: commit,
      quantization: file.quantization,
      files: [
        ArtifactFile(
          path: file.path.split('/').last,
          bytes: file.bytes,
          sha256: file.sha256,
          sourceUrl:
              'https://huggingface.co/$repo/resolve/$commit/${file.path}',
        ),
      ],
      licenseId: license ?? 'unknown',
      licenseUrl: 'https://huggingface.co/$repo',
      attribution: 'https://huggingface.co/$repo',
      extraJson: {
        artifactCustomKey: true,
        artifactNameKey: ?displayName,
        artifactVendorKey: ?vendor,
      },
    );
  }
}

/// Reads repositories from huggingface.co.
class HuggingFaceModelSource {
  /// Purpose: Bind an HTTP client. Inputs: [client]; [host] for tests.
  /// Returns: Source. Side effects: None. Notes: Does not close [client].
  HuggingFaceModelSource(this.client, {this.host = 'huggingface.co'});

  final http.Client client;
  final String host;

  /// Purpose: List a repository's GGUF files at its current commit.
  /// Inputs: [repo], `owner/name`. Returns: Listing.
  /// Side effects: One GET to the Hugging Face API.
  /// Notes: Throws [ArtifactListingException] (`notFound`,
  /// `notFoundOrPrivate`, `gated`, `network`, `badResponse`). Files without an LFS hash are skipped:
  /// they cannot be verified.
  Future<HuggingFaceRepoListing> list(String repo) async {
    final http.Response r;
    try {
      r = await client
          .get(Uri.https(host, '/api/models/$repo', {'blobs': 'true'}))
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw const ArtifactListingException('network');
    }
    // Hugging Face answers 401 alike for a missing and a private repository.
    if (r.statusCode == 401) {
      throw const ArtifactListingException('notFoundOrPrivate');
    }
    if (r.statusCode == 403) throw const ArtifactListingException('gated');
    if (r.statusCode == 404) throw const ArtifactListingException('notFound');
    if (r.statusCode != 200) {
      throw ArtifactListingException('http ${r.statusCode}');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw const ArtifactListingException('badResponse');
    }
    if (json is! Map || json['sha'] is! String) {
      throw const ArtifactListingException('badResponse');
    }
    final card = json['cardData'];
    final license = card is Map && card['license'] is String
        ? card['license'] as String
        : null;
    return HuggingFaceRepoListing(
      repo: repo,
      commit: json['sha'] as String,
      license: license,
      files: [
        if (json['siblings'] case final List siblings)
          for (final s in siblings)
            if (s is Map &&
                s['rfilename'] is String &&
                (s['rfilename'] as String).toLowerCase().endsWith('.gguf') &&
                s['lfs'] is Map &&
                (s['lfs'] as Map)['sha256'] is String &&
                (s['lfs'] as Map)['size'] is int)
              HuggingFaceFile(
                s['rfilename'] as String,
                (s['lfs'] as Map)['size'] as int,
                (s['lfs'] as Map)['sha256'] as String,
              ),
      ]..sort((a, b) => a.path.compareTo(b.path)),
    );
  }

  /// Purpose: The first bytes of a file, to read its header before
  /// downloading it.
  /// Inputs: [listing], [file], [bytes] to fetch. Returns: The bytes.
  /// Side effects: One ranged GET. Notes: Throws
  /// [ArtifactListingException] (`network`).
  Future<Uint8List> head(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file, {
    int bytes = 256 << 10,
  }) async {
    try {
      final r = await client
          .get(
            Uri.https(
              host,
              '/${listing.repo}/resolve/${listing.commit}/${file.path}',
            ),
            headers: {'Range': 'bytes=0-${bytes - 1}'},
          )
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 && r.statusCode != 206) {
        throw ArtifactListingException('http ${r.statusCode}');
      }
      return r.bodyBytes;
    } on ArtifactListingException {
      rethrow;
    } on Exception {
      throw const ArtifactListingException('network');
    }
  }
}

/// Why a repository could not be listed.
class ArtifactListingException implements Exception {
  /// Purpose: Create a failure. Inputs: [reason]. Returns: Exception.
  /// Side effects: None. Notes: [reason] is an untranslated identifier.
  const ArtifactListingException(this.reason);

  /// `notFound`, `notFoundOrPrivate`, `gated`, `network`, `badResponse`,
  /// `invalidRepository` or `http <status>`.
  final String reason;

  /// Purpose: Render. Inputs: None. Returns: Text. Side effects: None.
  /// Notes: None.
  @override
  String toString() => 'ArtifactListingException($reason)';
}

/// What a model file's header says, before it is downloaded.
class CustomModelProbe {
  /// Purpose: Describe a probed file.
  /// Inputs: [architecture] and [name] from its header; [supported] whether
  /// the runtime lists the architecture (null when the header did not say);
  /// [contextLength]; [displayName] the name the model will show.
  /// Returns: Probe. Side effects: None. Notes: None.
  const CustomModelProbe({
    required this.displayName,
    this.architecture,
    this.name,
    this.supported,
    this.contextLength,
  });

  final String displayName;
  final String? architecture;
  final String? name;
  final bool? supported;
  final int? contextLength;
}

/// What the "add a custom model" flow needs from an application.
abstract interface class CustomModelController {
  /// Purpose: List a repository's model files.
  /// Inputs: [input] as typed. Returns: Listing.
  /// Side effects: One request to Hugging Face. Notes: Throws
  /// [ArtifactListingException]; `invalidRepository` for unreadable input.
  Future<HuggingFaceRepoListing> listRepository(String input);

  /// Purpose: Read a file's header without downloading it.
  /// Inputs: [listing], [file]. Returns: Probe.
  /// Side effects: One ranged request. Notes: A failed read yields a probe
  /// with unknown architecture rather than an error.
  Future<CustomModelProbe> probe(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
  );

  /// Purpose: Add [file] as a custom model and start its download.
  /// Inputs: [listing], [file], [probe]. Returns: The new model id.
  /// Side effects: Stores the record on this device; downloads explicitly.
  /// Notes: Called only after the user accepted the warning.
  Future<String> addCustomModel(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
    CustomModelProbe probe,
  );

  /// Purpose: Whether [modelId] is a custom model. Inputs: [modelId].
  /// Returns: bool. Side effects: None. Notes: None.
  bool isCustom(String modelId);

  /// Purpose: Remove a custom model and its files. Inputs: [modelId].
  /// Returns: Completion. Side effects: Deletes files and the record.
  /// Notes: Fails while the model is leased.
  Future<void> removeCustomModel(String modelId);
}
