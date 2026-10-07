import 'package:flutter/foundation.dart';

import 'failure.dart';
import 'manager.dart';
import 'manifest.dart';

/// An action the settings UI may offer for a model.
enum ModelAction {
  /// Start (or resume) a download.
  download,

  /// Cancel a running download; partial bytes are kept.
  cancel,

  /// Pause or resume a download. Only for sources that support it.
  pauseResume,

  /// Re-hash installed files.
  verify,

  /// Remove installed files.
  remove,
}

/// Install state as the settings UI presents it.
enum ModelInstallState {
  /// Nothing installed.
  notInstalled,

  /// Downloading.
  downloading,

  /// Unpacking or hashing.
  verifying,

  /// Ready to use.
  installed,

  /// Last attempt failed with nothing installed.
  failed,

  /// Installed files no longer match.
  corrupt,

  /// A system-managed model whose state this app cannot inspect.
  unknown;

  /// Purpose: Map an artifact state.
  /// Inputs: [state]. Returns: The matching install state.
  /// Side effects: None. Notes: None.
  static ModelInstallState from(ArtifactState state) => switch (state) {
    ArtifactState.notInstalled => notInstalled,
    ArtifactState.downloading => downloading,
    ArtifactState.verifying => verifying,
    ArtifactState.installed => installed,
    ArtifactState.failed => failed,
    ArtifactState.corrupt => corrupt,
  };
}

/// One model row in the shared settings UI.
///
/// Presentation-only: building UI from it never downloads, queries or
/// persists anything. Labels are localised by the application.
@immutable
class ModelCatalogEntry {
  /// Purpose: Stable logical model id (e.g. MyTranscribe's `local:` id).
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String modelId;

  /// Purpose: Artifact backing this row, or null for system models.
  /// Inputs: None. Returns: String or null. Side effects: None. Notes: None.
  final String? artifactId;

  /// Purpose: Capability, e.g. `asr` or `llm`.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Free-form so new capabilities need no change here.
  final String capability;

  /// Purpose: Download size in bytes for this platform, when known.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  final int? downloadBytes;

  /// Purpose: Bytes installed, when known.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  final int? installedBytes;

  /// Purpose: Install state.
  /// Inputs: None. Returns: [ModelInstallState]. Side effects: None.
  /// Notes: None.
  final ModelInstallState state;

  /// Purpose: Fraction 0..1 while downloading/verifying; null when unknown.
  /// Inputs: None. Returns: double or null. Side effects: None. Notes: None.
  final double? progress;

  /// Purpose: Bytes received while downloading.
  /// Inputs: None. Returns: int or null. Side effects: None.
  /// Notes: Shown when [progress] is null (unknown total).
  final int? receivedBytes;

  /// Purpose: Failure of the last attempt.
  /// Inputs: None. Returns: [ArtifactFailure] or null. Side effects: None.
  /// Notes: None.
  final ArtifactFailure? failure;

  /// Purpose: Whether the platform manages the model (ML Kit, Foundation
  /// Models), not this app.
  /// Inputs: None. Returns: bool. Side effects: None.
  /// Notes: System models list only [actions] they actually support.
  final bool systemManaged;

  /// Purpose: Whether the model is in use and cannot be removed.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  final bool leased;

  /// Purpose: Actions available now.
  /// Inputs: None. Returns: Set. Side effects: None.
  /// Notes: Computed by [ModelCatalogEntry.forArtifact] or supplied by a
  /// system adapter.
  final Set<ModelAction> actions;

  /// Purpose: Create an entry.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: Prefer the factories.
  const ModelCatalogEntry({
    required this.modelId,
    required this.capability,
    required this.state,
    required this.actions,
    this.artifactId,
    this.downloadBytes,
    this.installedBytes,
    this.progress,
    this.receivedBytes,
    this.failure,
    this.systemManaged = false,
    this.leased = false,
  });

  /// Purpose: Build a downloadable model's row from manager state.
  /// Inputs: [manifest], [status], [platform], [capability], [leased],
  /// [supportsPauseResume].
  /// Returns: An entry with consistent actions.
  /// Side effects: None.
  /// Notes: download when not installed/failed/corrupt; cancel while
  /// downloading; verify and remove when installed or corrupt and idle;
  /// remove is withheld while leased; pauseResume only when supported.
  factory ModelCatalogEntry.forArtifact({
    required ArtifactManifest manifest,
    required ArtifactStatus status,
    required ModelPlatform platform,
    required String capability,
    bool leased = false,
    bool supportsPauseResume = false,
  }) {
    final state = ModelInstallState.from(status.state);
    final actions = <ModelAction>{
      if (state == ModelInstallState.notInstalled ||
          state == ModelInstallState.failed ||
          state == ModelInstallState.corrupt)
        ModelAction.download,
      if (state == ModelInstallState.downloading) ModelAction.cancel,
      if (state == ModelInstallState.downloading && supportsPauseResume)
        ModelAction.pauseResume,
      if (state == ModelInstallState.installed ||
          state == ModelInstallState.corrupt)
        ModelAction.verify,
      if (!leased &&
          (state == ModelInstallState.installed ||
              state == ModelInstallState.corrupt ||
              state == ModelInstallState.failed))
        ModelAction.remove,
    };
    return ModelCatalogEntry(
      modelId: manifest.modelId,
      artifactId: manifest.artifactId,
      capability: capability,
      state: state,
      actions: actions,
      downloadBytes: manifest.downloadBytesFor(platform),
      installedBytes: status.manifest?.installedBytes,
      progress: status.progress?.fraction,
      receivedBytes: status.progress?.receivedBytes,
      failure: status.failure,
      leased: leased,
    );
  }

  /// Purpose: Build a system-managed model's row.
  /// Inputs: [modelId], [capability], [state], [supported] actions, optional
  /// [progress] and [downloadBytes].
  /// Returns: An entry with [systemManaged] true.
  /// Side effects: None.
  /// Notes: Only actions the system really offers belong in [supported];
  /// typically `download` alone.
  factory ModelCatalogEntry.system({
    required String modelId,
    required String capability,
    required ModelInstallState state,
    Set<ModelAction> supported = const {},
    double? progress,
    int? receivedBytes,
    int? downloadBytes,
  }) => ModelCatalogEntry(
    modelId: modelId,
    capability: capability,
    state: state,
    actions: Set.unmodifiable(supported),
    progress: progress,
    receivedBytes: receivedBytes,
    downloadBytes: downloadBytes,
    systemManaged: true,
  );

  /// Purpose: Report whether [action] is available.
  /// Inputs: [action]. Returns: bool. Side effects: None. Notes: None.
  bool can(ModelAction action) => actions.contains(action);
}

/// Everything the shared model-management UI shows.
@immutable
class ModelManagementState {
  /// Purpose: Rows in display order.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<ModelCatalogEntry> entries;

  /// Purpose: Bytes all managed models occupy, when measured.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  final int? usedBytes;

  /// Purpose: Free bytes on the models volume, when known.
  /// Inputs: None. Returns: int or null. Side effects: None. Notes: None.
  final int? freeBytes;

  /// Purpose: Create a state.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const ModelManagementState({
    this.entries = const [],
    this.usedBytes,
    this.freeBytes,
  });

  /// Purpose: Find an entry by model id.
  /// Inputs: [modelId]. Returns: The entry or null. Side effects: None.
  /// Notes: None.
  ModelCatalogEntry? entryFor(String modelId) {
    for (final entry in entries) {
      if (entry.modelId == modelId) return entry;
    }
    return null;
  }

  /// Purpose: Rows for one capability.
  /// Inputs: [capability]. Returns: Filtered list. Side effects: None.
  /// Notes: None.
  List<ModelCatalogEntry> forCapability(String capability) => [
    for (final entry in entries)
      if (entry.capability == capability) entry,
  ];

  /// Purpose: Report whether any download is running.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get anyBusy => entries.any(
    (e) =>
        e.state == ModelInstallState.downloading ||
        e.state == ModelInstallState.verifying,
  );
}

/// Commands the shared settings UI sends back to the application adapter.
abstract interface class ModelManagementController {
  /// Purpose: Current state.
  /// Inputs: None. Returns: [ModelManagementState]. Side effects: None.
  /// Notes: None.
  ModelManagementState get state;

  /// Purpose: Observe state changes.
  /// Inputs: None. Returns: Stream of states. Side effects: None.
  /// Notes: None.
  Stream<ModelManagementState> get changes;

  /// Purpose: Perform [action] on [modelId].
  /// Inputs: [modelId], [action]. Returns: Completes when accepted/finished.
  /// Side effects: Implementation-defined (download, remove, ...).
  /// Notes: Must refuse actions not in the entry's [ModelCatalogEntry.actions].
  /// Downloads start only from this explicit user action.
  Future<void> perform(String modelId, ModelAction action);
}
