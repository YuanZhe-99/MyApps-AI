/// Purpose: What the online sources pages need from an application.
/// Inputs: Implemented by [OnlineSourceManager] or by an application.
/// Returns: [OnlineSourcesController].
/// Side effects: None.
/// Notes: Moved from `myapps_ai_online_ui` in 0.6.0, which re-exports it.
library;

import 'package:flutter/foundation.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

import 'http_support.dart';
import 'privacy_notice.dart';
import 'provider.dart';
import 'templates.dart';

/// Application-owned storage behind the online sources pages.
///
/// The application keeps provider records, keys (through its secret channel)
/// and device-local privacy acknowledgements; these pages only read and
/// request changes.
abstract interface class OnlineSourcesController {
  /// Purpose: Configured providers in display order.
  /// Inputs: None. Returns: List. Side effects: None.
  /// Notes: Read again whenever [changes] notifies.
  List<OnlineProvider> get providers;

  /// Purpose: Notifies when [providers] or stored keys change.
  /// Inputs: None. Returns: Listenable. Side effects: None. Notes: None.
  Listenable get changes;

  /// Purpose: Templates offered when adding a provider.
  /// Inputs: None. Returns: Registry. Side effects: None. Notes: None.
  OnlineProviderTemplateRegistry get templates;

  /// Purpose: Create an id for a new provider record.
  /// Inputs: None. Returns: A unique stable id such as `provider:<uuid>`.
  /// Side effects: None. Notes: Seeded template ids are never reused.
  String newProviderId();

  /// Purpose: Whether a key is stored for a provider.
  /// Inputs: [providerId]. Returns: bool.
  /// Side effects: Reads the secret store. Notes: The key itself is never
  /// shown again after saving.
  Future<bool> hasKey(String providerId);

  /// Purpose: Save a provider and optionally change its key.
  /// Inputs: [provider]; [newKey] to store; [clearKey] to delete the stored
  /// key. Returns: None.
  /// Side effects: Writes records and secrets; may schedule sync.
  /// Notes: Called only after any needed privacy acknowledgement.
  Future<void> save(OnlineProvider provider, {String? newKey, bool clearKey});

  /// Purpose: Delete a provider and its key.
  /// Inputs: [providerId]. Returns: None.
  /// Side effects: Writes records and secrets.
  /// Notes: Selection that pointed at it falls back to the app's default.
  Future<void> remove(String providerId);

  /// Purpose: Test an unsaved draft.
  /// Inputs: [draft]; [draftKey] typed but unsaved, or null to use the stored
  /// key. Returns: The status report.
  /// Side effects: One request to the draft's endpoint; sends no user content.
  /// Notes: Usually `OpenAiCompatibleLlmBackend.testConnection`.
  Future<GenAiStatusReport> testConnection(
    OnlineProvider draft,
    String? draftKey,
  );

  /// Purpose: Build the privacy notice for a provider.
  /// Inputs: [provider]. Returns: The notice, or null when its host is
  /// unknown (the provider cannot be enabled).
  /// Side effects: None.
  /// Notes: Usually [OnlinePrivacyNotice.forProvider] with the app's items.
  OnlinePrivacyNotice? privacyNotice(OnlineProvider provider);

  /// Purpose: Read this device's acknowledgement for a provider.
  /// Inputs: [providerId]. Returns: The record or null.
  /// Side effects: Reads device-local storage. Notes: Never synced.
  Future<OnlinePrivacyAcknowledgement?> acknowledgement(String providerId);

  /// Purpose: Store this device's acknowledgement for a provider.
  /// Inputs: [providerId], [record]. Returns: None.
  /// Side effects: Writes device-local storage. Notes: Never synced.
  Future<void> acknowledge(
    String providerId,
    OnlinePrivacyAcknowledgement record,
  );

  /// Purpose: List the models a draft source offers.
  /// Inputs: [draft]; [draftKey] typed but unsaved, or null for the stored
  /// key. Returns: Models with names, context and inputs where known,
  /// enriched from the built-in catalog.
  /// Side effects: One `GET <base>/models`; sends no user content.
  /// Notes: Only when the user asks; never polled.
  Future<List<OnlineModelEntry>> fetchModels(
    OnlineProvider draft,
    String? draftKey,
  );

  /// Purpose: The built-in catalog's models for a source.
  /// Inputs: [provider]. Returns: Entries; empty when its template has no
  /// catalog. Side effects: None.
  /// Notes: Offered when the source cannot list its models.
  List<OnlineModelEntry> catalogModels(OnlineProvider provider);
}
