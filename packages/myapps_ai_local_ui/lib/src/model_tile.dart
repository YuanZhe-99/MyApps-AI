import 'package:flutter/material.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'labels.dart';

/// Display order of action buttons on a tile.
const List<ModelAction> _actionOrder = [
  ModelAction.download,
  ModelAction.pauseResume,
  ModelAction.cancel,
  ModelAction.verify,
  ModelAction.remove,
];

/// Purpose: Actions a tile offers for [entry], in display order.
/// Inputs: [entry]. Returns: Ordered list of actions.
/// Side effects: None.
/// Notes: System-managed entries never offer verify or remove, even if
/// listed, because their files are not this app's to hash or delete.
List<ModelAction> visibleModelActions(ModelCatalogEntry entry) => [
  for (final action in _actionOrder)
    if (entry.can(action) &&
        !(entry.systemManaged &&
            (action == ModelAction.verify || action == ModelAction.remove)))
      action,
];

/// One model row: name, size, install state, progress, notes, errors and the
/// actions the entry currently allows.
class MyAppsLocalModelTile extends StatelessWidget {
  /// Purpose: Bind one entry.
  /// Inputs: `entry`; `labels`; `formatBytes`; `onAction` — receives the
  /// tapped action; `icon`; `highlighted` — deep-link emphasis; `busy` —
  /// disables all actions while one is in flight; `error` — action error text
  /// from the caller, shown in addition to the entry's own failure.
  /// Returns: A new tile.
  /// Side effects: None.
  /// Notes: Presentation only; the caller performs actions and confirmation.
  const MyAppsLocalModelTile({
    super.key,
    required this.entry,
    required this.labels,
    required this.formatBytes,
    required this.onAction,
    this.icon = Icons.memory_outlined,
    this.highlighted = false,
    this.busy = false,
    this.error,
    this.menu,
  });

  /// Extra controls at the end of the row, such as rename or delete for a
  /// model the user added; null for none.
  final Widget? menu;

  /// Purpose: Entry shown. Inputs: None. Returns: Entry.
  /// Side effects: None. Notes: None.
  final ModelCatalogEntry entry;

  /// Purpose: Wording. Inputs: None. Returns: Labels.
  /// Side effects: None. Notes: None.
  final MyAppsLocalModelLabels labels;

  /// Purpose: Byte formatter. Inputs: None. Returns: Formatter.
  /// Side effects: None. Notes: None.
  final MyAppsByteFormatter formatBytes;

  /// Purpose: Action callback. Inputs: None. Returns: Callback.
  /// Side effects: None. Notes: None.
  final ValueChanged<ModelAction> onAction;

  /// Purpose: Leading icon. Inputs: None. Returns: IconData.
  /// Side effects: None. Notes: None.
  final IconData icon;

  /// Purpose: Whether the tile is emphasised. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: Set for the deep-linked entry.
  final bool highlighted;

  /// Purpose: Whether actions are disabled. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: Duplicate-tap protection.
  final bool busy;

  /// Purpose: Caller-supplied error text. Inputs: None. Returns: String or
  /// null. Side effects: None. Notes: None.
  final String? error;

  /// Purpose: Size shown for the entry.
  /// Inputs: None. Returns: Formatted bytes or null when unknown.
  /// Side effects: None.
  /// Notes: Installed size once installed, otherwise the download size.
  String? get _size {
    final bytes = entry.state == ModelInstallState.installed
        ? entry.installedBytes ?? entry.downloadBytes
        : entry.downloadBytes;
    return bytes == null ? null : formatBytes(bytes);
  }

  /// Purpose: Whether progress is shown. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: None.
  bool get _inProgress =>
      entry.state == ModelInstallState.downloading ||
      entry.state == ModelInstallState.verifying;

  /// Purpose: Render the tile.
  /// Inputs: context. Returns: Widget.
  /// Side effects: None.
  /// Notes: Uses directional geometry so it mirrors under RTL.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = labels.modelName(entry);
    final size = _size;
    final failure = entry.failure;
    final errors = [
      if (failure != null && failure != ArtifactFailure.cancelled)
        labels.failure(failure),
      ?error,
    ];
    final actions = visibleModelActions(entry);
    final received = entry.receivedBytes;
    final progressText = labels.progress(
      entry.progress,
      received == null ? null : formatBytes(received),
    );

    return Semantics(
      container: true,
      selected: highlighted,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: highlighted
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16, top: 2),
              child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(name, style: theme.textTheme.titleMedium),
                      if (labels.badge?.call(entry) case final badge?)
                        Chip(
                          label: Text(badge),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  Text(
                    [labels.state(entry.state), ?size].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.systemManaged)
                    _Note(labels.systemManaged, Icons.info_outline),
                  if (entry.leased && labels.leased != null)
                    _Note(labels.leased!, Icons.lock_outline),
                  if (_inProgress) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      container: true,
                      liveRegion: true,
                      label: progressText,
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: entry.progress),
                            const SizedBox(height: 4),
                            Text(
                              progressText,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  for (final text in errors)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 4),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in actions)
                          _ActionButton(
                            action: action,
                            label: labels.action(action),
                            tooltip:
                                labels.actionTooltip?.call(action, name) ??
                                labels.action(action),
                            onPressed: busy ? null : () => onAction(action),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            ?menu,
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  /// Purpose: Create a small note line. Inputs: text, icon. Returns: Widget.
  /// Side effects: None. Notes: Internal.
  const _Note(this.text, this.icon);

  final String text;
  final IconData icon;

  /// Purpose: Render the note. Inputs: context. Returns: Row.
  /// Side effects: None. Notes: Icon is decorative.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: style?.color),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  /// Purpose: Create one action button.
  /// Inputs: action, label, tooltip, onPressed (null disables).
  /// Returns: Widget. Side effects: None. Notes: Internal.
  const _ActionButton({
    required this.action,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final ModelAction action;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Purpose: Icon per action. Inputs: None. Returns: IconData.
  /// Side effects: None. Notes: None.
  IconData get _icon => switch (action) {
    ModelAction.download => Icons.download_outlined,
    ModelAction.cancel => Icons.close,
    ModelAction.pauseResume => Icons.pause_circle_outline,
    ModelAction.verify => Icons.verified_outlined,
    ModelAction.remove => Icons.delete_outline,
  };

  /// Purpose: Render a tooltip-wrapped button.
  /// Inputs: context. Returns: Widget. Side effects: Calls [onPressed].
  /// Notes: Download is the primary (filled) action.
  @override
  Widget build(BuildContext context) {
    final icon = Icon(_icon);
    final text = Text(label);
    final button = action == ModelAction.download
        ? FilledButton.tonalIcon(onPressed: onPressed, icon: icon, label: text)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: text);
    return Tooltip(message: tooltip, child: button);
  }
}
