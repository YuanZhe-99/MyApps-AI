import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'engine_state.dart';

/// The result of reading the engine state file.
@immutable
class EngineStateRead {
  /// Purpose: The parsed state; empty when absent or unreadable.
  /// Inputs: None. Returns: [LocalEngineState]. Side effects: None.
  /// Notes: None.
  final LocalEngineState state;

  /// Purpose: Whether the file exists but its content could not be parsed.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: The next write sets the file aside rather than overwriting it.
  final bool unreadable;

  /// Purpose: Create a read result.
  /// Inputs: [state], [unreadable]. Returns: A new value.
  /// Side effects: None. Notes: None.
  const EngineStateRead(this.state, {this.unreadable = false});
}

/// Reads and writes the device-local engine state file.
///
/// The file location comes from the application (MyTranscribe:
/// `local_engine_state.json` beside its data files). It must never be a
/// sync, backup or export module.
class LocalEngineStateStore {
  /// Purpose: Create a store.
  /// Inputs: [file] resolver, optional [clock].
  /// Returns: A new store. Side effects: None.
  /// Notes: Writes are serialised inside the store.
  LocalEngineStateStore({required this._file, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<File> Function() _file;
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();

  /// Purpose: Path set aside on the last write, if any.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: For diagnostics; the bytes there are recoverable by hand.
  String? lastSetAsidePath;

  /// Purpose: Read the state with its readability.
  /// Inputs: None. Returns: [EngineStateRead].
  /// Side effects: Reads the file.
  /// Notes: Absent or blank is empty and readable. Content that is not a JSON
  /// object is unreadable. An I/O error is thrown, never taken for content.
  Future<EngineStateRead> read() async {
    final file = await _file();
    if (!await file.exists()) return const EngineStateRead(LocalEngineState());
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const EngineStateRead(LocalEngineState());
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return EngineStateRead(LocalEngineState.fromJson(json));
      }
    } on FormatException {
      // Unreadable content.
    }
    return const EngineStateRead(LocalEngineState(), unreadable: true);
  }

  /// Purpose: Read the state leniently.
  /// Inputs: None. Returns: The state; empty when absent or unreadable.
  /// Side effects: Reads the file; renames nothing.
  /// Notes: An unreadable or locked file reads as a device that never checked
  /// anything, which costs a re-check and never a wrong answer — as in
  /// MyTranscribe. Use [read] to learn whether it was unreadable.
  Future<LocalEngineState> load() async {
    try {
      return (await read()).state;
    } catch (_) {
      return const LocalEngineState();
    }
  }

  /// Purpose: Change the state.
  /// Inputs: [change] applied to the state on disk now.
  /// Returns: The state written.
  /// Side effects: Atomically rewrites the file; when its content was
  /// unreadable, first renames it to `<name>.unreadable-<UTC stamp>`.
  /// Notes: Queued behind running writes. An I/O error on read fails the
  /// write and leaves the file untouched.
  Future<LocalEngineState> update(
    LocalEngineState Function(LocalEngineState current) change,
  ) {
    final result = Completer<LocalEngineState>();
    _tail = _tail.then((_) async {
      try {
        final file = await _file();
        final current = await read();
        if (current.unreadable) {
          lastSetAsidePath = await _setAside(file);
        }
        final next = change(current.state);
        await _atomicWrite(
          file,
          const JsonEncoder.withIndent('  ').convert(next.toJson()),
        );
        result.complete(next);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  /// Purpose: Record that a native call is starting.
  /// Inputs: [routeKey], [fingerprint], optional [jobId].
  /// Returns: None. Side effects: Writes the marker.
  /// Notes: Written before the call so a process that dies inside leaves it
  /// for [recoverFromCrash].
  Future<void> markInFlight({
    required String routeKey,
    required HealthFingerprint fingerprint,
    String? jobId,
  }) => update(
    (state) => state.copyWith(
      inFlight: InFlightMarker(
        routeKey: routeKey,
        fingerprintKey: fingerprint.encode(),
        jobId: jobId,
        startedAt: _clock().toUtc(),
      ),
    ),
  );

  /// Purpose: Record that the native call returned.
  /// Inputs: None. Returns: None. Side effects: Removes the marker.
  /// Notes: Called on success, failure and cancel alike.
  Future<void> clearInFlight() =>
      update((state) => state.copyWith(clearInFlight: true));

  /// Purpose: Record one self-test.
  /// Inputs: [fingerprint], [record]. Returns: None.
  /// Side effects: Writes the record under the encoded fingerprint.
  /// Notes: Records under other fingerprints are kept.
  Future<void> recordSelfTest(
    HealthFingerprint fingerprint,
    SelfTestRecord record,
  ) => update(
    (state) => state.copyWith(
      selfTests: {...state.selfTests, fingerprint.encode(): record},
    ),
  );

  /// Purpose: Look up a reusable self-test.
  /// Inputs: [fingerprint]. Returns: The record, or null.
  /// Side effects: Reads the file.
  /// Notes: A record is reused only for an exact fingerprint match.
  Future<SelfTestRecord?> selfTestFor(HealthFingerprint fingerprint) async =>
      (await load()).selfTestFor(fingerprint);

  /// Purpose: Turn a marker left by a crash into a `crashed` record.
  /// Inputs: None. Returns: The marker, or null after a clean exit.
  /// Side effects: Records `crashed` under the marker's fingerprint key and
  /// removes the marker.
  /// Notes: Call once at startup before any native work.
  Future<InFlightMarker?> recoverFromCrash() async {
    InFlightMarker? found;
    final current = await read();
    if (current.state.inFlight == null) return null;
    await update((state) {
      final marker = state.inFlight;
      if (marker == null) return state;
      found = marker;
      return state.copyWith(
        clearInFlight: true,
        selfTests: {
          ...state.selfTests,
          marker.fingerprintKey: SelfTestRecord(
            routeKey: marker.routeKey,
            outcome: SelfTestOutcome.crashed,
            checkedAt: _clock().toUtc(),
            reason:
                'The app stopped while this route was running '
                '(started ${marker.startedAt.toIso8601String()}).',
          ),
        },
      );
    });
    return found;
  }

  /// Purpose: Move an unreadable file aside.
  /// Inputs: [file]. Returns: The new path.
  /// Side effects: Renames the file.
  /// Notes: Same naming as MyTranscribe's `setAsideUnreadable`: no colons,
  /// microseconds included.
  Future<String> _setAside(File file) async {
    final stamp = _clock()
        .toUtc()
        .toIso8601String()
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceAll('.', '');
    var target = '${file.path}.unreadable-$stamp';
    var n = 1;
    while (await File(target).exists()) {
      target = '${file.path}.unreadable-$stamp-${n++}';
    }
    await file.rename(target);
    return target;
  }

  /// Purpose: Replace [file] atomically.
  /// Inputs: [file], [content]. Returns: None.
  /// Side effects: Writes a flushed temporary file, then renames it.
  /// Notes: A crash mid-write leaves the previous file intact.
  static Future<void> _atomicWrite(File file, String content) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }
}
