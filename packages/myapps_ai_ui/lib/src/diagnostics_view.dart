/// Purpose: Technical details as collapsed, copyable sections.
/// Inputs: A loader for an [AiDiagnosticsReport] and localized labels.
/// Returns: [MyAppsAiDiagnosticsView], [AiDiagnosticsLabels].
/// Side effects: Loads the report when expanded; copies to the clipboard.
/// Notes: Rows are untranslated identifiers; only titles and buttons are
/// localized.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Localized text for [MyAppsAiDiagnosticsView].
class AiDiagnosticsLabels {
  /// Purpose: Bind localized text.
  /// Inputs: [title]; [copy] button; [copied] confirmation; [notIncluded]
  /// for a backend this build lacks; [sectionTitle] to translate section ids
  /// (null keeps the untranslated title).
  /// Returns: Labels. Side effects: None. Notes: None.
  const AiDiagnosticsLabels({
    required this.title,
    required this.copy,
    required this.copied,
    required this.notIncluded,
    this.sectionTitle,
  });

  final String title;
  final String copy;
  final String copied;
  final String notIncluded;
  final String? Function(AiDiagnosticSection section)? sectionTitle;
}

/// Every section of technical details, loaded on expansion.
class MyAppsAiDiagnosticsView extends StatefulWidget {
  /// Purpose: Bind the loader. Inputs: [load], usually the source
  /// controller's `diagnostics`; [labels]. Returns: Widget.
  /// Side effects: None until expanded. Notes: Collapsing and expanding
  /// again reloads, so the details are current.
  const MyAppsAiDiagnosticsView({
    super.key,
    required this.load,
    required this.labels,
  });

  final Future<AiDiagnosticsReport> Function() load;
  final AiDiagnosticsLabels labels;

  @override
  State<MyAppsAiDiagnosticsView> createState() =>
      _MyAppsAiDiagnosticsViewState();
}

class _MyAppsAiDiagnosticsViewState extends State<MyAppsAiDiagnosticsView> {
  Future<AiDiagnosticsReport>? _report;

  /// Purpose: Name a section. Inputs: [s]. Returns: Text.
  /// Side effects: None. Notes: Internal.
  String _title(AiDiagnosticSection s) =>
      widget.labels.sectionTitle?.call(s) ?? s.title;

  /// Purpose: Copy [report] as text. Inputs: [report]. Returns: None.
  /// Side effects: Writes the clipboard; shows a snack bar. Notes: Internal.
  Future<void> _copy(AiDiagnosticsReport report) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(
      ClipboardData(
        text: AiDiagnosticsReport([
          for (final s in report.sections)
            AiDiagnosticSection(s.id, _title(s), s.rows),
        ]).toPlainText(notIncluded: widget.labels.notIncluded),
      ),
    );
    messenger?.showSnackBar(SnackBar(content: Text(widget.labels.copied)));
  }

  /// Purpose: Build the tile. Inputs: [context]. Returns: ExpansionTile.
  /// Side effects: Starts loading on expansion. Notes: None.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ExpansionTile(
      leading: const Icon(Icons.memory_outlined),
      title: Text(widget.labels.title),
      onExpansionChanged: (open) {
        setState(() {
          _report = open ? widget.load() : null;
        });
      },
      children: [
        FutureBuilder<AiDiagnosticsReport>(
          future: _report,
          builder: (context, snapshot) {
            final report = snapshot.data;
            if (report == null) {
              return snapshot.hasError
                  ? ListTile(title: Text('${snapshot.error}'))
                  : const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(widget.labels.copy),
                    onPressed: () => _copy(report),
                  ),
                ),
                for (final s in report.sections)
                  ListTile(
                    dense: true,
                    title: Text(_title(s), style: theme.textTheme.labelLarge),
                    subtitle: s.rows.isEmpty
                        ? Text(widget.labels.notIncluded)
                        : SelectableText.rich(
                            TextSpan(
                              children: [
                                for (final (i, r) in s.rows.indexed)
                                  TextSpan(
                                    text: '${i == 0 ? '' : '\n'}$r',
                                    style: switch (r.severity) {
                                      AiDiagnosticSeverity.error => TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                      AiDiagnosticSeverity.warning => TextStyle(
                                        color: theme.colorScheme.tertiary,
                                      ),
                                      AiDiagnosticSeverity.info => null,
                                    },
                                  ),
                              ],
                            ),
                            style: mono,
                          ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
