/// Purpose: The source rows of AI settings, shared by every application:
/// the source picker, the local-model and online-source entries and the GPU
/// choice for local models.
/// Inputs: An [AiSourceController] and localized labels.
/// Returns: [MyAppsAiSourceSection] and [AiSourceSectionLabels].
/// Side effects: None beyond the controller calls the user triggers.
/// Notes: Applications keep what differs: pausing their AI service around a
/// switch, clearing old results, and the pages the entries open.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

import 'unified_settings.dart';

/// Localized text for [MyAppsAiSourceSection].
class AiSourceSectionLabels {
  /// Purpose: Bind localized text.
  /// Inputs: [title] of the picker; [automatic] and [system] source names;
  /// [needsPreparation] for sources that need a download or setup; [cancel];
  /// [localModels] and [onlineSources] entry titles; [gpuTitle],
  /// [gpuDescription] and [gpuUnavailable] for the GPU switch.
  /// Returns: Labels. Side effects: None. Notes: None.
  const AiSourceSectionLabels({
    required this.title,
    required this.automatic,
    required this.system,
    required this.needsPreparation,
    required this.cancel,
    required this.localModels,
    required this.onlineSources,
    required this.gpuTitle,
    required this.gpuDescription,
    required this.gpuUnavailable,
  });

  final String title;
  final String automatic;
  final String system;
  final String needsPreparation;
  final String cancel;
  final String localModels;
  final String onlineSources;
  final String gpuTitle;
  final String gpuDescription;
  final String gpuUnavailable;
}

/// Source picker, model entries and GPU choice over an [AiSourceController].
class MyAppsAiSourceSection extends StatelessWidget {
  /// Purpose: Bind the controller.
  /// Inputs: [controller]; [labels]; [onSelected], which applications use to
  /// pause their service and offer to clear old results (the controller's
  /// `select` by default); [onOpenLocalModels] with the model to show, or
  /// null; [onOpenOnlineSources], or null when the application has none;
  /// [sourceIcon] for online options.
  /// Returns: Widget. Side effects: None. Notes: Rebuilds on
  /// `controller.sourceChanges`.
  const MyAppsAiSourceSection({
    super.key,
    required this.controller,
    required this.labels,
    required this.onOpenLocalModels,
    this.onSelected,
    this.onOpenOnlineSources,
    this.sourceIcon,
  });

  final AiSourceController controller;
  final AiSourceSectionLabels labels;
  final Future<void> Function(String id)? onSelected;
  final void Function(String? modelId) onOpenLocalModels;
  final VoidCallback? onOpenOnlineSources;
  final Widget? Function(AiSourceOption option)? sourceIcon;

  /// Purpose: Name a source. Inputs: [o]. Returns: Text.
  /// Side effects: None. Notes: Internal.
  String _name(AiSourceOption o) => switch (o.kind) {
    AiSourceKind.auto => labels.automatic,
    AiSourceKind.system => labels.system,
    _ => controller.sourceName(o.id) ?? o.id,
  };

  /// Purpose: Build the rows. Inputs: [context]. Returns: Column.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.sourceChanges,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MyAppsAiSourcePicker(
          title: labels.title,
          options: controller.sourceOptions,
          selectedId: controller.selection.global,
          labels: AiSourceLabels(
            sourceName: _name,
            sourceDetail: (o) => controller.sourceDetail(o.id),
            sourceIcon: sourceIcon,
            readiness: (r) =>
                r == AiSourceReadiness.ready ? null : labels.needsPreparation,
            followGlobal: labels.automatic,
            cancel: labels.cancel,
          ),
          onSelected: (id) {
            if (id != null) (onSelected ?? controller.select)(id);
          },
          onResolve: (o) => o.kind == AiSourceKind.online
              ? onOpenOnlineSources?.call()
              : onOpenLocalModels(o.id),
        ),
        MyAppsAiManagementEntry(
          title: labels.localModels,
          icon: Icons.folder_outlined,
          onTap: () => onOpenLocalModels(null),
        ),
        if (onOpenOnlineSources case final open?)
          MyAppsAiManagementEntry(
            title: labels.onlineSources,
            icon: Icons.cloud_outlined,
            onTap: open,
          ),
        _GpuSwitch(controller: controller, labels: labels),
      ],
    ),
  );
}

/// The GPU switch for local models.
class _GpuSwitch extends StatefulWidget {
  /// Purpose: Bind the controller. Inputs: [controller], [labels].
  /// Returns: Widget. Side effects: None. Notes: Internal.
  const _GpuSwitch({required this.controller, required this.labels});
  final AiSourceController controller;
  final AiSourceSectionLabels labels;

  @override
  State<_GpuSwitch> createState() => _GpuSwitchState();
}

class _GpuSwitchState extends State<_GpuSwitch> {
  late final Future<bool> _selectable = widget.controller.gpuSelectable();

  /// Purpose: Build the switch. Inputs: [context]. Returns: Tile.
  /// Side effects: None. Notes: Disabled, saying why, where no verified GPU
  /// exists; an already allowed GPU can still be turned off.
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _selectable,
    builder: (context, snapshot) {
      final selectable = snapshot.data ?? false;
      final allowed = widget.controller.gpuAllowed;
      return SwitchListTile(
        secondary: const Icon(Icons.memory_outlined),
        title: Text(widget.labels.gpuTitle),
        subtitle: Text(
          selectable || allowed
              ? widget.labels.gpuDescription
              : widget.labels.gpuUnavailable,
        ),
        value: allowed,
        onChanged: selectable || allowed
            ? widget.controller.setGpuAllowed
            : null,
      );
    },
  );
}
