import 'package:flutter/foundation.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Where a card is in its life cycle.
enum AiInsightPhase {
  /// Nothing requested yet, or the model cannot run right now.
  idle,

  /// A generation is queued or running.
  generating,

  /// [AiInsightState.entry] matches the current facts.
  ready,

  /// The last attempt failed; see [AiInsightState.failure].
  failed,
}

/// What a card shows.
@immutable
class AiInsightState {
  /// The phase.
  final AiInsightPhase phase;

  /// The entry to show: current when [stale] is false, else the previous one.
  final AiInsightEntry? entry;

  /// Why the last attempt failed, when [phase] is `failed`.
  final GenAiFailure? failure;

  /// Whether [entry] belongs to older facts.
  final bool stale;

  /// Purpose: Create a card state.
  /// Inputs: see fields.
  /// Returns: A new `AiInsightState`.
  /// Side effects: None.
  /// Notes: None.
  const AiInsightState({
    this.phase = AiInsightPhase.idle,
    this.entry,
    this.failure,
    this.stale = false,
  });
}

/// Generic app-local insight orchestration with injected business and storage policy.
class AiInsightCoordinator<K, R> extends ChangeNotifier {
  /// Purpose: Construct coordinator. Inputs: business and I/O callbacks.
  /// Returns: Coordinator. Side effects: None until ensure. Notes: Keys/data remain app-owned.
  AiInsightCoordinator({
    required this.keyOf,
    required this.fingerprintOf,
    required this.modelOf,
    required this.canGenerate,
    required this.answer,
    required this.skippedEntry,
    required this.load,
    required this.save,
    required this.clear,
  });
  final K Function(R) keyOf;
  final String Function(R, String) fingerprintOf;
  final String Function() modelOf;
  final bool Function() canGenerate;
  final Future<AiInsightEntry?> Function(R, String, String, bool) answer;
  final AiInsightEntry Function(R, String, String) skippedEntry;
  final Future<Map<K, AiInsightEntry>> Function() load;
  final Future<void> Function(Map<K, AiInsightEntry>) save;
  final Future<void> Function() clear;
  Map<K, AiInsightEntry>? _cache;
  Future<Map<K, AiInsightEntry>>? _loading;
  final _states = <K, AiInsightState>{};
  final _running = <K, String>{};
  final _pending = <K, (R, bool)>{};
  final _latest = <K, String>{};
  int _epoch = 0;
  bool _disposed = false;

  /// Purpose: Read a card's state.
  /// Inputs: `module`.
  /// Returns: `AiInsightState`.
  /// Side effects: None.
  /// Notes: Idle until [ensure] runs for the module.
  AiInsightState stateOf(K module) => _states[module] ?? const AiInsightState();

  /// Purpose: Load the cache once.
  /// Inputs: None.
  /// Returns: `Future<Map<K, AiInsightEntry>>`.
  /// Side effects: Reads local storage on first call.
  /// Notes: Internal helper used within this file only.
  Future<Map<K, AiInsightEntry>> _cached() {
    final c = _cache;
    if (c != null) return Future.value(c);
    return _loading ??= load()
        .catchError((Object _) => <K, AiInsightEntry>{})
        .then((value) {
          _cache ??= value;
          _loading = null;
          return _cache!;
        });
  }

  /// Purpose: Make a card current: show the cached entry when it matches,
  /// otherwise generate.
  /// Inputs: `request`; `force` — regenerate even when the cache matches
  /// (the card's refresh button).
  /// Returns: `Future<void>` — completes when this call's work is done.
  /// Side effects: May run the model, write `ai_insights.json`, notify.
  /// Notes: Does nothing but show cached text while the model cannot run.
  /// Page opens use background priority; a forced refresh is interactive.
  Future<void> ensure(R request, {bool force = false}) async {
    final epoch = _epoch;
    final module = keyOf(request);
    final cache = await _cached();
    if (epoch != _epoch || _disposed) return;
    final fingerprint = fingerprintOf(request, modelOf());
    final entry = cache[module];
    if (!force && entry != null && entry.fingerprint == fingerprint) {
      _latest[module] = fingerprint;
      _pending.remove(module);
      _set(module, AiInsightState(phase: AiInsightPhase.ready, entry: entry));
      return;
    }
    if (!canGenerate()) {
      _set(module, AiInsightState(entry: entry, stale: entry != null));
      return;
    }
    if (!force && _latest[module] == fingerprint) {
      // Already running, queued, or failed for these exact facts; a failure
      // is retried only by the refresh button or a change in the facts.
      return;
    }
    _latest[module] = fingerprint;
    if (_running.containsKey(module)) {
      _pending[module] = (request, force);
      _set(
        module,
        AiInsightState(
          phase: AiInsightPhase.generating,
          entry: stateOf(module).entry ?? entry,
          stale: true,
        ),
      );
      return;
    }
    await _run(request, fingerprint, force);
  }

  /// Purpose: Generate one card and then any request that replaced it.
  /// Inputs: `request`, `fingerprint`, `force`.
  /// Returns: `Future<void>`.
  /// Side effects: Runs the model; writes the cache; notifies.
  /// Notes: Internal helper used within this file only. A result whose
  /// fingerprint is no longer the latest is discarded.
  Future<void> _run(R request, String fingerprint, bool force) async {
    final epoch = _epoch;
    final module = keyOf(request);
    final cache = await _cached();
    final previous = cache[module];
    _running[module] = fingerprint;
    _set(
      module,
      AiInsightState(
        phase: AiInsightPhase.generating,
        entry: previous,
        stale: previous != null,
      ),
    );
    final model = modelOf();
    AiInsightState next;
    try {
      final entry = await answer(request, fingerprint, model, force);
      if (entry == null) {
        next = AiInsightState(
          phase: AiInsightPhase.failed,
          entry: previous,
          failure: GenAiFailure.failed,
          stale: previous != null,
        );
      } else {
        next = AiInsightState(phase: AiInsightPhase.ready, entry: entry);
        await _store(module, entry, fingerprint, epoch);
      }
    } on GenAiException catch (e) {
      if (e.failure == GenAiFailure.guardrail ||
          e.failure == GenAiFailure.unsupportedLanguage) {
        final entry = skippedEntry(request, fingerprint, model);
        next = AiInsightState(
          phase: AiInsightPhase.ready,
          entry: entry,
          failure: e.failure,
        );
        await _store(module, entry, fingerprint, epoch);
      } else {
        next = AiInsightState(
          phase: AiInsightPhase.failed,
          entry: previous,
          failure: e.failure,
          stale: previous != null,
        );
      }
    } catch (_) {
      next = AiInsightState(
        phase: AiInsightPhase.failed,
        entry: previous,
        failure: GenAiFailure.failed,
        stale: previous != null,
      );
    }
    _running.remove(module);
    if (_disposed) return;
    if (epoch != _epoch) {
      final pending = _pending.remove(module);
      if (pending != null) {
        _latest.remove(module);
        await ensure(pending.$1, force: pending.$2);
      }
      return;
    }
    final pending = _pending.remove(module);
    if (pending != null) {
      final (req, f) = pending;
      final fp = fingerprintOf(req, modelOf());
      _latest[module] = fp;
      final cached = (await _cached())[module];
      if (!f && cached != null && cached.fingerprint == fp) {
        // The facts went back to what is already cached (a task ticked and
        // unticked again).
        _set(
          module,
          AiInsightState(phase: AiInsightPhase.ready, entry: cached),
        );
        return;
      }
      if (canGenerate()) {
        await _run(req, fp, f);
        return;
      }
      // Not run: forget it so the next page build asks again.
      _latest.remove(module);
      final shown = next.entry ?? previous;
      _set(module, AiInsightState(entry: shown, stale: shown != null));
      return;
    }
    if (_latest[module] == fingerprint) {
      _set(module, next);
      // A transient failure is retried on the next page build; a real one
      // only by the refresh button or new facts, so it cannot loop.
      if (next.phase == AiInsightPhase.failed &&
          const {
            GenAiFailure.busy,
            GenAiFailure.background,
            GenAiFailure.cancelled,
            GenAiFailure.unavailable,
          }.contains(next.failure)) {
        _latest.remove(module);
      }
    }
  }

  /// Purpose: Put an entry into the cache and persist it.
  /// Inputs: `module`, `entry`, `fingerprint`.
  /// Returns: `Future<void>`.
  /// Side effects: Writes `ai_insights.json`.
  /// Notes: Skipped when newer facts have arrived meanwhile. A failed write is
  /// ignored: the card still shows the text, it just regenerates next time.
  Future<void> _store(
    K module,
    AiInsightEntry entry,
    String fingerprint,
    int epoch,
  ) async {
    if (epoch != _epoch || _latest[module] != fingerprint) return;
    final cache = await _cached();
    if (epoch != _epoch || _latest[module] != fingerprint || _disposed) return;
    cache[module] = entry;
    try {
      await save(cache);
    } catch (_) {}
  }

  /// Purpose: Forget every generated insight.
  /// Inputs: None.
  /// Returns: `Future<void>`.
  /// Side effects: Deletes `ai_insights.json`; resets every card; notifies.
  /// Notes: Settings' "Clear generated insights". Cards regenerate the next
  /// time their page builds.
  Future<void> clearAll() async {
    _epoch++;
    _cache = <K, AiInsightEntry>{};
    _states.clear();
    _latest.clear();
    _pending.clear();
    try {
      await clear();
    } catch (_) {}
    notifyListeners();
  }

  /// Purpose: Update one card's state and notify.
  /// Inputs: `module`, `state`.
  /// Returns: None.
  /// Side effects: Notifies listeners.
  /// Notes: Internal helper used within this file only.
  void _set(K module, AiInsightState state) {
    if (_disposed) return;
    _states[module] = state;
    notifyListeners();
  }

  /// Purpose: Invalidate obsolete work. Inputs: None. Returns: None.
  /// Side effects: Stops state publication. Notes: Backend lifetime belongs to runtime.
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _latest.clear();
    _pending.clear();
    super.dispose();
  }
}
