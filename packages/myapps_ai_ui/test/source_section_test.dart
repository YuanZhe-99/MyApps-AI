import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_ui/myapps_ai_ui.dart';

const _labels = AiSourceSectionLabels(
  title: 'AI source',
  automatic: 'Automatic',
  system: 'System AI',
  needsPreparation: 'Needs setup',
  cancel: 'Cancel',
  localModels: 'Local models',
  onlineSources: 'Online sources',
  gpuTitle: 'Use GPU',
  gpuDescription: 'Faster local models',
  gpuUnavailable: 'No GPU available',
);

const _diagLabels = AiDiagnosticsLabels(
  title: 'Technical details',
  copy: 'Copy',
  copied: 'Copied',
  notIncluded: 'Not included',
);

/// Purpose: Controller double recording calls. Inputs: configurable state.
/// Returns: A controller. Side effects: None. Notes: Test helper.
class _FakeController implements AiSourceController {
  _FakeController({
    this.options = const [],
    this.global = 'auto',
    this.selectable = true,
    this.gpuAllowed = false,
    this.names = const {},
    this.details = const {},
  });

  final List<AiSourceOption> options;
  String global;
  final bool selectable;
  final Map<String, String> names;
  final Map<String, String> details;
  final ValueNotifier<int> notifier = ValueNotifier(0);
  final List<String> selected = [];
  final List<bool> gpuCalls = [];

  @override
  bool gpuAllowed;

  @override
  Listenable get sourceChanges => notifier;

  @override
  AiSourceSelection get selection => AiSourceSelection(global: global);

  @override
  List<AiSourceOption> get sourceOptions => options;

  @override
  String? sourceName(String id) => names[id];

  @override
  String? sourceDetail(String id) => details[id];

  @override
  Future<void> select(String id) async {
    selected.add(id);
  }

  @override
  Future<bool> gpuSelectable() async => selectable;

  @override
  Future<void> setGpuAllowed(bool allowed) async {
    gpuCalls.add(allowed);
    gpuAllowed = allowed;
    notifier.value++;
  }

  @override
  Future<AiDiagnosticsReport> diagnostics({String? localeTag}) =>
      throw UnimplementedError();
}

const _options = [
  AiSourceOption(id: 'auto', kind: AiSourceKind.auto),
  AiSourceOption(id: 'system', kind: AiSourceKind.system),
  AiSourceOption(
    id: 'local1',
    kind: AiSourceKind.local,
    readiness: AiSourceReadiness.needsDownload,
  ),
  AiSourceOption(id: 'online1', kind: AiSourceKind.online),
  AiSourceOption(
    id: 'online2',
    kind: AiSourceKind.online,
    readiness: AiSourceReadiness.needsConfiguration,
  ),
];

/// Purpose: Build a controller with the shared options. Inputs: overrides.
/// Returns: Controller. Side effects: None. Notes: Test helper.
_FakeController _controller({
  String global = 'auto',
  bool selectable = true,
  bool gpuAllowed = false,
}) => _FakeController(
  options: _options,
  global: global,
  selectable: selectable,
  gpuAllowed: gpuAllowed,
  names: {'local1': 'Qwen Local', 'online1': 'GPT Online', 'online2': 'Other'},
  details: {'online1': 'My provider'},
);

/// Purpose: Wrap a widget for testing. Inputs: child. Returns: app.
/// Side effects: None. Notes: Test helper.
Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Purpose: Pump the section. Inputs: tester, controller, callbacks.
/// Returns: None. Side effects: Pumps. Notes: Test helper.
Future<void> _pumpSection(
  WidgetTester tester,
  _FakeController c, {
  Future<void> Function(String id)? onSelected,
  void Function(String? id)? onLocal,
  VoidCallback? onOnline,
}) async {
  await tester.pumpWidget(
    _app(
      MyAppsAiSourceSection(
        controller: c,
        labels: _labels,
        onSelected: onSelected,
        onOpenLocalModels: onLocal ?? (_) {},
        onOpenOnlineSources: onOnline,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Purpose: Open the picker dialog. Inputs: tester. Returns: None.
/// Side effects: Taps. Notes: Test helper.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.text('AI source'));
  await tester.pumpAndSettle();
}

/// Purpose: Find text inside the open dialog. Inputs: text. Returns: Finder.
/// Side effects: None. Notes: Test helper.
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(SimpleDialog), matching: find.text(text));

/// Purpose: Verify the source section and diagnostics view.
/// Inputs: None. Returns: None. Side effects: Pumps widgets, mocks clipboard.
/// Notes: No backend.
void main() {
  group('source picker row', () {
    testWidgets('automatic and system use labels', (tester) async {
      await _pumpSection(tester, _controller());
      expect(find.text('Automatic'), findsOneWidget);
      final c = _controller(global: 'system');
      await _pumpSection(tester, c);
      expect(find.text('System AI'), findsOneWidget);
    });

    testWidgets('local and online use controller.sourceName', (tester) async {
      await _pumpSection(tester, _controller(global: 'online1'));
      expect(find.text('GPT Online'), findsOneWidget);
      await _pumpSection(tester, _controller(global: 'local1'));
      expect(find.textContaining('Qwen Local'), findsOneWidget);
    });
  });

  group('picker dialog', () {
    testWidgets('lists options and online detail subtitle', (tester) async {
      await _pumpSection(tester, _controller());
      await _openPicker(tester);
      expect(_inDialog('Automatic'), findsOneWidget);
      expect(_inDialog('System AI'), findsOneWidget);
      expect(_inDialog('Qwen Local'), findsOneWidget);
      expect(_inDialog('GPT Online'), findsOneWidget);
      expect(_inDialog('My provider'), findsOneWidget);
    });

    testWidgets('tap calls onSelected when given', (tester) async {
      final c = _controller();
      final got = <String>[];
      await _pumpSection(
        tester,
        c,
        onSelected: (id) async {
          got.add(id);
        },
      );
      await _openPicker(tester);
      await tester.tap(_inDialog('GPT Online'));
      await tester.pumpAndSettle();
      expect(got, ['online1']);
      expect(c.selected, isEmpty);
    });

    testWidgets('tap calls controller.select without onSelected', (
      tester,
    ) async {
      final c = _controller();
      await _pumpSection(tester, c);
      await _openPicker(tester);
      await tester.tap(_inDialog('System AI'));
      await tester.pumpAndSettle();
      expect(c.selected, ['system']);
    });

    testWidgets('needsDownload opens local models with id', (tester) async {
      final c = _controller();
      final opened = <String?>[];
      await _pumpSection(tester, c, onLocal: opened.add);
      await _openPicker(tester);
      await tester.tap(_inDialog('Qwen Local'));
      await tester.pumpAndSettle();
      expect(opened, ['local1']);
      expect(c.selected, ['local1']);
    });

    testWidgets('online needsConfiguration opens online sources', (
      tester,
    ) async {
      var online = 0;
      final local = <String?>[];
      await _pumpSection(
        tester,
        _controller(),
        onLocal: local.add,
        onOnline: () => online++,
      );
      await _openPicker(tester);
      await tester.tap(_inDialog('Other'));
      await tester.pumpAndSettle();
      expect(online, 1);
      expect(local, isEmpty);
    });
  });

  group('entries', () {
    testWidgets('online sources entry absent when callback null', (
      tester,
    ) async {
      await _pumpSection(tester, _controller());
      expect(find.text('Local models'), findsOneWidget);
      expect(find.text('Online sources'), findsNothing);
    });

    testWidgets('online sources entry present and tappable', (tester) async {
      var taps = 0;
      await _pumpSection(tester, _controller(), onOnline: () => taps++);
      await tester.tap(find.text('Online sources'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('local models entry passes null id', (tester) async {
      final opened = <String?>[];
      await _pumpSection(tester, _controller(), onLocal: opened.add);
      await tester.tap(find.text('Local models'));
      await tester.pump();
      expect(opened, [null]);
    });
  });

  group('gpu switch', () {
    testWidgets('disabled with explanation when unavailable', (tester) async {
      final c = _controller(selectable: false);
      await _pumpSection(tester, c);
      expect(find.text('No GPU available'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(c.gpuCalls, isEmpty);
    });

    testWidgets('enabled when selectable and toggles', (tester) async {
      final c = _controller();
      await _pumpSection(tester, c);
      expect(find.text('Faster local models'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(c.gpuCalls, [true]);
    });
  });

  group('diagnostics view', () {
    String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final report = AiDiagnosticsReport([
      AiDiagnosticSection('llama', 'Llama', [
        AiDiagnosticRow('version', '1.2'),
        AiDiagnosticRow('apiKey', 'sk-secret-value'),
      ]),
      const AiDiagnosticSection('system', 'System AI', []),
    ]);

    testWidgets('loads only on expansion and shows sections', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        _app(
          MyAppsAiDiagnosticsView(
            load: () async {
              loads++;
              return report;
            },
            labels: _diagLabels,
          ),
        ),
      );
      expect(loads, 0);
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Llama'), findsOneWidget);
      expect(find.text('System AI'), findsOneWidget);
      expect(
        find.textContaining('version: 1.2', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Not included'), findsOneWidget);
    });

    testWidgets('copy puts plain text without secrets', (tester) async {
      await tester.pumpWidget(
        _app(
          MyAppsAiDiagnosticsView(
            load: () async => report,
            labels: _diagLabels,
          ),
        ),
      );
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('sk-secret-value', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard, contains('[Llama]'));
      expect(clipboard, contains('version: 1.2'));
      expect(clipboard, contains('apiKey: present'));
      expect(clipboard, contains('[System AI]'));
      expect(clipboard, contains('Not included'));
      expect(clipboard, isNot(contains('sk-secret-value')));
      expect(find.text('Copied'), findsOneWidget);
    });
  });
}
