import 'dart:async';
import 'dart:isolate';

import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'route.dart';

/// Runs native calls with a device-local in-flight marker around them.
///
/// Dart isolates do not contain native crashes; the marker is how the next
/// launch learns the process died inside a route, so that route is marked
/// `crashed` and never chosen automatically again under its fingerprint.
class AsrCrashGuard {
  /// Purpose: Create a guard.
  /// Inputs: [state] store. Returns: A guard. Side effects: None.
  /// Notes: None.
  const AsrCrashGuard(this.state);

  /// Purpose: Device-local state store.
  /// Inputs: None. Returns: [LocalEngineStateStore]. Side effects: None.
  /// Notes: None.
  final LocalEngineStateStore state;

  /// Purpose: Run [call] with the marker set.
  /// Inputs: [route], optional [jobId], [call].
  /// Returns: What [call] returns.
  /// Side effects: Writes the marker before and clears it after, on success,
  /// failure and cancel alike.
  /// Notes: Wrap prepare and every transcribe window.
  Future<T> run<T>(
    AsrRoute route,
    Future<T> Function() call, {
    String? jobId,
  }) async {
    await state.markInFlight(
      routeKey: route.key,
      fingerprint: route.fingerprint,
      jobId: jobId,
    );
    try {
      return await call();
    } finally {
      await state.clearInFlight();
    }
  }

  /// Purpose: Turn a marker left by a crash into a `crashed` record.
  /// Inputs: None. Returns: The marker found, or null after a clean exit.
  /// Side effects: See [LocalEngineStateStore.recoverFromCrash].
  /// Notes: Call once at startup before any native work.
  Future<InFlightMarker?> recover() => state.recoverFromCrash();
}

/// A failure answered by a [NativeWorker] handler.
class NativeWorkerFailure {
  /// Purpose: Create a failure.
  /// Inputs: [message]. Returns: A new value. Side effects: None.
  /// Notes: Sent across the isolate boundary; keep it a plain string.
  const NativeWorkerFailure(this.message);

  /// Purpose: What went wrong.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String message;

  /// Purpose: Render for a log.
  /// Inputs: None. Returns: [message]. Side effects: None. Notes: None.
  @override
  String toString() => message;
}

/// Handles one request on a worker isolate.
///
/// Must be a top-level or static function. Its isolate's static fields hold
/// the native handles it owns.
typedef NativeWorkerHandler = FutureOr<Object?> Function(Object? request);

/// A long-lived isolate that owns native handles and runs blocking calls one
/// at a time.
///
/// Every request is answered with a value; a thrown error becomes a
/// [NativeWorkerFailure], so no exception crosses the isolate boundary.
/// Requests are serialised so a release never reaches a model still in use.
class NativeWorker {
  NativeWorker._(this._isolate, this._send, this._receive) {
    _receive.listen((message) {
      final (id, result) = message as (int, Object?);
      _pending.remove(id)?.complete(result);
    });
  }

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;

  /// Purpose: Start a worker.
  /// Inputs: [handler], [debugName].
  /// Returns: A connected worker.
  /// Side effects: Spawns an isolate.
  /// Notes: None.
  static Future<NativeWorker> spawn(
    NativeWorkerHandler handler, {
    String debugName = 'asr-worker',
  }) async {
    final handshake = ReceivePort();
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      handshake.sendPort,
      replies.sendPort,
      handler,
    ), debugName: debugName);
    final send = await handshake.first as SendPort;
    return NativeWorker._(isolate, send, replies);
  }

  /// Purpose: Send a request and wait for its answer.
  /// Inputs: [request], a sendable value.
  /// Returns: The handler's answer, or a [NativeWorkerFailure].
  /// Side effects: The handler's.
  /// Notes: Answers arrive in request order.
  Future<Object?> call(Object? request) {
    final id = _next++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send.send((id, request));
    return completer.future;
  }

  /// Purpose: Kill the worker.
  /// Inputs: None. Returns: None.
  /// Side effects: Kills the isolate; pending calls never complete.
  /// Notes: Release native handles through [call] first.
  void close() {
    _isolate.kill();
    _receive.close();
  }

  /// Purpose: Worker isolate entry point.
  /// Inputs: Handshake port, reply port, handler.
  /// Returns: None. Side effects: Serves requests until killed.
  /// Notes: Internal.
  static void _main((SendPort, SendPort, NativeWorkerHandler) args) {
    final (handshake, replies, handler) = args;
    final requests = ReceivePort();
    handshake.send(requests.sendPort);
    var queue = Future<void>.value();
    requests.listen((message) {
      queue = queue.then((_) async {
        final (id, request) = message as (int, Object?);
        Object? answer;
        try {
          answer = await handler(request);
        } catch (error) {
          answer = NativeWorkerFailure('$error');
        }
        replies.send((id, answer));
      });
    });
  }
}
