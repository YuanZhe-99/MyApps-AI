import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine_state.dart';
import 'engine_state_store.dart';

/// What a capability's evaluation decided about one self-test run.
@immutable
class SelfTestEvaluation {
  /// Purpose: Whether the run passed.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool passed;

  /// Purpose: Score 0..1, when the evaluator gives one.
  /// Inputs: None. Returns: double or null. Side effects: None. Notes: None.
  final double? score;

  /// Purpose: Fixture output to keep for diagnostics.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Fixture content only; never user data.
  final String? output;

  /// Purpose: Why it failed, in words.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? reason;

  /// Purpose: Capability metrics such as `realTimeFactor` or
  /// `tokensPerSecond`.
  /// Inputs: None. Returns: Map. Side effects: None.
  /// Notes: Stored in [SelfTestRecord.extraJson].
  final Map<String, Object> metrics;

  /// Purpose: Create an evaluation.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const SelfTestEvaluation({
    required this.passed,
    this.score,
    this.output,
    this.reason,
    this.metrics = const {},
  });
}

/// A capability-supplied self-test: one fixture, how to run it, how to judge.
///
/// ASR supplies a clip and word-error evaluation; LLM supplies a prompt and
/// its own checks. The runner owns the crash marker, error capture and
/// persistence.
abstract class SelfTestFixture<R> {
  /// Purpose: Route being checked.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Stable across launches.
  String get routeKey;

  /// Purpose: Fingerprint the result is filed under.
  /// Inputs: None. Returns: [HealthFingerprint]. Side effects: None.
  /// Notes: None.
  HealthFingerprint get fingerprint;

  /// Purpose: Run the fixture through the route.
  /// Inputs: None. Returns: The raw result.
  /// Side effects: Loads and runs the model.
  /// Notes: May throw; the runner records the error as a failure.
  Future<R> run();

  /// Purpose: Judge a raw result.
  /// Inputs: [result], [elapsed] run time.
  /// Returns: [SelfTestEvaluation]. Side effects: None. Notes: None.
  SelfTestEvaluation evaluate(R result, Duration elapsed);

  /// Purpose: Release resources after [run].
  /// Inputs: None. Returns: None. Side effects: Unloads the model.
  /// Notes: Called whether [run] succeeded or not; errors are ignored.
  Future<void> release() async {}
}

/// Runs self-tests with in-flight crash markers and persistence.
class SelfTestRunner {
  /// Purpose: Create a runner.
  /// Inputs: [store], optional [clock] and [stopwatch] factory.
  /// Returns: A new runner. Side effects: None. Notes: None.
  SelfTestRunner({
    required this._store,
    DateTime Function()? clock,
    Stopwatch Function()? stopwatch,
  }) : _clock = clock ?? DateTime.now,
       _stopwatch = stopwatch ?? Stopwatch.new;

  final LocalEngineStateStore _store;
  final DateTime Function() _clock;
  final Stopwatch Function() _stopwatch;

  /// Purpose: Return a reusable record, or run the fixture.
  /// Inputs: [fixture], [force] to rerun even with a matching record.
  /// Returns: The matching or new record.
  /// Side effects: May run the model and write state.
  /// Notes: A record is reused only when its fingerprint matches exactly.
  Future<SelfTestRecord> ensure<R>(
    SelfTestFixture<R> fixture, {
    bool force = false,
  }) async {
    if (!force) {
      final existing = await _store.selfTestFor(fixture.fingerprint);
      if (existing != null) return existing;
    }
    return run(fixture);
  }

  /// Purpose: Run one fixture and record the result.
  /// Inputs: [fixture]. Returns: The record written.
  /// Side effects: Writes the in-flight marker, runs the model, clears the
  /// marker, writes the record.
  /// Notes: Errors become a failed record, never an exception, so a throwing
  /// check does not leave the route unchecked forever.
  Future<SelfTestRecord> run<R>(SelfTestFixture<R> fixture) async {
    final fingerprint = fixture.fingerprint;
    SelfTestRecord record;
    await _store.markInFlight(
      routeKey: fixture.routeKey,
      fingerprint: fingerprint,
    );
    try {
      final watch = _stopwatch()..start();
      final result = await fixture.run();
      watch.stop();
      final verdict = fixture.evaluate(result, watch.elapsed);
      record = SelfTestRecord(
        routeKey: fixture.routeKey,
        outcome: verdict.passed
            ? SelfTestOutcome.passed
            : SelfTestOutcome.failed,
        checkedAt: _clock().toUtc(),
        output: verdict.output,
        score: verdict.score,
        reason: verdict.passed ? null : verdict.reason,
        extraJson: verdict.metrics,
      );
    } catch (error) {
      record = SelfTestRecord(
        routeKey: fixture.routeKey,
        outcome: SelfTestOutcome.failed,
        checkedAt: _clock().toUtc(),
        reason: '$error',
      );
    } finally {
      try {
        await fixture.release();
      } catch (_) {}
      await _store.clearInFlight();
    }
    await _store.recordSelfTest(fingerprint, record);
    return record;
  }
}
