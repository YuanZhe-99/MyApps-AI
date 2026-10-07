import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// Purpose: Hash bytes as manifests do.
/// Inputs: [bytes]. Returns: Lower-case hex. Side effects: None. Notes: None.
String sha(List<int> bytes) => sha256.convert(bytes).toString();

/// Purpose: Deterministic test payload.
/// Inputs: [length], [seed]. Returns: Bytes. Side effects: None. Notes: None.
List<int> payload(int length, [int seed = 7]) =>
    List<int>.generate(length, (i) => (i * 31 + seed) & 0xff);

/// A scriptable fake HTTP host serving files with range support.
class FakeHost {
  /// Purpose: Files by URL. Inputs: None. Returns: Map. Side effects: None.
  /// Notes: None.
  final Map<String, List<int>> files = {};

  /// Purpose: Requests seen, with their Range header.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<({String url, String? range})> requests = [];

  /// Purpose: When set, the next response drops after this many body bytes.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: Reset
  /// after use.
  int? dropAfter;

  /// Purpose: Ignore Range headers (always reply 200).
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool ignoreRange = false;

  /// Purpose: Status override for every reply.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  int? status;

  /// Purpose: When set, responses wait on this before sending the body.
  /// Inputs: None. Returns: Completer or null. Side effects: None.
  /// Notes: Lets tests hold a download open.
  Completer<void>? gate;

  /// Purpose: Build an injected client factory.
  /// Inputs: None. Returns: Factory. Side effects: None. Notes: None.
  http.Client Function() get factory =>
      () => MockClient.streaming((request, _) async {
        final url = request.url.toString();
        final range = request.headers['Range'];
        requests.add((url: url, range: range));
        final body = files[url];
        if (status != null || body == null) {
          return http.StreamedResponse(Stream.value(const []), status ?? 404);
        }
        var start = 0;
        var code = 200;
        if (range != null && !ignoreRange) {
          start = int.parse(range.substring(6, range.length - 1));
          if (start >= body.length) {
            return http.StreamedResponse(Stream.value(const []), 416);
          }
          code = 206;
        }
        final rest = body.sublist(start);
        final drop = dropAfter;
        dropAfter = null;
        final wait = gate;
        final controller = StreamController<List<int>>();
        var stopped = false;
        controller.onCancel = () => stopped = true;
        controller.onListen = () async {
          if (wait != null) await wait.future;
          if (stopped) return;
          if (drop != null && drop < rest.length) {
            if (drop > 0) controller.add(rest.sublist(0, drop));
            controller.addError(const SocketException('connection reset'));
            await controller.close();
            return;
          }
          for (var i = 0; i < rest.length && !stopped; i += 64) {
            controller.add(
              rest.sublist(i, i + 64 > rest.length ? rest.length : i + 64),
            );
            await Future<void>.delayed(Duration.zero);
          }
          if (!stopped) await controller.close();
        };

        return http.StreamedResponse(controller.stream, code);
      });

  /// Purpose: Register a file and return its manifest entry.
  /// Inputs: [path], [bytes], optional manifest overrides.
  /// Returns: [ArtifactFile]. Side effects: Stores the bytes.
  /// Notes: None.
  ArtifactFile serve(
    String path,
    List<int> bytes, {
    String? hash,
    List<String> platforms = const [],
    ArchiveKind unpack = ArchiveKind.none,
  }) {
    final url = 'https://models.example/$path';
    files[url] = bytes;
    return ArtifactFile(
      path: path,
      bytes: bytes.length,
      sha256: hash ?? sha(bytes),
      sourceUrl: url,
      platforms: platforms,
      unpack: unpack,
    );
  }
}

/// Purpose: Build a simple manifest.
/// Inputs: [id], [files], optional [revision].
/// Returns: [ArtifactManifest]. Side effects: None. Notes: None.
ArtifactManifest manifestOf(
  String id,
  List<ArtifactFile> files, {
  String revision = 'r1',
}) => ArtifactManifest(
  artifactId: id,
  modelId: 'local:$id',
  backendId: 'test_runtime',
  format: ArtifactFormat.gguf,
  revision: revision,
  files: files,
  licenseId: 'MIT',
);

/// Test platform used everywhere.
const testPlatform = ModelPlatform('linux', abi: 'x64');
