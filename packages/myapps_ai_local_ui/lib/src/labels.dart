import 'package:flutter/material.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// Purpose: Format a byte count for display.
/// Inputs: A non-negative byte count. Returns: Localized text such as "1.2 GB".
/// Side effects: None.
/// Notes: Supplied by the application so units follow its locale.
typedef MyAppsByteFormatter = String Function(int bytes);

/// Application-owned wording for the local-models page.
///
/// The package ships no strings: every visible or announced text comes from
/// here, so the application keeps its own localization catalogue.
@immutable
class MyAppsLocalModelLabels {
  /// Purpose: Bind application-owned wording.
  /// Inputs: `modelName` — display name of an entry; `state` — install state
  /// label; `action` — button label per action; `failure` — error text per
  /// failure; `progress` — progress text from the fraction (null when
  /// unknown) and formatted received bytes (null when unknown);
  /// `systemManaged` — note for platform-managed entries; `removeTitle` —
  /// confirmation title for a model name; `removeBody` — confirmation body
  /// stating that only downloaded files are removed and records and history
  /// are kept; `removeConfirm` — confirm button; `storage` — summary from
  /// formatted used and free bytes (either may be null); `empty` — text when
  /// no registered entry exists; `actionFailed` — fallback text when an action
  /// throws something other than an [ArtifactException]; optional `leased`
  /// note, `cancel` dialog label and `actionTooltip`.
  /// Returns: Labels. Side effects: None.
  /// Notes: `cancel` defaults to the Material cancel label; `actionTooltip`
  /// defaults to the action label.
  const MyAppsLocalModelLabels({
    required this.modelName,
    required this.state,
    required this.action,
    required this.failure,
    required this.progress,
    required this.systemManaged,
    required this.removeTitle,
    required this.removeBody,
    required this.removeConfirm,
    required this.storage,
    required this.empty,
    required this.actionFailed,
    this.leased,
    this.cancel,
    this.actionTooltip,
    this.badge,
  });

  /// Purpose: A short badge after an entry's name, such as "Unverified"
  /// for a model the user added. Inputs: entry. Returns: Text or null.
  /// Side effects: None. Notes: Optional.
  final String? Function(ModelCatalogEntry entry)? badge;

  /// Purpose: Name an entry. Inputs: entry. Returns: String.
  /// Side effects: None. Notes: Usually resolved from the app's model record.
  final String Function(ModelCatalogEntry entry) modelName;

  /// Purpose: Word an install state. Inputs: state. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(ModelInstallState state) state;

  /// Purpose: Word an action button. Inputs: action. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(ModelAction action) action;

  /// Purpose: Word a failure. Inputs: failure. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(ArtifactFailure failure) failure;

  /// Purpose: Word progress. Inputs: fraction 0..1 or null; formatted
  /// received bytes or null. Returns: String such as "42 %".
  /// Side effects: None. Notes: Also announced to assistive technology.
  final String Function(double? fraction, String? received) progress;

  /// Purpose: Note shown on system-managed entries. Inputs: None.
  /// Returns: String, e.g. "Managed by the system". Side effects: None.
  /// Notes: None.
  final String systemManaged;

  /// Purpose: Remove-confirmation title. Inputs: model name. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(String name) removeTitle;

  /// Purpose: Remove-confirmation body. Inputs: None. Returns: String.
  /// Side effects: None.
  /// Notes: Must say that only downloaded files are removed and the model
  /// records and history are kept.
  final String removeBody;

  /// Purpose: Remove-confirmation confirm button. Inputs: None.
  /// Returns: String. Side effects: None. Notes: None.
  final String removeConfirm;

  /// Purpose: Storage summary. Inputs: formatted used bytes or null, formatted
  /// free bytes or null. Returns: String. Side effects: None.
  /// Notes: Only called when at least one figure is known.
  final String Function(String? used, String? free) storage;

  /// Purpose: Text when nothing registered is listed. Inputs: None.
  /// Returns: String. Side effects: None. Notes: None.
  final String empty;

  /// Purpose: Fallback error for an action that threw an unclassified error.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String actionFailed;

  /// Purpose: Note shown while an entry is in use and cannot be removed.
  /// Inputs: None. Returns: String or null. Side effects: None.
  /// Notes: Null hides the note.
  final String? leased;

  /// Purpose: Dialog cancel label. Inputs: None. Returns: String or null.
  /// Side effects: None. Notes: Null uses [MaterialLocalizations].
  final String? cancel;

  /// Purpose: Tooltip for an action on a named entry.
  /// Inputs: action, model name. Returns: String. Side effects: None.
  /// Notes: Null uses [action].
  final String Function(ModelAction action, String name)? actionTooltip;
}

/// One capability section on the local-models page, e.g. "Speech recognition".
@immutable
class MyAppsLocalModelGroup {
  /// Purpose: Register a capability section.
  /// Inputs: `capability` — matches [ModelCatalogEntry.capability];
  /// `title` — localized heading; optional `icon` for entries.
  /// Returns: A group. Side effects: None.
  /// Notes: Entries whose capability has no group are not shown, so an app
  /// lists only capabilities it registered.
  const MyAppsLocalModelGroup({
    required this.capability,
    required this.title,
    this.icon = Icons.memory_outlined,
  });

  /// Purpose: Capability id. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String capability;

  /// Purpose: Localized heading. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String title;

  /// Purpose: Leading icon for this group's entries. Inputs: None.
  /// Returns: IconData. Side effects: None. Notes: None.
  final IconData icon;
}
