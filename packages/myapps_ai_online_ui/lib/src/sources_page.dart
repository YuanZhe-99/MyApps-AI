/// Purpose: The online sources library: every source with its models,
/// adding from templates, and editing.
/// Inputs: The application's controller, labels and input widgets.
/// Returns: [MyAppsOnlineSourcesPage].
/// Side effects: Navigation; saving goes through the editor.
/// Notes: Same shape as MyTranscribe's source library: sources with their
/// models indented beneath; on wide windows the editor opens beside the
/// list instead of over it.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';
import 'editor.dart';
import 'provider_icon.dart';
import 'template_picker.dart';

/// Width at which the editor opens beside the list.
const _twoPaneWidth = 840.0;

/// Online sources page.
class MyAppsOnlineSourcesPage extends StatefulWidget {
  /// Purpose: Bind the page.
  /// Inputs: [title]; [editorTitle]; [controller]; [labels]; [fields];
  /// [header] above the list; [editorFooter] inside the editor;
  /// [bottomPadding] kept clear below the list and the editor.
  /// Returns: Page. Side effects: None. Notes: None.
  const MyAppsOnlineSourcesPage({
    super.key,
    required this.title,
    required this.editorTitle,
    required this.controller,
    required this.labels,
    required this.fields,
    this.header,
    this.editorFooter,
    this.bottomPadding = 0,
  });

  final String title;
  final String editorTitle;
  final OnlineSourcesController controller;
  final MyAppsOnlineLabels labels;
  final MyAppsOnlineFieldBuilders fields;
  final Widget? header;
  final Widget? editorFooter;

  /// Space to keep clear at the bottom of the list and editor, such as an
  /// application's floating navigation bar.
  final double bottomPadding;

  @override
  State<MyAppsOnlineSourcesPage> createState() => _SourcesState();
}

class _SourcesState extends State<MyAppsOnlineSourcesPage> {
  Map<String, bool> _keys = const {};

  /// The record open in the second pane, and whether it is new.
  (OnlineProvider, bool)? _open;

  @override
  void initState() {
    super.initState();
    widget.controller.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.changes.removeListener(_reload);
    super.dispose();
  }

  /// Purpose: Refresh key presence. Inputs: None. Returns: Completion.
  /// Side effects: Reads the secret store; setState. Notes: None.
  Future<void> _reload() async {
    final providers = widget.controller.providers;
    final keys = {
      for (final p in providers) p.id: await widget.controller.hasKey(p.id),
    };
    if (mounted) setState(() => _keys = keys);
  }

  /// Purpose: Open [provider] in the pane or as a page.
  /// Inputs: [provider], [isNew]. Returns: Completion.
  /// Side effects: Navigation or setState. Notes: None.
  Future<void> _edit(OnlineProvider provider, {bool isNew = false}) async {
    if (MediaQuery.sizeOf(context).width >= _twoPaneWidth) {
      setState(() => _open = (provider, isNew));
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MyAppsOnlineSourceEditorPage(
          title: widget.editorTitle,
          controller: widget.controller,
          provider: provider,
          isNew: isNew,
          labels: widget.labels,
          fields: widget.fields,
          footer: widget.editorFooter,
          bottomPadding: widget.bottomPadding,
        ),
      ),
    );
  }

  /// Purpose: Add a source from a template. Inputs: None.
  /// Returns: Completion. Side effects: Shows the template picker.
  /// Notes: A seeded template reuses its derived id when free.
  Future<void> _add() async {
    final template = await showOnlineTemplatePicker(
      context,
      templates: widget.controller.templates,
      labels: widget.labels,
    );
    if (template == null || !mounted) return;
    final taken = {for (final p in widget.controller.providers) p.id};
    final seeded = template.seedProviderId;
    final id = seeded != null && !taken.contains(seeded)
        ? seeded
        : widget.controller.newProviderId();
    await _edit(template.create(id: id), isNew: true);
  }

  /// Purpose: The list. Inputs: [context]. Returns: ListView.
  /// Side effects: None. Notes: None.
  Widget _list(BuildContext context) {
    final labels = widget.labels;
    final providers = widget.controller.providers;
    final templates = widget.controller.templates;
    final open = _open?.$1.id;
    return ListView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      children: [
        ?widget.header,
        if (providers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(labels.empty, textAlign: TextAlign.center),
          ),
        for (final p in providers) ...[
          ListTile(
            selected: p.id == open,
            leading: MyAppsProviderIcon(
              iconKey: onlineProviderIconKey(p, templates),
              name: p.name,
            ),
            title: Text(p.name),
            subtitle: Text(
              [
                ?p.recipientHost,
                labels.status(
                  p,
                  p.configurationGaps(
                    (_keys[p.id] ?? false) ? 'set' : null,
                    requireModel: false,
                  ),
                ),
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _edit(p),
          ),
          for (final m in p.models)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsetsDirectional.only(
                start: 72,
                end: 16,
              ),
              title: Text(m.name(vendorHint: p.name)),
              subtitle: Text(m.modelName),
              onTap: () => _edit(p),
            ),
        ],
      ],
    );
  }

  /// Purpose: Build the page. Inputs: [context]. Returns: Scaffold.
  /// Side effects: None. Notes: Two panes at [_twoPaneWidth] and wider.
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _twoPaneWidth;
    final open = _open;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: widget.labels.add,
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: !wide
          ? _list(context)
          : Row(
              children: [
                SizedBox(width: 360, child: _list(context)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: open == null
                      ? Center(child: Text(widget.labels.empty))
                      : MyAppsOnlineSourceEditor(
                          key: ValueKey(open.$1.id),
                          controller: widget.controller,
                          provider: open.$1,
                          isNew: open.$2,
                          labels: widget.labels,
                          fields: widget.fields,
                          footer: widget.editorFooter,
                          bottomPadding: widget.bottomPadding,
                          onDone: () => setState(() => _open = null),
                        ),
                ),
              ],
            ),
    );
  }
}
