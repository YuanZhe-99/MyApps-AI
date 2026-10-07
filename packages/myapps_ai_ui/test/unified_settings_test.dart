import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_ui/myapps_ai_ui.dart';

const _labels = AiSourceLabels(
  sourceName: _name,
  readiness: _readiness,
  followGlobal: 'Follow global',
  cancel: 'Cancel',
);

/// Purpose: Name a test option. Inputs: option. Returns: id. Side effects: None.
/// Notes: Test helper.
String _name(AiSourceOption o) => o.id;

/// Purpose: Word readiness. Inputs: readiness. Returns: hint or null.
/// Side effects: None. Notes: Test helper.
String? _readiness(AiSourceReadiness r) =>
    r == AiSourceReadiness.ready ? null : r.name;

/// Purpose: Wrap a widget for testing. Inputs: child. Returns: app.
/// Side effects: None. Notes: Test helper.
Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Purpose: Verify skeleton gating, source picking and clear question.
/// Inputs: None. Returns: None. Side effects: Pumps widgets. Notes: No backend.
void main() {
  testWidgets('disabled skeleton shows only master and data', (tester) async {
    await tester.pumpWidget(
      _app(
        const MyAppsAiSettingsSkeleton(
          enabled: false,
          master: Text('master'),
          source: [Text('source')],
          diagnostics: Text('diag'),
          data: [Text('clear')],
          headings: {MyAppsAiSettingsSection.source: 'Source'},
        ),
      ),
    );
    expect(find.text('master'), findsOneWidget);
    expect(find.text('clear'), findsOneWidget);
    expect(find.text('source'), findsNothing);
    expect(find.text('Source'), findsNothing);
    expect(find.text('diag'), findsNothing);
  });

  testWidgets('enabled skeleton keeps order and omits empty sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MyAppsAiSettingsSkeleton(
          enabled: true,
          master: Text('master'),
          source: [Text('source')],
          diagnostics: Text('diag'),
          headings: {
            MyAppsAiSettingsSection.source: 'Source',
            MyAppsAiSettingsSection.device: 'Device',
          },
        ),
      ),
    );
    expect(find.text('Device'), findsNothing);
    final source = tester.getTopLeft(find.text('source')).dy;
    expect(tester.getTopLeft(find.text('Source')).dy, lessThan(source));
    expect(tester.getTopLeft(find.text('diag')).dy, greaterThan(source));
  });

  testWidgets('choosing an unready source selects it then resolves', (
    tester,
  ) async {
    String? selected = 'system';
    AiSourceOption? resolved;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => MyAppsAiSourcePicker(
            title: 'Model',
            selectedId: selected,
            labels: _labels,
            options: const [
              AiSourceOption(id: 'system', kind: AiSourceKind.system),
              AiSourceOption(
                id: 'local:a',
                kind: AiSourceKind.local,
                readiness: AiSourceReadiness.needsDownload,
              ),
              AiSourceOption(
                id: 'none',
                kind: AiSourceKind.local,
                readiness: AiSourceReadiness.unavailable,
              ),
            ],
            onSelected: (id) => setState(() => selected = id),
            onResolve: (o) => resolved = o,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('none'));
    await tester.pumpAndSettle();
    expect(selected, 'system');
    await tester.tap(find.text('local:a'));
    await tester.pumpAndSettle();
    expect(selected, 'local:a');
    expect(resolved?.id, 'local:a');
    expect(find.text('local:a · needsDownload'), findsOneWidget);
  });

  testWidgets('override picker can follow global', (tester) async {
    String? selected = 'system';
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => MyAppsAiSourcePicker(
            title: 'Proofreading',
            selectedId: selected,
            labels: _labels,
            allowFollowGlobal: true,
            options: const [
              AiSourceOption(id: 'system', kind: AiSourceKind.system),
            ],
            onSelected: (id) => setState(() => selected = id),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Proofreading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow global').last);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Follow global'), findsOneWidget);
  });

  testWidgets('clear question defaults to keep on dismissal', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    const labels = AiClearAfterSwitchLabels(
      title: 'Clear?',
      body: 'Old insights',
      clear: 'Clear',
      keep: 'Keep',
    );
    var answer = confirmClearAfterSourceChange(ctx, labels);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
    answer = confirmClearAfterSourceChange(ctx, labels);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('diagnostics group lines per backend', (tester) async {
    await tester.pumpWidget(
      _app(
        const MyAppsAiDiagnostics(
          title: 'Technical details',
          groups: [
            AiDiagnosticGroup('System', ['status: available']),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('status: available'), findsOneWidget);
  });
}
