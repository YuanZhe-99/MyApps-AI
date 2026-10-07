import 'package:flutter/material.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Ordered slots of the unified "Settings → AI" page.
///
/// Every application uses this order and fills only the slots it registers.
/// Slots are plain widgets so the application keeps persistence, navigation
/// and localization; the skeleton owns order, grouping and spacing.
class MyAppsAiSettingsSkeleton extends StatelessWidget {
  /// Purpose: Bind the unified AI settings sections.
  /// Inputs: `master` — the "use AI" switch; `source` — source/model selection;
  /// `features` — per-feature status rows; `device` — run device and fallback;
  /// `localModels`, `onlineSources` — entries to management pages;
  /// `diagnostics` — technical details; `data` — app data actions such as
  /// clearing insights; `enabled` — whether sections after `master` show;
  /// `headings` — optional localized section headings keyed by section.
  /// Returns: A new skeleton.
  /// Side effects: None.
  /// Notes: While disabled only `master` renders, so no section can trigger a
  /// probe, download or network call. `data` stays visible when disabled so
  /// previously generated content can still be cleared.
  const MyAppsAiSettingsSkeleton({
    super.key,
    required this.master,
    required this.enabled,
    this.source = const [],
    this.features = const [],
    this.device = const [],
    this.localModels,
    this.onlineSources,
    this.diagnostics,
    this.data = const [],
    this.headings = const {},
  });

  final Widget master;
  final bool enabled;
  final List<Widget> source;
  final List<Widget> features;
  final List<Widget> device;
  final Widget? localModels;
  final Widget? onlineSources;
  final Widget? diagnostics;
  final List<Widget> data;
  final Map<MyAppsAiSettingsSection, String> headings;

  /// Purpose: Render sections in the fixed order.
  /// Inputs: context. Returns: Column. Side effects: None.
  /// Notes: Empty sections are omitted entirely, headings included.
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[master];
    void add(MyAppsAiSettingsSection section, List<Widget> tiles) {
      if (tiles.isEmpty) return;
      final heading = headings[section];
      if (heading != null) {
        children.add(_Heading(heading));
      }
      children.addAll(tiles);
    }

    if (enabled) {
      add(MyAppsAiSettingsSection.source, source);
      add(MyAppsAiSettingsSection.features, features);
      add(MyAppsAiSettingsSection.device, device);
      add(MyAppsAiSettingsSection.models, [?localModels, ?onlineSources]);
      add(MyAppsAiSettingsSection.diagnostics, [?diagnostics]);
    }
    add(MyAppsAiSettingsSection.data, data);
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Section identifiers for optional headings.
enum MyAppsAiSettingsSection {
  source,
  features,
  device,
  models,
  diagnostics,
  data,
}

class _Heading extends StatelessWidget {
  /// Purpose: Create a section heading. Inputs: text. Returns: Widget.
  /// Side effects: None. Notes: Internal to the skeleton.
  const _Heading(this.text);
  final String text;

  /// Purpose: Render a heading with the theme's primary label style.
  /// Inputs: context. Returns: Padded text. Side effects: None.
  /// Notes: Marked as a header for assistive technology.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Localized text for source selection.
class AiSourceLabels {
  /// Purpose: Bind application-owned wording.
  /// Inputs: `sourceName` — label for an option; `readiness` — subtitle for
  /// an unready option, null when ready; `followGlobal` — the override entry
  /// meaning "use the global choice"; `cancel` — dialog dismiss label.
  /// Returns: Labels. Side effects: None.
  /// Notes: None.
  const AiSourceLabels({
    required this.sourceName,
    required this.readiness,
    required this.followGlobal,
    required this.cancel,
  });

  final String Function(AiSourceOption option) sourceName;
  final String? Function(AiSourceReadiness readiness) readiness;
  final String followGlobal;
  final String cancel;
}

/// A settings row choosing one source, opening a dialog of registered options.
class MyAppsAiSourcePicker extends StatelessWidget {
  /// Purpose: Bind a source choice.
  /// Inputs: `title`; `options` — registered sources; `selectedId`; `labels`;
  /// `onSelected` — receives the chosen id, or null for "follow global";
  /// `allowFollowGlobal` — adds the follow-global entry for overrides;
  /// `onResolve` — invoked for an unready option (deep link to download or
  /// configuration); `icon`; `enabled`.
  /// Returns: A new picker.
  /// Side effects: None.
  /// Notes: Choosing an unready option still selects it, then calls
  /// `onResolve` so the application can navigate; nothing downloads or
  /// connects silently.
  const MyAppsAiSourcePicker({
    super.key,
    required this.title,
    required this.options,
    required this.selectedId,
    required this.labels,
    required this.onSelected,
    this.allowFollowGlobal = false,
    this.onResolve,
    this.icon = Icons.hub_outlined,
    this.enabled = true,
  });

  final String title;
  final List<AiSourceOption> options;
  final String? selectedId;
  final AiSourceLabels labels;
  final ValueChanged<String?> onSelected;
  final bool allowFollowGlobal;
  final ValueChanged<AiSourceOption>? onResolve;
  final IconData icon;
  final bool enabled;

  /// Purpose: Find the selected option.
  /// Inputs: None. Returns: Option or null. Side effects: None.
  /// Notes: A persisted id no longer registered resolves to null.
  AiSourceOption? get _selected {
    for (final o in options) {
      if (o.id == selectedId) return o;
    }
    return null;
  }

  /// Purpose: Render the current choice and open the chooser.
  /// Inputs: context. Returns: ListTile. Side effects: Opens a dialog on tap.
  /// Notes: The subtitle shows the readiness of the chosen source.
  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final name = selected == null
        ? (allowFollowGlobal && selectedId == null ? labels.followGlobal : '—')
        : labels.sourceName(selected);
    final hint = selected == null ? null : labels.readiness(selected.readiness);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(hint == null ? name : '$name · $hint'),
      trailing: const Icon(Icons.arrow_drop_down),
      enabled: enabled,
      onTap: enabled ? () => _choose(context) : null,
    );
  }

  /// Purpose: Show options and apply the choice.
  /// Inputs: context. Returns: None.
  /// Side effects: Calls `onSelected`, then `onResolve` for unready options.
  /// Notes: Dismissing the dialog changes nothing.
  Future<void> _choose(BuildContext context) async {
    const follow = '\u0000follow';
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          if (allowFollowGlobal)
            _OptionTile(
              label: labels.followGlobal,
              selected: selectedId == null,
              onTap: () => Navigator.pop(context, follow),
            ),
          for (final o in options)
            _OptionTile(
              label: labels.sourceName(o),
              hint: labels.readiness(o.readiness),
              selected: o.id == selectedId,
              enabled: o.readiness != AiSourceReadiness.unavailable,
              onTap: () => Navigator.pop(context, o.id),
            ),
        ],
      ),
    );
    if (picked == null) return;
    if (picked == follow) {
      onSelected(null);
      return;
    }
    onSelected(picked);
    final option = options.firstWhere((o) => o.id == picked);
    if (option.readiness == AiSourceReadiness.needsDownload ||
        option.readiness == AiSourceReadiness.needsConfiguration) {
      onResolve?.call(option);
    }
  }
}

class _OptionTile extends StatelessWidget {
  /// Purpose: Create one dialog option. Inputs: label, hint, state, tap.
  /// Returns: Widget. Side effects: None. Notes: Internal to the picker.
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hint,
    this.enabled = true,
  });
  final String label;
  final String? hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Purpose: Render a selectable option with a check mark.
  /// Inputs: context. Returns: ListTile. Side effects: Supplied tap.
  /// Notes: Selection is exposed to assistive technology.
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(label),
      subtitle: hint == null ? null : Text(hint!),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    ),
  );
}

/// One backend's diagnostic lines inside technical details.
class AiDiagnosticGroup {
  /// Purpose: Describe a diagnostic group.
  /// Inputs: `title` — backend or source name; `lines` — untranslated
  /// identifiers such as status codes, versions and actual run device.
  /// Returns: A group. Side effects: None.
  /// Notes: Never include prompts, audio, generated text or API keys.
  const AiDiagnosticGroup(this.title, this.lines);
  final String title;
  final List<String> lines;
}

/// Collapsed technical details, grouped by backend.
class MyAppsAiDiagnostics extends StatelessWidget {
  /// Purpose: Bind technical details.
  /// Inputs: `title`; `groups`.
  /// Returns: Expansion tile. Side effects: None.
  /// Notes: The application decides whether to show it at all.
  const MyAppsAiDiagnostics({
    super.key,
    required this.title,
    required this.groups,
  });
  final String title;
  final List<AiDiagnosticGroup> groups;

  /// Purpose: Render selectable diagnostic text per group.
  /// Inputs: context. Returns: ExpansionTile. Side effects: None.
  /// Notes: Monospace so identifiers can be copied into bug reports.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: const Icon(Icons.memory_outlined),
      title: Text(title),
      children: [
        for (final g in groups)
          ListTile(
            dense: true,
            title: Text(g.title, style: theme.textTheme.labelLarge),
            subtitle: SelectableText(
              g.lines.join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}

/// Localized text for the clear-after-switch question.
class AiClearAfterSwitchLabels {
  /// Purpose: Bind wording. Inputs: title, body, clear, keep.
  /// Returns: Labels. Side effects: None. Notes: None.
  const AiClearAfterSwitchLabels({
    required this.title,
    required this.body,
    required this.clear,
    required this.keep,
  });
  final String title;
  final String body;
  final String clear;
  final String keep;
}

/// Purpose: Ask whether to clear content generated by the previous source.
/// Inputs: `context`, `labels`.
/// Returns: `Future<bool>` — true to clear; false to keep, including dismissal.
/// Side effects: Shows a dialog.
/// Notes: Callers ask once per source change, only when affected features
/// (see `featuresWithChangedSource`) have stored generated content. Keeping is
/// the safe default.
Future<bool> confirmClearAfterSourceChange(
  BuildContext context,
  AiClearAfterSwitchLabels labels,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.title),
        content: Text(labels.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(labels.keep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(labels.clear),
          ),
        ],
      ),
    ) ??
    false;

/// An entry row opening a management page (local models, online sources).
class MyAppsAiManagementEntry extends StatelessWidget {
  /// Purpose: Bind a navigation row.
  /// Inputs: `title`, `subtitle`, `icon`, `onTap`, `selected` for two-pane.
  /// Returns: ListTile. Side effects: None.
  /// Notes: The application owns the route.
  const MyAppsAiManagementEntry({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  /// Purpose: Render the entry with a chevron.
  /// Inputs: context. Returns: ListTile. Side effects: Supplied tap.
  /// Notes: None.
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    selected: selected,
    onTap: onTap,
  );
}
