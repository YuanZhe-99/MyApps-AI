/// Whether a cached insight holds text or records a refusal.
enum AiInsightStatus {
  /// The model answered; `lines` holds the text.
  ok,

  /// The model refused (guardrail) or cannot write this language; kept so
  /// the same facts are not retried until they change.
  skipped,
}

/// One cached card.
class AiInsightEntry {
  /// Hex SHA-256 of everything the card depends on.
  final String fingerprint;

  /// The validated sentences, in slot order; empty for [AiInsightStatus.skipped].
  final List<String> lines;

  /// Slot id of each entry in [lines] (e.g. `flowSummary`), so a card can put a
  /// line under the right section when an earlier slot was dropped.
  final List<String> slots;

  /// Text or refusal.
  final AiInsightStatus status;

  /// When it was generated, in UTC.
  final DateTime generatedAt;

  /// The model identity it was generated with, for diagnostics.
  final String? model;

  /// The request language tag, e.g. `zh_CN`.
  final String language;

  /// `insightPromptVersion` at generation time.
  final int promptVersion;

  /// Purpose: Create a cache entry.
  /// Inputs: see fields.
  /// Returns: A new `AiInsightEntry`.
  /// Side effects: None.
  /// Notes: `slots` defaults to empty (no section grouping).
  AiInsightEntry({
    required this.fingerprint,
    required this.lines,
    List<String>? slots,
    required this.status,
    required this.generatedAt,
    this.model,
    required this.language,
    required this.promptVersion,
  }) : slots = slots ?? const [];

  /// Purpose: Serialize the entry.
  /// Inputs: None.
  /// Returns: A JSON map.
  /// Side effects: None.
  /// Notes: `generatedAt` is written in UTC.
  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'language': language,
    'lines': lines,
    if (model != null) 'model': model,
    'promptVersion': promptVersion,
    'slots': slots,
    'status': status.name,
  };

  /// Purpose: Parse an entry.
  /// Inputs: `json`.
  /// Returns: `AiInsightEntry?` — null when malformed.
  /// Side effects: None.
  /// Notes: Tolerant: a bad entry is dropped, not fatal.
  static AiInsightEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final fingerprint = json['fingerprint'];
    final lines = json['lines'];
    final status = AiInsightStatus.values
        .where((s) => s.name == json['status'])
        .firstOrNull;
    final generatedAt = DateTime.tryParse('${json['generatedAt']}');
    if (fingerprint is! String ||
        lines is! List ||
        status == null ||
        generatedAt == null) {
      return null;
    }
    final text = [for (final l in lines) '$l'];
    final rawSlots = json['slots'];
    final slots = rawSlots is List ? [for (final s in rawSlots) '$s'] : null;
    return AiInsightEntry(
      fingerprint: fingerprint,
      lines: text,
      slots: slots != null && slots.length == text.length ? slots : null,
      status: status,
      generatedAt: generatedAt.toUtc(),
      model: json['model'] is String ? json['model'] as String : null,
      language: json['language'] is String ? json['language'] as String : '',
      promptVersion: json['promptVersion'] is int
          ? json['promptVersion'] as int
          : 0,
    );
  }
}
