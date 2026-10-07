import 'package:flutter/foundation.dart';

/// What a route's self-test on this device found.
///
/// Wire names match MyTranscribe's `SmokeTestOutcome`.
enum SelfTestOutcome {
  /// Not checked under the current fingerprint.
  notRun,

  /// The fixture's evaluation passed.
  passed,

  /// Ran, and produced a wrong result or an error.
  failed,

  /// The process died inside the route; found by the in-flight marker at the
  /// next start. Never chosen automatically again under this fingerprint.
  crashed;

  /// Purpose: Parse a persisted outcome.
  /// Inputs: [value]. Returns: The outcome; unrecognised reads as [notRun].
  /// Side effects: None.
  /// Notes: An unreadable outcome asks for a new check.
  static SelfTestOutcome parse(Object? value) {
    for (final outcome in SelfTestOutcome.values) {
      if (outcome.name == value) return outcome;
    }
    return notRun;
  }

  /// Purpose: Report whether a route with this outcome may run work at all.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: `notRun` allows use only after a check, by caller policy.
  bool get allowsUse => this == passed || this == notRun;
}

/// What a self-test result is filed under.
///
/// Any part changing asks for a new check: a new runtime build, a different
/// model file, an OS or driver update, another processor, another precision.
@immutable
class HealthFingerprint {
  /// Purpose: Runtime (adapter) id and native library version.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String runtimeVersion;

  /// Purpose: SHA-256 of the model file the route loads.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String modelHash;

  /// Purpose: Operating-system version.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String osVersion;

  /// Purpose: GPU/NPU driver version; empty for the CPU.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String driverVersion;

  /// Purpose: Processor the route drives, as the runtime names it.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String deviceId;

  /// Purpose: Precision the route runs at, e.g. `f16`, `q4_k_m`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String precision;

  /// Purpose: Create a fingerprint.
  /// Inputs: All six parts. Returns: A new immutable value.
  /// Side effects: None. Notes: Same parts as MyTranscribe's `SmokeTestKey`.
  const HealthFingerprint({
    required this.runtimeVersion,
    required this.modelHash,
    required this.osVersion,
    required this.driverVersion,
    required this.deviceId,
    required this.precision,
  });

  /// Purpose: Render the key results are filed under.
  /// Inputs: None. Returns: The six parts joined with `|` (`|` inside a part
  /// becomes `/`).
  /// Side effects: None.
  /// Notes: Byte-identical to `SmokeTestKey.encode()`, so existing records
  /// keep matching.
  String encode() => [
    runtimeVersion,
    modelHash,
    osVersion,
    driverVersion,
    deviceId,
    precision,
  ].map((part) => part.replaceAll('|', '/')).join('|');

  /// Purpose: Compare by value.
  /// Inputs: [other]. Returns: bool. Side effects: None. Notes: None.
  @override
  bool operator ==(Object other) =>
      other is HealthFingerprint && other.encode() == encode();

  /// Purpose: Hash by value.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  @override
  int get hashCode => encode().hashCode;

  /// Purpose: Render for diagnostics.
  /// Inputs: None. Returns: [encode]. Side effects: None. Notes: None.
  @override
  String toString() => encode();
}

const _recordKeys = {
  'routeKey',
  'outcome',
  'checkedAt',
  'text',
  'similarity',
  'reason',
};

/// One self-test of one route on this device.
@immutable
class SelfTestRecord {
  /// Purpose: Route checked.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String routeKey;

  /// Purpose: What the check found.
  /// Inputs: None. Returns: [SelfTestOutcome]. Side effects: None. Notes: None.
  final SelfTestOutcome outcome;

  /// Purpose: When it was checked, UTC.
  /// Inputs: None. Returns: DateTime. Side effects: None. Notes: None.
  final DateTime checkedAt;

  /// Purpose: Output the route produced, when diagnostic-safe.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Persisted as `text`. Fixture output only — never user content.
  final String? output;

  /// Purpose: Evaluation score 0..1, when the evaluator gives one.
  /// Inputs: None. Returns: double or null. Side effects: None.
  /// Notes: Persisted as `similarity` for compatibility.
  final double? score;

  /// Purpose: Why it failed, in words.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? reason;

  /// Purpose: Capability-specific fields (e.g. `realTimeFactor`,
  /// `tokensPerSecond`) and fields from newer builds.
  /// Inputs: None. Returns: Map. Side effects: None.
  /// Notes: Written back verbatim at the record's top level.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create a record.
  /// Inputs: All fields; [routeKey], [outcome], [checkedAt] required.
  /// Returns: A new immutable value. Side effects: None. Notes: None.
  const SelfTestRecord({
    required this.routeKey,
    required this.outcome,
    required this.checkedAt,
    this.output,
    this.score,
    this.reason,
    this.extraJson = const {},
  });

  /// Purpose: Read a numeric capability metric.
  /// Inputs: [key]. Returns: double or null. Side effects: None.
  /// Notes: ASR stores `realTimeFactor` here.
  double? metric(String key) => (extraJson[key] as num?)?.toDouble();

  /// Purpose: Parse a record.
  /// Inputs: [json]. Returns: [SelfTestRecord]. Side effects: None.
  /// Notes: An unreadable time falls back to the epoch, never to now.
  factory SelfTestRecord.fromJson(Map<String, dynamic> json) => SelfTestRecord(
    routeKey: json['routeKey'] as String? ?? '',
    outcome: SelfTestOutcome.parse(json['outcome']),
    checkedAt:
        DateTime.tryParse('${json['checkedAt']}')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    output: json['text'] as String?,
    score: (json['similarity'] as num?)?.toDouble(),
    reason: json['reason'] as String?,
    extraJson: {
      for (final e in json.entries)
        if (!_recordKeys.contains(e.key)) e.key: e.value,
    },
  );

  /// Purpose: Serialize a record.
  /// Inputs: None. Returns: JSON map. Side effects: None. Notes: None.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'routeKey': routeKey,
    'outcome': outcome.name,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    if (output != null) 'text': output,
    if (score != null) 'similarity': score,
    if (reason != null) 'reason': reason,
  };
}

/// A native call in progress, written before it starts and cleared after.
@immutable
class InFlightMarker {
  /// Purpose: Route the call runs on.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String routeKey;

  /// Purpose: Encoded [HealthFingerprint] its result is filed under.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Persisted as `smokeKey`.
  final String fingerprintKey;

  /// Purpose: Job the call was for, or null for a self-test.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? jobId;

  /// Purpose: When the call started, UTC.
  /// Inputs: None. Returns: DateTime. Side effects: None. Notes: None.
  final DateTime startedAt;

  /// Purpose: Create a marker.
  /// Inputs: All fields. Returns: A new immutable value.
  /// Side effects: None. Notes: None.
  const InFlightMarker({
    required this.routeKey,
    required this.fingerprintKey,
    required this.startedAt,
    this.jobId,
  });

  /// Purpose: Parse a marker.
  /// Inputs: [json]. Returns: [InFlightMarker]. Side effects: None.
  /// Notes: None.
  factory InFlightMarker.fromJson(Map<String, dynamic> json) => InFlightMarker(
    routeKey: json['routeKey'] as String? ?? '',
    fingerprintKey: json['smokeKey'] as String? ?? '',
    jobId: json['jobId'] as String?,
    startedAt:
        DateTime.tryParse('${json['startedAt']}')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// Purpose: Serialize a marker.
  /// Inputs: None. Returns: JSON map. Side effects: None. Notes: None.
  Map<String, dynamic> toJson() => {
    'routeKey': routeKey,
    'smokeKey': fingerprintKey,
    if (jobId != null) 'jobId': jobId,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
}

const _stateKeys = {'smokeTests', 'inFlight'};

/// The device-local engine state document (`local_engine_state.json`).
///
/// Never synced or backed up. Only self-test records and the in-flight
/// marker are typed here; application or capability fields (MyTranscribe's
/// `routeChoices`, `fallbackPolicy`, `allowServerSpeechRecognition`) are kept
/// in [extraJson] and written back unchanged.
@immutable
class LocalEngineState {
  /// Purpose: Self-test records by encoded fingerprint.
  /// Inputs: None. Returns: Map. Side effects: None.
  /// Notes: Persisted as `smokeTests`.
  final Map<String, SelfTestRecord> selfTests;

  /// Purpose: Native call running when the app last stopped, if any.
  /// Inputs: None. Returns: Marker or null. Side effects: None. Notes: None.
  final InFlightMarker? inFlight;

  /// Purpose: Every other top-level field.
  /// Inputs: None. Returns: Map. Side effects: None. Notes: None.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create a state document.
  /// Inputs: All fields. Returns: A new immutable value.
  /// Side effects: None. Notes: Defaults are a device that never ran anything.
  const LocalEngineState({
    this.selfTests = const {},
    this.inFlight,
    this.extraJson = const {},
  });

  /// Purpose: Find the record for [fingerprint].
  /// Inputs: [fingerprint]. Returns: The record, or null.
  /// Side effects: None.
  /// Notes: Only an exact fingerprint match is reused; a changed driver,
  /// model or runtime finds nothing and needs a new check.
  SelfTestRecord? selfTestFor(HealthFingerprint fingerprint) =>
      selfTests[fingerprint.encode()];

  /// Purpose: Outcome for [fingerprint].
  /// Inputs: [fingerprint]. Returns: Outcome; [SelfTestOutcome.notRun] when
  /// no record matches. Side effects: None. Notes: None.
  SelfTestOutcome outcomeFor(HealthFingerprint fingerprint) =>
      selfTestFor(fingerprint)?.outcome ?? SelfTestOutcome.notRun;

  /// Purpose: Records for [routeKey] filed under another fingerprint.
  /// Inputs: [routeKey], [current]. Returns: Encoded keys of stale records.
  /// Side effects: None. Notes: Use for diagnostics or pruning.
  List<String> staleFor(String routeKey, HealthFingerprint current) => [
    for (final e in selfTests.entries)
      if (e.value.routeKey == routeKey && e.key != current.encode()) e.key,
  ];

  /// Purpose: Return a copy with some fields replaced.
  /// Inputs: Fields, [clearInFlight]. Returns: A new state.
  /// Side effects: None. Notes: [extraJson] carries over unless replaced.
  LocalEngineState copyWith({
    Map<String, SelfTestRecord>? selfTests,
    InFlightMarker? inFlight,
    bool clearInFlight = false,
    Map<String, dynamic>? extraJson,
  }) => LocalEngineState(
    selfTests: selfTests ?? this.selfTests,
    inFlight: clearInFlight ? null : (inFlight ?? this.inFlight),
    extraJson: extraJson ?? this.extraJson,
  );

  /// Purpose: Parse the state document.
  /// Inputs: [json]. Returns: [LocalEngineState]. Side effects: None.
  /// Notes: An unreadable entry is dropped, which at worst asks for a check.
  factory LocalEngineState.fromJson(Map<String, dynamic> json) {
    final tests = json['smokeTests'];
    final inFlight = json['inFlight'];
    return LocalEngineState(
      selfTests: {
        if (tests is Map<String, dynamic>)
          for (final e in tests.entries)
            if (e.value is Map<String, dynamic>)
              e.key: SelfTestRecord.fromJson(e.value as Map<String, dynamic>),
      },
      inFlight: inFlight is Map<String, dynamic>
          ? InFlightMarker.fromJson(inFlight)
          : null,
      extraJson: {
        for (final e in json.entries)
          if (!_stateKeys.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// Purpose: Serialize the state document.
  /// Inputs: None. Returns: JSON map. Side effects: None.
  /// Notes: Self-test keys are sorted so an unchanged state writes the same
  /// bytes. Extra fields are written first; known keys win collisions.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'smokeTests': {
      for (final key in (selfTests.keys.toList()..sort()))
        key: selfTests[key]!.toJson(),
    },
    if (inFlight != null) 'inFlight': inFlight!.toJson(),
  };
}
