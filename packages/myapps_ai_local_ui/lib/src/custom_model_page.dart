/// Purpose: Add a model file from Hugging Face, after an explicit warning.
/// Inputs: A [CustomModelController] and labels.
/// Returns: [MyAppsAddCustomModelPage], [MyAppsCustomModelLabels].
/// Side effects: Lists a repository and reads a file header on request;
/// downloads only after the user accepts the warning.
/// Notes: Custom models are unverified: the warning must be ticked before
/// the download button enables, and it names the detected architecture.
library;

import 'package:flutter/material.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'labels.dart';

/// Localized text for the custom model flow.
class MyAppsCustomModelLabels {
  /// Purpose: Bind localized text. Inputs: every field below.
  /// Returns: Labels. Side effects: None. Notes: None.
  const MyAppsCustomModelLabels({
    required this.title,
    required this.repositoryLabel,
    required this.repositoryHint,
    required this.list,
    required this.noFiles,
    required this.splitUnsupported,
    required this.listFailed,
    required this.warningTitle,
    required this.warningBody,
    required this.architecture,
    required this.storageAndMemory,
    required this.license,
    required this.accept,
    required this.download,
    required this.cancel,
  });

  /// Page title, such as "Add a custom model".
  final String title;

  /// Repository field label.
  final String repositoryLabel;

  /// Repository field hint, such as "owner/name or a huggingface.co link".
  final String repositoryHint;

  /// Button listing the repository's files.
  final String list;

  /// Text when a repository has no GGUF files.
  final String noFiles;

  /// Note on split files, which cannot be used.
  final String splitUnsupported;

  /// Text when listing failed, given the reason identifier.
  final String Function(String reason) listFailed;

  /// Warning dialog title.
  final String warningTitle;

  /// Warning body: not verified; may fail to load or answer badly.
  final String warningBody;

  /// Architecture line, given the detected name (or null) and whether the
  /// built-in runtime lists it (null when unknown).
  final String Function(String? architecture, bool? supported) architecture;

  /// Storage and memory line, given the formatted file size.
  final String Function(String size) storageAndMemory;

  /// License line, given the model card's license id (or null).
  final String Function(String? license) license;

  /// Checkbox the user must tick.
  final String accept;

  /// Button that adds the model and starts its download.
  final String download;

  /// Cancel button.
  final String cancel;
}

/// The custom model page.
class MyAppsAddCustomModelPage extends StatefulWidget {
  /// Purpose: Bind the flow. Inputs: [controller]; [labels];
  /// [formatBytes]. Returns: Page. Side effects: None.
  /// Notes: Pops the new model id after the user accepted the warning.
  const MyAppsAddCustomModelPage({
    super.key,
    required this.controller,
    required this.labels,
    required this.formatBytes,
  });

  final CustomModelController controller;
  final MyAppsCustomModelLabels labels;
  final MyAppsByteFormatter formatBytes;

  @override
  State<MyAppsAddCustomModelPage> createState() => _CustomModelState();
}

class _CustomModelState extends State<MyAppsAddCustomModelPage> {
  final _repo = TextEditingController();
  HuggingFaceRepoListing? _listing;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  /// Purpose: List the typed repository. Inputs: None. Returns: Completion.
  /// Side effects: One request. Notes: None.
  Future<void> _list() async {
    setState(() {
      _busy = true;
      _error = null;
      _listing = null;
    });
    try {
      final listing = await widget.controller.listRepository(_repo.text);
      if (mounted) setState(() => _listing = listing);
    } on ArtifactListingException catch (e) {
      if (mounted) setState(() => _error = widget.labels.listFailed(e.reason));
    } catch (e) {
      if (mounted) setState(() => _error = widget.labels.listFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Purpose: Probe [file], warn, and add it when accepted.
  /// Inputs: [file]. Returns: Completion.
  /// Side effects: One ranged request; may add and start a download.
  /// Notes: None.
  Future<void> _choose(HuggingFaceFile file) async {
    final listing = _listing!;
    setState(() => _busy = true);
    final probe = await widget.controller.probe(listing, file);
    if (!mounted) return;
    setState(() => _busy = false);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => _WarningDialog(
        labels: widget.labels,
        probe: probe,
        size: widget.formatBytes(file.bytes),
        license: listing.license,
      ),
    );
    if (accepted != true || !mounted) return;
    final id = await widget.controller.addCustomModel(listing, file, probe);
    if (mounted) Navigator.of(context).pop(id);
  }

  /// Purpose: Build the page. Inputs: [context]. Returns: Scaffold.
  /// Side effects: None. Notes: None.
  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final listing = _listing;
    return Scaffold(
      appBar: AppBar(title: Text(labels.title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _repo,
              decoration: InputDecoration(
                labelText: labels.repositoryLabel,
                hintText: labels.repositoryHint,
              ),
              onSubmitted: (_) => _busy ? null : _list(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: _busy ? null : _list,
                child: Text(labels.list),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?)
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(error),
            ),
          if (listing != null && listing.files.isEmpty)
            ListTile(title: Text(labels.noFiles)),
          if (listing != null)
            for (final f in listing.files)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(f.path),
                subtitle: Text(
                  f.split
                      ? labels.splitUnsupported
                      : widget.formatBytes(f.bytes),
                ),
                enabled: !f.split && !_busy,
                onTap: () => _choose(f),
              ),
        ],
      ),
    );
  }
}

/// The warning the user must accept before a custom download.
class _WarningDialog extends StatefulWidget {
  /// Purpose: Bind the warning. Inputs: [labels], [probe], [size],
  /// [license]. Returns: Dialog. Side effects: None. Notes: Internal.
  const _WarningDialog({
    required this.labels,
    required this.probe,
    required this.size,
    required this.license,
  });
  final MyAppsCustomModelLabels labels;
  final CustomModelProbe probe;
  final String size;
  final String? license;

  @override
  State<_WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<_WarningDialog> {
  var _accepted = false;

  /// Purpose: Build the dialog. Inputs: [context]. Returns: AlertDialog.
  /// Side effects: None. Notes: Download stays disabled until ticked; an
  /// architecture the runtime does not list is shown in the error color.
  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    final theme = Theme.of(context);
    final supported = widget.probe.supported;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_outlined),
      title: Text(l.warningTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.probe.displayName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.warningBody),
            const SizedBox(height: 8),
            Text(
              l.architecture(widget.probe.architecture, supported),
              style: supported == false
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            Text(l.storageAndMemory(widget.size)),
            Text(l.license(widget.license)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              title: Text(l.accept),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
          child: Text(l.download),
        ),
      ],
    );
  }
}
