import 'package:flutter/widgets.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

export 'package:myapps_ai_online/myapps_ai_online.dart'
    show OnlineSourcesController;

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
    required this.addSourceTitle,
    required this.searchHint,
    required this.endpointLabel,
    required this.customEndpoint,
    required this.docs,
    required this.models,
    required this.noModels,
    required this.fetchModels,
    required this.fetchFailed,
    required this.fromCatalog,
    required this.addModelId,
    required this.modelIdHint,
    required this.alias,
    required this.aliasHint,
    required this.originalId,
    required this.showAllModels,
    required this.contextTokens,
    required this.selectModels,
    required this.done,
    required this.removeModel,
    required this.localServer,
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

  /// Purpose: Title of the template picker.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String addSourceTitle;

  /// Purpose: Hint of search fields.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String searchHint;

  /// Purpose: Label of the service-endpoint choice.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String endpointLabel;

  /// Purpose: Choice for typing another endpoint address.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String customEndpoint;

  /// Purpose: Label before the provider documentation address.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String docs;

  /// Purpose: Heading of a source's models.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String models;

  /// Purpose: Text when a source has no models yet.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String noModels;

  /// Purpose: Button that lists the source's models.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String fetchModels;

  /// Purpose: Text when listing models failed; the catalog is offered instead.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String Function(String detail) fetchFailed;

  /// Purpose: Note on models shown from the built-in catalog.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String fromCatalog;

  /// Purpose: Button and dialog title for typing a model id.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String addModelId;

  /// Purpose: Hint of the model id field.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String modelIdHint;

  /// Purpose: Label of the alias field.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String alias;

  /// Purpose: Hint of the alias field, saying the friendly name is used when empty.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String aliasHint;

  /// Purpose: Line showing a model's raw id.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String Function(String id) originalId;

  /// Purpose: Switch that also shows non-chat models.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String showAllModels;

  /// Purpose: Context length of a model.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String Function(int tokens) contextTokens;

  /// Purpose: Title of the model selection.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String selectModels;

  /// Purpose: Confirm button of the model selection.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String done;

  /// Purpose: Tooltip of a model's remove button.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String removeModel;

  /// Purpose: Badge for a server on the user's machine or network.
  /// Inputs: None. Returns: Text. Side effects: None. Notes: None.
  final String localServer;
}
