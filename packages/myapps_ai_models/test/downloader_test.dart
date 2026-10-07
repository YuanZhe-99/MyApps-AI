import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'support.dart';

/// A consumer that fails like a full disk.
class _FullDisk implements StreamConsumer<List<int>> {
  /// Purpose: Fail on write. Inputs: [stream]. Returns: Error.
  /// Side effects: Drains nothing. Notes: ENOSPC.
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.first;
    throw const FileSystemException(
      'No space left on device',
      'partial',
      OSError('No space left on device', 28),
    );
  }

  /// Purpose: Close. Inputs: None. Returns: None. Side effects: None.
  /// Notes: None.
  @override
  Future<void> close() async {}
}

/// Purpose: Verify resumable verified downloads. Inputs: None.
/// Returns: None. Side effects: Temp files. Notes: Fake HTTP only.
void main() {
  late Directory temp;
  late FakeHost host;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('models_dl_');
    host = FakeHost();
  });
  tearDown(() => temp.delete(recursive: true));

  test('interrupted download resumes with a range request', () async {
    final bytes = payload(1000);
    final file = host.serve('m.gguf', bytes);
    final partial = File('${temp.path}/m.part');
    final downloader = ArtifactDownloader(clientFactory: host.factory);

    host.dropAfter = 300;
    await expectLater(
      downloader.download(file, partial),
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.network,
        ),
      ),
    );
    expect(await partial.length(), 300);

    final progress = <int>[];
    await downloader.download(
      file,
      partial,
      onProgress: (received, _) => progress.add(received),
    );
    expect(host.requests.last.range, 'bytes=300-');
    expect(progress.first, 300);
    expect(progress.last, 1000);
    expect(await partial.readAsBytes(), bytes);
  });

  test('server ignoring range restarts the file', () async {
    final bytes = payload(500);
    final file = host.serve('m.gguf', bytes);
    final partial = File('${temp.path}/m.part');
    await partial.writeAsBytes(bytes.sublist(0, 100));
    host.ignoreRange = true;
    await ArtifactDownloader(
      clientFactory: host.factory,
    ).download(file, partial);
    expect(await partial.readAsBytes(), bytes);
  });

  test('hash mismatch deletes the partial', () async {
    final file = host.serve('m.gguf', payload(200), hash: '00' * 32);
    final partial = File('${temp.path}/m.part');
    await expectLater(
      ArtifactDownloader(clientFactory: host.factory).download(file, partial),
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.hashMismatch,
        ),
      ),
    );
    expect(await partial.exists(), isFalse);
  });

  test('complete partial is verified without the network', () async {
    final bytes = payload(64);
    final file = host.serve('m.gguf', bytes);
    final partial = File('${temp.path}/m.part');
    await partial.writeAsBytes(bytes);
    await ArtifactDownloader(
      clientFactory: host.factory,
    ).download(file, partial);
    expect(host.requests, isEmpty);
  });

  test('disk full while writing is reported as diskFull', () async {
    final file = host.serve('m.gguf', payload(300));
    final downloader = ArtifactDownloader(
      clientFactory: host.factory,
      openSink: (_, {required append}) => IOSink(_FullDisk()),
    );
    await expectLater(
      downloader.download(file, File('${temp.path}/m.part')),
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.diskFull,
        ),
      ),
    );
  });

  test('HTTP error is classified', () async {
    final file = host.serve('m.gguf', payload(10));
    host.status = 500;
    await expectLater(
      ArtifactDownloader(
        clientFactory: host.factory,
      ).download(file, File('${temp.path}/m.part')),
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.httpError,
        ),
      ),
    );
  });

  test('cancel mid-body stops and keeps the partial', () async {
    final file = host.serve('m.gguf', payload(400));
    final partial = File('${temp.path}/m.part');
    final token = DownloadCancelToken();
    host.gate = Completer<void>();
    final future = ArtifactDownloader(
      clientFactory: host.factory,
    ).download(file, partial, cancel: token);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    host.gate!.complete();
    await expectLater(
      future,
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.cancelled,
        ),
      ),
    );
    expect(await partial.exists(), isTrue);
  });

  test('stall times out as a network failure', () async {
    final file = host.serve('m.gguf', payload(10));
    host.gate = Completer<void>();
    await expectLater(
      ArtifactDownloader(
        clientFactory: host.factory,
        stallTimeout: const Duration(milliseconds: 30),
      ).download(file, File('${temp.path}/m.part')),
      throwsA(
        isA<ArtifactException>().having(
          (e) => e.failure,
          'failure',
          ArtifactFailure.network,
        ),
      ),
    );
    host.gate!.complete();
  });
}
