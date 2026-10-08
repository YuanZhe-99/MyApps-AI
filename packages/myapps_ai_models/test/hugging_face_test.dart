import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

const _sha = 'f36b1ea49a332ede8fe5f389bbf5b3575ef71f48';
const _lfs = 'fb044e93939a70469c905781334f5de1e6c8b608ced6cbc8c9249bd4127d9526';

Map<String, dynamic> _sibling(String name, {int size = 579615840}) => {
  'rfilename': name,
  'size': size,
  'lfs': {'sha256': _lfs, 'size': size, 'pointerSize': 135},
};

String _body({List<Object?>? siblings, Object? card}) => jsonEncode({
  'sha': _sha,
  'cardData': card ?? {'license': 'apache-2.0'},
  'siblings':
      siblings ??
      [
        _sibling('Qwen_Qwen3.5-0.8B-Q4_K_M.gguf'),
        {'rfilename': 'README.md', 'size': 1000},
      ],
});

HuggingFaceModelSource _source(
  Future<http.Response> Function(http.Request) handler,
) => HuggingFaceModelSource(MockClient(handler));

HuggingFaceModelSource _ok(String body) =>
    _source((_) async => http.Response(body, 200));

Future<ArtifactListingException> _failure(HuggingFaceModelSource s) async {
  try {
    await s.list('owner/name');
  } on ArtifactListingException catch (e) {
    return e;
  }
  throw StateError('expected a failure');
}

void main() {
  group('parseHuggingFaceRepo', () {
    test('accepts names and huggingface.co links', () {
      for (final input in [
        'owner/name',
        '  owner/name  ',
        'https://huggingface.co/owner/name',
        'https://huggingface.co/owner/name/',
        'https://huggingface.co/owner/name/blob/main/x.gguf',
        'https://huggingface.co/owner/name/resolve/abc/x.gguf',
        'https://www.huggingface.co/owner/name/tree/main',
      ]) {
        expect(parseHuggingFaceRepo(input), 'owner/name', reason: input);
      }
    });

    test('rejects everything else', () {
      for (final input in [
        'garbage',
        'owner',
        '',
        '   ',
        'https://huggingface.co/owner',
        'https://huggingface.co/',
        'a b/c',
        'owner/na me',
        'a/b/c',
      ]) {
        expect(parseHuggingFaceRepo(input), isNull, reason: input);
      }
    });
  });

  group('HuggingFaceFile', () {
    test('quantization is lower-cased from the file name', () {
      HuggingFaceFile f(String p) => HuggingFaceFile(p, 1, 'x');
      expect(f('Qwen_Qwen3.5-0.8B-Q4_K_M.gguf').quantization, 'q4_k_m');
      expect(f('m-IQ3_XS.gguf').quantization, 'iq3_xs');
      expect(f('m-BF16.gguf').quantization, 'bf16');
      expect(f('m-f16.gguf').quantization, 'f16');
      expect(f('dir/m-Q8_0.GGUF').quantization, 'q8_0');
      expect(f('m.gguf').quantization, '');
    });

    test('split parts are flagged', () {
      expect(
        const HuggingFaceFile('m-Q4-00001-of-00002.gguf', 1, 'x').split,
        isTrue,
      );
      expect(const HuggingFaceFile('m-Q4.gguf', 1, 'x').split, isFalse);
    });
  });

  group('list', () {
    test(
      'keeps only LFS gguf files, sorted, with commit and license',
      () async {
        final s = _ok(
          _body(
            siblings: [
              _sibling('z-Q8_0.gguf', size: 3),
              _sibling('a-Q4_K_M.gguf', size: 2),
              {'rfilename': 'README.md', 'size': 1000},
              // A gguf without an LFS hash cannot be verified.
              {'rfilename': 'plain.gguf', 'size': 10},
              // LFS entry without a size.
              {
                'rfilename': 'nosize.gguf',
                'lfs': {'sha256': _lfs},
              },
              _sibling('weights.safetensors'),
              _sibling('UPPER-Q4_0.GGUF', size: 4),
              'junk',
            ],
          ),
        );
        final listing = await s.list('owner/name');
        expect(listing.repo, 'owner/name');
        expect(listing.commit, _sha);
        expect(listing.license, 'apache-2.0');
        expect(listing.files.map((f) => f.path), [
          'UPPER-Q4_0.GGUF',
          'a-Q4_K_M.gguf',
          'z-Q8_0.gguf',
        ]);
        final a = listing.files[1];
        expect(a.bytes, 2);
        expect(a.sha256, _lfs);
      },
    );

    test('requests the blobs API of the repository', () async {
      late Uri uri;
      final s = _source((r) async {
        uri = r.url;
        return http.Response(_body(), 200);
      });
      await s.list('bartowski/Qwen_Qwen3.5-0.8B-GGUF');
      expect(uri.host, 'huggingface.co');
      expect(uri.path, '/api/models/bartowski/Qwen_Qwen3.5-0.8B-GGUF');
      expect(uri.queryParameters, {'blobs': 'true'});
    });

    test('license is null without a model card license', () async {
      final listing = await _ok(_body(card: <String, Object>{})).list('o/n');
      expect(listing.license, isNull);
    });

    test('flags split files and parses quantizations', () async {
      final listing = await _ok(
        _body(
          siblings: [
            _sibling('m-Q4_K_M-00001-of-00002.gguf'),
            _sibling('m-IQ3_XS.gguf'),
            _sibling('m-BF16.gguf'),
          ],
        ),
      ).list('o/n');
      final by = {for (final f in listing.files) f.path: f};
      expect(by['m-Q4_K_M-00001-of-00002.gguf']!.split, isTrue);
      expect(by['m-IQ3_XS.gguf']!.split, isFalse);
      expect(by['m-IQ3_XS.gguf']!.quantization, 'iq3_xs');
      expect(by['m-BF16.gguf']!.quantization, 'bf16');
    });

    test('maps failures to reasons', () async {
      expect(
        (await _failure(_source((_) async => http.Response('', 404)))).reason,
        'notFound',
      );
      for (final (code, reason) in [
        (401, 'notFoundOrPrivate'),
        (403, 'gated'),
      ]) {
        expect(
          (await _failure(
            _source((_) async => http.Response('', code)),
          )).reason,
          reason,
        );
      }
      expect(
        (await _failure(_source((_) async => http.Response('', 500)))).reason,
        'http 500',
      );
      expect((await _failure(_ok('{not json'))).reason, 'badResponse');
      expect((await _failure(_ok('[]'))).reason, 'badResponse');
      expect((await _failure(_ok('{"siblings": []}'))).reason, 'badResponse');
      expect(
        (await _failure(
          _source((_) async => throw http.ClientException('offline')),
        )).reason,
        'network',
      );
    });
  });

  group('head', () {
    test(
      'sends a range request to the pinned file and returns bytes',
      () async {
        late http.Request seen;
        final s = _source((r) async {
          seen = r;
          return http.Response.bytes([1, 2, 3], 206);
        });
        final listing = HuggingFaceRepoListing(
          repo: 'owner/name',
          commit: _sha,
          files: const [],
        );
        final bytes = await s.head(
          listing,
          const HuggingFaceFile('sub/x-Q4_0.gguf', 3, _lfs),
          bytes: 1024,
        );
        expect(bytes, Uint8List.fromList([1, 2, 3]));
        expect(seen.headers['Range'], 'bytes=0-1023');
        expect(seen.url.path, '/owner/name/resolve/$_sha/sub/x-Q4_0.gguf');
      },
    );

    test('default range is 256 KiB', () async {
      String? range;
      final s = _source((r) async {
        range = r.headers['Range'];
        return http.Response('', 200);
      });
      await s.head(
        HuggingFaceRepoListing(repo: 'o/n', commit: 'c', files: const []),
        const HuggingFaceFile('x.gguf', 1, 'h'),
      );
      expect(range, 'bytes=0-${(256 << 10) - 1}');
    });

    test('failures are listing exceptions', () async {
      final listing = HuggingFaceRepoListing(
        repo: 'o/n',
        commit: 'c',
        files: const [],
      );
      const file = HuggingFaceFile('x.gguf', 1, 'h');
      await expectLater(
        _source((_) async => http.Response('', 404)).head(listing, file),
        throwsA(
          isA<ArtifactListingException>().having(
            (e) => e.reason,
            'reason',
            'http 404',
          ),
        ),
      );
      await expectLater(
        _source(
          (_) async => throw http.ClientException('offline'),
        ).head(listing, file),
        throwsA(
          isA<ArtifactListingException>().having(
            (e) => e.reason,
            'reason',
            'network',
          ),
        ),
      );
    });
  });

  group('manifestFor', () {
    late HuggingFaceRepoListing listing;
    setUp(() async {
      listing = await _ok(_body()).list('bartowski/Qwen_Qwen3.5-0.8B-GGUF');
    });

    test('pins the commit and carries LFS hash and size', () {
      final file = listing.files.single;
      final m = listing.manifestFor(
        file,
        backendId: 'llama',
        displayName: 'Qwen3.5 0.8B',
        vendor: 'Qwen',
      );
      expect(
        m.modelId,
        'local:hf:bartowski/Qwen_Qwen3.5-0.8B-GGUF/${file.path}',
      );
      expect(m.backendId, 'llama');
      expect(m.format, ArtifactFormat.gguf);
      expect(m.revision, _sha);
      expect(m.quantization, 'q4_k_m');
      expect(m.licenseId, 'apache-2.0');
      final f = m.files.single;
      expect(f.path, 'Qwen_Qwen3.5-0.8B-Q4_K_M.gguf');
      expect(f.bytes, 579615840);
      expect(f.sha256, _lfs);
      expect(
        f.sourceUrl,
        'https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/'
        '$_sha/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
      );
      expect(m.extraJson[artifactCustomKey], true);
      expect(m.extraJson[artifactNameKey], 'Qwen3.5 0.8B');
      expect(m.extraJson[artifactVendorKey], 'Qwen');
      expect(artifactDisplayName(m), 'Qwen: Qwen3.5 0.8B (Q4_K_M)');
    });

    test('omits absent naming keys and unknown license', () async {
      final bare = await _ok(_body(card: <String, Object>{})).list('o/n');
      final m = bare.manifestFor(bare.files.single, backendId: 'llama');
      expect(m.extraJson, {artifactCustomKey: true});
      expect(m.licenseId, 'unknown');
    });

    test('the same input gives the same ids and round-trips as JSON', () {
      final file = listing.files.single;
      final a = listing.manifestFor(file, backendId: 'llama');
      final b = listing.manifestFor(file, backendId: 'llama');
      expect(a.artifactId, b.artifactId);
      expect(a.artifactId, startsWith('hf-'));
      expect(a.artifactId, matches(RegExp(r'^[a-z0-9._-]+$')));
      final back = ArtifactManifest.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );
      expect(back.artifactId, a.artifactId);
      expect(back.extraJson[artifactCustomKey], true);
    });

    test('different files give different ids', () async {
      final two = await _ok(
        _body(siblings: [_sibling('a-Q4_0.gguf'), _sibling('b-Q4_0.gguf')]),
      ).list('o/n');
      expect(
        two.manifestFor(two.files[0], backendId: 'l').artifactId,
        isNot(two.manifestFor(two.files[1], backendId: 'l').artifactId),
      );
    });
  });

  test('ArtifactListingException renders its reason', () {
    expect(
      const ArtifactListingException('gated').toString(),
      contains('gated'),
    );
  });
}
