import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myapps_ai/myapps_ai.dart';

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
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: Text(label("aiUseOnDevice")),
              subtitle: Text(label("aiUseOnDeviceDesc")),
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
                SwitchListTile(
                  secondary: const SizedBox(width: 24),
                  title: Text(label("aiPreferFast")),
                  subtitle: Text(label("aiPreferFastBody")),
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
