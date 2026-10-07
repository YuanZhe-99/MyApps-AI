import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'support.dart';

/// Purpose: Match an [ArtifactException] by failure.
/// Inputs: [failure]. Returns: Matcher. Side effects: None. Notes: None.
Matcher failsWith(ArtifactFailure failure) => throwsA(
  isA<ArtifactException>().having((e) => e.failure, 'failure', failure),
);

/// Purpose: Verify install, rollback, leases, coalescing and status.
/// Inputs: None. Returns: None. Side effects: Temp dirs. Notes: Fake HTTP.
void main() {
  late Directory temp;
  late Directory models;
  late FakeHost host;

  ArtifactManager managerFor({
    Future<int?> Function(Directory)? freeSpace,
    DirectoryRenamer? rename,
  }) => ArtifactManager(
    storage: CallbackModelStorageRoot.fixed(models),
    downloader: ArtifactDownloader(clientFactory: host.factory),
    freeSpace: freeSpace,
    platform: testPlatform,
    clock: () => DateTime.utc(2026, 10, 6),
    renameDirectory: rename,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('models_mgr_');
    models = Directory('${temp.path}/models');
    host = FakeHost();
  });
  tearDown(() => temp.delete(recursive: true));

  test('installs into the MyTranscribe layout and records hashes', () async {
    final a = host.serve('weights/model.gguf', payload(700));
    final skipped = host.serve('apple.bin', payload(5), platforms: ['ios']);
    final manager = managerFor();
    final stages = <InstallStage>[];
    final result = await manager.install(
      manifestOf('llm-a', [a, skipped]),
      onProgress: (p) => stages.add(p.stage),
    );

    expect(stages.first, InstallStage.checkingSpace);
    expect(stages.last, InstallStage.done);
    expect(
      File('${models.path}/llm-a/weights/model.gguf').existsSync(),
      isTrue,
    );
    expect(File('${models.path}/llm-a/apple.bin').existsSync(), isFalse);
    final onDisk = jsonDecode(
      File('${models.path}/llm-a/manifest.json').readAsStringSync(),
    );
    expect(onDisk['installedAt'], '2026-10-06T00:00:00.000Z');
    expect(result.installed.single.path, 'weights/model.gguf');
    expect(
      Directory('${models.path}/.downloads/llm-a.staging').existsSync(),
      isFalse,
    );
    expect(await manager.verify('llm-a'), isTrue);
    expect(await manager.diskUsage('llm-a'), greaterThan(700));
    expect(manager.statusOf('llm-a').state, ArtifactState.installed);
    expect(host.requests.map((r) => r.url), isNot(contains(skipped.sourceUrl)));
  });

  test('existing MyTranscribe install and partial are reused', () async {
    final bytes = payload(400);
    final file = host.serve('model.bin', bytes);
    final manifest = manifestOf('whisper-x', [file]);
    final manager = managerFor();

    // A partial left by MyTranscribe at its naming scheme resumes.
    final partial = await manager.partialFile('whisper-x', file);
    expect(
      partial.path,
      '${models.path}/.downloads/whisper-x/model.bin.'
      '${file.sha256.substring(0, 12)}.part',
    );
    await partial.create(recursive: true);
    await partial.writeAsBytes(bytes.sublist(0, 150));
    await manager.install(manifest);
    expect(host.requests.single.range, 'bytes=150-');

    // A fresh manager sees the installed folder without downloading.
    final again = managerFor();
    expect((await again.installed('whisper-x'))?.revision, 'r1');
    expect((await again.refresh('whisper-x')).state, ArtifactState.installed);
  });

  test('unpacks a verified zip and hashes its contents', () async {
    final inner = utf8.encode('hello tokenizer');
    final zip = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('tok/vocab.txt', inner.length, inner)),
    );
    final file = host.serve('bundle.zip', zip, unpack: ArchiveKind.zip);
    final result = await managerFor().install(manifestOf('zipped', [file]));
    expect(result.installed.single.path, 'tok/vocab.txt');
    expect(result.installed.single.sha256, sha(inner));
    expect(
      File('${models.path}/zipped/tok/vocab.txt').readAsStringSync(),
      'hello tokenizer',
    );
  });

  test('hash mismatch fails, publishes failed, installs nothing', () async {
    final file = host.serve('m.gguf', payload(100), hash: 'ff' * 32);
    final manager = managerFor();
    await expectLater(
      manager.install(manifestOf('bad', [file])),
      failsWith(ArtifactFailure.hashMismatch),
    );
    final status = manager.statusOf('bad');
    expect(status.state, ArtifactState.failed);
    expect(status.failure, ArtifactFailure.hashMismatch);
    expect(Directory('${models.path}/bad').existsSync(), isFalse);
  });

  test('free-space probe refuses before downloading', () async {
    final file = host.serve('m.gguf', payload(100));
    await expectLater(
      managerFor(freeSpace: (_) async => 10).install(manifestOf('big', [file])),
      failsWith(ArtifactFailure.diskFull),
    );
    expect(host.requests, isEmpty);
  });

  test('failed rename into place rolls back the previous version', () async {
    final v1 = host.serve('v1.bin', payload(50, 1));
    await managerFor().install(manifestOf('roll', [v1]));

    final v2 = host.serve('v2.bin', payload(60, 2));
    final manager = managerFor(
      rename: (from, to) async {
        if (from.path.endsWith('.staging')) {
          throw const FileSystemException('rename refused');
        }
        await from.rename(to);
      },
    );
    await expectLater(
      manager.install(manifestOf('roll', [v2], revision: 'r2')),
      failsWith(ArtifactFailure.unpackFailed),
    );
    final kept = await manager.installed('roll');
    expect(kept?.revision, 'r1');
    expect(File('${models.path}/roll/v1.bin').existsSync(), isTrue);
    final status = manager.statusOf('roll');
    expect(status.state, ArtifactState.installed);
    expect(status.failure, ArtifactFailure.unpackFailed);
    expect(
      Directory('${models.path}/.downloads/roll.staging').existsSync(),
      isFalse,
    );
  });

  test('leases block remove and replace until every holder releases', () async {
    final file = host.serve('m.gguf', payload(30));
    final manager = managerFor();
    await manager.install(manifestOf('held', [file]));
    final first = manager.lease('held');
    final second = manager.lease('held');
    await expectLater(
      manager.remove('held'),
      failsWith(ArtifactFailure.leased),
    );
    await expectLater(
      manager.install(manifestOf('held', [file], revision: 'r2')),
      failsWith(ArtifactFailure.leased),
    );
    first.release();
    first.release();
    expect(manager.isLeased('held'), isTrue);
    second.release();
    await manager.remove('held');
    expect(await manager.installed('held'), isNull);
    expect(manager.statusOf('held').state, ArtifactState.notInstalled);
  });

  test('duplicate concurrent installs coalesce into one download', () async {
    final file = host.serve('m.gguf', payload(300));
    host.gate = Completer<void>();
    final manager = managerFor();
    final manifest = manifestOf('dup', [file]);
    final a = manager.install(manifest);
    final b = manager.install(manifest);
    expect(manager.isInstalling('dup'), isTrue);
    await expectLater(manager.remove('dup'), failsWith(ArtifactFailure.leased));
    host.gate!.complete();
    final results = await Future.wait([a, b]);
    expect(results[0].installedAt, results[1].installedAt);
    expect(host.requests, hasLength(1));
    expect(manager.isInstalling('dup'), isFalse);
  });

  test('cancel keeps the partial and the next install resumes it', () async {
    final bytes = payload(900);
    final file = host.serve('m.gguf', bytes);
    final manager = managerFor();
    final states = <ArtifactState>[];
    final sub = manager.watch('cx').listen((s) => states.add(s.state));
    host.gate = Completer<void>();
    final future = manager.install(manifestOf('cx', [file]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    manager.cancel('cx');
    host.gate!.complete();
    await expectLater(future, failsWith(ArtifactFailure.cancelled));
    expect(manager.statusOf('cx').state, ArtifactState.notInstalled);
    expect(manager.statusOf('cx').failure, isNull);
    expect(states, contains(ArtifactState.downloading));

    host.gate = null;
    host.dropAfter = 200;
    await expectLater(
      manager.install(manifestOf('cx', [file])),
      failsWith(ArtifactFailure.network),
    );
    await manager.install(manifestOf('cx', [file]));
    expect(host.requests.last.range, 'bytes=200-');
    await sub.cancel();
  });

  test('verify marks a changed file corrupt and offers download', () async {
    final file = host.serve('m.gguf', payload(80));
    final manifest = manifestOf('cor', [file]);
    final manager = managerFor();
    await manager.install(manifest);
    await File('${models.path}/cor/m.gguf').writeAsBytes(payload(80, 99));
    expect(await manager.verify('cor'), isFalse);
    final status = manager.statusOf('cor');
    expect(status.state, ArtifactState.corrupt);
    expect((await manager.refresh('cor')).state, ArtifactState.corrupt);

    final entry = ModelCatalogEntry.forArtifact(
      manifest: manifest,
      status: status,
      platform: testPlatform,
      capability: 'llm',
    );
    expect(entry.state, ModelInstallState.corrupt);
    expect(entry.actions, {
      ModelAction.download,
      ModelAction.verify,
      ModelAction.remove,
    });
  });

  test('unsafe paths and ids are refused as bad manifests', () async {
    final manager = managerFor();
    final evil = host.serve('ok.bin', payload(4));
    final traversal = ArtifactFile(
      path: '../escape.bin',
      bytes: evil.bytes,
      sha256: evil.sha256,
      sourceUrl: evil.sourceUrl,
    );
    await expectLater(
      manager.install(manifestOf('evil', [traversal])),
      failsWith(ArtifactFailure.badManifest),
    );
    await expectLater(
      manager.install(manifestOf('a/b', [evil])),
      failsWith(ArtifactFailure.badManifest),
    );
    expect(host.requests, isEmpty);
  });
}
