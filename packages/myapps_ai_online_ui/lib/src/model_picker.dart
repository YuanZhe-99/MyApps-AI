/// Purpose: Choose which listed models a source enables.
/// Inputs: The listed entries, the currently enabled ids and labels.
/// Returns: [showOnlineModelPicker].
/// Side effects: Shows a full-screen dialog.
/// Notes: Grouped by vendor, searchable; non-chat models are hidden unless
/// the user shows them.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';

/// Purpose: Let the user choose models from a list.
/// Inputs: [context]; [entries]; [enabled], ids already enabled; [labels];
/// [note], such as the from-catalog notice; [vendorHint] for names.
/// Returns: The chosen entries, or null when dismissed.
/// Side effects: Pushes a dialog. Notes: None.
Future<List<OnlineModelEntry>?> showOnlineModelPicker(
  BuildContext context, {
  required List<OnlineModelEntry> entries,
  required Set<String> enabled,
  required MyAppsOnlineLabels labels,
  String? note,
  String? vendorHint,
}) => Navigator.of(context, rootNavigator: true).push<List<OnlineModelEntry>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ModelPicker(
      entries: entries,
      enabled: enabled,
      labels: labels,
      note: note,
      vendorHint: vendorHint,
    ),
  ),
);

/// Purpose: The display name of a listed model.
/// Inputs: [e]; [vendorHint]. Returns: `Vendor: Model`.
/// Side effects: None. Notes: A listed `Vendor: Model` name is kept.
String onlineEntryName(OnlineModelEntry e, {String? vendorHint}) =>
    e.displayName != null && e.displayName!.contains(': ')
    ? e.displayName!
    : friendlyModelName(
        e.id,
        vendor: e.vendor,
        name: e.displayName,
        vendorHint: vendorHint,
      );

class _ModelPicker extends StatefulWidget {
  /// Purpose: Bind the picker. Inputs: see [showOnlineModelPicker].
  /// Returns: Widget. Side effects: None. Notes: Internal.
  const _ModelPicker({
    required this.entries,
    required this.enabled,
    required this.labels,
    this.note,
    this.vendorHint,
  });
  final List<OnlineModelEntry> entries;
  final Set<String> enabled;
  final MyAppsOnlineLabels labels;
  final String? note;
  final String? vendorHint;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  late final Set<String> _chosen = {...widget.enabled};
  var _query = '';
  var _all = false;

  /// Purpose: Build the list. Inputs: [context]. Returns: Scaffold.
  /// Side effects: None. Notes: A chosen non-chat model stays visible.
  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final q = _query.trim().toLowerCase();
    final groups = <String, List<(OnlineModelEntry, String)>>{};
    for (final e in widget.entries) {
      if (!_all && !e.chat && !_chosen.contains(e.id)) continue;
      final name = onlineEntryName(e, vendorHint: widget.vendorHint);
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !e.id.toLowerCase().contains(q)) {
        continue;
      }
      final colon = name.indexOf(': ');
      final vendor = colon > 0 ? name.substring(0, colon) : '';
      (groups[vendor] ??= []).add((e, name));
    }
    final vendors = groups.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(labels.selectModels),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop([
              for (final e in widget.entries)
                if (_chosen.contains(e.id)) e,
            ]),
            child: Text(labels.done),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (widget.note case final note?)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(note),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: labels.searchHint,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SwitchListTile(
            title: Text(labels.showAllModels),
            value: _all,
            onChanged: (v) => setState(() => _all = v),
          ),
          for (final vendor in vendors) ...[
            if (vendor.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  vendor,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            for (final (e, name) in groups[vendor]!)
              CheckboxListTile(
                value: _chosen.contains(e.id),
                onChanged: (v) => setState(
                  () => v == true ? _chosen.add(e.id) : _chosen.remove(e.id),
                ),
                title: Text(name),
                subtitle: Text(
                  [
                    e.id,
                    if (e.contextTokens case final c?) labels.contextTokens(c),
                    if (e.inputModalities.length > 1)
                      e.inputModalities.join(' · '),
                  ].join('  ·  '),
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
