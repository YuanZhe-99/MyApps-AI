import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';
import 'package:myapps_ai_sources/myapps_ai_sources.dart';
import 'package:path/path.dart' as p;

class _Store implements AiSourceStore {
  final Map<String, dynamic> config = {'unrelated': 'keep'};
  @override
  Future<Map<String, dynamic>> read() async => Map.of(config);
  @override
  Future<void> write(Map<String, dynamic> values) async =>
      config.addAll(jsonDecode(jsonEncode(values)) as Map<String, dynamic>);
}

class _System extends CapabilityGenAiBackend {
  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) async => const GenAiStatusReport(GenAiStatus.available, code: 0);
  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async => null;
  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async => 'system';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> prewarm() async {}
  @override
  Future<bool> download({void Function(int, int)? onProgress}) async => false;
  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async => [];
}

const _repo = 'HuggingFaceTB/SmolLM2-135M-Instruct-GGUF';
const _path = 'SmolLM2-135M-Instruct-Q4_K_M.gguf';
const _commit = 'f36b1ea49a332ede8fe5f389bbf5b3575ef71f48';
const _sha = 'fb044e93939a70469c905781334f5de1e6c8b608ced6cbc8c9249bd4127d9526';
const _realFile = '/tmp/opencode/SmolLM2-135M-Instruct-Q4_K_M.gguf';
final _haveFile = File(_realFile).existsSync();

String _listingJson() => jsonEncode({
  'sha': _commit,
  'cardData': {'license': 'apache-2.0'},
  'siblings': [
    {
      'rfilename': _path,
      'size': 105454432,
      'lfs': {'sha256': _sha, 'size': 105454432, 'pointerSize': 135},
    },
    {'rfilename': 'README.md', 'size': 1000},
  ],
});

/// Serves the listing, the header range (when [head] is not null, else 500)
/// and 404 for any other file request, so nothing large is downloaded.
MockClient _mock({Uint8List? head}) => MockClient((r) async {
  if (r.url.path.startsWith('/api/models/')) {
    return http.Response(_listingJson(), 200);
  }
  final range = r.headers['Range'];
  if (range == 'bytes=0-${(256 << 10) - 1}') {
    return head == null
        ? http.Response('', 500)
        : http.Response.bytes(head, 206);
  }
  return http.Response('', 404);
});

AiSourceRouter _router(Directory dir, _Store store, http.Client client) {
  final storage = CallbackModelStorageRoot(
    () async => Directory(p.join(dir.path, 'ai_models')),
  );
  return AiSourceRouter(
    store: store,
    system: _System(),
    models: storage,
    client: () => client,
    manager: ArtifactManager(
      storage: storage,
      downloader: ArtifactDownloader(clientFactory: () => client),
    ),
  );
}

Uint8List _realHead() =>
    Uint8List.fromList(File(_realFile).openSync().readSync(256 << 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('custom'));
  tearDown(() async {
    // Let the background download attempt finish before deleting its files.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await dir.delete(recursive: true);
  });

  Future<(AiSourceRouter, HuggingFaceRepoListing, CustomModelProbe)> added(
    _Store store, {
    Uint8List? head,
  }) async {
    final router = _router(dir, store, _mock(head: head));
    await router.initialize();
    final listing = await router.listRepository(_repo);
    final file = listing.files.single;
    final probe = await router.probe(listing, file);
    return (router, listing, probe);
  }

  group('listRepository', () {
    test('rejects unreadable input', () async {
      final router = _router(dir, _Store(), _mock());
      for (final input in ['garbage', '', 'owner']) {
        await expectLater(
          router.listRepository(input),
          throwsA(
            isA<ArtifactListingException>().having(
              (e) => e.reason,
              'reason',
              'invalidRepository',
            ),
          ),
          reason: input,
        );
      }
    });

    test('lists a repository given as a link', () async {
      final router = _router(dir, _Store(), _mock());
      final listing = await router.listRepository(
        'https://huggingface.co/$_repo/blob/main/$_path',
      );
      expect(listing.repo, _repo);
      expect(listing.commit, _commit);
      expect(listing.files.single.path, _path);
    });
  });

  group('probe', () {
    test('reads the architecture from the real header', () async {
      final (router, _, probe) = await added(_Store(), head: _realHead());
      expect(probe.architecture, 'llama');
      expect(probe.supported, isTrue);
      expect(probe.displayName, endsWith('(Q4_K_M)'));
      expect(probe.contextLength, isNotNull);
      expect(router.catalog.where((m) => m.extraJson['custom'] == true), []);
    }, skip: _haveFile ? false : 'missing $_realFile');

    test('a failed range request still yields a probe', () async {
      final (_, _, probe) = await added(_Store());
      expect(probe.architecture, isNull);
      expect(probe.supported, isNull);
      expect(probe.displayName, endsWith('(Q4_K_M)'));
    });

    test('non-GGUF bytes yield an unknown architecture', () async {
      final (_, _, probe) = await added(
        _Store(),
        head: Uint8List.fromList(List.filled(64, 7)),
      );
      expect(probe.architecture, isNull);
      expect(probe.supported, isNull);
    });
  });

  group('addCustomModel', () {
    test('adds, persists and is seen by a new router', () async {
      final store = _Store();
      final (router, listing, probe) = await added(store);
      final builtIn = router.catalog.length;
      final id = await router.addCustomModel(
        listing,
        listing.files.single,
        probe,
      );
      expect(id, 'local:hf:$_repo/$_path');
      expect(router.isCustom(id), isTrue);
      expect(router.isCustom('local:qwen3.5-0.8b'), isFalse);
      expect(router.catalog.length, builtIn + 1);
      expect(router.catalog.last.modelId, id);
      final option = router.sourceOptions.singleWhere((o) => o.id == id);
      expect(option.kind, AiSourceKind.local);
      expect(router.sourceName(id), probe.displayName);

      final stored = store.config['aiCustomModels'] as List;
      expect(stored, hasLength(1));
      expect((stored.single as Map)['modelId'], id);
      expect(store.config['unrelated'], 'keep');

      // Adding the same file again keeps one record.
      await router.addCustomModel(listing, listing.files.single, probe);
      expect((store.config['aiCustomModels'] as List), hasLength(1));
      expect(router.catalog.length, builtIn + 1);

      final other = _router(dir, store, _mock());
      await other.initialize();
      expect(other.isCustom(id), isTrue);
      expect(other.catalog.last.modelId, id);
      expect(other.sourceName(id), probe.displayName);
      expect(other.state.entryFor(id), isNotNull);
    });

    test('aliases win, persist and clear', () async {
      final store = _Store();
      final (router, listing, probe) = await added(store);
      final id = await router.addCustomModel(
        listing,
        listing.files.single,
        probe,
      );
      var notified = 0;
      router.sourceChanges.addListener(() => notified++);
      await router.setModelAlias(id, '  My small model ');
      expect(router.sourceName(id), 'My small model');
      expect(store.config['aiModelAliases'], {id: 'My small model'});
      expect(notified, greaterThan(0));

      final other = _router(dir, store, _mock());
      await other.initialize();
      expect(other.sourceName(id), 'My small model');

      await router.setModelAlias(id, '   ');
      expect(router.sourceName(id), probe.displayName);
      expect(store.config['aiModelAliases'], isEmpty);
    });
  });

  group('removeCustomModel', () {
    test('forgets the record', () async {
      final store = _Store();
      final (router, listing, probe) = await added(store);
      final builtIn = router.catalog.length;
      final id = await router.addCustomModel(
        listing,
        listing.files.single,
        probe,
      );
      await router.removeCustomModel(id);
      expect(router.isCustom(id), isFalse);
      expect(router.catalog.length, builtIn);
      expect(router.sourceOptions.where((o) => o.id == id), isEmpty);
      expect(store.config['aiCustomModels'], isEmpty);
      final other = _router(dir, store, _mock());
      await other.initialize();
      expect(other.isCustom(id), isFalse);
    });

    test('falls back to automatic when it was selected', () async {
      final store = _Store();
      final (router, listing, probe) = await added(store);
      final id = await router.addCustomModel(
        listing,
        listing.files.single,
        probe,
      );
      await router.select(id);
      expect(router.selection.global, id);
      await router.removeCustomModel(id);
      expect(router.selection.global, 'auto');
      final other = _router(dir, store, _mock());
      await other.initialize();
      expect(other.selection.global, 'auto');
    });

    test('keeps the selection when another model is removed', () async {
      final store = _Store();
      final (router, listing, probe) = await added(store);
      final id = await router.addCustomModel(
        listing,
        listing.files.single,
        probe,
      );
      await router.select('local:qwen3.5-0.8b');
      await router.removeCustomModel(id);
      expect(router.selection.global, 'local:qwen3.5-0.8b');
    });

    test('unknown and recommended models are ignored', () async {
      final (router, _, _) = await added(_Store());
      final n = router.catalog.length;
      await router.removeCustomModel('local:qwen3.5-0.8b');
      await router.removeCustomModel('nope');
      expect(router.catalog.length, n);
    });
  });
}
