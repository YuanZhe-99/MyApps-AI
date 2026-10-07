import 'package:flutter/foundation.dart';

/// Whether a route does one thing a job may need.
///
/// Wire names match MyTranscribe's `Capability`.
enum AsrCapability {
  /// The route does this.
  supported,

  /// The route does not.
  unsupported,

  /// Nobody has established either way.
  unknown;

  /// Purpose: Parse a persisted capability.
  /// Inputs: [value]. Returns: The capability; unrecognised reads as
  /// [unknown]. Side effects: None.
  /// Notes: Unknown is exactly "we cannot say".
  static AsrCapability parse(Object? value) {
    for (final capability in AsrCapability.values) {
      if (capability.name == value) return capability;
    }
    return unknown;
  }

  /// Purpose: Report whether a feature should be offered.
  /// Inputs: None. Returns: bool — true unless known unsupported.
  /// Side effects: None. Notes: Unknown is offerable, with a warning.
  bool get mayOffer => this != unsupported;
}

/// How well a route is documented to work on this kind of device.
///
/// Grades A, B, E and U of the local-ASR support survey.
enum EvidenceLevel {
  /// A: the runtime's or chip vendor's documentation covers it.
  official,

  /// B: reproducible community results exist.
  community,

  /// E: only the generic backend is documented.
  experimental,

  /// U: nothing found either way.
  none;

  /// Purpose: Parse a persisted evidence level.
  /// Inputs: [value]. Returns: The level; unrecognised reads as [none].
  /// Side effects: None.
  /// Notes: The weakest grade is the safe fallback.
  static EvidenceLevel parse(Object? value) {
    for (final level in EvidenceLevel.values) {
      if (level.name == value) return level;
    }
    return none;
  }

  /// Purpose: Name the grade as the support matrix does.
  /// Inputs: None. Returns: `A`, `B`, `E` or `U`. Side effects: None.
  /// Notes: For diagnostics.
  String get letter => switch (this) {
    official => 'A',
    community => 'B',
    experimental => 'E',
    none => 'U',
  };
}

/// Where work actually ran, as the runtime reported it.
enum PlacementKind {
  /// Only the CPU.
  cpu,

  /// A GPU.
  gpu,

  /// A neural processor.
  npu,

  /// Parts ran in different places.
  mixed,

  /// The runtime did not say. Never replaced by a guess.
  unknown;

  /// Purpose: Parse a persisted placement.
  /// Inputs: [value]. Returns: The placement; unrecognised reads as
  /// [unknown]. Side effects: None. Notes: None.
  static PlacementKind parse(Object? value) {
    for (final kind in PlacementKind.values) {
      if (kind.name == value) return kind;
    }
    return unknown;
  }
}

/// The kind of processor a route is built for.
enum ComputeDevice {
  /// The CPU; every local adapter has this route.
  cpu,

  /// A GPU backend (Metal, OpenCL, Vulkan, ...).
  gpu,

  /// A neural processor (Neural Engine, Hexagon, ...).
  npu;

  /// Purpose: Parse a persisted device.
  /// Inputs: [value]. Returns: The device; unrecognised reads as [cpu].
  /// Side effects: None.
  /// Notes: The CPU exists wherever a local model runs at all.
  static ComputeDevice parse(Object? value) {
    for (final device in ComputeDevice.values) {
      if (device.name == value) return device;
    }
    return cpu;
  }
}

/// What a route can do, declared by its adapter.
@immutable
class AsrCapabilities {
  /// Purpose: Whether segments carry real start/end times.
  /// Inputs: None. Returns: [AsrCapability]. Side effects: None. Notes: None.
  final AsrCapability segmentTimestamps;

  /// Purpose: Whether word-level times are produced.
  /// Inputs: None. Returns: [AsrCapability]. Side effects: None. Notes: None.
  final AsrCapability wordTimestamps;

  /// Purpose: Whether the detected language is reported.
  /// Inputs: None. Returns: [AsrCapability]. Side effects: None. Notes: None.
  final AsrCapability languageDetection;

  /// Purpose: Whether a context prompt is used.
  /// Inputs: None. Returns: [AsrCapability]. Side effects: None. Notes: None.
  final AsrCapability prompt;

  /// Purpose: Whether keyword (hotword) hints are used.
  /// Inputs: None. Returns: [AsrCapability]. Side effects: None. Notes: None.
  final AsrCapability keywords;

  /// Purpose: Whether a cancel stops a window mid-way.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: False means the window finishes and its result is discarded.
  final bool cancelsMidWindow;

  /// Purpose: Whether progress events are emitted.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool reportsProgress;

  /// Purpose: Create a capability declaration.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: Defaults are "unknown", what an adapter that said nothing is.
  const AsrCapabilities({
    this.segmentTimestamps = AsrCapability.unknown,
    this.wordTimestamps = AsrCapability.unknown,
    this.languageDetection = AsrCapability.unknown,
    this.prompt = AsrCapability.unknown,
    this.keywords = AsrCapability.unknown,
    this.cancelsMidWindow = false,
    this.reportsProgress = false,
  });
}
