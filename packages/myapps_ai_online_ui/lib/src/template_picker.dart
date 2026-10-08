/// Purpose: Choose a provider template when adding an online source.
/// Inputs: The registry and labels.
/// Returns: [showOnlineTemplatePicker].
/// Side effects: Shows a full-screen dialog.
/// Notes: A flat, searchable grid sorted by name; never grouped by region.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';
import 'provider_icon.dart';

/// Purpose: Let the user pick a template.
/// Inputs: [context]; [templates]; [labels].
/// Returns: The chosen template, or null when dismissed.
/// Side effects: Pushes a full-screen dialog.
/// Notes: The custom template stays last regardless of the search order.
/// Pushed on the root navigator so an application's bottom navigation bar
/// does not cover it.
Future<OnlineProviderTemplate?> showOnlineTemplatePicker(
  BuildContext context, {
  required OnlineProviderTemplateRegistry templates,
  required MyAppsOnlineLabels labels,
}) => Navigator.of(context, rootNavigator: true).push<OnlineProviderTemplate>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TemplatePicker(templates: templates, labels: labels),
  ),
);

class _TemplatePicker extends StatefulWidget {
  /// Purpose: Bind the picker. Inputs: [templates], [labels].
  /// Returns: Widget. Side effects: None. Notes: Internal.
  const _TemplatePicker({required this.templates, required this.labels});
  final OnlineProviderTemplateRegistry templates;
  final MyAppsOnlineLabels labels;

  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  var _query = '';

  /// Purpose: Build the grid. Inputs: [context]. Returns: Scaffold.
  /// Side effects: None. Notes: Matches name, id and host.
  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = widget.templates.templates;
    final custom = all.where((t) => t.id == openAiCompatibleTemplateId);
    final shown =
        [
          ...(all.where((t) => t.id != openAiCompatibleTemplateId).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            )),
          ...custom,
        ].where((t) {
          if (q.isEmpty) return true;
          final name = widget.labels.templateName(t).toLowerCase();
          return name.contains(q) ||
              t.id.toLowerCase().contains(q) ||
              t.defaultBaseUrl.toLowerCase().contains(q);
        }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.labels.addSourceTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.labels.searchHint,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisExtent: 148,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final t = shown[i];
                final name = widget.labels.templateName(t);
                return Card.outlined(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(t),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MyAppsProviderIcon(
                            iconKey: t.iconKey,
                            name: name,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          if (t.local)
                            Text(
                              widget.labels.localServer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
