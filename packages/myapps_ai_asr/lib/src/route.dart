import 'package:flutter/foundation.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'capability.dart';

/// Which route the caller asked a job to use: Auto, the CPU, or one route.
///
/// Persisted as `auto`, `cpu` or a route key, as MyTranscribe does.
@immutable
class RouteRequest {
  /// Purpose: The persisted value.
  /// Inputs: None. Returns: `auto`, `cpu` or an [AsrRoute.key].
  /// Side effects: None. Notes: None.
  final String value;

  /// Purpose: Create a request from its persisted value.
  /// Inputs: [value]. Returns: A new value. Side effects: None.
  /// Notes: Empty reads as Auto.
  const RouteRequest(String value) : value = value == '' ? 'auto' : value;

  /// Let the router choose.
  static const auto = RouteRequest('auto');

  /// The CPU route.
  static const cpu = RouteRequest('cpu');

  /// Purpose: Ask for one named route.
  /// Inputs: [routeKey]. Returns: A request. Side effects: None. Notes: None.
  factory RouteRequest.route(String routeKey) => RouteRequest(routeKey);

  /// Purpose: Whether this is Auto.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isAuto => value == 'auto';

  /// Purpose: Whether this is the CPU.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isCpu => value == 'cpu';

  /// Purpose: The named route's key.
  /// Inputs: None. Returns: Key, or null for Auto and the CPU.
  /// Side effects: None. Notes: None.
  String? get routeKey => isAuto || isCpu ? null : value;

  /// Purpose: Compare by value.
  /// Inputs: [other]. Returns: bool. Side effects: None. Notes: None.
  @override
  bool operator ==(Object other) =>
      other is RouteRequest && other.value == value;

  /// Purpose: Hash by value.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  @override
  int get hashCode => value.hashCode;

  /// Purpose: Render the persisted value.
  /// Inputs: None. Returns: [value]. Side effects: None. Notes: None.
  @override
  String toString() => value;
}

/// A route's latest self-test on this device, as routing needs it.
@immutable
class RouteHealth {
  /// Purpose: What the check found.
  /// Inputs: None. Returns: [SelfTestOutcome]. Side effects: None.
  /// Notes: None.
  final SelfTestOutcome outcome;

  /// Purpose: Seconds of work per second of audio in the check.
  /// Inputs: None. Returns: double or null when it did not finish.
  /// Side effects: None. Notes: Lower is faster.
  final double? realTimeFactor;

  /// Purpose: Why it failed, when it did.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? reason;

  /// Purpose: Create a summary.
  /// Inputs: [outcome], optional [realTimeFactor], [reason].
  /// Returns: A new value. Side effects: None. Notes: None.
  const RouteHealth(this.outcome, {this.realTimeFactor, this.reason});

  /// A route not checked under its current fingerprint.
  static const notRun = RouteHealth(SelfTestOutcome.notRun);

  /// Purpose: Summarise a stored self-test record.
  /// Inputs: [record], or null for none.
  /// Returns: The summary; [notRun] for null.
  /// Side effects: None.
  /// Notes: Reads the `realTimeFactor` metric the ASR fixture writes.
  factory RouteHealth.fromRecord(SelfTestRecord? record) => record == null
      ? notRun
      : RouteHealth(
          record.outcome,
          realTimeFactor: record.metric(asrRealTimeFactorMetric),
          reason: record.reason,
        );
}

/// The [SelfTestRecord.extraJson] key the ASR fixture stores its speed under.
///
/// Same key MyTranscribe writes, so existing records keep their speed.
const asrRealTimeFactorMetric = 'realTimeFactor';

/// One way this device could run one artifact: adapter, backend, processor.
@immutable
class AsrRoute {
  /// Purpose: Adapter id, e.g. `whisper_cpp`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String adapterId;

  /// Purpose: Logical model the route serves.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Routing never moves a job to another model's routes.
  final String modelId;

  /// Purpose: Installed artifact it would load.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String artifactId;

  /// Purpose: Processor kind.
  /// Inputs: None. Returns: [ComputeDevice]. Side effects: None. Notes: None.
  final ComputeDevice device;

  /// Purpose: Backend name inside the adapter (`cpu`, `metal`, `vulkan`...).
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Keeps two GPU routes apart; part of [key].
  final String backend;

  /// Purpose: Documented evidence for this kind of device.
  /// Inputs: None. Returns: [EvidenceLevel]. Side effects: None. Notes: None.
  final EvidenceLevel evidence;

  /// Purpose: Whether the consuming project verified this route on this
  /// device class.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: Supplied by the application's [TestedRouteTable]; never guessed.
  final bool testedHere;

  /// Purpose: This device's self-test result under [fingerprint].
  /// Inputs: None. Returns: [RouteHealth]. Side effects: None.
  /// Notes: Attached by the registry, not by adapters.
  final RouteHealth health;

  /// Purpose: What the self-test result is filed under.
  /// Inputs: None. Returns: [HealthFingerprint]. Side effects: None.
  /// Notes: Encodes byte-identically to MyTranscribe's `smokeKey`.
  final HealthFingerprint fingerprint;

  /// Purpose: Whether the backend is built and its driver answers.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool available;

  /// Purpose: Why not, when [available] is false.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? unavailableReason;

  /// Purpose: What the route can do.
  /// Inputs: None. Returns: [AsrCapabilities]. Side effects: None.
  /// Notes: None.
  final AsrCapabilities capabilities;

  /// Purpose: Longest window, in seconds.
  /// Inputs: None. Returns: int or null for no limit of its own.
  /// Side effects: None. Notes: None.
  final int? maxWindowSeconds;

  /// Purpose: Memory a loaded session needs.
  /// Inputs: None. Returns: Bytes or null. Side effects: None. Notes: None.
  final int? memoryBytes;

  /// Purpose: Where [memoryBytes] came from.
  /// Inputs: None. Returns: [EstimateSource]. Side effects: None.
  /// Notes: None.
  final EstimateSource memorySource;

  /// Purpose: Whether the route serves no particular model (a system
  /// recogniser).
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: Such routes are only reachable through an explicit fallback
  /// target the application's policy names.
  final bool modelIndependent;

  /// Purpose: Create a route.
  /// Inputs: All fields; identity fields and [fingerprint] required.
  /// Returns: A new value. Side effects: None.
  /// Notes: Capabilities default to unknown.
  const AsrRoute({
    required this.adapterId,
    required this.modelId,
    required this.artifactId,
    required this.device,
    required this.backend,
    required this.evidence,
    required this.fingerprint,
    this.testedHere = false,
    this.health = RouteHealth.notRun,
    this.available = true,
    this.unavailableReason,
    this.capabilities = const AsrCapabilities(),
    this.maxWindowSeconds,
    this.memoryBytes,
    this.memorySource = EstimateSource.unknown,
    this.modelIndependent = false,
  });

  /// Purpose: Identify the route on this device.
  /// Inputs: None. Returns: `adapterId:artifactId:backend`.
  /// Side effects: None.
  /// Notes: Same spelling as MyTranscribe so stored choices keep matching.
  String get key => '$adapterId:$artifactId:$backend';

  /// Purpose: Whether this is a CPU route.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isCpu => device == ComputeDevice.cpu;

  /// Purpose: Return a copy with some fields replaced.
  /// Inputs: [health], [testedHere]. Returns: A new route.
  /// Side effects: None.
  /// Notes: The registry attaches health; the tested-route table sets
  /// [testedHere].
  AsrRoute copyWith({RouteHealth? health, bool? testedHere}) => AsrRoute(
    adapterId: adapterId,
    modelId: modelId,
    artifactId: artifactId,
    device: device,
    backend: backend,
    evidence: evidence,
    fingerprint: fingerprint,
    testedHere: testedHere ?? this.testedHere,
    health: health ?? this.health,
    available: available,
    unavailableReason: unavailableReason,
    capabilities: capabilities,
    maxWindowSeconds: maxWindowSeconds,
    memoryBytes: memoryBytes,
    memorySource: memorySource,
    modelIndependent: modelIndependent,
  );

  /// Purpose: Render for diagnostics.
  /// Inputs: None. Returns: [key]. Side effects: None. Notes: None.
  @override
  String toString() => key;
}

/// One route the consuming project verified on real hardware.
typedef TestedRoute = ({String deviceClass, String adapterId, String backend});

/// The application-owned table of verified routes, and this device's class.
///
/// The shared package ships no rows: verification records belong to the
/// project that did the testing.
class TestedRouteTable {
  /// Purpose: Create a table.
  /// Inputs: [rows], this device's [deviceClass].
  /// Returns: A new table. Side effects: None. Notes: None.
  const TestedRouteTable({this.rows = const [], this.deviceClass = ''});

  /// Purpose: Verified routes.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<TestedRoute> rows;

  /// Purpose: This device's class, e.g. `windows-arm64-qualcomm`.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Computed by the application's platform layer.
  final String deviceClass;

  /// Purpose: Report whether [route] was verified on this device class.
  /// Inputs: [route]. Returns: bool. Side effects: None. Notes: None.
  bool covers(AsrRoute route) => rows.any(
    (row) =>
        row.deviceClass == deviceClass &&
        row.adapterId == route.adapterId &&
        row.backend == route.backend,
  );

  /// Purpose: Mark [route] tested when the table covers it.
  /// Inputs: [route]. Returns: The route, flagged when covered.
  /// Side effects: None. Notes: Adapters call this from probe.
  AsrRoute apply(AsrRoute route) =>
      covers(route) ? route.copyWith(testedHere: true) : route;
}
