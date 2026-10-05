import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';
import 'package:myapps_ai_ui/myapps_ai_ui.dart';

/// Purpose: Check card progress and obsolete text presentation. Inputs: None.
/// Returns: None. Side effects: Pumps widget. Notes: Consumer owns localization.
void main() {
  testWidgets('generating disables refresh and keeps labelled previous text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyAppsAiInsightCard(
            state: AiInsightState(
              phase: AiInsightPhase.generating,
              stale: true,
              entry: AiInsightEntry(
                fingerprint: 'old',
                lines: ['Previous'],
                status: AiInsightStatus.ok,
                generatedAt: DateTime.utc(2026),
                language: 'en',
                promptVersion: 1,
              ),
            ),
            labels: AiInsightLabels(
              aiInsightTitle: 'Insight',
              aiRegenerate: 'Refresh',
              aiInsightSkipped: 'Declined',
              aiGenerating: 'Generating',
              aiQuotaHint: 'Quota',
              aiForegroundHint: 'Foreground',
              aiInsightFailed: 'Failed',
              aiGeneratedLabel: 'On device',
              generatedAt: (time) => time,
            ),
            onRefresh: () {},
          ),
        ),
      ),
    );
    expect(find.text('Previous'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('On device'), findsOneWidget);
  });
}
