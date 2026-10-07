import 'package:flutter/foundation.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'capability.dart';
import 'errors.dart';
import 'route.dart';

/// The logical model a job asked for, as routing needs it.
///
/// Applications adapt their own model records to this; the shared package
/// knows nothing about how they are stored or templated.
abstract interface class AsrModelDescriptor {
  /// Purpose: Model id (MyTranscribe's are `local:`-prefixed).
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  String get id;

  /// Purpose: Name used in diagnostic sentences.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  String get displayName;

  /// Purpose: Lower-case language codes the model transcribes.
  /// Inputs: None. Returns: List; empty means any. Side effects: None.
  /// Notes: None.
  List<String> get languages;

  /// Purpose: Artifact ids by adapter id.
  /// Inputs: None. Returns: Map. Side effects: None.
  /// Notes: Only these artifacts' routes are ever considered.
  Map<String, List<String>> get artifacts;
}

/// A plain [AsrModelDescriptor].
@immutable
class AsrModel implements AsrModelDescriptor {
  /// Purpose: Create a descriptor.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrModel({
    required this.id,
    required this.displayName,
    this.languages = const [],
    this.artifacts = const {},
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final List<String> languages;

  @override
  final Map<String, List<String>> artifacts;
}

/// Purpose: Collect a model's artifact ids.
/// Inputs: [model]. Returns: The set. Side effects: None. Notes: None.
Set<String> asrModelArtifactIds(AsrModelDescriptor model) => {
  for (final ids in model.artifacts.values) ...ids,
};

/// Purpose: Report whether a job in [requested] languages may use [model].
/// Inputs: [model], [requested] codes.
/// Returns: bool — true when the model lists none or covers every primary
/// subtag. Side effects: None.
/// Notes: `pt-BR` is compared as `pt`.
bool asrModelAcceptsLanguages(
  AsrModelDescriptor model,
  List<String> requested,
) {
  if (model.languages.isEmpty) return true;
  for (final code in requested) {
    final primary = code.toLowerCase().split(RegExp('[-_]')).first;
    if (!model.languages.contains(primary)) return false;
  }
  return true;
}

/// One explicit step the application allows when a route cannot run.
@immutable
sealed class AsrFallbackStep {
  /// Purpose: Base constructor.
  /// Inputs: None. Returns: A step. Side effects: None. Notes: None.
  const AsrFallbackStep();
}

/// Run the same model on its best usable CPU route.
final class SameModelCpuFallback extends AsrFallbackStep {
  /// Purpose: Create the step.
  /// Inputs: None. Returns: The step. Side effects: None. Notes: None.
  const SameModelCpuFallback();
}

/// Use a model-independent route of one named adapter (a system recogniser).
final class ModelIndependentFallback extends AsrFallbackStep {
  /// Purpose: Create the step.
  /// Inputs: [adapterId]. Returns: The step. Side effects: None.
  /// Notes: Only routes with [AsrRoute.modelIndependent] qualify, so this is
  /// a different engine, never another model under the same name.
  const ModelIndependentFallback(this.adapterId);

  /// Purpose: Adapter whose route may be used.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String adapterId;
}

/// What the application allows when the requested route cannot run.
///
/// Steps are tried in order; an empty policy fails the job. The shared
/// package never chooses a policy.
@immutable
class AsrFallbackPolicy {
  /// Purpose: Create a policy.
  /// Inputs: [steps], [name] for diagnostics.
  /// Returns: A new policy. Side effects: None. Notes: None.
  const AsrFallbackPolicy(this.steps, {this.name = ''});

  /// Allow nothing.
  static const none = AsrFallbackPolicy([], name: 'none');

  /// Purpose: Steps in order.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<AsrFallbackStep> steps;

  /// Purpose: Name used in failure sentences.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String name;
}

/// The Auto rule's application-tunable parts.
@immutable
class AsrAutoPolicy {
  /// Purpose: Create an Auto policy.
  /// Inputs: [untestedEvidence], the grades an accelerator not tested here
  /// may have and still be chosen after passing and beating the CPU.
  /// Returns: A new policy. Side effects: None.
  /// Notes: The default is A and B, MyTranscribe's decision D20.
  const AsrAutoPolicy({
    this.untestedEvidence = const {
      EvidenceLevel.official,
      EvidenceLevel.community,
    },
  });

  /// Purpose: Grades allowed for untested accelerators.
  /// Inputs: None. Returns: Set. Side effects: None. Notes: None.
  final Set<EvidenceLevel> untestedEvidence;
}

/// Why a route was not chosen.
enum RouteRejection {
  /// Its artifact is not installed.
  notInstalled,

  /// The backend is missing or its driver does not answer.
  unavailable,

  /// Its self-test on this device failed.
  checkFailed,

  /// The app stopped while it was running.
  crashed,

  /// It lacks the timestamps the job needs.
  lacksTimestamps,

  /// Auto passed it over: untested here with insufficient evidence.
  untestedForAuto,

  /// Auto passed it over: not self-tested on this device yet.
  notChecked,

  /// Auto passed it over: not measurably faster than the CPU.
  notFasterThanCpu,
}

/// Everything routing looks at.
@immutable
class AsrRoutingRequest {
  /// Purpose: Model chosen. Inputs: None. Returns: [AsrModelDescriptor].
  /// Side effects: None. Notes: None.
  final AsrModelDescriptor model;

  /// Purpose: Job's language hints; empty to detect.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<String> languages;

  /// Purpose: Whether the job needs segment times.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool requireSegmentTimestamps;

  /// Purpose: Every route here, with health attached.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<AsrRoute> routes;

  /// Purpose: Installed artifact ids.
  /// Inputs: None. Returns: Set. Side effects: None. Notes: None.
  final Set<String> installedArtifacts;

  /// Purpose: Adapters this build contains.
  /// Inputs: None. Returns: Set. Side effects: None.
  /// Notes: Tells "not downloaded" from "cannot run here".
  final Set<String> builtAdapters;

  /// Purpose: What the caller asked for.
  /// Inputs: None. Returns: [RouteRequest]. Side effects: None. Notes: None.
  final RouteRequest requested;

  /// Purpose: What the application allows instead.
  /// Inputs: None. Returns: [AsrFallbackPolicy]. Side effects: None.
  /// Notes: None.
  final AsrFallbackPolicy fallback;

  /// Purpose: Auto rule tuning.
  /// Inputs: None. Returns: [AsrAutoPolicy]. Side effects: None. Notes: None.
  final AsrAutoPolicy auto;

  /// Purpose: Create a routing request.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: [fallback] has no default: the application must decide.
  const AsrRoutingRequest({
    required this.model,
    required this.routes,
    required this.installedArtifacts,
    required this.fallback,
    this.builtAdapters = const {},
    this.languages = const [],
    this.requireSegmentTimestamps = false,
    this.requested = RouteRequest.auto,
    this.auto = const AsrAutoPolicy(),
  });
}

/// A visible move away from the route asked for, within policy.
@immutable
class AsrFallbackDecision {
  /// Purpose: What was asked for: a route key, `auto` or `cpu`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String from;

  /// Purpose: Route taken instead.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String toRouteKey;

  /// Purpose: Why.
  /// Inputs: None. Returns: [AsrErrorCode]. Side effects: None. Notes: None.
  final AsrErrorCode reason;

  /// Purpose: The policy step that allowed it.
  /// Inputs: None. Returns: [AsrFallbackStep]. Side effects: None.
  /// Notes: Applications record it on the job.
  final AsrFallbackStep step;

  /// Purpose: Create a fallback decision.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const AsrFallbackDecision({
    required this.from,
    required this.toRouteKey,
    required this.reason,
    required this.step,
  });
}

/// What routing decided.
@immutable
class AsrRouteDecision {
  /// Purpose: Route to run on, or null when none can.
  /// Inputs: None. Returns: [AsrRoute] or null. Side effects: None.
  /// Notes: None.
  final AsrRoute? route;

  /// Purpose: Whether the route must pass its self-test first.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool needsSelfTest;

  /// Purpose: The fallback taken, when there was one.
  /// Inputs: None. Returns: Decision or null. Side effects: None.
  /// Notes: None.
  final AsrFallbackDecision? fallback;

  /// Purpose: Why nothing can run, when [route] is null.
  /// Inputs: None. Returns: Code or null. Side effects: None. Notes: None.
  final AsrErrorCode? failure;

  /// Purpose: A sentence explaining [failure].
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Diagnostic English; applications localize from [failure].
  final String? failureDetail;

  /// Purpose: Why each passed-over route of this model was, by key.
  /// Inputs: None. Returns: Map. Side effects: None. Notes: None.
  final Map<String, RouteRejection> rejected;

  const AsrRouteDecision._({
    this.route,
    this.needsSelfTest = false,
    this.fallback,
    this.failure,
    this.failureDetail,
    this.rejected = const {},
  });

  /// Purpose: Decide on a route.
  /// Inputs: [route], optional [fallback], [rejected].
  /// Returns: A running decision. Side effects: None.
  /// Notes: [needsSelfTest] follows the route's health.
  factory AsrRouteDecision.run(
    AsrRoute route, {
    AsrFallbackDecision? fallback,
    Map<String, RouteRejection> rejected = const {},
  }) => AsrRouteDecision._(
    route: route,
    needsSelfTest: route.health.outcome == SelfTestOutcome.notRun,
    fallback: fallback,
    rejected: rejected,
  );

  /// Purpose: Decide that nothing can run.
  /// Inputs: [failure], [detail], optional [rejected].
  /// Returns: A failing decision. Side effects: None. Notes: None.
  const AsrRouteDecision.fail(
    AsrErrorCode failure,
    String detail, {
    Map<String, RouteRejection> rejected = const {},
  }) : this._(failure: failure, failureDetail: detail, rejected: rejected);

  /// Purpose: Whether a route was chosen.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get runs => route != null;
}

/// Generic, pure route selection.
///
/// Three rules hold: only the chosen model's own routes are considered; a
/// fallback happens only through an explicit policy step and is returned as a
/// separate decision; and Auto takes an accelerator only when tested here, or
/// when its evidence is allowed and it passed and beat the CPU here.
class AsrRouter {
  const AsrRouter._();

  /// Purpose: Choose the route for a job before it starts.
  /// Inputs: [request]. Returns: [AsrRouteDecision]. Side effects: None.
  /// Notes: Order: language; own routes; installed; available; health;
  /// timestamps; then CPU, named route, or Auto.
  static AsrRouteDecision choose(AsrRoutingRequest request) {
    final model = request.model;
    if (!asrModelAcceptsLanguages(model, request.languages)) {
      return AsrRouteDecision.fail(
        AsrErrorCode.unsupportedLanguage,
        '${model.displayName} does not transcribe '
        '${request.languages.join(', ')}; it covers '
        '${model.languages.join(', ')}.',
      );
    }
    final rejected = <String, RouteRejection>{};
    final usable = filterUsable(request, rejected);
    final own = ownRoutes(request);
    if (own.isEmpty) {
      final canRun = model.artifacts.keys.any(request.builtAdapters.contains);
      if (canRun &&
          !asrModelArtifactIds(
            model,
          ).any(request.installedArtifacts.contains)) {
        return AsrRouteDecision.fail(
          AsrErrorCode.modelMissing,
          '${model.displayName} is not downloaded on this device.',
          rejected: rejected,
        );
      }
      return AsrRouteDecision.fail(
        AsrErrorCode.backendNotBuilt,
        'This build has no engine for ${model.displayName}.',
        rejected: rejected,
      );
    }
    if (!own.any((r) => request.installedArtifacts.contains(r.artifactId))) {
      return AsrRouteDecision.fail(
        AsrErrorCode.modelMissing,
        '${model.displayName} is not downloaded on this device.',
        rejected: rejected,
      );
    }
    final cpu = bestCpu(usable);

    if (request.requested.isCpu) {
      if (cpu != null) return AsrRouteDecision.run(cpu, rejected: rejected);
      return _fallbackOrFail(
        request,
        from: 'cpu',
        reason: _reasonFor(own.where((r) => r.isCpu), rejected),
        cpu: null,
        rejected: rejected,
      );
    }

    final key = request.requested.routeKey;
    if (key != null) {
      for (final route in usable) {
        if (route.key == key) {
          return AsrRouteDecision.run(route, rejected: rejected);
        }
      }
      return _fallbackOrFail(
        request,
        from: key,
        reason: _reasonFor(own.where((r) => r.key == key), rejected),
        cpu: cpu,
        rejected: rejected,
      );
    }

    final accelerators = <AsrRoute>[];
    for (final route in usable) {
      if (route.isCpu) continue;
      if (route.health.outcome != SelfTestOutcome.passed) {
        rejected[route.key] = RouteRejection.notChecked;
        continue;
      }
      if (route.testedHere) {
        accelerators.add(route);
        continue;
      }
      if (!request.auto.untestedEvidence.contains(route.evidence)) {
        rejected[route.key] = RouteRejection.untestedForAuto;
        continue;
      }
      if (!_fasterThan(route, cpu)) {
        rejected[route.key] = RouteRejection.notFasterThanCpu;
        continue;
      }
      accelerators.add(route);
    }
    accelerators.sort(_preferForAuto);
    if (accelerators.isNotEmpty) {
      return AsrRouteDecision.run(accelerators.first, rejected: rejected);
    }
    if (cpu != null) return AsrRouteDecision.run(cpu, rejected: rejected);
    return AsrRouteDecision.fail(
      _reasonFor(own, rejected),
      'No route for ${model.displayName} can run on this device.',
      rejected: rejected,
    );
  }

  /// Purpose: Decide what to do when a running route fails mid-job.
  /// Inputs: Original [request], the [failed] route, the error [code].
  /// Returns: A fallback decision, or a failure.
  /// Side effects: None.
  /// Notes: Only route problems away from the CPU may fall back.
  static AsrRouteDecision fallbackAfter(
    AsrRoutingRequest request,
    AsrRoute failed,
    AsrErrorCode code,
  ) {
    if (!code.isRouteProblem || failed.isCpu) {
      return AsrRouteDecision.fail(code, 'The ${failed.backend} route failed.');
    }
    final rejected = <String, RouteRejection>{};
    final cpu = bestCpu(
      filterUsable(request, rejected).where((r) => r.key != failed.key),
    );
    return _fallbackOrFail(
      request,
      from: failed.key,
      reason: code,
      cpu: cpu,
      rejected: rejected,
    );
  }

  /// Purpose: List the chosen model's own routes.
  /// Inputs: [request]. Returns: Routes of the model's artifacts.
  /// Side effects: None.
  /// Notes: This filter is the "never substitute a model" rule.
  static List<AsrRoute> ownRoutes(AsrRoutingRequest request) {
    final artifacts = asrModelArtifactIds(request.model);
    return [
      for (final route in request.routes)
        if (route.modelId == request.model.id &&
            artifacts.contains(route.artifactId))
          route,
    ];
  }

  /// Purpose: List own routes that could run a job at all.
  /// Inputs: [request], [rejected] to record reasons in.
  /// Returns: Usable routes. Side effects: Adds to [rejected].
  /// Notes: Public so diagnostics can show the same reasons.
  static List<AsrRoute> filterUsable(
    AsrRoutingRequest request,
    Map<String, RouteRejection> rejected,
  ) {
    final usable = <AsrRoute>[];
    for (final route in ownRoutes(request)) {
      final reason = switch (route) {
        _ when !request.installedArtifacts.contains(route.artifactId) =>
          RouteRejection.notInstalled,
        _ when !route.available => RouteRejection.unavailable,
        _ when route.health.outcome == SelfTestOutcome.crashed =>
          RouteRejection.crashed,
        _ when route.health.outcome == SelfTestOutcome.failed =>
          RouteRejection.checkFailed,
        _
            when request.requireSegmentTimestamps &&
                route.capabilities.segmentTimestamps ==
                    AsrCapability.unsupported =>
          RouteRejection.lacksTimestamps,
        _ => null,
      };
      if (reason == null) {
        usable.add(route);
      } else {
        rejected[route.key] = reason;
      }
    }
    return usable;
  }

  /// Purpose: Pick the CPU route to use.
  /// Inputs: [usable] routes. Returns: Best CPU route, or null.
  /// Side effects: None.
  /// Notes: Passed before unchecked, then tested here, then evidence, then
  /// key, so the choice is stable.
  static AsrRoute? bestCpu(Iterable<AsrRoute> usable) {
    final cpu = [
      for (final route in usable)
        if (route.isCpu) route,
    ];
    if (cpu.isEmpty) return null;
    cpu.sort((a, b) {
      final checked =
          _rank(b.health.outcome == SelfTestOutcome.passed) -
          _rank(a.health.outcome == SelfTestOutcome.passed);
      if (checked != 0) return checked;
      final tested = _rank(b.testedHere) - _rank(a.testedHere);
      if (tested != 0) return tested;
      final evidence = a.evidence.index - b.evidence.index;
      if (evidence != 0) return evidence;
      return a.key.compareTo(b.key);
    });
    return cpu.first;
  }

  /// Purpose: Apply the application's fallback steps in order.
  /// Inputs: [request], [from], [reason], best [cpu], [rejected].
  /// Returns: A running decision with a fallback, or a failure.
  /// Side effects: None. Notes: Internal.
  static AsrRouteDecision _fallbackOrFail(
    AsrRoutingRequest request, {
    required String from,
    required AsrErrorCode reason,
    required AsrRoute? cpu,
    required Map<String, RouteRejection> rejected,
  }) {
    for (final step in request.fallback.steps) {
      final AsrRoute? target = switch (step) {
        SameModelCpuFallback() => cpu != null && cpu.key != from ? cpu : null,
        ModelIndependentFallback(:final adapterId) => () {
          for (final route in request.routes) {
            if (route.adapterId == adapterId &&
                route.modelIndependent &&
                route.available &&
                route.health.outcome.allowsUse) {
              return route;
            }
          }
          return null;
        }(),
      };
      if (target != null) {
        return AsrRouteDecision.run(
          target,
          fallback: AsrFallbackDecision(
            from: from,
            toRouteKey: target.key,
            reason: reason,
            step: step,
          ),
          rejected: rejected,
        );
      }
    }
    return AsrRouteDecision.fail(
      reason,
      'The route asked for ($from) cannot run here, and the fallback policy '
      '(${request.fallback.name}) allows nothing else.',
      rejected: rejected,
    );
  }

  /// Purpose: Order Auto candidates, best first.
  /// Inputs: Two routes. Returns: Comparison. Side effects: None.
  /// Notes: Internal.
  static int _preferForAuto(AsrRoute a, AsrRoute b) {
    final tested = _rank(b.testedHere) - _rank(a.testedHere);
    if (tested != 0) return tested;
    final speedA = a.health.realTimeFactor ?? double.infinity;
    final speedB = b.health.realTimeFactor ?? double.infinity;
    final speed = speedA.compareTo(speedB);
    if (speed != 0) return speed;
    final evidence = a.evidence.index - b.evidence.index;
    if (evidence != 0) return evidence;
    return a.key.compareTo(b.key);
  }

  /// Purpose: Whether [route] beat [cpu] in its self-test.
  /// Inputs: Routes. Returns: bool; false when either speed is unknown.
  /// Side effects: None. Notes: Internal.
  static bool _fasterThan(AsrRoute route, AsrRoute? cpu) {
    final mine = route.health.realTimeFactor;
    final theirs = cpu?.health.realTimeFactor;
    if (mine == null || theirs == null) return false;
    return mine < theirs;
  }

  /// Purpose: Name the most specific error for routes that cannot run.
  /// Inputs: [routes], [rejected]. Returns: Code. Side effects: None.
  /// Notes: Internal.
  static AsrErrorCode _reasonFor(
    Iterable<AsrRoute> routes,
    Map<String, RouteRejection> rejected,
  ) {
    if (routes.isEmpty) return AsrErrorCode.backendNotBuilt;
    final reasons = {for (final route in routes) rejected[route.key]};
    if (reasons.contains(RouteRejection.crashed)) {
      return AsrErrorCode.routeCrashed;
    }
    if (reasons.contains(RouteRejection.notInstalled)) {
      return AsrErrorCode.modelMissing;
    }
    if (reasons.contains(RouteRejection.lacksTimestamps)) {
      return AsrErrorCode.unsupportedFeature;
    }
    if (reasons.contains(RouteRejection.unavailable)) {
      return AsrErrorCode.driverMissing;
    }
    return AsrErrorCode.deviceUnavailable;
  }

  /// Purpose: Flag to sort rank.
  /// Inputs: [flag]. Returns: 1 or 0. Side effects: None. Notes: Internal.
  static int _rank(bool flag) => flag ? 1 : 0;
}
