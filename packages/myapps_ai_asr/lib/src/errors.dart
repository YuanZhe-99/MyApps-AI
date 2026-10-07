/// Why a speech engine could not do what it was asked, in one code set.
///
/// Names and wire spellings match MyTranscribe's `LocalAsrErrorCode`, so codes
/// stored on jobs keep parsing.
enum AsrErrorCode {
  /// The artifact is not installed.
  modelMissing,

  /// The artifact's files are damaged.
  modelCorrupt,

  /// The artifact is not the format this adapter reads.
  modelFormatMismatch,

  /// The model does not transcribe the requested language.
  unsupportedLanguage,

  /// The model or route does not do something the job asked for.
  unsupportedFeature,

  /// This build has no such backend.
  backendNotBuilt,

  /// The backend needs a driver this device lacks.
  driverMissing,

  /// The processor is there but will not take work.
  deviceUnavailable,

  /// The runtime could not compile the model for the processor.
  modelCompileFailed,

  /// Not enough memory to load or run.
  outOfMemory,

  /// The window is longer than the route takes.
  inputTooLong,

  /// The processor went away mid-run.
  deviceLost,

  /// The process died inside this route; found by the in-flight marker.
  routeCrashed,

  /// The caller cancelled.
  cancelled;

  /// Purpose: Spell the code as docs and persisted records do.
  /// Inputs: None. Returns: e.g. `MODEL_MISSING`. Side effects: None.
  /// Notes: None.
  String get wire =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

  /// Purpose: Parse a persisted code.
  /// Inputs: [value], enum or wire spelling.
  /// Returns: The code, or [deviceUnavailable] when unrecognised.
  /// Side effects: None.
  /// Notes: A device problem is the fallback because it never claims the
  /// model is broken.
  static AsrErrorCode parse(Object? value) {
    for (final code in AsrErrorCode.values) {
      if (code.name == value || code.wire == value) return code;
    }
    return deviceUnavailable;
  }

  /// Purpose: Report whether the problem is with the route, not the model.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: Only route problems can be answered by moving to another route
  /// of the same model.
  bool get isRouteProblem => switch (this) {
    backendNotBuilt ||
    driverMissing ||
    deviceUnavailable ||
    modelCompileFailed ||
    deviceLost ||
    routeCrashed ||
    outOfMemory => true,
    _ => false,
  };
}

/// A speech engine failure.
class AsrException implements Exception {
  /// Purpose: Which failure.
  /// Inputs: None. Returns: [AsrErrorCode]. Side effects: None. Notes: None.
  final AsrErrorCode code;

  /// Purpose: Diagnostic sentence, with numbers where there are any.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Not localized; applications map [code] to their own copy.
  final String message;

  /// Purpose: Whether the same call might work if retried unchanged.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool retryable;

  /// Purpose: Create a failure.
  /// Inputs: [code], [message], optional [retryable].
  /// Returns: A new exception. Side effects: None. Notes: None.
  const AsrException(this.code, this.message, {this.retryable = false});

  /// Purpose: Render the failure for a log.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  @override
  String toString() => 'AsrException(${code.wire}): $message';
}
