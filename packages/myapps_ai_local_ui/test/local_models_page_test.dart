import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_local_ui/myapps_ai_local_ui.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// A controller whose state the test drives and whose commands it records.
class _FakeController implements ModelManagementController {
  /// Purpose: Create with an initial state. Inputs: [state].
  /// Returns: Controller. Side effects: None. Notes: Test helper.
  _FakeController(this._state);

  ModelManagementState _state;
  final _changes = StreamController<ModelManagementState>.broadcast();
  final List<(String, ModelAction)> calls = [];
  Completer<void>? gate;
  Object? throwOnPerform;

  /// Purpose: Current state. Inputs: None. Returns: State.
  /// Side effects: None. Notes: Test helper.
  @override
  ModelManagementState get state => _state;

  /// Purpose: State changes. Inputs: None. Returns: Stream.
  /// Side effects: None. Notes: Test helper.
  @override
  Stream<ModelManagementState> get changes => _changes.stream;

  /// Purpose: Record a command. Inputs: id, action. Returns: Future.
  /// Side effects: Appends to [calls]; may wait on [gate] or throw.
  /// Notes: Test helper.
  @override
  Future<void> perform(String modelId, ModelAction action) async {
    calls.add((modelId, action));
    if (gate != null) await gate!.future;
    if (throwOnPerform != null) throw throwOnPerform!;
  }

  /// Purpose: Push a new state. Inputs: entries. Returns: None.
  /// Side effects: Emits on [changes]. Notes: Test helper.
  void emit(List<ModelCatalogEntry> entries) {
    _state = ModelManagementState(entries: entries);
    _changes.add(_state);
  }
}

/// Purpose: Build a downloadable entry. Inputs: id, state, optional fields.
/// Returns: Entry. Side effects: None. Notes: Test helper.
ModelCatalogEntry _entry(
  String id,
  ModelInstallState state, {
  String capability = 'asr',
  Set<ModelAction>? actions,
  double? progress,
  int? received,
  ArtifactFailure? failure,
}) => ModelCatalogEntry(
  modelId: id,
  artifactId: '$id-artifact',
  capability: capability,
  state: state,
  downloadBytes: 1000,
  progress: progress,
  receivedBytes: received,
  failure: failure,
  actions:
      actions ??
      switch (state) {
        ModelInstallState.notInstalled => {ModelAction.download},
        ModelInstallState.downloading => {ModelAction.cancel},
        ModelInstallState.installed => {ModelAction.verify, ModelAction.remove},
        ModelInstallState.failed => {ModelAction.download, ModelAction.remove},
        _ => const {},
      },
);

final _labels = MyAppsLocalModelLabels(
  modelName: (e) => 'Model ${e.modelId}',
  state: (s) => 'state:${s.name}',
  action: (a) => 'act:${a.name}',
  failure: (f) => 'fail:${f.name}',
  progress: (fraction, received) => fraction == null
      ? 'progress:${received ?? '?'}'
      : 'progress:${(fraction * 100).round()}%',
  systemManaged: 'Managed by the system',
  removeTitle: (name) => 'Remove $name?',
  removeBody:
      'Removes the downloaded files only; your model records and history '
      'are kept.',
  removeConfirm: 'Remove',
  storage: (used, free) => 'used:$used free:$free',
  empty: 'No models',
  actionFailed: 'Something went wrong',
  cancel: 'Cancel',
);

const _groups = [
  MyAppsLocalModelGroup(capability: 'asr', title: 'Speech recognition'),
  MyAppsLocalModelGroup(capability: 'llm', title: 'Text generation'),
];

/// Purpose: Pump the list. Inputs: tester, controller, options.
/// Returns: Completes when pumped. Side effects: Pumps widgets.
/// Notes: Test helper.
Future<void> _pump(
  WidgetTester tester,
  _FakeController controller, {
  String? initialEntryId,
  ValueChanged<String>? onInstalled,
  List<MyAppsLocalModelGroup> groups = _groups,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: MyAppsLocalModelsPage(
          title: 'Local models',
          controller: controller,
          groups: groups,
          labels: _labels,
          formatBytes: (b) => '${b}B',
          initialEntryId: initialEntryId,
          onInstalled: onInstalled,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Purpose: Verify the local-models page against a fake controller.
/// Inputs: None. Returns: None. Side effects: Pumps widgets. Notes: No backend.
void main() {
  testWidgets('actions follow each entry state', (tester) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          _entry('a', ModelInstallState.notInstalled),
          _entry('b', ModelInstallState.installed),
          _entry(
            'c',
            ModelInstallState.failed,
            failure: ArtifactFailure.network,
          ),
        ],
      ),
    );
    await _pump(tester, controller);
    expect(find.text('act:download'), findsNWidgets(2));
    expect(find.text('act:verify'), findsOneWidget);
    expect(find.text('act:remove'), findsNWidgets(2));
    expect(find.text('act:cancel'), findsNothing);
    expect(find.text('act:pauseResume'), findsNothing);
    expect(find.text('fail:network'), findsOneWidget);
    expect(find.text('state:installed · 1000B'), findsOneWidget);

    await tester.tap(find.text('act:download').first);
    await tester.pumpAndSettle();
    expect(controller.calls, [('a', ModelAction.download)]);
  });

  testWidgets('only registered capabilities are shown', (tester) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          _entry('a', ModelInstallState.notInstalled),
          _entry('l', ModelInstallState.notInstalled, capability: 'llm'),
          _entry('d', ModelInstallState.notInstalled, capability: 'diarize'),
        ],
      ),
    );
    await _pump(tester, controller, groups: [_groups.first]);
    expect(find.text('Speech recognition'), findsOneWidget);
    expect(find.text('Text generation'), findsNothing);
    expect(find.text('Model l'), findsNothing);
    expect(find.text('Model d'), findsNothing);
  });

  testWidgets('empty and storage summary', (tester) async {
    final controller = _FakeController(
      const ModelManagementState(usedBytes: 5, freeBytes: 9),
    );
    await _pump(tester, controller);
    expect(find.text('No models'), findsOneWidget);
    expect(find.text('used:5B free:9B'), findsOneWidget);
  });

  testWidgets('remove asks first and states records are kept', (tester) async {
    final controller = _FakeController(
      ModelManagementState(entries: [_entry('b', ModelInstallState.installed)]),
    );
    await _pump(tester, controller);
    await tester.tap(find.text('act:remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Model b?'), findsOneWidget);
    expect(find.textContaining('records and history are kept'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.calls, isEmpty);

    await tester.tap(find.text('act:remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(controller.calls, [('b', ModelAction.remove)]);
  });

  testWidgets('system entry shows supported actions only and a note', (
    tester,
  ) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          ModelCatalogEntry.system(
            modelId: 's',
            capability: 'llm',
            state: ModelInstallState.installed,
            supported: const {ModelAction.remove, ModelAction.verify},
          ),
          ModelCatalogEntry.system(
            modelId: 't',
            capability: 'llm',
            state: ModelInstallState.notInstalled,
            supported: const {ModelAction.download},
          ),
        ],
      ),
    );
    await _pump(tester, controller);
    expect(find.text('Managed by the system'), findsNWidgets(2));
    expect(find.text('act:remove'), findsNothing);
    expect(find.text('act:verify'), findsNothing);
    expect(find.text('act:download'), findsOneWidget);
  });

  testWidgets('progress renders determinate and indeterminate', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          _entry('a', ModelInstallState.downloading, progress: 0.42),
          _entry('b', ModelInstallState.downloading, received: 300),
          _entry(
            'c',
            ModelInstallState.downloading,
            progress: 0.1,
            actions: {ModelAction.cancel, ModelAction.pauseResume},
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MyAppsLocalModelsPage(
          title: 'Local models',
          controller: controller,
          groups: _groups,
          labels: _labels,
          formatBytes: (b) => '${b}B',
        ),
      ),
    );
    await tester.pump();
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars.map((b) => b.value), [0.42, null, 0.1]);
    expect(find.text('progress:42%'), findsOneWidget);
    expect(find.text('progress:300B'), findsOneWidget);
    expect(find.text('act:cancel'), findsNWidgets(3));
    expect(find.text('act:pauseResume'), findsOneWidget);
    expect(find.bySemanticsLabel('progress:42%'), findsOneWidget);
    expect(find.byTooltip('act:cancel'), findsNWidgets(3));
    handle.dispose();
  });

  testWidgets('duplicate taps issue one command', (tester) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [_entry('a', ModelInstallState.notInstalled)],
      ),
    )..gate = Completer<void>();
    await _pump(tester, controller);
    await tester.tap(find.text('act:download'));
    await tester.pump();
    await tester.tap(find.text('act:download'));
    await tester.pump();
    expect(controller.calls, hasLength(1));
    controller.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('action error is shown', (tester) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [_entry('a', ModelInstallState.notInstalled)],
      ),
    )..throwOnPerform = const ArtifactException(ArtifactFailure.diskFull, 'x');
    await _pump(tester, controller);
    await tester.tap(find.text('act:download'));
    await tester.pumpAndSettle();
    expect(find.text('fail:diskFull'), findsOneWidget);
  });

  testWidgets('deep link scrolls to and highlights the entry', (tester) async {
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          for (var i = 0; i < 30; i++)
            _entry('m$i', ModelInstallState.notInstalled),
        ],
      ),
    );
    await _pump(tester, controller, initialEntryId: 'm25');
    final target = find.text('Model m25');
    expect(target.hitTestable(), findsOneWidget);
    final tiles = tester
        .widgetList<MyAppsLocalModelTile>(find.byType(MyAppsLocalModelTile))
        .where((t) => t.highlighted);
    expect(tiles.single.entry.modelId, 'm25');
  });

  testWidgets('onInstalled fires once on transition to installed', (
    tester,
  ) async {
    final installed = <String>[];
    final controller = _FakeController(
      ModelManagementState(
        entries: [
          _entry('a', ModelInstallState.notInstalled),
          _entry('b', ModelInstallState.installed),
        ],
      ),
    );
    await _pump(tester, controller, onInstalled: installed.add);
    controller.emit([
      _entry('a', ModelInstallState.downloading, progress: 0.5),
      _entry('b', ModelInstallState.installed),
    ]);
    await tester.pump();
    controller.emit([
      _entry('a', ModelInstallState.installed),
      _entry('b', ModelInstallState.installed),
    ]);
    await tester.pump();
    controller.emit([
      _entry('a', ModelInstallState.installed),
      _entry('b', ModelInstallState.installed),
    ]);
    await tester.pump();
    expect(installed, ['a']);
    expect(find.text('act:verify'), findsNWidgets(2));
  });

  testWidgets('lays out right-to-left', (tester) async {
    final controller = _FakeController(
      ModelManagementState(entries: [_entry('a', ModelInstallState.installed)]),
    );
    await _pump(tester, controller, direction: TextDirection.rtl);
    final icon = tester.getCenter(find.byIcon(Icons.memory_outlined));
    final name = tester.getCenter(find.text('Model a'));
    expect(icon.dx, greaterThan(name.dx));
  });
}
