/// Purpose: Structured technical details for AI settings.
/// Inputs: Rows collected from every backend an application includes.
/// Returns: [AiDiagnosticsReport] and its parts.
/// Side effects: None.
/// Notes: Rows carry untranslated identifiers and values (versions, status
/// codes, devices). They never carry prompts, generated text, audio or keys;
/// [AiDiagnosticRow] refuses values under a key that names a secret.
library;

import 'package:flutter/foundation.dart';

/// How a diagnostic row should be read.
enum AiDiagnosticSeverity {
  /// A plain fact.
  info,

  /// Something works but deserves attention, such as a GPU fallback.
  warning,

  /// Something failed; the value says why.
  error,
}

/// One `key: value` line of technical details.
@immutable
class AiDiagnosticRow {
  /// Purpose: Create a row.
  /// Inputs: [key], an untranslated identifier; [value]; [severity].
  /// Returns: Row. Side effects: None.
  /// Notes: A key that names a secret (key, token, secret, password,
  /// authorization) keeps only whether a value exists.
  AiDiagnosticRow(
    this.key,
    Object? value, {
    this.severity = AiDiagnosticSeverity.info,
  }) : value = _redacted(key, value);

  /// Identifier such as `ggml` or `status`.
  final String key;

  /// Value as text; `-` when unknown.
  final String value;

  /// How to read it.
  final AiDiagnosticSeverity severity;

  static final _secret = RegExp(
    r'(^|[^a-z])(api.?key|key|token|secret|password|authorization)$',
    caseSensitive: false,
  );

  /// Purpose: Render [value], hiding secrets.
  /// Inputs: [key], [value]. Returns: Text. Side effects: None.
  /// Notes: Internal.
  static String _redacted(String key, Object? value) {
    if (value == null) return '-';
    if (_secret.hasMatch(key)) {
      return '$value'.isEmpty ? 'absent' : 'present';
    }
    return '$value';
  }

  /// Purpose: Render as one line. Inputs: None. Returns: `key: value`.
  /// Side effects: None. Notes: Errors and warnings are marked.
  @override
  String toString() => switch (severity) {
    AiDiagnosticSeverity.info => '$key: $value',
    AiDiagnosticSeverity.warning => '$key: $value (!)',
    AiDiagnosticSeverity.error => '$key: $value (error)',
  };
}

/// A titled group of rows: one backend, source or subsystem.
@immutable
class AiDiagnosticSection {
  /// Purpose: Create a section.
  /// Inputs: [id], a stable identifier applications may translate; [title]
  /// shown when they do not; [rows]. Returns: Section. Side effects: None.
  /// Notes: An empty [rows] list means "not included in this build".
  const AiDiagnosticSection(this.id, this.title, this.rows);

  /// Stable identifier, such as `systemAi` or `llama.cpp`.
  final String id;

  /// Untranslated title.
  final String title;

  /// Rows in display order.
  final List<AiDiagnosticRow> rows;
}

/// Every section of technical details, for display and copying.
@immutable
class AiDiagnosticsReport {
  /// Purpose: Create a report. Inputs: [sections]. Returns: Report.
  /// Side effects: None. Notes: None.
  const AiDiagnosticsReport(this.sections);

  /// Sections in display order.
  final List<AiDiagnosticSection> sections;

  /// Purpose: The report as plain text for bug reports.
  /// Inputs: [notIncluded], the text for an empty section.
  /// Returns: `[title]` headings followed by their rows.
  /// Side effects: None. Notes: None.
  String toPlainText({String notIncluded = 'not included'}) => [
    for (final s in sections) ...[
      '[${s.title}]',
      if (s.rows.isEmpty) notIncluded,
      for (final r in s.rows) '$r',
      '',
    ],
  ].join('\n').trimRight();
}
