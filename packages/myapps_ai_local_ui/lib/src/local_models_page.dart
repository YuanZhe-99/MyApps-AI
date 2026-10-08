import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'labels.dart';
import 'model_tile.dart';

/// The local-models list: storage summary, capability sections and one tile
/// per registered entry, driven by a [ModelManagementController].
///
/// Usable on its own as a two-pane detail; [MyAppsLocalModelsPage] wraps it
/// in a scaffold for a pushed route.
class MyAppsLocalModelList extends StatefulWidget {
  /// Purpose: Bind the list.
  /// Inputs: `controller` — state and commands; `groups` — registered
  /// capability sections in display order; `labels`; `formatBytes`;
  /// `initialEntryId` — model id to scroll to and highlight (deep link);
  /// `onInstalled` — receives a model id each time its entry changes to
  /// installed; `padding` around the content.
  /// Returns: A new list.
  /// Side effects: None until mounted.
  /// Notes: Entries whose capability has no group are hidden. Nothing
  /// downloads, verifies or removes without an explicit tap; remove asks
  /// first.
  const MyAppsLocalModelList({
    super.key,
    required this.controller,
    required this.groups,
    required this.labels,
    required this.formatBytes,
    this.initialEntryId,
    this.onInstalled,
    this.entryMenu,
    this.padding = const EdgeInsetsDirectional.only(bottom: 16),
  });

  /// Purpose: Model-management controller. Inputs: None.
  /// Returns: Controller. Side effects: None. Notes: None.
  final ModelManagementController controller;

  /// Purpose: Registered capability sections. Inputs: None. Returns: List.
  /// Side effects: None. Notes: Order is display order.
  final List<MyAppsLocalModelGroup> groups;

  /// Purpose: Wording. Inputs: None. Returns: Labels.
  /// Side effects: None. Notes: None.
  final MyAppsLocalModelLabels labels;

  /// Purpose: Byte formatter. Inputs: None. Returns: Formatter.
  /// Side effects: None. Notes: None.
  final MyAppsByteFormatter formatBytes;

  /// Purpose: Deep-linked model id. Inputs: None. Returns: String or null.
  /// Side effects: None. Notes: Unknown ids are ignored.
  final String? initialEntryId;

  /// Purpose: Installed callback. Inputs: None. Returns: Callback or null.
  /// Side effects: None.
  /// Notes: Fires once per transition into installed, never for entries
  /// already installed when the list mounted.
  final ValueChanged<String>? onInstalled;

  /// Extra controls for an entry, such as rename and delete for a model the
  /// user added; null for none.
  final Widget? Function(ModelCatalogEntry entry)? entryMenu;

  /// Purpose: Content padding. Inputs: None. Returns: Insets.
  /// Side effects: None. Notes: None.
  final EdgeInsetsGeometry padding;

  /// Purpose: Create the state. Inputs: None. Returns: State.
  /// Side effects: None. Notes: None.
  @override
  State<MyAppsLocalModelList> createState() => _MyAppsLocalModelListState();
}

class _MyAppsLocalModelListState extends State<MyAppsLocalModelList> {
  late ModelManagementState _state;
  StreamSubscription<ModelManagementState>? _subscription;
  final Set<String> _pending = {};
  final Map<String, String> _errors = {};
  final GlobalKey _highlightKey = GlobalKey();

  /// Purpose: Read the first state, subscribe and schedule the deep-link
  /// scroll. Inputs: None. Returns: None.
  /// Side effects: Subscribes to the controller; posts a frame callback.
  /// Notes: None.
  @override
  void initState() {
    super.initState();
    _bind();
    if (widget.initialEntryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  /// Purpose: Rebind when the controller changes.
  /// Inputs: old widget. Returns: None.
  /// Side effects: Replaces the subscription. Notes: None.
  @override
  void didUpdateWidget(MyAppsLocalModelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _subscription?.cancel();
      _bind();
    }
  }

  /// Purpose: Cancel the subscription. Inputs: None. Returns: None.
  /// Side effects: Cancels the stream subscription. Notes: None.
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Purpose: Take the controller's state and listen for changes.
  /// Inputs: None. Returns: None.
  /// Side effects: Subscribes to [ModelManagementController.changes].
  /// Notes: None.
  void _bind() {
    _state = widget.controller.state;
    _subscription = widget.controller.changes.listen(_onState);
  }

  /// Purpose: Apply a new state and report installs.
  /// Inputs: [next]. Returns: None.
  /// Side effects: Rebuilds; calls `onInstalled` for transitions.
  /// Notes: Compares against the previous state per model id.
  void _onState(ModelManagementState next) {
    if (!mounted) return;
    final previous = _state;
    setState(() => _state = next);
    final onInstalled = widget.onInstalled;
    if (onInstalled == null) return;
    for (final entry in next.entries) {
      if (entry.state != ModelInstallState.installed) continue;
      final before = previous.entryFor(entry.modelId)?.state;
      if (before != ModelInstallState.installed) onInstalled(entry.modelId);
    }
  }

  /// Purpose: Scroll the deep-linked tile into view.
  /// Inputs: None. Returns: None.
  /// Side effects: Scrolls the enclosing scrollable.
  /// Notes: No-op when the entry is not shown.
  void _reveal() {
    final target = _highlightKey.currentContext;
    if (!mounted || target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.3,
      duration: const Duration(milliseconds: 300),
    );
  }

  /// Purpose: Handle a tapped action.
  /// Inputs: [entry], [action]. Returns: Completes when done.
  /// Side effects: May show a dialog; calls the controller; updates errors.
  /// Notes: Taps on an entry with an action in flight are ignored, so a
  /// double tap issues one command.
  Future<void> _perform(ModelCatalogEntry entry, ModelAction action) async {
    final id = entry.modelId;
    if (_pending.contains(id)) return;
    setState(() {
      _pending.add(id);
      _errors.remove(id);
    });
    try {
      if (action == ModelAction.remove && !await _confirmRemove(entry)) {
        return;
      }
      await widget.controller.perform(id, action);
    } on ArtifactException catch (e) {
      if (mounted) _errors[id] = widget.labels.failure(e.failure);
    } catch (_) {
      if (mounted) _errors[id] = widget.labels.actionFailed;
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  /// Purpose: Ask before removing files.
  /// Inputs: [entry]. Returns: Whether the user confirmed.
  /// Side effects: Shows a dialog.
  /// Notes: The body states records and history are kept.
  Future<bool> _confirmRemove(ModelCatalogEntry entry) async {
    final labels = widget.labels;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.removeTitle(labels.modelName(entry))),
        content: Text(labels.removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              labels.cancel ??
                  MaterialLocalizations.of(context).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(labels.removeConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Purpose: Render summary, sections and tiles.
  /// Inputs: context. Returns: Scrollable column.
  /// Side effects: None.
  /// Notes: Every tile is built (lists are short) so the deep-link target
  /// can always be scrolled to.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = widget.labels;
    final children = <Widget>[];
    final used = _state.usedBytes;
    final free = _state.freeBytes;
    if (used != null || free != null) {
      children.add(
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(
            labels.storage(
              used == null ? null : widget.formatBytes(used),
              free == null ? null : widget.formatBytes(free),
            ),
          ),
        ),
      );
    }
    var shown = 0;
    for (final group in widget.groups) {
      final entries = _state.forCapability(group.capability);
      if (entries.isEmpty) continue;
      children.add(_GroupHeading(group.title));
      for (final entry in entries) {
        shown++;
        final highlighted = entry.modelId == widget.initialEntryId;
        children.add(
          MyAppsLocalModelTile(
            key: highlighted ? _highlightKey : ValueKey(entry.modelId),
            entry: entry,
            labels: labels,
            formatBytes: widget.formatBytes,
            icon: group.icon,
            highlighted: highlighted,
            busy: _pending.contains(entry.modelId),
            error: _errors[entry.modelId],
            onAction: (action) => _perform(entry, action),
            menu: widget.entryMenu?.call(entry),
          ),
        );
      }
    }
    if (shown == 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            labels.empty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  /// Purpose: Create a capability heading. Inputs: text. Returns: Widget.
  /// Side effects: None. Notes: Internal.
  const _GroupHeading(this.text);

  final String text;

  /// Purpose: Render the heading in the shared settings style.
  /// Inputs: context. Returns: Padded text. Side effects: None.
  /// Notes: Marked as a header for assistive technology.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "Settings → AI → Local models" as a pushed page.
class MyAppsLocalModelsPage extends StatelessWidget {
  /// Purpose: Bind the page.
  /// Inputs: `title` — app bar title; remaining inputs as
  /// [MyAppsLocalModelList].
  /// Returns: A new page.
  /// Side effects: None.
  /// Notes: In a two-pane layout embed [MyAppsLocalModelList] instead, or
  /// keep this page; it does not assume a full-screen width.
  const MyAppsLocalModelsPage({
    super.key,
    required this.title,
    required this.controller,
    required this.groups,
    required this.labels,
    required this.formatBytes,
    this.initialEntryId,
    this.onInstalled,
  });

  /// Purpose: App bar title. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String title;

  /// Purpose: See [MyAppsLocalModelList.controller]. Inputs: None.
  /// Returns: Controller. Side effects: None. Notes: None.
  final ModelManagementController controller;

  /// Purpose: See [MyAppsLocalModelList.groups]. Inputs: None.
  /// Returns: List. Side effects: None. Notes: None.
  final List<MyAppsLocalModelGroup> groups;

  /// Purpose: See [MyAppsLocalModelList.labels]. Inputs: None.
  /// Returns: Labels. Side effects: None. Notes: None.
  final MyAppsLocalModelLabels labels;

  /// Purpose: See [MyAppsLocalModelList.formatBytes]. Inputs: None.
  /// Returns: Formatter. Side effects: None. Notes: None.
  final MyAppsByteFormatter formatBytes;

  /// Purpose: See [MyAppsLocalModelList.initialEntryId]. Inputs: None.
  /// Returns: String or null. Side effects: None. Notes: None.
  final String? initialEntryId;

  /// Purpose: See [MyAppsLocalModelList.onInstalled]. Inputs: None.
  /// Returns: Callback or null. Side effects: None.
  /// Notes: A caller resuming configuration typically pops here.
  final ValueChanged<String>? onInstalled;

  /// Purpose: Render the scaffolded list.
  /// Inputs: context. Returns: Scaffold. Side effects: None.
  /// Notes: Content respects safe areas.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: MyAppsLocalModelList(
        controller: controller,
        groups: groups,
        labels: labels,
        formatBytes: formatBytes,
        initialEntryId: initialEntryId,
        onInstalled: onInstalled,
      ),
    ),
  );
}
