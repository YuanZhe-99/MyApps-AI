import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'downloader.dart';
import 'failure.dart';
import 'manifest.dart';
import 'storage.dart';

/// What an install is doing.
enum InstallStage {
  /// Checking there is room.
  checkingSpace,

  /// Fetching a file.
  downloading,

  /// Unpacking an archive.
  unpacking,

  /// Hashing what was installed.
  verifying,

  /// Renaming it into place.
  installing,

  /// Finished.
  done,
}

/// How far an install has got.
@immutable
class InstallProgress {
  /// Purpose: Current stage.
  /// Inputs: None. Returns: [InstallStage]. Side effects: None. Notes: None.
  final InstallStage stage;

  /// Purpose: Bytes downloaded so far across the artifact.
  /// Inputs: None. Returns: int. Side effects: None.
  /// Notes: Includes bytes resumed from disk.
  final int receivedBytes;

  /// Purpose: Bytes to download in total for this platform.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int totalBytes;

  /// Purpose: Create a progress report.
  /// Inputs: [stage], [receivedBytes], [totalBytes].
  /// Returns: A new immutable value. Side effects: None. Notes: None.
  const InstallProgress(this.stage, this.receivedBytes, this.totalBytes);

  /// Purpose: Fraction downloaded.
  /// Inputs: None. Returns: 0..1, or null when the total is unknown.
  /// Side effects: None. Notes: None.
  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// The space an install needs, counted in its three phases.
@immutable
class SpaceBudget {
  /// Purpose: Bytes still to download.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int download;

  /// Purpose: Bytes archives unpack to, alongside the archives.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int unpack;

  /// Purpose: Extra bytes the rename into place needs.
  /// Inputs: None. Returns: int. Side effects: None.
  /// Notes: Zero on one volume.
  final int install;

  /// Purpose: Create a space budget.
  /// Inputs: [download], [unpack], [install]. Returns: A new value.
  /// Side effects: None. Notes: None.
  const SpaceBudget({
    required this.download,
    required this.unpack,
    required this.install,
  });

  /// Purpose: Most the install has on disk at once.
  /// Inputs: None. Returns: Bytes. Side effects: None. Notes: None.
  int get peak => download + unpack + install;
}

/// Lifecycle state of one artifact on this device.
enum ArtifactState {
  /// No readable installed manifest.
  notInstalled,

  /// An install is fetching files.
  downloading,

  /// Files are being unpacked, hashed or checked.
  verifying,

  /// Installed with a readable manifest.
  installed,

  /// The last install failed and nothing usable is installed.
  failed,

  /// Installed, but a verification found missing or changed files.
  corrupt,
}

/// The latest known status of one artifact.
@immutable
class ArtifactStatus {
  /// Purpose: Artifact this status describes.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String artifactId;

  /// Purpose: Lifecycle state.
  /// Inputs: None. Returns: [ArtifactState]. Side effects: None. Notes: None.
  final ArtifactState state;

  /// Purpose: Progress while downloading or verifying.
  /// Inputs: None. Returns: [InstallProgress] or null. Side effects: None.
  /// Notes: Null outside an active operation.
  final InstallProgress? progress;

  /// Purpose: Failure of the last operation, when it failed.
  /// Inputs: None. Returns: [ArtifactFailure] or null. Side effects: None.
  /// Notes: May accompany [ArtifactState.installed] when an update failed
  /// and the previous version stayed in place. Cancellation is not a failure.
  final ArtifactFailure? failure;

  /// Purpose: Detail for the failure.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? message;

  /// Purpose: Installed manifest, when installed or corrupt.
  /// Inputs: None. Returns: [ArtifactManifest] or null. Side effects: None.
  /// Notes: None.
  final ArtifactManifest? manifest;

  /// Purpose: Create a status.
  /// Inputs: All fields. Returns: A new immutable value. Side effects: None.
  /// Notes: None.
  const ArtifactStatus(
    this.artifactId,
    this.state, {
    this.progress,
    this.failure,
    this.message,
    this.manifest,
  });

  /// Purpose: Bytes installed, as recorded in the manifest.
  /// Inputs: None. Returns: int. Side effects: None. Notes: Zero if none.
  int get installedBytes => manifest?.installedBytes ?? 0;

  /// Purpose: Render for diagnostics.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  @override
  String toString() =>
      'ArtifactStatus($artifactId, ${state.name}'
      '${failure == null ? '' : ', ${failure!.name}'})';
}

/// A holder's claim that keeps an artifact from being replaced or removed.
class ArtifactLease {
  /// Purpose: Create a lease.
  /// Inputs: [artifactId], release callback.
  /// Returns: A new lease. Side effects: None.
  /// Notes: Created only by [ArtifactManager.lease].
  ArtifactLease._(this.artifactId, this._release);

  /// Purpose: Artifact held.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String artifactId;

  final void Function() _release;
  bool _released = false;

  /// Purpose: Report whether this lease was released.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get released => _released;

  /// Purpose: Let go of the artifact.
  /// Inputs: None. Returns: None.
  /// Side effects: Decrements the lease count.
  /// Notes: Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Purpose: Rename a directory.
/// Inputs: [from], destination path [to].
/// Returns: None. Side effects: Renames on disk.
/// Notes: Injectable to test rollback.
typedef DirectoryRenamer = Future<void> Function(Directory from, String to);

/// Installs, verifies, leases and removes model artifacts.
///
/// Layout under the models root (identical to MyTranscribe):
/// `<artifactId>/manifest.json` plus files; `.downloads/<artifactId>/<name>.<sha12>.part`
/// for partial downloads; `.downloads/<artifactId>.staging` and
/// `.downloads/<artifactId>.old` during an install.
class ArtifactManager {
  /// Purpose: Create a manager.
  /// Inputs: [storage] root, [downloader], optional [freeSpace] probe,
  /// [platform] and [clock].
  /// Returns: A new manager. Side effects: None.
  /// Notes: [freeSpace] returning null defers to the write's own disk-full
  /// error. [platform] defaults to [ModelPlatform.current].
  ArtifactManager({
    required this._storage,
    required this._downloader,
    Future<int?> Function(Directory directory)? freeSpace,
    ModelPlatform? platform,
    DateTime Function()? clock,
    @visibleForTesting DirectoryRenamer? renameDirectory,
  }) : _freeSpace = freeSpace ?? ((_) async => null),
       platform = platform ?? ModelPlatform.current(),
       _clock = clock ?? DateTime.now,
       _rename = renameDirectory ?? _defaultRename;

  final ModelStorageRoot _storage;
  final ArtifactDownloader _downloader;
  final Future<int?> Function(Directory) _freeSpace;
  final DateTime Function() _clock;
  final DirectoryRenamer _rename;

  /// Purpose: Platform that manifest filters are evaluated for.
  /// Inputs: None. Returns: [ModelPlatform]. Side effects: None. Notes: None.
  final ModelPlatform platform;

  final _leases = <String, int>{};
  final _active = <String, Future<ArtifactManifest>>{};
  final _cancels = <String, DownloadCancelToken>{};
  final _status = <String, ArtifactStatus>{};
  final _changes = StreamController<ArtifactStatus>.broadcast(sync: true);

  /// Purpose: Default rename.
  /// Inputs: [from], [to]. Returns: None. Side effects: Renames.
  /// Notes: Internal.
  static Future<void> _defaultRename(Directory from, String to) async {
    await from.rename(to);
  }

  /// Purpose: Resolve the models root.
  /// Inputs: None. Returns: Directory. Side effects: Storage adapter.
  /// Notes: None.
  Future<Directory> modelsDir() => _storage.modelsDir();

  /// Purpose: Locate one artifact's folder.
  /// Inputs: [artifactId]. Returns: Directory, which may not exist.
  /// Side effects: None. Notes: Id is made folder-safe.
  Future<Directory> artifactDir(String artifactId) async =>
      Directory(p.join((await modelsDir()).path, safeArtifactName(artifactId)));

  /// Purpose: Read an installed artifact's manifest.
  /// Inputs: [artifactId].
  /// Returns: The manifest, or null when absent, unreadable or for another id.
  /// Side effects: Reads the file.
  /// Notes: A folder without a readable manifest counts as not installed —
  /// what a system purge of a caches directory leaves at worst.
  Future<ArtifactManifest?> installed(String artifactId) async {
    final file = File(
      p.join((await artifactDir(artifactId)).path, artifactManifestFileName),
    );
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final manifest = ArtifactManifest.fromJson(json);
      return manifest.artifactId == artifactId ? manifest : null;
    } catch (_) {
      return null;
    }
  }

  /// Purpose: List every installed artifact.
  /// Inputs: None. Returns: Manifests sorted by id.
  /// Side effects: Reads the models root.
  /// Notes: Dot-folders (`.downloads`) are skipped.
  Future<List<ArtifactManifest>> installedAll() async {
    final dir = await modelsDir();
    if (!await dir.exists()) return const [];
    final result = <ArtifactManifest>[];
    await for (final entry in dir.list()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;
      final manifest = await installed(name);
      if (manifest != null) result.add(manifest);
    }
    return result..sort((a, b) => a.artifactId.compareTo(b.artifactId));
  }

  /// Purpose: Latest known status of an artifact.
  /// Inputs: [artifactId]. Returns: [ArtifactStatus].
  /// Side effects: None.
  /// Notes: [ArtifactState.notInstalled] until [refresh] or an operation ran.
  ArtifactStatus statusOf(String artifactId) =>
      _status[artifactId] ??
      ArtifactStatus(artifactId, ArtifactState.notInstalled);

  /// Purpose: Re-read an artifact's status from disk.
  /// Inputs: [artifactId]. Returns: The status.
  /// Side effects: Reads the manifest; publishes a change.
  /// Notes: Leaves an active install's status alone. Keeps a `corrupt`
  /// verdict for the same installed revision until the next verify/install.
  Future<ArtifactStatus> refresh(String artifactId) async {
    if (_active.containsKey(artifactId)) return statusOf(artifactId);
    final manifest = await installed(artifactId);
    final previous = _status[artifactId];
    final ArtifactStatus next;
    if (manifest == null) {
      next = previous?.state == ArtifactState.failed
          ? previous!
          : ArtifactStatus(artifactId, ArtifactState.notInstalled);
    } else if (previous?.state == ArtifactState.corrupt &&
        previous?.manifest?.installedAt == manifest.installedAt) {
      next = previous!;
    } else {
      next = ArtifactStatus(
        artifactId,
        ArtifactState.installed,
        manifest: manifest,
        failure: previous?.failure,
        message: previous?.message,
      );
    }
    _publish(next);
    return next;
  }

  /// Purpose: Observe an artifact's status.
  /// Inputs: [artifactId].
  /// Returns: A stream starting with the current status, then each change.
  /// Side effects: The first listen triggers a [refresh] when nothing is
  /// known yet.
  /// Notes: Single-subscription per call; cancel to stop.
  Stream<ArtifactStatus> watch(String artifactId) {
    late StreamController<ArtifactStatus> controller;
    StreamSubscription<ArtifactStatus>? sub;
    controller = StreamController<ArtifactStatus>(
      onListen: () {
        sub = _changes.stream
            .where((s) => s.artifactId == artifactId)
            .listen(controller.add);
        if (_status.containsKey(artifactId)) {
          controller.add(_status[artifactId]!);
        } else {
          unawaited(refresh(artifactId));
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Purpose: Work out how much room an install needs from here.
  /// Inputs: [manifest]. Returns: [SpaceBudget].
  /// Side effects: Reads partial-download sizes.
  /// Notes: Bytes already on disk are not counted again.
  Future<SpaceBudget> spaceNeeded(ArtifactManifest manifest) async {
    var download = 0;
    var unpack = 0;
    for (final file in manifest.filesFor(platform)) {
      final partial = await partialFile(manifest.artifactId, file);
      final have = await partial.exists() ? await partial.length() : 0;
      download += (file.bytes - have).clamp(0, file.bytes);
      if (file.unpack != ArchiveKind.none) {
        unpack += file.unpackedBytes ?? file.bytes;
      }
    }
    return SpaceBudget(download: download, unpack: unpack, install: 0);
  }

  /// Purpose: Measure what an artifact occupies on disk.
  /// Inputs: [artifactId].
  /// Returns: Bytes in its folder plus its partial downloads.
  /// Side effects: Lists files.
  /// Notes: Measured, unlike [ArtifactStatus.installedBytes].
  Future<int> diskUsage(String artifactId) async {
    final root = await modelsDir();
    final name = safeArtifactName(artifactId);
    return await _sizeOf(Directory(p.join(root.path, name))) +
        await _sizeOf(
          Directory(p.join(root.path, modelDownloadsDirName, name)),
        );
  }

  /// Purpose: Measure the whole models root.
  /// Inputs: None. Returns: Bytes. Side effects: Lists files.
  /// Notes: Includes partials, staging and orphaned folders.
  Future<int> totalDiskUsage() async => _sizeOf(await modelsDir());

  /// Purpose: Hold an artifact so it cannot be replaced or removed.
  /// Inputs: [artifactId]. Returns: [ArtifactLease].
  /// Side effects: Counts the lease.
  /// Notes: Leases count; every holder has to release.
  ArtifactLease lease(String artifactId) {
    _leases[artifactId] = (_leases[artifactId] ?? 0) + 1;
    return ArtifactLease._(artifactId, () {
      final left = (_leases[artifactId] ?? 1) - 1;
      if (left <= 0) {
        _leases.remove(artifactId);
      } else {
        _leases[artifactId] = left;
      }
    });
  }

  /// Purpose: Report whether an artifact is held.
  /// Inputs: [artifactId]. Returns: bool. Side effects: None. Notes: None.
  bool isLeased(String artifactId) => (_leases[artifactId] ?? 0) > 0;

  /// Purpose: Report whether an install of [artifactId] is running.
  /// Inputs: [artifactId]. Returns: bool. Side effects: None. Notes: None.
  bool isInstalling(String artifactId) => _active.containsKey(artifactId);

  /// Purpose: Cancel a running install.
  /// Inputs: [artifactId]. Returns: None.
  /// Side effects: Closes the connection; the install fails with
  /// [ArtifactFailure.cancelled].
  /// Notes: Partial downloads are kept for resumption. No-op when idle.
  void cancel(String artifactId) => _cancels[artifactId]?.cancel();

  /// Purpose: Download, verify, unpack and install an artifact.
  /// Inputs: [manifest], optional [onProgress] and [cancel].
  /// Returns: The installed manifest with what was installed hashed.
  /// Side effects: Downloads into `.downloads/`, stages, renames into place,
  /// removes the replaced version; publishes status changes.
  /// Notes: Only the manifest URLs are contacted. A second call for an id
  /// already installing returns the same future (its [onProgress] is not
  /// attached; observe [watch] instead). Partials survive failure or cancel.
  Future<ArtifactManifest> install(
    ArtifactManifest manifest, {
    void Function(InstallProgress progress)? onProgress,
    DownloadCancelToken? cancel,
  }) {
    final id = manifest.artifactId;
    final running = _active[id];
    if (running != null) {
      if (cancel != null) cancel.onCancel(() => this.cancel(id));
      return running;
    }
    final token = DownloadCancelToken();
    cancel?.onCancel(token.cancel);
    _cancels[id] = token;
    final future = _install(manifest, onProgress, token);
    _active[id] = future;
    return future.whenComplete(() {
      _active.remove(id);
      _cancels.remove(id);
    });
  }

  /// Purpose: Install body.
  /// Inputs: [manifest], [onProgress], [cancel]. Returns: Installed manifest.
  /// Side effects: See [install]. Notes: Internal.
  Future<ArtifactManifest> _install(
    ArtifactManifest manifest,
    void Function(InstallProgress progress)? onProgress,
    DownloadCancelToken cancel,
  ) async {
    final id = manifest.artifactId;
    final previous = await installed(id);
    void report(InstallProgress progress) {
      _publish(
        ArtifactStatus(
          id,
          progress.stage == InstallStage.downloading ||
                  progress.stage == InstallStage.checkingSpace
              ? ArtifactState.downloading
              : ArtifactState.verifying,
          progress: progress,
          manifest: previous,
        ),
      );
      onProgress?.call(progress);
    }

    try {
      final result = await _installSteps(manifest, report, cancel);
      _publish(ArtifactStatus(id, ArtifactState.installed, manifest: result));
      return result;
    } on ArtifactException catch (error) {
      final still = await installed(id);
      if (error.failure == ArtifactFailure.cancelled) {
        _publish(
          ArtifactStatus(
            id,
            still == null
                ? ArtifactState.notInstalled
                : ArtifactState.installed,
            manifest: still,
          ),
        );
      } else {
        _publish(
          ArtifactStatus(
            id,
            still == null ? ArtifactState.failed : ArtifactState.installed,
            manifest: still,
            failure: error.failure,
            message: error.message,
          ),
        );
      }
      rethrow;
    } catch (error) {
      final still = await installed(id);
      _publish(
        ArtifactStatus(
          id,
          still == null ? ArtifactState.failed : ArtifactState.installed,
          manifest: still,
          failure: ArtifactFailure.unpackFailed,
          message: '$error',
        ),
      );
      rethrow;
    }
  }

  /// Purpose: The ordered install steps.
  /// Inputs: [manifest], [report], [cancel]. Returns: Installed manifest.
  /// Side effects: Disk and network. Notes: Internal; mirrors MyTranscribe.
  Future<ArtifactManifest> _installSteps(
    ArtifactManifest manifest,
    void Function(InstallProgress) report,
    DownloadCancelToken cancel,
  ) async {
    final id = manifest.artifactId;
    if (id.isEmpty || safeArtifactName(id) != id || manifest.files.isEmpty) {
      throw const ArtifactException(
        ArtifactFailure.badManifest,
        'The manifest names no files or has an unusable id.',
      );
    }
    final files = manifest.filesFor(platform);
    if (files.isEmpty || !manifest.supports(platform)) {
      throw ArtifactException(
        ArtifactFailure.badManifest,
        'The artifact has no files for $platform.',
      );
    }
    for (final file in files) {
      safeRelativePath(file.path);
    }
    _refuseIfLeased(id);
    final total = files.fold<int>(0, (sum, file) => sum + file.bytes);

    report(InstallProgress(InstallStage.checkingSpace, 0, total));
    final models = await modelsDir();
    final Directory staging;
    try {
      await models.create(recursive: true);
      final budget = await spaceNeeded(manifest);
      final free = await _freeSpace(models);
      if (free != null && free < budget.peak) {
        throw ArtifactException(
          ArtifactFailure.diskFull,
          'This model needs ${budget.peak} bytes free (download '
          '${budget.download}, unpacking ${budget.unpack}, install '
          '${budget.install}); $free are free.',
        );
      }
      staging = Directory(
        p.join(models.path, modelDownloadsDirName, '$id.staging'),
      );
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
    } on FileSystemException catch (error) {
      throw diskFullOr(error);
    }

    final installedFiles = <InstalledFile>[];
    var done = 0;
    try {
      for (final file in files) {
        final relative = safeRelativePath(file.path);
        final partial = await partialFile(id, file);
        await _downloader.download(
          file,
          partial,
          cancel: cancel,
          onProgress: (received, _) => report(
            InstallProgress(InstallStage.downloading, done + received, total),
          ),
        );
        done += file.bytes;
        if (cancel.isCancelled) throw cancelledFailure();

        if (file.unpack == ArchiveKind.none) {
          final target = File(p.join(staging.path, relative));
          await target.parent.create(recursive: true);
          await partial.rename(target.path);
          installedFiles.add(
            InstalledFile(
              path: file.path,
              bytes: file.bytes,
              sha256: file.sha256,
            ),
          );
        } else {
          report(InstallProgress(InstallStage.unpacking, done, total));
          await _unpack(file, partial, staging);
          await partial.delete();
        }
      }

      report(InstallProgress(InstallStage.verifying, done, total));
      final direct = {for (final f in installedFiles) f.path};
      await for (final entry in staging.list(recursive: true)) {
        if (entry is! File) continue;
        final relative = p
            .relative(entry.path, from: staging.path)
            .replaceAll(r'\', '/');
        if (direct.contains(relative)) continue;
        installedFiles.add(
          InstalledFile(
            path: relative,
            bytes: await entry.length(),
            sha256: await hashFile(entry),
          ),
        );
      }
      installedFiles.sort((a, b) => a.path.compareTo(b.path));

      final result = manifest.asInstalled(installedFiles, _clock());
      await File(p.join(staging.path, artifactManifestFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
        flush: true,
      );

      report(InstallProgress(InstallStage.installing, done, total));
      if (cancel.isCancelled) throw cancelledFailure();
      _refuseIfLeased(id);
      final target = await artifactDir(id);
      final old = Directory(
        p.join(models.path, modelDownloadsDirName, '$id.old'),
      );
      if (await old.exists()) await old.delete(recursive: true);
      final hadPrevious = await target.exists();
      if (hadPrevious) await _rename(target, old.path);
      try {
        await _rename(staging, target.path);
      } catch (_) {
        // Put the previous version back so a failed update never leaves the
        // model with nothing installed.
        if (hadPrevious && !await target.exists()) {
          try {
            await _rename(old, target.path);
          } catch (_) {}
        }
        rethrow;
      }
      try {
        if (await old.exists()) await old.delete(recursive: true);
      } catch (_) {}

      report(InstallProgress(InstallStage.done, total, total));
      return result;
    } on FileSystemException catch (error) {
      throw diskFullOr(error);
    } finally {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Purpose: Check an installed artifact against what was installed.
  /// Inputs: [artifactId].
  /// Returns: true when every installed file has its recorded size and hash.
  /// Side effects: Hashes every file; publishes `verifying`, then
  /// `installed` or `corrupt` (or `notInstalled` without a manifest).
  /// Notes: Slow for large artifacts; run on request or after a load failure.
  Future<bool> verify(String artifactId) async {
    final manifest = await installed(artifactId);
    if (manifest == null) {
      _publish(ArtifactStatus(artifactId, ArtifactState.notInstalled));
      return false;
    }
    final total = manifest.installedBytes;
    _publish(
      ArtifactStatus(
        artifactId,
        ArtifactState.verifying,
        manifest: manifest,
        progress: InstallProgress(InstallStage.verifying, 0, total),
      ),
    );
    var ok = manifest.installed.isNotEmpty;
    final dir = await artifactDir(artifactId);
    var checked = 0;
    try {
      for (final file in manifest.installed) {
        if (!ok) break;
        final onDisk = File(p.join(dir.path, safeRelativePath(file.path)));
        ok =
            await onDisk.exists() &&
            await onDisk.length() == file.bytes &&
            await hashFile(onDisk) == file.sha256;
        checked += file.bytes;
        _publish(
          ArtifactStatus(
            artifactId,
            ArtifactState.verifying,
            manifest: manifest,
            progress: InstallProgress(InstallStage.verifying, checked, total),
          ),
        );
      }
    } catch (_) {
      ok = false;
    }
    _publish(
      ArtifactStatus(
        artifactId,
        ok ? ArtifactState.installed : ArtifactState.corrupt,
        manifest: manifest,
      ),
    );
    return ok;
  }

  /// Purpose: Remove an installed artifact and its partial downloads.
  /// Inputs: [artifactId]. Returns: None.
  /// Side effects: Deletes its folder and `.downloads/<artifactId>/`;
  /// publishes `notInstalled`.
  /// Notes: Refused while leased or installing.
  Future<void> remove(String artifactId) async {
    _refuseIfLeased(artifactId);
    if (_active.containsKey(artifactId)) {
      throw const ArtifactException(
        ArtifactFailure.leased,
        'The artifact is being installed; cancel the install first.',
      );
    }
    final dir = await artifactDir(artifactId);
    if (await dir.exists()) await dir.delete(recursive: true);
    final partials = Directory(
      p.join(
        (await modelsDir()).path,
        modelDownloadsDirName,
        safeArtifactName(artifactId),
      ),
    );
    if (await partials.exists()) await partials.delete(recursive: true);
    _publish(ArtifactStatus(artifactId, ArtifactState.notInstalled));
  }

  /// Purpose: Locate a file's partial download.
  /// Inputs: [artifactId], [file]. Returns: File path.
  /// Side effects: None.
  /// Notes: `.downloads/<artifactId>/<basename>.<sha256[0:12]>.part`, as in
  /// MyTranscribe, so its partials resume and a changed file never resumes
  /// the old bytes.
  Future<File> partialFile(String artifactId, ArtifactFile file) async {
    final models = await modelsDir();
    final hash = file.sha256.length >= 12
        ? file.sha256.substring(0, 12)
        : file.sha256;
    final name = '${p.basename(safeRelativePath(file.path))}.$hash.part';
    return File(
      p.join(
        models.path,
        modelDownloadsDirName,
        safeArtifactName(artifactId),
        name,
      ),
    );
  }

  /// Purpose: Release the status stream.
  /// Inputs: None. Returns: None. Side effects: Closes listeners.
  /// Notes: Cancels running installs.
  Future<void> dispose() async {
    for (final token in _cancels.values) {
      token.cancel();
    }
    await _changes.close();
  }

  /// Purpose: Record and broadcast a status.
  /// Inputs: [status]. Returns: None. Side effects: Emits a change.
  /// Notes: Internal.
  void _publish(ArtifactStatus status) {
    _status[status.artifactId] = status;
    if (!_changes.isClosed) _changes.add(status);
  }

  /// Purpose: Refuse to touch a leased artifact.
  /// Inputs: [artifactId]. Returns: None; throws when leased.
  /// Side effects: None. Notes: Internal.
  void _refuseIfLeased(String artifactId) {
    if (isLeased(artifactId)) {
      throw const ArtifactException(
        ArtifactFailure.leased,
        'The model is in use; it can be changed when that work finishes.',
      );
    }
  }

  /// Purpose: Unpack a verified archive into the staging folder.
  /// Inputs: Manifest [file], downloaded [archive], [staging].
  /// Returns: None. Side effects: Writes contents.
  /// Notes: Internal. The archive is given its real extension because the
  /// unpacker chooses its decoder by name.
  Future<void> _unpack(
    ArtifactFile file,
    File archive,
    Directory staging,
  ) async {
    final extension = switch (file.unpack) {
      ArchiveKind.zip => '.zip',
      ArchiveKind.tarBz2 => '.tar.bz2',
      ArchiveKind.none => '',
    };
    final named = await archive.rename('${archive.path}$extension');
    try {
      await extractFileToDisk(named.path, staging.path);
    } on FileSystemException {
      rethrow;
    } catch (error) {
      throw ArtifactException(
        ArtifactFailure.unpackFailed,
        '${file.path}: $error',
      );
    } finally {
      if (await named.exists()) await named.rename(archive.path);
    }
  }

  /// Purpose: Sum file sizes under a directory.
  /// Inputs: [dir]. Returns: Bytes; zero when absent.
  /// Side effects: Lists files. Notes: Internal.
  static Future<int> _sizeOf(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }
}

/// Purpose: Make an id safe to use as a folder name.
/// Inputs: [id].
/// Returns: The id with anything but letters, digits, `.`, `-`, `_` replaced
/// by `_`.
/// Side effects: None.
/// Notes: Same rule as MyTranscribe, so existing folders are found.
String safeArtifactName(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// Purpose: Check a manifest path stays inside the artifact folder.
/// Inputs: [path], forward slashes.
/// Returns: A relative path in the platform's form.
/// Side effects: None; throws [ArtifactFailure.badManifest] when unsafe.
/// Notes: Absolute paths and `..` or empty segments are refused, not cleaned.
String safeRelativePath(String path) {
  final parts = path.split('/');
  if (path.isEmpty ||
      path.startsWith('/') ||
      p.isAbsolute(path) ||
      parts.any((part) => part == '..' || part.isEmpty)) {
    throw ArtifactException(
      ArtifactFailure.badManifest,
      'The manifest names an unsafe path: $path',
    );
  }
  return p.joinAll(parts);
}
