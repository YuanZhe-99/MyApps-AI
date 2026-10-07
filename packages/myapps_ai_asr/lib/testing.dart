/// Test doubles for ASR consumers: a scripted engine that runs no model and a
/// route builder. Import from tests only.
library;

import 'dart:async';

import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'myapps_ai_asr.dart';

/// What one window of the fake returns.
class FakeAsrWindow {
  /// Purpose: Segments emitted. Inputs: None. Returns: List.
  /// Side effects: None. Notes: None.
  final List<AsrSegment> segments;

  /// Purpose: Error to end with instead of completing.
  /// Inputs: None. Returns: Exception or null. Side effects: None.
  /// Notes: None.
  final AsrException? error;

  /// Purpose: How long it takes; a cancel cuts it short.
  /// Inputs: None. Returns: Duration. Side effects: None. Notes: None.
  final Duration delay;

  /// Purpose: Placement it reports.
  /// Inputs: None. Returns: Placement or null for the route's device.
  /// Side effects: None. Notes: None.
  final PlacementKind? placement;

  /// Purpose: Create a scripted window.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const FakeAsrWindow({
    this.segments = const [],
    this.error,
    this.delay = Duration.zero,
    this.placement,
  });

  /// Purpose: A window saying [text] over its first five seconds.
  /// Inputs: [text], optional [placement]. Returns: A window.
  /// Side effects: None. Notes: None.
  factory FakeAsrWindow.text(String text, {PlacementKind? placement}) =>
      FakeAsrWindow(
        segments: [AsrSegment(startSeconds: 0, endSeconds: 5, text: text)],
        placement: placement,
      );
}

/// Purpose: Build a route for tests.
/// Inputs: Identity fields and the rest.
/// Returns: An [AsrRoute] whose fingerprint is unique per route key.
/// Side effects: None. Notes: None.
AsrRoute fakeAsrRoute({
  required String adapterId,
  required String modelId,
  required String artifactId,
  ComputeDevice device = ComputeDevice.cpu,
  String? backend,
  EvidenceLevel evidence = EvidenceLevel.official,
  bool testedHere = false,
  bool available = true,
  RouteHealth health = RouteHealth.notRun,
  AsrCapability segmentTimestamps = AsrCapability.supported,
  bool modelIndependent = false,
}) {
  final name = backend ?? device.name;
  return AsrRoute(
    adapterId: adapterId,
    modelId: modelId,
    artifactId: artifactId,
    device: device,
    backend: name,
    evidence: evidence,
    testedHere: testedHere,
    available: available,
    health: health,
    modelIndependent: modelIndependent,
    capabilities: AsrCapabilities(segmentTimestamps: segmentTimestamps),
    fingerprint: HealthFingerprint(
      runtimeVersion: 'fake',
      modelHash: artifactId,
      osVersion: '',
      driverVersion: '',
      deviceId: name,
      precision: '',
    ),
  );
}

/// A scripted engine.
class FakeAsrEngine implements AsrEngine {
  /// Purpose: Create a fake engine.
  /// Inputs: [adapterId], [routes] it offers when installed, [script] of
  /// windows by route key and call number.
  /// Returns: A new engine. Side effects: None. Notes: None.
  FakeAsrEngine({
    required this.adapterId,
    required this.routes,
    FakeAsrWindow Function(String routeKey, int call)? script,
  }) : script = script ?? ((_, call) => FakeAsrWindow.text('window $call'));

  @override
  final String adapterId;

  /// Purpose: Offered routes. Inputs: None. Returns: List.
  /// Side effects: None. Notes: None.
  final List<AsrRoute> routes;

  /// Purpose: What each window returns. Inputs: None. Returns: Function.
  /// Side effects: None. Notes: Mutable for tests.
  FakeAsrWindow Function(String routeKey, int call) script;

  /// Purpose: Errors thrown from prepare, by route key.
  /// Inputs: None. Returns: Map. Side effects: None. Notes: None.
  final Map<String, AsrException> prepareError = {};

  /// Purpose: Route keys prepared, in order.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> prepared = [];

  /// Purpose: Session ids released, in order.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> released = [];

  /// Purpose: Route key of every window run.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> windows = [];

  /// Purpose: Job ids cancelled.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> cancelled = [];

  final _sessions = <String, AsrRoute>{};
  final _running = <String, Completer<void>>{};
  final _finished = <String, Completer<void>>{};

  @override
  Future<List<AsrRoute>> probe(List<ArtifactManifest> manifests) async {
    final installed = {for (final m in manifests) m.artifactId};
    return [
      for (final route in routes)
        if (installed.contains(route.artifactId)) route,
    ];
  }

  @override
  Future<AsrSession> prepare(AsrPrepareRequest request) async {
    final error = prepareError[request.route.key];
    if (error != null) throw error;
    prepared.add(request.route.key);
    final id = 'session-${prepared.length}';
    _sessions[id] = request.route;
    return AsrSession(
      sessionId: id,
      artifactRevision: request.manifest.revision,
      requestedDevice: request.route.device,
      placement: request.route.isCpu ? PlacementKind.cpu : PlacementKind.gpu,
    );
  }

  @override
  Stream<AsrEvent> transcribe(AsrRequest request) async* {
    final route = _sessions[request.sessionId]!;
    windows.add(route.key);
    final window = script(route.key, windows.length - 1);
    final event = asrEventSequence(request.jobId);
    final stop = Completer<void>();
    final done = Completer<void>();
    _running[request.jobId] = stop;
    _finished[request.jobId] = done;
    try {
      yield event(AsrEventType.started);
      if (window.delay > Duration.zero) {
        await Future.any([Future<void>.delayed(window.delay), stop.future]);
      }
      if (stop.isCompleted) {
        yield event(AsrEventType.cancelled);
        return;
      }
      for (final segment in window.segments) {
        yield event(AsrEventType.segment, segment: segment);
      }
      if (window.error != null) {
        yield event(AsrEventType.error, error: window.error);
      } else {
        yield event(
          AsrEventType.completed,
          hasRealTimestamps: true,
          placement:
              window.placement ??
              (route.isCpu ? PlacementKind.cpu : PlacementKind.gpu),
        );
      }
    } finally {
      _running.remove(request.jobId);
      _finished.remove(request.jobId);
      done.complete();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    final stop = _running[jobId];
    final done = _finished[jobId];
    if (stop != null && !stop.isCompleted) stop.complete();
    if (done != null) await done.future;
  }

  @override
  Future<void> release(String sessionId) async {
    released.add(sessionId);
    _sessions.remove(sessionId);
  }
}
