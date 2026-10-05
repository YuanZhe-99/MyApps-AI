import 'dart:async';

/// App-local single-flight execution with invalidation of obsolete results.
class AiExecutionGate {
  bool _busy = false;
  int _generation = 0;

  /// Purpose: Report occupancy. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: Includes status checks and cancellation cleanup.
  bool get busy => _busy;

  /// Purpose: Capture current generation. Inputs: None. Returns: int.
  /// Side effects: None. Notes: Used to protect asynchronous status publication.
  int get generation => _generation;

  /// Purpose: Invalidate pending results. Inputs: None. Returns: None.
  /// Side effects: Advances generation. Notes: Does not release occupied slot.
  void invalidate() => _generation++;

  /// Purpose: Execute one operation. Inputs: policy callbacks, body, timeout.
  /// Returns: Result. Side effects: Runs and possibly cancels backend work.
  /// Notes: Typed failures are supplied by the consumer; no business data is stored.
  Future<T> run<T>({
    required bool Function() enabled,
    required Future<T> Function(bool Function() current) body,
    required Future<void> Function() cancel,
    required Object Function() unavailable,
    required Object Function() occupied,
    required Object Function() cancelled,
    required Object Function() timedOut,
    required Duration timeout,
    void Function()? changed,
  }) async {
    if (!enabled()) throw unavailable();
    if (_busy) throw occupied();
    final epoch = _generation;
    bool current() => enabled() && epoch == _generation;
    _busy = true;
    changed?.call();
    try {
      final value = await body(current).timeout(
        timeout,
        onTimeout: () async {
          invalidate();
          await cancel();
          throw timedOut();
        },
      );
      if (!current()) throw cancelled();
      return value;
    } finally {
      _busy = false;
      changed?.call();
    }
  }
}
