import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'failure.dart';
import 'manifest.dart';

/// A cancellation signal shared by a download and its caller.
class DownloadCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  /// Purpose: Report whether cancellation was requested.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isCancelled => _cancelled;

  /// Purpose: Request cancellation.
  /// Inputs: None. Returns: None.
  /// Side effects: Notifies listeners once.
  /// Notes: Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Purpose: Run [listener] when cancellation is requested.
  /// Inputs: [listener]. Returns: None.
  /// Side effects: Registers the listener; runs it now if already cancelled.
  /// Notes: Used to close a connection mid-read.
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// Purpose: Report download progress.
/// Inputs: Bytes on disk so far for this file, and the file's total.
/// Returns: None. Side effects: Caller-defined.
/// Notes: Bytes a resume found on disk count from the first report.
typedef DownloadProgress = void Function(int received, int total);

/// Purpose: Open the sink a download writes to.
/// Inputs: The partial [file] and whether to [append].
/// Returns: An [IOSink].
/// Side effects: Opens the file.
/// Notes: Injectable so tests can simulate a full disk.
typedef PartialSinkOpener = IOSink Function(File file, {required bool append});

/// Downloads single files with HTTP range resumption and SHA-256 verification.
class ArtifactDownloader {
  /// Purpose: Create a downloader.
  /// Inputs: Injected [clientFactory], optional [connectTimeout],
  /// [stallTimeout] and [openSink].
  /// Returns: A new downloader. Side effects: None.
  /// Notes: The package never constructs an HTTP client itself; consumers
  /// pass `http.Client.new` or their own client. A stall or unanswered
  /// request fails as [ArtifactFailure.network], which is resumable.
  ArtifactDownloader({
    required this.clientFactory,
    this.connectTimeout = const Duration(seconds: 30),
    this.stallTimeout = const Duration(seconds: 60),
    @visibleForTesting PartialSinkOpener? openSink,
  }) : _openSink = openSink ?? _defaultSink;

  /// Purpose: Create one HTTP client per request.
  /// Inputs: None. Returns: [http.Client]. Side effects: Caller-defined.
  /// Notes: The client is closed after each request or on cancel.
  final http.Client Function() clientFactory;

  /// Purpose: Wait limit for response headers.
  /// Inputs: None. Returns: Duration. Side effects: None. Notes: None.
  final Duration connectTimeout;

  /// Purpose: Longest gap between body chunks.
  /// Inputs: None. Returns: Duration. Side effects: None. Notes: None.
  final Duration stallTimeout;

  final PartialSinkOpener _openSink;

  /// Purpose: Default sink opener.
  /// Inputs: [file], [append]. Returns: [IOSink]. Side effects: Opens file.
  /// Notes: Internal.
  static IOSink _defaultSink(File file, {required bool append}) =>
      file.openWrite(mode: append ? FileMode.append : FileMode.writeOnly);

  /// Purpose: Download [file] to [partial], resuming, and verify it.
  /// Inputs: Manifest entry, partial path, optional [onProgress], [cancel].
  /// Returns: [partial], complete and verified.
  /// Side effects: HTTP request; writes [partial]; deletes it on hash mismatch.
  /// Notes: A partial already at full size is verified without the network.
  /// A 200 reply to a range request restarts the file. 416 with bytes on disk
  /// lets the hash decide. A wrong hash deletes the file so a corrupt prefix
  /// is never resumed.
  Future<File> download(
    ArtifactFile file,
    File partial, {
    DownloadProgress? onProgress,
    DownloadCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw cancelledFailure();
    try {
      await partial.parent.create(recursive: true);
      var have = await partial.exists() ? await partial.length() : 0;
      if (have > file.bytes) {
        await partial.delete();
        have = 0;
      }
      if (have < file.bytes) {
        await _fetch(file, partial, have, onProgress, cancel);
      } else {
        onProgress?.call(have, file.bytes);
      }
      if (cancel?.isCancelled ?? false) throw cancelledFailure();
      final length = await partial.length();
      final digest = await hashFile(partial);
      if (length != file.bytes || digest != file.sha256) {
        await _deleteQuietly(partial);
        throw ArtifactException(
          ArtifactFailure.hashMismatch,
          '${file.path}: expected ${file.bytes} bytes with SHA-256 '
          '${file.sha256}, got $length bytes with $digest.',
        );
      }
      return partial;
    } on FileSystemException catch (error) {
      throw diskFullOr(error);
    }
  }

  /// Purpose: Fetch the missing tail of a file.
  /// Inputs: Entry, [partial], bytes already [have], callbacks.
  /// Returns: None. Side effects: One HTTP request; appends or rewrites.
  /// Notes: Internal.
  Future<void> _fetch(
    ArtifactFile file,
    File partial,
    int have,
    DownloadProgress? onProgress,
    DownloadCancelToken? cancel,
  ) async {
    final client = clientFactory();
    cancel?.onCancel(client.close);
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    try {
      final request = http.Request('GET', Uri.parse(file.sourceUrl));
      if (have > 0) request.headers['Range'] = 'bytes=$have-';

      final http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(connectTimeout);
      } on TimeoutException {
        if (cancel?.isCancelled ?? false) throw cancelledFailure();
        throw const ArtifactException(
          ArtifactFailure.network,
          'The server did not answer in time.',
        );
      } on SocketException catch (error) {
        if (cancel?.isCancelled ?? false) throw cancelledFailure();
        throw ArtifactException(ArtifactFailure.network, error.message);
      } on http.ClientException catch (error) {
        if (cancel?.isCancelled ?? false) throw cancelledFailure();
        throw ArtifactException(ArtifactFailure.network, error.message);
      }
      if (cancel?.isCancelled ?? false) throw cancelledFailure();

      final int start;
      if (response.statusCode == 206 && have > 0) {
        start = have;
      } else if (response.statusCode == 200) {
        start = 0;
      } else if (response.statusCode == 416 && have > 0) {
        await response.stream.drain<void>();
        return;
      } else {
        await response.stream.drain<void>();
        throw ArtifactException(
          ArtifactFailure.httpError,
          '${file.path}: the server answered ${response.statusCode}.',
        );
      }

      sink = _openSink(partial, append: start > 0);
      var received = start;
      onProgress?.call(received, file.bytes);

      final done = Completer<void>();
      // A write error (e.g. ENOSPC) surfaces on the sink's done future, not
      // on the add that caused it; fail the transfer as soon as it does.
      sink.done.then<void>(
        (_) {},
        onError: (Object error) {
          if (!done.isCompleted) done.completeError(error);
        },
      );
      subscription = response.stream
          .timeout(stallTimeout)
          .listen(
            (chunk) {
              sink!.add(chunk);
              received += chunk.length;
              onProgress?.call(received, file.bytes);
            },
            onError: (Object error) {
              if (done.isCompleted) return;
              if (cancel?.isCancelled ?? false) {
                done.completeError(cancelledFailure());
              } else if (error is TimeoutException) {
                done.completeError(
                  const ArtifactException(
                    ArtifactFailure.network,
                    'The download stalled.',
                  ),
                );
              } else if (error is FileSystemException) {
                done.completeError(error);
              } else {
                done.completeError(
                  ArtifactException(ArtifactFailure.network, '$error'),
                );
              }
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      cancel?.onCancel(() {
        if (!done.isCompleted) done.completeError(cancelledFailure());
      });
      await done.future;
      final written = sink;
      sink = null;
      await written.flush();
      await written.close();
    } on FileSystemException catch (error) {
      throw diskFullOr(error);
    } finally {
      await subscription?.cancel();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close();
    }
  }
}

/// Purpose: Compute a file's SHA-256 without reading it into memory.
/// Inputs: [file]. Returns: Lower-case hex digest.
/// Side effects: Reads the file.
/// Notes: Streams, because artifacts reach gigabytes.
Future<String> hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Purpose: Delete a file, ignoring failure.
/// Inputs: [file]. Returns: None. Side effects: May delete the file.
/// Notes: Internal.
Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } catch (_) {}
}
