import 'package:flutter/material.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// A titled group of insight lines inside a card.
class AiInsightSection {
  /// The section heading.
  final String title;

  /// The slot ids whose lines belong here.
  final Set<String> slotIds;

  /// Purpose: Create a section.
  /// Inputs: `title`, `slotIds`.
  /// Returns: A new `AiInsightSection`.
  /// Side effects: None.
  /// Notes: Lines whose slot is in no section are shown first, ungrouped.
  const AiInsightSection(this.title, this.slotIds);
}

/// Application-owned localized labels.
class AiInsightLabels {
  const AiInsightLabels({
    required this.aiInsightTitle,
    required this.aiRegenerate,
    required this.aiInsightSkipped,
    required this.aiGenerating,
    required this.aiQuotaHint,
    required this.aiForegroundHint,
    required this.aiInsightFailed,
    required this.aiGeneratedLabel,
    required this.generatedAt,
  });
  final String aiInsightTitle;
  final String aiRegenerate;
  final String aiInsightSkipped;
  final String aiGenerating;
  final String aiQuotaHint;
  final String aiForegroundHint;
  final String aiInsightFailed;
  final String aiGeneratedLabel;
  final String Function(String) generatedAt;
}

/// Shared insight presentation; application owns request scheduling and routes.
class MyAppsAiInsightCard extends StatelessWidget {
  const MyAppsAiInsightCard({
    super.key,
    required this.state,
    required this.labels,
    required this.onRefresh,
    this.subtitle,
    this.sections = const [],
    this.compact = false,
    this.expanded = false,
    this.onToggle,
    this.footnote,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });
  final AiInsightState state;
  final AiInsightLabels labels;
  final VoidCallback? onRefresh;
  final String? subtitle;
  final List<AiInsightSection> sections;
  final bool compact;
  final bool expanded;
  final VoidCallback? onToggle;
  final String? footnote;
  final EdgeInsetsGeometry margin;

  /// Purpose: Render shared states. Inputs: context. Returns: Widget.
  /// Side effects: None until callbacks. Notes: No business data or routes.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generating = state.phase == AiInsightPhase.generating;
    final entry = state.entry;
    final dim = generating || state.stale;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final header = Row(
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: labels.aiInsightTitle,
              children: [
                if (subtitle != null)
                  TextSpan(
                    text: ' · $subtitle',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: labels.aiRegenerate,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: generating ? null : onRefresh,
        ),
        if (compact)
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );

    final body = <Widget>[];
    if (entry != null && entry.status == AiInsightStatus.skipped) {
      body.add(Text(labels.aiInsightSkipped, style: muted));
    } else if (entry != null && entry.lines.isNotEmpty) {
      final lineStyle = theme.textTheme.bodyMedium?.copyWith(
        color: dim
            ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
            : theme.colorScheme.onSurface,
      );
      final lines = [
        for (var i = 0; i < entry.lines.length; i++)
          (i < entry.slots.length ? entry.slots[i] : '', entry.lines[i]),
      ];
      final sectioned = {for (final s in sections) ...s.slotIds};
      Widget bullet(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: lineStyle),
            Expanded(child: Text(text, style: lineStyle)),
          ],
        ),
      );
      if (compact && !expanded) {
        body.add(
          Text(
            lines.first.$2,
            style: lineStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else {
        for (final (slot, text) in lines) {
          if (!sectioned.contains(slot)) body.add(bullet(text));
        }
        for (final section in sections) {
          final own = [
            for (final (slot, text) in lines)
              if (section.slotIds.contains(slot)) text,
          ];
          if (own.isEmpty) continue;
          body
            ..add(const SizedBox(height: 8))
            ..add(
              Text(
                section.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
            ..addAll(own.map(bullet));
        }
      }
    } else if (state.phase != AiInsightPhase.failed) {
      body.add(Text(labels.aiGenerating, style: muted));
    }

    if (state.phase == AiInsightPhase.failed) {
      final hint = switch (state.failure) {
        GenAiFailure.quota => labels.aiQuotaHint,
        GenAiFailure.background => labels.aiForegroundHint,
        _ => labels.aiInsightFailed,
      };
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(hint, style: muted),
        ),
      );
    }

    final showDetails = !compact || expanded;
    if (showDetails && footnote != null && entry != null) {
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(footnote!, style: muted),
        ),
      );
    }
    if (showDetails && entry != null && entry.status == AiInsightStatus.ok) {
      final time = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(entry.generatedAt.toLocal()));
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${labels.aiGeneratedLabel} · ${labels.generatedAt(time)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: compact ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
              child: header,
            ),
          ),
          SizedBox(
            height: 2,
            child: generating
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: body,
            ),
          ),
        ],
      ),
    );
  }
}
