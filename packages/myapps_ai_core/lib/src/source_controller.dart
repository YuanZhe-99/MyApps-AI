/// Purpose: What AI settings need from an application's source routing, and
/// what that routing needs from online sources.
/// Inputs: Implemented by `myapps_ai_sources` and `myapps_ai_online`.
/// Returns: [AiSourceController], [AiOnlineSources].
/// Side effects: None.
/// Notes: Both live here so the settings UI, the router and the online
/// package depend only on this package, never on each other.
library;

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'diagnostics.dart';
import 'source_selection.dart';

/// The source choice as AI settings see it.
abstract interface class AiSourceController {
  /// Purpose: Notifies on selection, catalog and readiness changes.
  /// Inputs: None. Returns: Listenable. Side effects: None.
  /// Notes: Not `changes`, which model management uses for its stream.
  Listenable get sourceChanges;

  /// Purpose: The persisted selection. Inputs: None. Returns: Selection.
  /// Side effects: None. Notes: None.
  AiSourceSelection get selection;

  /// Purpose: Every choosable source: automatic, system, local models and
  /// online models. Inputs: None. Returns: Options.
  /// Side effects: None. Notes: None.
  List<AiSourceOption> get sourceOptions;

  /// Purpose: Display name for a source id. Inputs: [id]. Returns: Name,
  /// such as `Qwen: Qwen3.5 0.8B (Q4_K_M)`, or null for automatic/system.
  /// Side effects: None. Notes: Applications name automatic and system.
  String? sourceName(String id);

  /// Purpose: Secondary line for a source, such as the online source's name.
  /// Inputs: [id]. Returns: Text or null. Side effects: None. Notes: None.
  String? sourceDetail(String id);

  /// Purpose: Persist a new global source.
  /// Inputs: [id]. Returns: Completion.
  /// Side effects: Cancels running work, releases the previous source.
  /// Notes: Callers pause their own AI service first.
  Future<void> select(String id);

  /// Purpose: Whether a GPU may be offered for local models here.
  /// Inputs: None. Returns: bool. Side effects: May load the native library.
  /// Notes: False wherever no verified GPU backend exists.
  Future<bool> gpuSelectable();

  /// Purpose: Whether local models may use the GPU, falling back to the CPU.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: Default false.
  bool get gpuAllowed;

  /// Purpose: Persist [allowed] for local models. Inputs: [allowed].
  /// Returns: Completion. Side effects: Unloads a loaded local model.
  /// Notes: Device-local, never synced.
  Future<void> setGpuAllowed(bool allowed);

  /// Purpose: Collect every technical detail this build can report.
  /// Inputs: [localeTag] for system AI language support.
  /// Returns: The report. Side effects: Status queries; never inference.
  /// Notes: Lists every included backend, not only the selected one.
  Future<AiDiagnosticsReport> diagnostics({String? localeTag});
}

/// Online models a router may offer, implemented by `myapps_ai_online`.
abstract interface class AiOnlineSources {
  /// Purpose: Load records. Inputs: None. Returns: Completion.
  /// Side effects: Reads application storage. Notes: Idempotent.
  Future<void> initialize();

  /// Purpose: Notifies when sources or models change. Inputs: None.
  /// Returns: Listenable. Side effects: None. Notes: None.
  Listenable get changes;

  /// Purpose: One option per enabled online model. Inputs: None.
  /// Returns: Options of kind online. Side effects: None. Notes: None.
  List<AiSourceOption> get sourceOptions;

  /// Purpose: Whether [id] names an online model or a legacy online id.
  /// Inputs: [id]. Returns: bool. Side effects: None. Notes: None.
  bool owns(String id);

  /// Purpose: Display name of an online model. Inputs: [id].
  /// Returns: Alias or friendly name, or null. Side effects: None.
  /// Notes: None.
  String? sourceName(String id);

  /// Purpose: The online source holding a model. Inputs: [id].
  /// Returns: Its name, or null. Side effects: None. Notes: None.
  String? sourceDetail(String id);

  /// Purpose: The backend for [id], ready to generate.
  /// Inputs: [id]. Returns: Backend.
  /// Side effects: None until it generates.
  /// Notes: Throws [GenAiException] (`unavailable`) with a detail such as
  /// `privacyNotice`, `missingKey` or `unknownSource`.
  Future<GenAiBackend> resolve(String id);

  /// Purpose: Stop running requests. Inputs: None. Returns: Completion.
  /// Side effects: Cancels network work. Notes: None.
  Future<void> cancel();

  /// Purpose: Drop cached clients. Inputs: None. Returns: Completion.
  /// Side effects: Closes connections. Notes: None.
  Future<void> release();

  /// Purpose: One diagnostic section per online source.
  /// Inputs: None. Returns: Sections. Side effects: Reads key presence.
  /// Notes: Keys are reported only as present or absent.
  Future<List<AiDiagnosticSection>> diagnostics();
}
