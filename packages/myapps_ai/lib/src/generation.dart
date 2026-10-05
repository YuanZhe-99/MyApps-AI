import 'backend.dart';

/// Purpose: Generate and validate with at most one fallback. Inputs: facts and callbacks.
/// Returns: Answered facts and validated result. Side effects: Runs consumer generation.
/// Notes: Only guardrail failures and unusable results trigger fallback; other failures propagate.
Future<(F, R)> generateWithFallback<F, R>({
  required F primary,
  F? fallback,
  required Future<R> Function(F facts) generate,
  required bool Function(R result) usable,
}) async {
  try {
    final result = await generate(primary);
    if (usable(result) || fallback == null) return (primary, result);
  } on GenAiException catch (error) {
    if (error.failure != GenAiFailure.guardrail || fallback == null) rethrow;
  }
  return (fallback, await generate(fallback));
}
