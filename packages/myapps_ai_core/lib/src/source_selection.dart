/// Backend-neutral AI source selection: which source serves each feature.
///
/// A source is a system model, an installed local model or a configured online
/// provider. Applications register the options they support; nothing here
/// probes, downloads or connects.
library;

import 'package:flutter/foundation.dart';

/// Where a source runs.
enum AiSourceKind {
  /// Let the application pick the best ready source by its own policy.
  auto,

  /// A model managed by the operating system (AICore, Foundation Models).
  system,

  /// A model file installed and run by this application.
  local,

  /// A provider reached over the network with the user's configuration.
  online,
}

/// Whether a source can be used right now.
enum AiSourceReadiness {
  /// Usable without further action.
  ready,

  /// A local model whose files are not installed.
  needsDownload,

  /// An online source missing an endpoint, model or API key.
  needsConfiguration,

  /// Not usable on this device or build.
  unavailable,
}

/// One selectable source, as registered by the application.
@immutable
class AiSourceOption {
  /// Purpose: Describe a selectable source.
  /// Inputs: `id` — stable persisted identifier; `kind`; `readiness`;
  /// `features` — feature ids this source can serve, empty meaning all.
  /// Returns: A new `AiSourceOption`.
  /// Side effects: None.
  /// Notes: Labels are resolved by the UI layer from injected callbacks so
  /// this type stays free of localization.
  const AiSourceOption({
    required this.id,
    required this.kind,
    this.readiness = AiSourceReadiness.ready,
    this.features = const {},
  });

  /// Stable identifier, persisted in [AiSourceSelection].
  final String id;

  /// Where the source runs.
  final AiSourceKind kind;

  /// Whether the source is usable now.
  final AiSourceReadiness readiness;

  /// Feature ids the source can serve; empty means every feature.
  final Set<String> features;

  /// Purpose: Report whether this source can serve a feature.
  /// Inputs: `feature`.
  /// Returns: `bool`.
  /// Side effects: None.
  /// Notes: Readiness is not considered; an unready source can still be chosen.
  bool supports(String feature) =>
      features.isEmpty || features.contains(feature);
}

/// The persisted source choice: one global selection plus optional
/// per-feature overrides for features the application allows.
@immutable
class AiSourceSelection {
  /// Purpose: Create a selection.
  /// Inputs: `global` — source id; `overrides` — feature id to source id;
  /// `extra` — unknown JSON fields preserved for newer builds.
  /// Returns: A new `AiSourceSelection`.
  /// Side effects: None.
  /// Notes: A feature without an override follows [global].
  const AiSourceSelection({
    this.global = autoSourceId,
    this.overrides = const {},
    this.extra = const {},
  });

  /// The id of the automatic source.
  static const autoSourceId = 'auto';

  /// The global source id.
  final String global;

  /// Feature-specific overrides.
  final Map<String, String> overrides;

  /// Unknown fields read from JSON, written back unchanged.
  final Map<String, Object?> extra;

  /// Purpose: Resolve the source id serving a feature.
  /// Inputs: `feature`; `overridable` — features the app allows to override.
  /// Returns: `String` source id.
  /// Side effects: None.
  /// Notes: An override for a feature no longer overridable is ignored, not
  /// deleted, so re-enabling it restores the user's choice.
  String sourceFor(String feature, {Set<String> overridable = const {}}) {
    if (overridable.contains(feature)) {
      final o = overrides[feature];
      if (o != null) return o;
    }
    return global;
  }

  /// Purpose: Return a copy with a new global source.
  /// Inputs: `id`.
  /// Returns: `AiSourceSelection`.
  /// Side effects: None.
  /// Notes: Overrides are kept.
  AiSourceSelection withGlobal(String id) =>
      AiSourceSelection(global: id, overrides: overrides, extra: extra);

  /// Purpose: Set or clear one feature's override.
  /// Inputs: `feature`; `id` — null to follow the global source.
  /// Returns: `AiSourceSelection`.
  /// Side effects: None.
  /// Notes: None.
  AiSourceSelection withOverride(String feature, String? id) {
    final next = Map<String, String>.of(overrides);
    if (id == null) {
      next.remove(feature);
    } else {
      next[feature] = id;
    }
    return AiSourceSelection(global: global, overrides: next, extra: extra);
  }

  /// Purpose: Serialize for app-owned persistence.
  /// Inputs: None.
  /// Returns: JSON map.
  /// Side effects: None.
  /// Notes: Unknown fields are written back first so known keys win.
  Map<String, Object?> toJson() => {
    ...extra,
    'global': global,
    'overrides': overrides,
  };

  /// Purpose: Read a persisted selection.
  /// Inputs: `json` — may be null or malformed.
  /// Returns: `AiSourceSelection`; defaults when unreadable.
  /// Side effects: None.
  /// Notes: Unknown keys are preserved in [extra]; non-string overrides drop.
  static AiSourceSelection fromJson(Object? json) {
    if (json is! Map) return const AiSourceSelection();
    final global = json['global'];
    final raw = json['overrides'];
    return AiSourceSelection(
      global: global is String && global.isNotEmpty ? global : autoSourceId,
      overrides: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      extra: {
        for (final e in json.entries)
          if (e.key is String && e.key != 'global' && e.key != 'overrides')
            e.key as String: e.value,
      },
    );
  }

  /// Purpose: Compare by value.
  /// Inputs: `other`.
  /// Returns: `bool`.
  /// Side effects: None.
  /// Notes: [extra] is ignored; it carries no meaning for this build.
  @override
  bool operator ==(Object other) =>
      other is AiSourceSelection &&
      other.global == global &&
      mapEquals(other.overrides, overrides);

  /// Purpose: Hash by value.
  /// Inputs: None.
  /// Returns: `int`.
  /// Side effects: None.
  /// Notes: Consistent with [operator ==].
  @override
  int get hashCode => Object.hash(
    global,
    Object.hashAllUnordered(
      overrides.entries.map((e) => '${e.key}=${e.value}'),
    ),
  );
}

/// Purpose: List features whose serving source changes between selections.
/// Inputs: `before`, `after`, `features`, `overridable`.
/// Returns: `Set<String>` of affected feature ids.
/// Side effects: None.
/// Notes: Used to decide whether to ask about clearing content generated by
/// the previous source. The caller asks only when one of the affected features
/// has stored generated content, and asks once per change.
Set<String> featuresWithChangedSource(
  AiSourceSelection before,
  AiSourceSelection after, {
  required Iterable<String> features,
  Set<String> overridable = const {},
}) => {
  for (final f in features)
    if (before.sourceFor(f, overridable: overridable) !=
        after.sourceFor(f, overridable: overridable))
      f,
};
