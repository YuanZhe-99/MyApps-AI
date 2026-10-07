import 'package:flutter/material.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';
import 'editor.dart';

/// "Settings → AI → Online sources": configured providers with their
/// readiness, an add menu from the registered templates, and the editor.
class MyAppsOnlineSourcesPage extends StatefulWidget {
  /// Purpose: Create the page.
  /// Inputs: [title]; [editorTitle]; [controller]; [labels]; [fields];
  /// optional [header] (for example a privacy banner) and [editorFooter].
  /// Returns: Page. Side effects: None.
  /// Notes: To deep-link to one provider, push
  /// [MyAppsOnlineSourceEditorPage] directly.
  const MyAppsOnlineSourcesPage({
    super.key,
    required this.title,
    required this.editorTitle,
    required this.controller,
    required this.labels,
    required this.fields,
    this.header,
    this.editorFooter,
  });

  /// Purpose: Page title. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String title;

  /// Purpose: Editor title. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String editorTitle;

  /// Purpose: Application storage. Inputs: None.
  /// Returns: [OnlineSourcesController]. Side effects: None. Notes: None.
  final OnlineSourcesController controller;

  /// Purpose: Wording. Inputs: None. Returns: [MyAppsOnlineLabels].
  /// Side effects: None. Notes: None.
  final MyAppsOnlineLabels labels;

  /// Purpose: Input widgets for the editor. Inputs: None.
  /// Returns: [MyAppsOnlineFieldBuilders]. Side effects: None. Notes: None.
  final MyAppsOnlineFieldBuilders fields;

  /// Purpose: Optional widget above the list. Inputs: None.
  /// Returns: Widget or null. Side effects: None. Notes: None.
  final Widget? header;

  /// Purpose: Optional editor footer. Inputs: None.
  /// Returns: Widget or null. Side effects: None. Notes: None.
  final Widget? editorFooter;

  /// Purpose: Create state. Inputs: None. Returns: State.
  /// Side effects: None. Notes: None.
  @override
  State<MyAppsOnlineSourcesPage> createState() => _SourcesState();
}

class _SourcesState extends State<MyAppsOnlineSourcesPage> {
  Map<String, bool> _keys = const {};

  /// Purpose: Subscribe and load key presence.
  /// Inputs: None. Returns: None.
  /// Side effects: Adds a listener; reads the secret store. Notes: None.
  @override
  void initState() {
    super.initState();
    widget.controller.changes.addListener(_reload);
    _reload();
  }

  /// Purpose: Unsubscribe. Inputs: None. Returns: None.
  /// Side effects: Removes the listener. Notes: None.
  @override
  void dispose() {
    widget.controller.changes.removeListener(_reload);
    super.dispose();
  }

  /// Purpose: Re-read providers and whether each has a key.
  /// Inputs: None. Returns: None.
  /// Side effects: Reads the secret store; setState.
  /// Notes: Keys themselves are never read here.
  Future<void> _reload() async {
    final providers = widget.controller.providers;
    final keys = {
      for (final p in providers) p.id: await widget.controller.hasKey(p.id),
    };
    if (mounted) setState(() => _keys = keys);
  }

  /// Purpose: Open the editor.
  /// Inputs: [provider], [isNew]. Returns: None.
  /// Side effects: Pushes a route. Notes: None.
  Future<void> _edit(OnlineProvider provider, {bool isNew = false}) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MyAppsOnlineSourceEditorPage(
            title: widget.editorTitle,
            controller: widget.controller,
            provider: provider,
            isNew: isNew,
            labels: widget.labels,
            fields: widget.fields,
            footer: widget.editorFooter,
          ),
        ),
      );

  /// Purpose: Start a provider from a template.
  /// Inputs: [template]. Returns: None.
  /// Side effects: Opens the editor with an unsaved draft.
  /// Notes: A seeded id already present gets a fresh id instead.
  Future<void> _add(OnlineProviderTemplate template) {
    final taken = {for (final p in widget.controller.providers) p.id};
    final seeded = template.seedProviderId;
    final id = seeded != null && !taken.contains(seeded)
        ? seeded
        : widget.controller.newProviderId();
    return _edit(template.create(id: id), isNew: true);
  }

  /// Purpose: Render the list. Inputs: `context`. Returns: Scaffold.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final providers = widget.controller.providers;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<OnlineProviderTemplate>(
            tooltip: labels.add,
            icon: const Icon(Icons.add),
            onSelected: _add,
            itemBuilder: (_) => [
              for (final t in widget.controller.templates.templates)
                PopupMenuItem(value: t, child: Text(labels.templateName(t))),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          ?widget.header,
          if (providers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(labels.empty, textAlign: TextAlign.center),
            ),
          for (final provider in providers)
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(provider.name),
              subtitle: Text(
                labels.status(
                  provider,
                  provider.configurationGaps(
                    _keys[provider.id] ?? false ? 'set' : null,
                  ),
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _edit(provider),
            ),
        ],
      ),
    );
  }
}
