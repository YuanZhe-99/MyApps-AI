/// Purpose: Edit one online source: name, endpoint, key, connection test
/// and its models (fetched, chosen, renamed, typed).
/// Inputs: The controller, the record and labels.
/// Returns: [MyAppsOnlineSourceEditor], [MyAppsOnlineSourceEditorPage],
/// [confirmOnlineSourceRemoval].
/// Side effects: Saves through the controller after the privacy notice.
/// Notes: Nothing is sent to a source before its privacy notice is
/// accepted; model lists are fetched only on request, or once right after
/// saving a new source with no models.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';
import 'model_picker.dart';
import 'privacy_dialog.dart';
import 'provider_icon.dart';

/// Purpose: Ask before deleting a source.
/// Inputs: [context], [name], [labels]. Returns: Whether confirmed.
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

/// The editor as a page, for narrow layouts.
class MyAppsOnlineSourceEditorPage extends StatelessWidget {
  /// Purpose: Bind the editor. Inputs: as [MyAppsOnlineSourceEditor], plus
  /// [title]. Returns: Page. Side effects: None.
  /// Notes: Pops `true` after a save or removal.
  const MyAppsOnlineSourceEditorPage({
    super.key,
    required this.title,
    required this.controller,
    required this.provider,
    required this.labels,
    required this.fields,
    this.isNew = false,
    this.footer,
    this.bottomPadding = 0,
  });

  final String title;
  final OnlineSourcesController controller;
  final OnlineProvider provider;
  final bool isNew;
  final MyAppsOnlineLabels labels;
  final MyAppsOnlineFieldBuilders fields;
  final Widget? footer;

  /// Space kept clear below the form.
  final double bottomPadding;

  /// Purpose: Build the page. Inputs: [context]. Returns: Scaffold.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: MyAppsOnlineSourceEditor(
      controller: controller,
      provider: provider,
      labels: labels,
      fields: fields,
      isNew: isNew,
      footer: footer,
      bottomPadding: bottomPadding,
      onDone: () => Navigator.of(context).pop(true),
    ),
  );
}

/// The editor body, shown in a page or in the wide layout's second pane.
class MyAppsOnlineSourceEditor extends StatefulWidget {
  /// Purpose: Bind a record.
  /// Inputs: [controller]; [provider], saved or new; [labels]; [fields],
  /// the application's input widgets; [isNew]; [footer]; [onDone] after a
  /// save or removal. Returns: Widget. Side effects: None. Notes: None.
  const MyAppsOnlineSourceEditor({
    super.key,
    required this.controller,
    required this.provider,
    required this.labels,
    required this.fields,
    required this.onDone,
    this.isNew = false,
    this.footer,
    this.bottomPadding = 0,
  });

  final OnlineSourcesController controller;
  final OnlineProvider provider;
  final bool isNew;
  final MyAppsOnlineLabels labels;
  final MyAppsOnlineFieldBuilders fields;
  final Widget? footer;
  final VoidCallback onDone;

  /// Space kept clear below the form, such as a floating navigation bar.
  final double bottomPadding;

  @override
  State<MyAppsOnlineSourceEditor> createState() => _EditorState();
}

class _EditorState extends State<MyAppsOnlineSourceEditor> {
  late final _name = TextEditingController(text: widget.provider.name);
  late final _endpoint = TextEditingController(text: widget.provider.baseUrl);
  final _key = TextEditingController();
  late List<OnlineModel> _models = [...widget.provider.models];
  late final _template = widget.controller.templates.byId(
    widget.provider.templateId,
  );
  var _hasSavedKey = false;
  var _clearKey = false;
  var _test = OnlineConnectionTestState.idle;
  String? _testMessage;
  String? _endpointError;
  String? _error;
  String? _fetchNote;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isNew) {
      widget.controller.hasKey(widget.provider.id).then((has) {
        if (mounted) setState(() => _hasSavedKey = has);
      });
    }
    for (final c in [_endpoint, _key]) {
      c.addListener(_draftChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _endpoint, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Purpose: Reset a stale test result when the draft changes.
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

  /// Purpose: The record as edited. Inputs: None. Returns: Provider.
  /// Side effects: None. Notes: `modelId` follows the first model.
  OnlineProvider _draft() {
    final name = _name.text.trim();
    return widget.provider.copyWith(
      name: name.isEmpty ? widget.provider.name : name,
      baseUrl: _endpoint.text.trim(),
      models: _models,
      modelId: _models.firstOrNull?.modelName,
      clearModelId: _models.isEmpty,
    );
  }

  /// Purpose: The key to use for a request from the editor.
  /// Inputs: None. Returns: Typed key, `''` when cleared, or null for the
  /// stored one. Side effects: None. Notes: None.
  String? get _requestKey {
    final key = _key.text.trim();
    return key.isNotEmpty ? key : (_clearKey ? '' : null);
  }

  /// Purpose: Run the connection test. Inputs: None. Returns: Completion.
  /// Side effects: One request after the privacy notice. Notes: None.
  Future<void> _runTest() async {
    final draft = _draft();
    if (draft.baseUri == null) {
      setState(() => _endpointError = widget.labels.invalidEndpoint);
      return;
    }
    if (!await _acknowledged(draft)) return;
    setState(() {
      _test = OnlineConnectionTestState.testing;
      _testMessage = null;
    });
    GenAiStatusReport report;
    try {
      report = await widget.controller.testConnection(draft, _requestKey);
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

  /// Purpose: Ask for the privacy notice when needed. Inputs: [draft].
  /// Returns: Whether requests may go to its host.
  /// Side effects: May show the notice. Notes: None.
  Future<bool> _acknowledged(OnlineProvider draft) async {
    final ok = await ensureOnlinePrivacyAcknowledged(
      context,
      controller: widget.controller,
      provider: draft,
      labels: widget.labels,
    );
    return ok && mounted;
  }

  /// Purpose: List the source's models and let the user choose.
  /// Inputs: None. Returns: Completion.
  /// Side effects: One `/models` request after the privacy notice; falls
  /// back to the built-in catalog, marked as such. Notes: None.
  Future<void> _fetch() async {
    final draft = _draft();
    if (draft.baseUri == null) {
      setState(() => _endpointError = widget.labels.invalidEndpoint);
      return;
    }
    if (!await _acknowledged(draft)) return;
    setState(() {
      _busy = true;
      _fetchNote = null;
    });
    List<OnlineModelEntry> entries;
    String? note;
    try {
      entries = await widget.controller.fetchModels(draft, _requestKey);
    } catch (e) {
      final detail = e is GenAiException ? (e.message ?? e.failure.name) : '$e';
      entries = widget.controller.catalogModels(draft);
      note = entries.isEmpty
          ? widget.labels.fetchFailed(detail)
          : '${widget.labels.fetchFailed(detail)}\n${widget.labels.fromCatalog}';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _fetchNote = entries.isEmpty ? note : null;
    });
    if (entries.isEmpty) return;
    final chosen = await showOnlineModelPicker(
      context,
      entries: entries,
      enabled: {for (final m in _models) m.modelName},
      labels: widget.labels,
      note: note,
      vendorHint: draft.name,
    );
    if (chosen == null || !mounted) return;
    final old = {for (final m in _models) m.modelName: m};
    setState(() {
      _models = [
        for (final e in chosen)
          OnlineModel(
            modelName: e.id,
            alias: old[e.id]?.alias,
            displayName: e.displayName,
            vendor: e.vendor,
            contextTokens: e.contextTokens,
            inputModalities: e.inputModalities,
            origin: note == null
                ? OnlineModelOrigin.fetched
                : OnlineModelOrigin.template,
            extra: old[e.id]?.extra ?? const {},
          ),
      ];
    });
  }

  /// Purpose: Add a typed model id. Inputs: None. Returns: Completion.
  /// Side effects: Shows a dialog. Notes: Duplicates are ignored.
  Future<void> _addModel() async {
    final id = await _textDialog(
      title: widget.labels.addModelId,
      hint: widget.labels.modelIdHint,
    );
    if (id == null || id.isEmpty || _models.any((m) => m.modelName == id)) {
      return;
    }
    setState(() => _models = [..._models, OnlineModel(modelName: id)]);
  }

  /// Purpose: Rename a model. Inputs: [m]. Returns: Completion.
  /// Side effects: Shows a dialog. Notes: An empty alias clears it.
  Future<void> _rename(OnlineModel m) async {
    final alias = await _textDialog(
      title: widget.labels.alias,
      hint: widget.labels.aliasHint,
      initial: m.alias ?? '',
      helper: widget.labels.originalId(m.modelName),
    );
    if (alias == null) return;
    setState(() {
      _models = [
        for (final x in _models)
          x.modelName == m.modelName
              ? x.copyWith(alias: alias, clearAlias: alias.isEmpty)
              : x,
      ];
    });
  }

  /// Purpose: Ask for one line of text.
  /// Inputs: [title], [hint], [initial], [helper]. Returns: Trimmed text,
  /// or null when cancelled. Side effects: Shows a dialog.
  /// Notes: The dialog owns its controller, which must outlive the pop
  /// animation.
  Future<String?> _textDialog({
    required String title,
    required String hint,
    String initial = '',
    String? helper,
  }) => showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(
      title: title,
      hint: hint,
      initial: initial,
      helper: helper,
      cancel: widget.labels.cancel,
      save: widget.labels.save,
    ),
  );

  /// Purpose: Save the record. Inputs: None. Returns: Completion.
  /// Side effects: Privacy notice, then writes; for a new source without
  /// models, lists its models once and saves the choice too.
  /// Notes: None.
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
      if (!await _acknowledged(draft)) return;
      final key = _key.text.trim();
      await widget.controller.save(
        draft,
        newKey: key.isEmpty ? null : key,
        clearKey: key.isEmpty && _clearKey,
      );
      final canList =
          !draft.needsApiKey || key.isNotEmpty || (_hasSavedKey && !_clearKey);
      if (_models.isEmpty && canList && mounted) {
        setState(() => _busy = false);
        await _fetch();
        if (_models.isNotEmpty && mounted) {
          await widget.controller.save(_draft());
        }
      }
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _error = widget.labels.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Purpose: Delete the record. Inputs: None. Returns: Completion.
  /// Side effects: Confirms, then removes record and key. Notes: None.
  Future<void> _remove() async {
    if (!await confirmOnlineSourceRemoval(
      context,
      widget.provider.name,
      widget.labels,
    )) {
      return;
    }
    await widget.controller.remove(widget.provider.id);
    if (mounted) widget.onDone();
  }

  /// Purpose: Build the form. Inputs: [context]. Returns: ListView.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final theme = Theme.of(context);
    final template = _template;
    final endpoints = template?.endpoints ?? const <OnlineEndpointOption>[];
    final current = _endpoint.text.trim();
    final draftName = _name.text.trim().isEmpty
        ? widget.provider.name
        : _name.text.trim();
    Widget pad(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    );
    return ListView(
      padding: EdgeInsets.only(top: 8, bottom: 8 + widget.bottomPadding),
      children: [
        ListTile(
          leading: MyAppsProviderIcon(
            iconKey: template?.iconKey,
            name: draftName,
            size: 32,
          ),
          title: Text(
            template == null ? draftName : labels.templateName(template),
          ),
          subtitle: template?.docsUrl == null
              ? null
              : SelectableText('${labels.docs}: ${template!.docsUrl}'),
          trailing: widget.isNew
              ? null
              : IconButton(
                  tooltip: labels.remove,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : _remove,
                ),
        ),
        pad(
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: labels.name),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (endpoints.isNotEmpty)
          pad(
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: endpoints.any((e) => e.url == current)
                  ? current
                  : '',
              decoration: InputDecoration(labelText: labels.endpointLabel),
              items: [
                for (final e in endpoints)
                  DropdownMenuItem(
                    value: e.url,
                    child: Text(
                      e.label == null ? e.host : '${e.label} · ${e.host}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                DropdownMenuItem(value: '', child: Text(labels.customEndpoint)),
              ],
              onChanged: (v) {
                if (v != null && v.isNotEmpty) {
                  setState(() => _endpoint.text = v);
                }
              },
            ),
          ),
        // The application's fields carry no margin of their own; align them
        // with the name field.
        pad(widget.fields.endpoint(context, _endpoint, _endpointError)),
        if (widget.provider.needsApiKey)
          pad(
            widget.fields.secret(
              context,
              _key,
              _hasSavedKey && !_clearKey,
              () => setState(() {
                _clearKey = true;
                _key.clear();
              }),
            ),
          ),
        widget.fields.connectionTest(
          context,
          _test,
          _testMessage,
          _busy ? null : _runTest,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            labels.models,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (_models.isEmpty)
          ListTile(dense: true, title: Text(labels.noModels)),
        for (final m in _models)
          ListTile(
            title: Text(m.name(vendorHint: draftName)),
            subtitle: Text(
              [
                m.modelName,
                if (m.contextTokens case final c?) labels.contextTokens(c),
              ].join('  ·  '),
            ),
            onTap: () => _rename(m),
            trailing: IconButton(
              tooltip: labels.removeModel,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(
                () => _models = [
                  for (final x in _models)
                    if (x.modelName != m.modelName) x,
                ],
              ),
            ),
          ),
        if (_fetchNote case final note?)
          ListTile(leading: const Icon(Icons.info_outline), title: Text(note)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(labels.fetchModels),
                onPressed: _busy ? null : _fetch,
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(labels.addModelId),
                onPressed: _busy ? null : _addModel,
              ),
            ],
          ),
        ),
        ?widget.footer,
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: theme.colorScheme.error),
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
    );
  }
}

/// A one-line text dialog that owns its controller.
class _TextDialog extends StatefulWidget {
  /// Purpose: Bind the dialog. Inputs: texts. Returns: Widget.
  /// Side effects: None. Notes: Internal.
  const _TextDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.cancel,
    required this.save,
    this.helper,
  });
  final String title;
  final String hint;
  final String initial;
  final String? helper;
  final String cancel;
  final String save;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Purpose: Build the dialog. Inputs: [context]. Returns: AlertDialog.
  /// Side effects: None. Notes: Pops the trimmed text on save.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: widget.helper,
      ),
      onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_c.text.trim()),
        child: Text(widget.save),
      ),
    ],
  );
}
