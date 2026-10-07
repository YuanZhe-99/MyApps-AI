import 'package:flutter/material.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';
import 'privacy_dialog.dart';

/// Purpose: Ask before deleting a provider.
/// Inputs: [context], provider [name], [labels].
/// Returns: True when confirmed; false on cancel or dismissal.
/// Side effects: Shows a dialog. Notes: None.
Future<bool> confirmOnlineSourceRemoval(
  BuildContext context,
  String name,
  MyAppsOnlineLabels labels,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.removeTitle(name)),
        content: Text(labels.removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(labels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(labels.removeConfirm),
          ),
        ],
      ),
    ) ??
    false;

/// Edits one online provider: name, endpoint, model, API key, connection
/// test; saving asks for the privacy notice first when this device has not
/// confirmed it for the provider's host.
///
/// Pops `true` after saving or removing, so the caller can resume what sent
/// the user here (for example a source picker's "needs configuration").
class MyAppsOnlineSourceEditorPage extends StatefulWidget {
  /// Purpose: Create the editor.
  /// Inputs: [title]; [controller]; [provider] — existing or a new draft from
  /// a template; [isNew] when not yet saved; [labels]; [fields]; optional
  /// [footer] such as the app's key-sync status.
  /// Returns: Page. Side effects: None.
  /// Notes: Nothing is sent until the user taps the connection test.
  const MyAppsOnlineSourceEditorPage({
    super.key,
    required this.title,
    required this.controller,
    required this.provider,
    required this.labels,
    required this.fields,
    this.isNew = false,
    this.footer,
  });

  /// Purpose: Page title. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String title;

  /// Purpose: Application storage. Inputs: None.
  /// Returns: [OnlineSourcesController]. Side effects: None. Notes: None.
  final OnlineSourcesController controller;

  /// Purpose: Provider being edited. Inputs: None.
  /// Returns: [OnlineProvider]. Side effects: None. Notes: None.
  final OnlineProvider provider;

  /// Purpose: Whether the provider is unsaved. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: Hides removal.
  final bool isNew;

  /// Purpose: Wording. Inputs: None. Returns: [MyAppsOnlineLabels].
  /// Side effects: None. Notes: None.
  final MyAppsOnlineLabels labels;

  /// Purpose: Input widgets. Inputs: None.
  /// Returns: [MyAppsOnlineFieldBuilders]. Side effects: None. Notes: None.
  final MyAppsOnlineFieldBuilders fields;

  /// Purpose: Optional widget below the form. Inputs: None.
  /// Returns: Widget or null. Side effects: None. Notes: None.
  final Widget? footer;

  /// Purpose: Create state. Inputs: None. Returns: State.
  /// Side effects: None. Notes: None.
  @override
  State<MyAppsOnlineSourceEditorPage> createState() => _EditorState();
}

class _EditorState extends State<MyAppsOnlineSourceEditorPage> {
  late final _name = TextEditingController(text: widget.provider.name);
  late final _endpoint = TextEditingController(text: widget.provider.baseUrl);
  late final _model = TextEditingController(
    text: widget.provider.modelId ?? '',
  );
  final _key = TextEditingController();
  var _hasSavedKey = false;
  var _clearKey = false;
  var _test = OnlineConnectionTestState.idle;
  String? _testMessage;
  String? _endpointError;
  String? _error;
  var _busy = false;

  /// Purpose: Load whether a key is stored; reset tests on edits.
  /// Inputs: None. Returns: None.
  /// Side effects: Reads the secret store; adds listeners. Notes: None.
  @override
  void initState() {
    super.initState();
    if (!widget.isNew) {
      widget.controller.hasKey(widget.provider.id).then((has) {
        if (mounted) setState(() => _hasSavedKey = has);
      });
    }
    for (final c in [_endpoint, _model, _key]) {
      c.addListener(_draftChanged);
    }
  }

  /// Purpose: Dispose controllers. Inputs: None. Returns: None.
  /// Side effects: Frees controllers. Notes: None.
  @override
  void dispose() {
    for (final c in [_name, _endpoint, _model, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Purpose: Forget a test result that no longer describes the draft.
  /// Inputs: None. Returns: None. Side effects: setState. Notes: None.
  void _draftChanged() {
    if (_test == OnlineConnectionTestState.idle && _endpointError == null) {
      return;
    }
    setState(() {
      if (_test != OnlineConnectionTestState.testing) {
        _test = OnlineConnectionTestState.idle;
        _testMessage = null;
      }
      _endpointError = null;
    });
  }

  /// Purpose: Build the provider described by the form.
  /// Inputs: None. Returns: Provider. Side effects: None. Notes: None.
  OnlineProvider _draft() {
    final model = _model.text.trim();
    final name = _name.text.trim();
    return widget.provider.copyWith(
      name: name.isEmpty ? widget.provider.name : name,
      baseUrl: _endpoint.text.trim(),
      modelId: model.isEmpty ? null : model,
      clearModelId: model.isEmpty,
    );
  }

  /// Purpose: Run the explicit connection test.
  /// Inputs: None. Returns: None.
  /// Side effects: One request through the controller; setState.
  /// Notes: The typed key is used when present, otherwise the stored one.
  Future<void> _runTest() async {
    final draft = _draft();
    if (draft.baseUri == null) {
      setState(() => _endpointError = widget.labels.invalidEndpoint);
      return;
    }
    setState(() {
      _test = OnlineConnectionTestState.testing;
      _testMessage = null;
    });
    final key = _key.text.trim();
    GenAiStatusReport report;
    try {
      report = await widget.controller.testConnection(
        draft,
        key.isNotEmpty ? key : (_clearKey ? '' : null),
      );
    } catch (_) {
      report = const GenAiStatusReport(GenAiStatus.unreachable);
    }
    if (!mounted) return;
    setState(() {
      _test = report.status == GenAiStatus.available
          ? OnlineConnectionTestState.success
          : OnlineConnectionTestState.failure;
      _testMessage = widget.labels.testResult(report);
    });
  }

  /// Purpose: Save after any needed privacy confirmation.
  /// Inputs: None. Returns: None.
  /// Side effects: May show the notice; writes through the controller; pops.
  /// Notes: Declining the notice saves nothing.
  Future<void> _save() async {
    final draft = _draft();
    if (draft.baseUri == null) {
      setState(() => _endpointError = widget.labels.invalidEndpoint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final allowed = await ensureOnlinePrivacyAcknowledged(
        context,
        controller: widget.controller,
        provider: draft,
        labels: widget.labels,
      );
      if (!allowed || !mounted) return;
      final key = _key.text.trim();
      await widget.controller.save(
        draft,
        newKey: key.isEmpty ? null : key,
        clearKey: key.isEmpty && _clearKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = widget.labels.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Purpose: Remove after confirmation.
  /// Inputs: None. Returns: None.
  /// Side effects: Dialog; writes through the controller; pops.
  /// Notes: None.
  Future<void> _remove() async {
    if (!await confirmOnlineSourceRemoval(
      context,
      widget.provider.name,
      widget.labels,
    )) {
      return;
    }
    await widget.controller.remove(widget.provider.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Purpose: Render the form. Inputs: `context`. Returns: Scaffold.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: labels.remove,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _remove,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _name,
              decoration: InputDecoration(labelText: labels.name),
            ),
          ),
          widget.fields.endpoint(context, _endpoint, _endpointError),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _model,
              decoration: InputDecoration(labelText: labels.model),
            ),
          ),
          if (widget.provider.needsApiKey)
            widget.fields.secret(
              context,
              _key,
              _hasSavedKey && !_clearKey,
              () => setState(() {
                _clearKey = true;
                _key.clear();
              }),
            ),
          widget.fields.connectionTest(
            context,
            _test,
            _testMessage,
            _busy ? null : _runTest,
          ),
          ?widget.footer,
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(labels.save),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
