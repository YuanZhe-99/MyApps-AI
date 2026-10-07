/// Purpose: Hand the Flutter tool upstream's prebuilt llama.cpp libraries for
/// the target it is building, as code assets.
/// Inputs: The hook input: target OS, architecture and (on iOS) SDK; a shared
/// output directory that caches the downloads between builds; and the
/// optional user-define `variant` (see Notes).
/// Returns: Code assets — `llama`, the library the Dart bindings name, and
/// every ggml library it needs beside it.
/// Side effects: Downloads one archive per target the first time, checks its
/// SHA-256, and unpacks the listed files into the hook's shared output.
/// Notes: Nothing is compiled: every archive is an asset of the llama.cpp
/// release pinned in `native/binaries.json`. `targets` is the CPU baseline.
/// An application may opt into a GPU set where one is listed under
/// `variants` by declaring, in its own pubspec:
///
/// ```yaml
/// hooks:
///   user_defines:
///     myapps_ai_llm_llama:
///       variant: vulkan
/// ```
///
/// A target without an entry — Android x86_64, the iOS simulator — gets no
/// assets, and the backend reports itself as unsupported there.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

/// Purpose: Run the hook.
/// Inputs: The arguments the Flutter tool passes.
/// Returns: None.
/// Side effects: Downloads, verifies and unpacks; reports the libraries.
/// Notes: None.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final manifestFile = File.fromUri(
      input.packageRoot.resolve('native/binaries.json'),
    );
    output.dependencies.add(manifestFile.uri);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final key = _targetKey(input.config.code);
    final variant = input.userDefines['variant'] as String?;
    final target = _selectTarget(manifest, key, variant);
    if (target == null) return;

    final shared = Directory.fromUri(input.outputDirectoryShared);
    final archive = await _fetch(target, Directory('${shared.path}/archives'));
    final files = await _unpack(
      archive,
      target,
      Directory('${shared.path}/lib/${variant ?? 'cpu'}/$key'),
    );

    final entry = target['entry'] as String;
    for (final file in files) {
      final name = _baseName(file.path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          // The bindings are generated against this id; the other libraries
          // are bundled beside it and never named from Dart.
          name: name == entry ? 'llama' : 'lib/$name',
          linkMode: DynamicLoadingBundled(),
          file: file.uri,
        ),
      );
    }
  });
}

/// Purpose: Pick the manifest entry for a target and optional variant.
/// Inputs: The [manifest], the target [key], the requested [variant].
/// Returns: The entry, or null when the target has no binaries.
/// Side effects: None.
/// Notes: An unknown variant name fails the build rather than silently
/// shipping the CPU set; a known variant without this target falls back to
/// the CPU baseline, since every variant is optional acceleration.
Map<String, dynamic>? _selectTarget(
  Map<String, dynamic> manifest,
  String key,
  String? variant,
) {
  final targets = manifest['targets'] as Map<String, dynamic>;
  if (variant == null || variant == 'cpu') {
    return targets[key] as Map<String, dynamic>?;
  }
  final variants = manifest['variants'] as Map<String, dynamic>? ?? const {};
  final sets = variants[variant] as Map<String, dynamic>?;
  if (sets == null) {
    throw StateError(
      'native/binaries.json has no variant "$variant"; '
      'known: cpu, ${variants.keys.join(', ')}.',
    );
  }
  return (sets[key] ?? targets[key]) as Map<String, dynamic>?;
}

/// Purpose: Name the manifest entry for a build target.
/// Inputs: The [code] config.
/// Returns: e.g. `windows_arm64`, `ios_simulator_x64`.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
String _targetKey(CodeConfig code) {
  final arch = switch (code.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x64',
    final other => other.name,
  };
  final os = code.targetOS;
  if (os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator) {
    return 'ios_simulator_$arch';
  }
  return '${os.name.toLowerCase()}_$arch';
}

/// Purpose: Make sure the target's archive is in the cache, with the right
/// hash.
/// Inputs: The manifest [target]; the cache [dir].
/// Returns: The archive file.
/// Side effects: Downloads when the cached copy is missing or wrong.
/// Notes: The file is named by its hash, so a changed manifest downloads anew
/// and never reuses the old bytes. A mismatch fails the build: a replaced
/// upstream asset must never become a different binary in the app.
Future<File> _fetch(Map<String, dynamic> target, Directory dir) async {
  final sha = target['sha256'] as String;
  final url = Uri.parse(target['url'] as String);
  final file = File('${dir.path}/$sha-${url.pathSegments.last}');
  if (file.existsSync() && await _sha256(file) == sha) return file;

  await dir.create(recursive: true);
  final part = File('${file.path}.part');
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    await response.pipe(part.openWrite());
  } finally {
    client.close();
  }
  final got = await _sha256(part);
  if (got != sha) {
    await part.delete();
    throw StateError(
      '$url has SHA-256 $got, but native/binaries.json pins $sha.',
    );
  }
  return part.rename(file.path);
}

/// Purpose: Unpack the files a target lists, once per archive.
/// Inputs: The [archive], the manifest [target], the output [dir].
/// Returns: The unpacked libraries.
/// Side effects: Replaces [dir]'s contents when its stamp does not match.
/// Notes: `from` may end in `*` to take every member with that prefix and
/// suffix; `as` renames (the Linux libraries are found by their sonames);
/// `slice` takes one architecture out of a universal Mach-O binary.
Future<List<File>> _unpack(
  File archive,
  Map<String, dynamic> target,
  Directory dir,
) async {
  final specs = [
    for (final spec in target['files'] as List) spec as Map<String, dynamic>,
  ];
  final stamp = File('${dir.path}/.stamp');
  final expected = '${target['sha256']} ${jsonEncode(specs)}';
  if (stamp.existsSync() && stamp.readAsStringSync() == expected) {
    return [
      for (final entry in dir.listSync())
        if (entry is File && !entry.path.endsWith('.stamp')) entry,
    ];
  }
  if (dir.existsSync()) await dir.delete(recursive: true);
  await dir.create(recursive: true);

  final members = _open(archive);
  final written = <File>[];
  for (final spec in specs) {
    final from = spec['from'] as String;
    final matches = members.files.where(
      (m) => m.isFile && !m.isSymbolicLink && _matches(m.name, from),
    );
    if (matches.isEmpty) {
      throw StateError('${archive.path} has no member matching $from.');
    }
    for (final member in matches) {
      var bytes = member.readBytes()!;
      if (spec['slice'] case final String arch) bytes = _thin(bytes, arch);
      final file = File('${dir.path}/${spec['as'] ?? _baseName(member.name)}');
      await file.writeAsBytes(bytes, flush: true);
      written.add(file);
    }
  }
  await stamp.writeAsString(expected);
  return written;
}

/// Purpose: Read an archive's member list.
/// Inputs: The [file]: a `.zip` or a `.tar.gz`.
/// Returns: The archive.
/// Side effects: Reads the file.
/// Notes: Internal helper used within this file only.
Archive _open(File file) {
  if (file.path.endsWith('.tar.gz')) {
    return TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(file.readAsBytesSync()),
    );
  }
  return ZipDecoder().decodeStream(InputFileStream(file.path));
}

/// Purpose: Match a member name against a pattern with at most one `*`.
/// Inputs: The member [name] and the [pattern].
/// Returns: `bool`.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
bool _matches(String name, String pattern) {
  final star = pattern.indexOf('*');
  if (star < 0) return name == pattern;
  final prefix = pattern.substring(0, star);
  final suffix = pattern.substring(star + 1);
  return name.length >= prefix.length + suffix.length &&
      name.startsWith(prefix) &&
      name.endsWith(suffix);
}

/// Purpose: Take one architecture out of a universal (fat) Mach-O binary.
/// Inputs: The binary's [bytes] and the [arch] wanted (`arm64`, `x86_64`).
/// Returns: The thin binary; [bytes] unchanged when it is already thin.
/// Side effects: None.
/// Notes: The Flutter tool combines the per-architecture assets itself, so it
/// must be given one slice each. The fat header is big-endian: a count, then
/// per slice its CPU type, subtype, offset, size and alignment.
Uint8List _thin(Uint8List bytes, String arch) {
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0) != 0xcafebabe) return bytes;
  final wanted = switch (arch) {
    'arm64' => 0x0100000c,
    'x86_64' => 0x01000007,
    _ => throw ArgumentError('No Mach-O CPU type for $arch.'),
  };
  final count = data.getUint32(4);
  for (var i = 0; i < count; i++) {
    final at = 8 + i * 20;
    if (data.getUint32(at) != wanted) continue;
    final offset = data.getUint32(at + 8);
    final size = data.getUint32(at + 12);
    return Uint8List.sublistView(bytes, offset, offset + size);
  }
  throw StateError('The universal binary has no $arch slice.');
}

/// Purpose: Hash a file.
/// Inputs: [file].
/// Returns: Its SHA-256 as lowercase hex.
/// Side effects: Reads the file.
/// Notes: Internal helper used within this file only.
Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Purpose: The last path segment.
/// Inputs: [path].
/// Returns: The file name.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;
