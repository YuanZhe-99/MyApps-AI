import 'package:flutter/widgets.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

/// State of an explicit connection test.
enum OnlineConnectionTestState {
  /// Not run since the editor opened or the draft changed.
  idle,

  /// Running.
  testing,

  /// The server answered.
  success,

  /// The test failed.
  failure,
}

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
}

/// Builds the endpoint input from the application's shared input widget.
typedef OnlineEndpointFieldBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      String? errorText,
    );

/// Builds the masked key input from the application's shared input widget.
typedef OnlineSecretFieldBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      bool hasSavedValue,
      VoidCallback onClear,
    );

/// Builds the connection-test row from the application's shared widget.
typedef OnlineConnectionTestBuilder =
    Widget Function(
      BuildContext context,
      OnlineConnectionTestState state,
      String? message,
      VoidCallback? onTest,
    );

/// The generic input widgets the editor places.
///
/// Applications pass MyApps-UI's `MyAppsEndpointField`, `MyAppsSecretField`
/// and `MyAppsConnectionTestRow` with their own wording, so this package needs
/// no dependency on MyApps-UI.
@immutable
class MyAppsOnlineFieldBuilders {
  /// Purpose: Bind the three builders.
  /// Inputs: [endpoint], [secret], [connectionTest].
  /// Returns: Builders. Side effects: None. Notes: None.
  const MyAppsOnlineFieldBuilders({
    required this.endpoint,
    required this.secret,
    required this.connectionTest,
  });

  /// Purpose: Endpoint input. Inputs: None. Returns: Builder.
  /// Side effects: None. Notes: None.
  final OnlineEndpointFieldBuilder endpoint;

  /// Purpose: Key input. Inputs: None. Returns: Builder.
  /// Side effects: None. Notes: None.
  final OnlineSecretFieldBuilder secret;

  /// Purpose: Connection test row. Inputs: None. Returns: Builder.
  /// Side effects: None. Notes: None.
  final OnlineConnectionTestBuilder connectionTest;
}

/// Application-owned wording for the online sources pages.
///
/// The package ships no strings.
@immutable
class MyAppsOnlineLabels {
  /// Purpose: Bind application-owned wording.
  /// Inputs: List: [empty], [add], [templateName], [status] (subtitle from
  /// configuration gaps), [remove], [removeTitle], [removeBody],
  /// [removeConfirm], [cancel]. Editor: [name], [model], [save],
  /// [saveFailed], [invalidEndpoint], [testResult]. Notice: [privacyTitle],
  /// [privacyIntro], [dataItem], [keySync], [onlyWhenSelected],
  /// [privacyConfirm].
  /// Returns: Labels. Side effects: None. Notes: None.
  const MyAppsOnlineLabels({
    required this.empty,
    required this.add,
    required this.templateName,
    required this.status,
    required this.remove,
    required this.removeTitle,
    required this.removeBody,
    required this.removeConfirm,
    required this.cancel,
    required this.name,
    required this.model,
    required this.save,
    required this.saveFailed,
    required this.invalidEndpoint,
    required this.testResult,
    required this.privacyTitle,
    required this.privacyIntro,
    required this.dataItem,
    required this.keySync,
    required this.onlyWhenSelected,
    required this.privacyConfirm,
  });

  /// Purpose: Text when no provider exists. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String empty;

  /// Purpose: Add-menu tooltip. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String add;

  /// Purpose: Name a template in the add menu. Inputs: template.
  /// Returns: String. Side effects: None. Notes: None.
  final String Function(OnlineProviderTemplate template) templateName;

  /// Purpose: Subtitle for a provider. Inputs: provider, its gaps (empty
  /// when ready). Returns: String. Side effects: None. Notes: None.
  final String Function(
    OnlineProvider provider,
    Set<OnlineConfigurationGap> gaps,
  )
  status;

  /// Purpose: Remove action label. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String remove;

  /// Purpose: Remove confirmation title. Inputs: provider name.
  /// Returns: String. Side effects: None. Notes: None.
  final String Function(String name) removeTitle;

  /// Purpose: Remove confirmation body, stating the key is deleted too.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String removeBody;

  /// Purpose: Remove confirm button. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String removeConfirm;

  /// Purpose: Cancel button for dialogs. Inputs: None. Returns: String.
  /// Side effects: None. Notes: Also the privacy notice's decline button.
  final String cancel;

  /// Purpose: Name field label. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String name;

  /// Purpose: Model field label. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String model;

  /// Purpose: Save button. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String save;

  /// Purpose: Text when saving throws. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String saveFailed;

  /// Purpose: Error for an endpoint that is not an absolute http(s) URL.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String invalidEndpoint;

  /// Purpose: Word a connection test result. Inputs: report.
  /// Returns: String. Side effects: None. Notes: None.
  final String Function(GenAiStatusReport report) testResult;

  /// Purpose: Privacy notice title. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String privacyTitle;

  /// Purpose: Notice opening sentence naming the recipient.
  /// Inputs: recipient host, provider name or null. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(String host, String? providerName) privacyIntro;

  /// Purpose: Word one sent item. Inputs: item. Returns: String.
  /// Side effects: None.
  /// Notes: Prefer the item's own description when present.
  final String Function(OnlineDataItem item) dataItem;

  /// Purpose: Word the key sync rule. Inputs: rule. Returns: String.
  /// Side effects: None. Notes: None.
  final String Function(OnlineKeySync rule) keySync;

  /// Purpose: Statement that the source is used only when chosen.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String onlyWhenSelected;

  /// Purpose: Confirm button of the notice. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String privacyConfirm;
}
