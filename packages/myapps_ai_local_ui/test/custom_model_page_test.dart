import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_local_ui/myapps_ai_local_ui.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

class _Controller implements CustomModelController {
  Object? listError;
  CustomModelProbe probeResult = const CustomModelProbe(
    displayName: 'Acme: Tiny 1B (Q4_K_M)',
    architecture: 'llama',
    supported: true,
  );
  final listed = <String>[];
  final added = <(HuggingFaceFile, CustomModelProbe)>[];
  var probes = 0;

  final listing = const HuggingFaceRepoListing(
    repo: 'acme/tiny',
    commit: 'c0ffee',
    license: 'apache-2.0',
    files: [
      HuggingFaceFile('tiny-Q4_K_M.gguf', 2048, 'aa'),
      HuggingFaceFile('big-Q8_0-00001-of-00002.gguf', 4096, 'bb'),
    ],
  );

  @override
  Future<HuggingFaceRepoListing> listRepository(String input) async {
    listed.add(input);
    if (listError case final e?) throw e;
    return listing;
  }

  @override
  Future<CustomModelProbe> probe(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
  ) async {
    probes++;
    return probeResult;
  }

  @override
  Future<String> addCustomModel(
    HuggingFaceRepoListing listing,
    HuggingFaceFile file,
    CustomModelProbe probe,
  ) async {
    added.add((file, probe));
    return 'local:hf:${listing.repo}/${file.path}';
  }

  @override
  bool isCustom(String modelId) => false;

  @override
  Future<void> removeCustomModel(String modelId) async {}
}

final _labels = MyAppsCustomModelLabels(
  title: 'Add a custom model',
  repositoryLabel: 'Repository',
  repositoryHint: 'owner/name',
  list: 'List files',
  noFiles: 'No files',
  splitUnsupported: 'Split files are not supported',
  listFailed: (reason) => 'Could not list: $reason',
  warningTitle: 'Unverified model',
  warningBody: 'This model is not verified.',
  architecture: (a, s) => 'arch: ${a ?? '?'} supported: ${s ?? '?'}',
  storageAndMemory: (size) => 'size: $size',
  license: (l) => 'license: ${l ?? 'unknown'}',
  accept: 'I understand',
  download: 'Download',
  cancel: 'Cancel',
);

/// Pushes the page from a home route and records what it pops.
Future<Future<Object?> Function()> _pump(
  WidgetTester tester,
  _Controller c,
) async {
  Object? result;
  var popped = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(error: Colors.red)),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => MyAppsAddCustomModelPage(
                  controller: c,
                  labels: _labels,
                  formatBytes: (b) => '${b}B',
                ),
              ),
            );
            popped = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  return () async => popped ? result : #open;
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _list(WidgetTester tester, [String text = 'acme/tiny']) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('List files'));
  await tester.pumpAndSettle();
}

FilledButton _downloadButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download'));

void main() {
  group('listing', () {
    testWidgets('shows files and disables split parts', (tester) async {
      final c = _Controller();
      await _pump(tester, c);
      await _open(tester);
      expect(find.text('Add a custom model'), findsOneWidget);
      await _list(tester);
      expect(c.listed, ['acme/tiny']);
      expect(find.text('tiny-Q4_K_M.gguf'), findsOneWidget);
      expect(find.text('2048B'), findsOneWidget);
      expect(find.text('big-Q8_0-00001-of-00002.gguf'), findsOneWidget);
      expect(find.text('Split files are not supported'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'big-Q8_0-00001-of-00002.gguf'),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('big-Q8_0-00001-of-00002.gguf'));
      await tester.pumpAndSettle();
      expect(c.probes, 0);
      expect(find.text('Unverified model'), findsNothing);
    });

    testWidgets('shows an empty repository', (tester) async {
      await _pump(tester, _EmptyController());
      await _open(tester);
      await _list(tester);
      expect(find.text('No files'), findsOneWidget);
    });

    testWidgets('shows listFailed with the reason', (tester) async {
      final c = _Controller()
        ..listError = const ArtifactListingException('notFound');
      await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      expect(find.text('Could not list: notFound'), findsOneWidget);
      expect(find.text('tiny-Q4_K_M.gguf'), findsNothing);
    });

    testWidgets('an unexpected error is also reported', (tester) async {
      final c = _Controller()..listError = StateError('boom');
      await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      expect(find.textContaining('Could not list:'), findsOneWidget);
    });
  });

  group('warning', () {
    Future<void> choose(WidgetTester tester) async {
      await tester.tap(find.text('tiny-Q4_K_M.gguf'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the facts and gates the download', (tester) async {
      final c = _Controller();
      final result = await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      await choose(tester);
      expect(c.probes, 1);
      expect(find.text('Unverified model'), findsOneWidget);
      expect(find.text('Acme: Tiny 1B (Q4_K_M)'), findsOneWidget);
      expect(find.text('This model is not verified.'), findsOneWidget);
      expect(find.text('arch: llama supported: true'), findsOneWidget);
      expect(find.text('size: 2048B'), findsOneWidget);
      expect(find.text('license: apache-2.0'), findsOneWidget);
      expect(_downloadButton(tester).onPressed, isNull);

      await tester.tap(find.text('Download'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(c.added, isEmpty);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(_downloadButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(c.added, hasLength(1));
      expect(c.added.single.$1.path, 'tiny-Q4_K_M.gguf');
      expect(c.added.single.$2.displayName, 'Acme: Tiny 1B (Q4_K_M)');
      expect(await result(), 'local:hf:acme/tiny/tiny-Q4_K_M.gguf');
      expect(find.text('Add a custom model'), findsNothing);
    });

    testWidgets('cancel adds nothing and stays on the page', (tester) async {
      final c = _Controller();
      final result = await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      await choose(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.added, isEmpty);
      expect(find.text('Unverified model'), findsNothing);
      expect(find.text('Add a custom model'), findsOneWidget);
      expect(await result(), #open);
    });

    testWidgets('an unsupported architecture is shown as an error', (
      tester,
    ) async {
      final c = _Controller()
        ..probeResult = const CustomModelProbe(
          displayName: 'Acme: Odd (Q4_K_M)',
          architecture: 'mamba9',
          supported: false,
        );
      await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      await choose(tester);
      final text = tester.widget<Text>(
        find.text('arch: mamba9 supported: false'),
      );
      expect(text.style?.color, Colors.red);
    });

    testWidgets('a supported or unknown architecture is not an error', (
      tester,
    ) async {
      final c = _Controller()
        ..probeResult = const CustomModelProbe(displayName: 'Acme: X (Q4_K_M)');
      await _pump(tester, c);
      await _open(tester);
      await _list(tester);
      await choose(tester);
      final text = tester.widget<Text>(find.text('arch: ? supported: ?'));
      expect(text.style?.color, isNot(Colors.red));
    });
  });

  group('local model list', () {
    final entry = ModelCatalogEntry(
      modelId: 'm1',
      artifactId: 'a1',
      capability: 'llm',
      state: ModelInstallState.notInstalled,
      downloadBytes: 10,
      actions: const {ModelAction.download},
    );
    final other = ModelCatalogEntry(
      modelId: 'm2',
      artifactId: 'a2',
      capability: 'llm',
      state: ModelInstallState.notInstalled,
      downloadBytes: 10,
      actions: const {ModelAction.download},
    );

    MyAppsLocalModelLabels labels({bool badge = true}) =>
        MyAppsLocalModelLabels(
          modelName: (e) => 'Model ${e.modelId}',
          state: (s) => s.name,
          action: (a) => a.name,
          failure: (f) => f.name,
          progress: (f, r) => '',
          systemManaged: 'sys',
          removeTitle: (n) => n,
          removeBody: 'body',
          removeConfirm: 'ok',
          storage: (u, f) => '',
          empty: 'none',
          actionFailed: 'failed',
          badge: badge ? (e) => e.modelId == 'm1' ? 'Unverified' : null : null,
        );

    testWidgets('shows the badge and entry menu only where given', (
      tester,
    ) async {
      final controller = _ListController(
        ModelManagementState(entries: [entry, other]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyAppsLocalModelList(
              controller: controller,
              groups: const [
                MyAppsLocalModelGroup(capability: 'llm', title: 'LLM'),
              ],
              labels: labels(),
              formatBytes: (b) => '${b}B',
              entryMenu: (e) =>
                  e.modelId == 'm1' ? const Text('MENU m1') : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'Unverified'), findsOneWidget);
      expect(find.byType(Chip), findsOneWidget);
      expect(find.text('MENU m1'), findsOneWidget);
      expect(find.textContaining('MENU'), findsOneWidget);
    });

    testWidgets('no badge or menu by default', (tester) async {
      final controller = _ListController(
        ModelManagementState(entries: [entry]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyAppsLocalModelList(
              controller: controller,
              groups: const [
                MyAppsLocalModelGroup(capability: 'llm', title: 'LLM'),
              ],
              labels: labels(badge: false),
              formatBytes: (b) => '${b}B',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Chip), findsNothing);
      expect(find.text('Model m1'), findsOneWidget);
    });
  });
}

class _EmptyController extends _Controller {
  @override
  Future<HuggingFaceRepoListing> listRepository(String input) async =>
      const HuggingFaceRepoListing(repo: 'acme/tiny', commit: 'c', files: []);
}

class _ListController implements ModelManagementController {
  _ListController(this._state);
  final ModelManagementState _state;
  @override
  ModelManagementState get state => _state;
  @override
  Stream<ModelManagementState> get changes => const Stream.empty();
  @override
  Future<void> perform(String modelId, ModelAction action) async {}
}
