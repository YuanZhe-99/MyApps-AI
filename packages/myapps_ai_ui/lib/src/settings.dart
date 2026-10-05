import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// AI enablement or model-preference control with injected application policy.
class MyAppsAiPreference extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final bool isThreeLine;

  /// Purpose: Bind a common AI preference without owning stored values.
  /// Inputs: Labels, value, callback and presentation options.
  /// Returns: Preference control. Side effects: None.
  /// Notes: Null callback disables the control.
  const MyAppsAiPreference({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.icon = Icons.auto_awesome_outlined,
    this.isThreeLine = false,
  });

  /// Purpose: Render a common AI switch and explanation.
  /// Inputs: context. Returns: Switch tile. Side effects: Forwards changes.
  /// Notes: No service requests during build.
  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Icon(icon),
    title: Text(title),
    subtitle: Text(description),
    value: value,
    onChanged: onChanged,
    isThreeLine: isThreeLine,
  );
}

/// System model ownership and download explanation with optional diagnostics.
class MyAppsAiModelNotes extends StatelessWidget {
  final String downloadNote;
  final String storageNote;
  final String? diagnostic;

  /// Purpose: Bind model ownership explanations and optional diagnostic text.
  /// Inputs: Localized notes and diagnostic. Returns: Notes. Side effects: None.
  /// Notes: Caller controls diagnostic visibility.
  const MyAppsAiModelNotes({
    super.key,
    required this.downloadNote,
    required this.storageNote,
    this.diagnostic,
  });

  /// Purpose: Render shared model explanation spacing and text styles.
  /// Inputs: context. Returns: Padded notes. Side effects: None.
  /// Notes: Describes system-managed models without providing deletion controls.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(downloadNote, style: style),
          const SizedBox(height: 8),
          Text(storageNote, style: style),
          if (diagnostic != null) ...[
            const SizedBox(height: 8),
            Text(
              diagnostic!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Common feature status presentation for capability-specific adapters.
class MyAppsAiCapabilityTile extends StatelessWidget {
  final String title;
  final String statusText;
  final IconData icon;
  final String? diagnostic;
  final Widget? action;

  /// Purpose: Bind a capability status without owning service policy.
  /// Inputs: Localized title/status, icon, diagnostic and action.
  /// Returns: Capability tile. Side effects: None.
  /// Notes: The application decides when diagnostic information is visible.
  const MyAppsAiCapabilityTile({
    super.key,
    required this.title,
    required this.statusText,
    required this.icon,
    this.diagnostic,
    this.action,
  });

  /// Purpose: Render shared capability status and optional diagnostic details.
  /// Inputs: context. Returns: Tile. Side effects: Supplied action only.
  /// Notes: No backend calls occur during build.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (diagnostic != null)
            Text(
              diagnostic!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
      isThreeLine: diagnostic != null,
      trailing: action,
    );
  }
}

/// Common prompt settings presentation with injected application interactions.
class MyAppsAiSettings extends StatelessWidget {
  const MyAppsAiSettings({
    super.key,
    required this.ai,
    required this.enabled,
    required this.preferFast,
    required this.onEnabledChanged,
    required this.onPreferFastChanged,
    required this.label,
    required this.format,
    required this.statusLabel,
    required this.localeTag,
    this.extraTiles = const [],
  });
  final OnDeviceAiService ai;
  final bool enabled;
  final bool preferFast;
  final ValueChanged<bool>? onEnabledChanged;
  final ValueChanged<bool>? onPreferFastChanged;
  final String Function(String) label;
  final String Function(String, String) format;
  final String Function(GenAiStatus) statusLabel;
  final String localeTag;
  final List<Widget> extraTiles;

  /// Purpose: Render model controls. Inputs: context. Returns: Widget.
  /// Side effects: Only supplied callbacks. Notes: Labels and persistence are app-owned.
  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return ListenableBuilder(
      listenable: ai,
      builder: (context, _) {
        final report = ai.report;
        final status = report.status;
        final info = ai.coreInfo;
        final progress = ai.downloadProgress;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MyAppsAiPreference(
              title: label("aiUseOnDevice"),
              description: label("aiUseOnDeviceDesc"),
              value: enabled,
              onChanged: onEnabledChanged,
            ),
            if (enabled) ...[
              ListTile(
                leading: const SizedBox(width: 24),
                title: Text(statusLabel(status)),
                subtitle: status == GenAiStatus.notEnabled
                    ? Text(label("aiTurnOnAppleIntelligence"))
                    : (ai.downloading && progress != null
                          ? Text(
                              format(
                                "aiDownloadedBytes",
                                (progress.bytes / (1024 * 1024))
                                    .toStringAsFixed(1),
                              ),
                            )
                          : null),
                trailing: switch (status) {
                  GenAiStatus.downloadable when isAndroid => FilledButton(
                    onPressed: ai.downloading ? null : ai.download,
                    child: Text(label("aiDownload")),
                  ),
                  GenAiStatus.unavailable ||
                  GenAiStatus.unreachable ||
                  GenAiStatus.notEnabled ||
                  GenAiStatus.unknown ||
                  GenAiStatus.downloading => TextButton(
                    onPressed: () => ai.refreshStatus(localeTag: localeTag),
                    child: Text(label("aiCheckAgain")),
                  ),
                  _ => null,
                },
              ),
              if (isAndroid && report.hasSizeChoice)
                MyAppsAiPreference(
                  icon: Icons.speed_outlined,
                  title: label("aiPreferFast"),
                  description: label("aiPreferFastBody"),
                  value: preferFast,
                  onChanged: onPreferFastChanged,
                ),
              ListTile(
                leading: const SizedBox(width: 24),
                subtitle: Text(
                  isAndroid
                      ? '${label("aiDownloadNote")}\n${label("aiModelStorageNote")}'
                      : label("aiModelAppleNote"),
                ),
              ),
              ExpansionTile(
                leading: const SizedBox(width: 24),
                title: Text(label("aiTechnicalDetails")),
                children: [
                  ListTile(
                    dense: true,
                    title: SelectableText(
                      [
                        'status: ${status.name} (${report.code})',
                        if (report.detail != null) 'detail: ${report.detail}',
                        if (report.variant != null)
                          'variant: ${report.variant}',
                        if (report.served != null) 'served: ${report.served}',
                        if (report.refused != null)
                          'refused: ${report.refused}',
                        if (report.baseModelName != null)
                          'model: ${report.baseModelName}',
                        if (report.tokenLimit != null)
                          'tokenLimit: ${report.tokenLimit}',
                        if (info?.versionName != null)
                          format("aiCoreVersion", info!.versionName!),
                        if (isAndroid && info != null && !info.installed)
                          label("aiCoreMissing"),
                        if (info?.sdk != null) 'sdk: ${info!.sdk}',
                        if (info?.device != null) 'device: ${info!.device}',
                        if (info?.compatible != null)
                          'compatible: ${info!.compatible}',
                        if (info?.osVersion != null) 'os: ${info!.osVersion}',
                        if (info?.localeSupported != null)
                          'localeSupported: ${info!.localeSupported}',
                      ].join('\n'),
                    ),
                  ),
                ],
              ),
              ...extraTiles,
            ],
          ],
        );
      },
    );
  }
}
