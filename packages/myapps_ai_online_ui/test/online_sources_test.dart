import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';
import 'package:myapps_ai_online_ui/myapps_ai_online_ui.dart';

class _FakeController implements OnlineSourcesController {
  _FakeController(this.providers, {OnlineProviderTemplateRegistry? templates})
    : templates = templates ?? OnlineProviderTemplateRegistry.builtIn();

  @override
  List<OnlineProvider> providers;

  final keys = <String, String>{};
  final acks = <String, OnlinePrivacyAcknowledgement>{};
  final saved = <({OnlineProvider provider, String? key, bool clear})>[];
  final removed = <String>[];
  final tested = <({OnlineProvider draft, String? key})>[];
  final fetchCalls = <({OnlineProvider draft, String? key})>[];
  List<OnlineModelEntry> fetchResult = const [];
  Object? fetchError;
  List<OnlineModelEntry> catalog = const [];
  final _changes = ChangeNotifier();
  var _next = 0;

  @override
  Listenable get changes => _changes;

  @override
  final OnlineProviderTemplateRegistry templates;

  @override
  String newProviderId() => 'provider:new${_next++}';

  @override
  Future<bool> hasKey(String providerId) async => keys.containsKey(providerId);

  @override
  Future<void> save(
    OnlineProvider provider, {
    String? newKey,
    bool clearKey = false,
  }) async {
    saved.add((provider: provider, key: newKey, clear: clearKey));
    if (newKey != null) keys[provider.id] = newKey;
    if (clearKey) keys.remove(provider.id);
    providers = [
      for (final p in providers)
        if (p.id != provider.id) p,
      provider,
    ];
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    _changes.notifyListeners();
  }

  @override
  Future<void> remove(String providerId) async {
    removed.add(providerId);
    providers = [
      for (final p in providers)
        if (p.id != providerId) p,
    ];
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    _changes.notifyListeners();
  }

  @override
  Future<GenAiStatusReport> testConnection(
    OnlineProvider draft,
    String? draftKey,
  ) async {
    tested.add((draft: draft, key: draftKey));
    return const GenAiStatusReport(GenAiStatus.available, detail: 'models:3');
  }

  @override
  OnlinePrivacyNotice? privacyNotice(OnlineProvider provider) =>
      OnlinePrivacyNotice.forProvider(
        version: 1,
        host: provider.recipientHost,
        providerName: provider.name,
        sent: const [OnlineDataItem(OnlineDataCategory.promptText)],
      );

  @override
  Future<OnlinePrivacyAcknowledgement?> acknowledgement(
    String providerId,
  ) async => acks[providerId];

  @override
  Future<void> acknowledge(
    String providerId,
    OnlinePrivacyAcknowledgement record,
  ) async => acks[providerId] = record;

  @override
  Future<List<OnlineModelEntry>> fetchModels(
    OnlineProvider draft,
    String? draftKey,
  ) async {
    fetchCalls.add((draft: draft, key: draftKey));
    if (fetchError case final e?) throw e;
    return fetchResult;
  }

  @override
  List<OnlineModelEntry> catalogModels(OnlineProvider provider) => catalog;
}

final _labels = MyAppsOnlineLabels(
  empty: 'No sources',
  add: 'Add',
  templateName: (t) => 'From ${t.name}',
  status: (p, gaps) =>
      gaps.isEmpty ? 'Ready' : 'Missing ${gaps.map((g) => g.name).join(',')}',
  remove: 'Remove',
  removeTitle: (name) => 'Remove $name?',
  removeBody: 'The key is deleted too.',
  removeConfirm: 'Delete',
  cancel: 'Cancel',
  name: 'Name',
  model: 'Model',
  save: 'Save',
  saveFailed: 'Could not save',
  invalidEndpoint: 'Bad URL',
  testResult: (r) => 'Result ${r.status.name}',
  privacyTitle: 'Before you enable',
  privacyIntro: (host, name) => 'Sent to $host',
  dataItem: (item) => 'Item ${item.category.name}',
  keySync: (rule) => 'Keys ${rule.name}',
  onlyWhenSelected: 'Only when chosen',
  privacyConfirm: 'Enable',
  addSourceTitle: 'Add a source',
  searchHint: 'Search',
  endpointLabel: 'Service',
  customEndpoint: 'Other address',
  docs: 'Docs',
  models: 'Models',
  noModels: 'No models yet',
  fetchModels: 'Fetch models',
  fetchFailed: (detail) => 'Failed: $detail',
  fromCatalog: 'Shown from the built-in catalog',
  addModelId: 'Add model id',
  modelIdHint: 'Model id',
  alias: 'Alias',
  aliasHint: 'Friendly name',
  originalId: (id) => 'Original: $id',
  showAllModels: 'Show all',
  contextTokens: (n) => '$n tokens',
  selectModels: 'Select models',
  done: 'Done',
  removeModel: 'Remove model',
  localServer: 'Local',
);

final _fields = MyAppsOnlineFieldBuilders(
  endpoint: (context, controller, error) => TextField(
    key: const Key('endpoint'),
    controller: controller,
    decoration: InputDecoration(errorText: error),
  ),
  secret: (context, controller, saved, onClear) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const Key('key'),
          controller: controller,
          decoration: InputDecoration(hintText: saved ? 'saved' : 'none'),
        ),
      ),
      IconButton(
        key: const Key('clear'),
        onPressed: onClear,
        icon: const Icon(Icons.clear),
      ),
    ],
  ),
  connectionTest: (context, state, message, onTest) => ListTile(
    title: Text('state ${state.name}'),
    subtitle: message == null ? null : Text(message),
    trailing: TextButton(onPressed: onTest, child: const Text('Test')),
  ),
);

Widget _page(_FakeController c) => MaterialApp(
  home: MyAppsOnlineSourcesPage(
    title: 'Online',
    editorTitle: 'Edit',
    controller: c,
    labels: _labels,
    fields: _fields,
  ),
);

OnlinePrivacyAcknowledgement _ack(String host) => OnlinePrivacyAcknowledgement(
  noticeVersion: 1,
  acknowledgedAt: DateTime.utc(2026),
  recipientHost: host,
);

OnlineProvider _openAi({String? model = 'gpt'}) =>
    openAiTemplate.create(modelId: model);

void main() {
  testWidgets('lists providers with readiness and an empty state', (
    tester,
  ) async {
    final c = _FakeController([]);
    await tester.pumpWidget(_page(c));
    expect(find.text('No sources'), findsOneWidget);

    c.providers = [_openAi()];
    c.keys['provider:openai'] = 'k';
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    (c.changes as ChangeNotifier).notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('OpenAI'), findsOneWidget);
    // The subtitle now leads with the recipient host.
    expect(find.text('api.openai.com · Ready'), findsOneWidget);
  });

  testWidgets('adding uses the seeded id once, then a fresh id', (
    tester,
  ) async {
    final c = _FakeController([_openAi()]);
    await tester.pumpWidget(_page(c));
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From OpenRouter'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(c.saved.single.provider.id, 'provider:openrouter');

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(c.saved.last.provider.id, 'provider:new0');
  });

  testWidgets('saving asks for the privacy notice; declining saves nothing', (
    tester,
  ) async {
    final c = _FakeController([_openAi()]);
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('key')), 'sk-1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Sent to api.openai.com'), findsOneWidget);
    expect(find.text('Item promptText'), findsOneWidget);
    expect(find.text('Keys secureEndpointsOnly'), findsOneWidget);
    expect(find.text('Only when chosen'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.saved, isEmpty);
    expect(c.acks, isEmpty);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(c.saved.single.key, 'sk-1');
    expect(c.acks['provider:openai']!.recipientHost, 'api.openai.com');
    expect(find.text('Edit'), findsNothing, reason: 'editor popped');
  });

  testWidgets('a confirmed host is not asked again; a new host is', (
    tester,
  ) async {
    final c = _FakeController([_openAi()]);
    c.acks['provider:openai'] = OnlinePrivacyAcknowledgement(
      noticeVersion: 1,
      acknowledgedAt: DateTime.utc(2026),
      recipientHost: 'api.openai.com',
    );
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Before you enable'), findsNothing);
    expect(c.saved, hasLength(1));

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('endpoint')),
      'https://proxy.example.com/v1',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Sent to proxy.example.com'), findsOneWidget);
  });

  testWidgets('an invalid endpoint is refused before anything is sent', (
    tester,
  ) async {
    final c = _FakeController([_openAi()]);
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('endpoint')), 'not a url');
    await tester.tap(find.text('Test'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Bad URL'), findsOneWidget);
    expect(c.tested, isEmpty);
    expect(c.saved, isEmpty);
    expect(find.text('Before you enable'), findsNothing);
  });

  testWidgets('the connection test runs only on tap and resets on edit', (
    tester,
  ) async {
    final c = _FakeController([_openAi()]);
    // The test now sends a request, so the notice must be acknowledged first.
    c.acks['provider:openai'] = _ack('api.openai.com');
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    expect(c.tested, isEmpty);
    await tester.enterText(find.byKey(const Key('key')), 'sk-typed');
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(c.tested.single.key, 'sk-typed');
    expect(find.text('state success'), findsOneWidget);
    expect(find.text('Result available'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('key')), 'sk-other');
    await tester.pump();
    expect(find.text('state idle'), findsOneWidget);
    expect(c.saved, isEmpty);
  });

  testWidgets('clearing the stored key saves a deletion', (tester) async {
    final c = _FakeController([_openAi()]);
    c.keys['provider:openai'] = 'old';
    c.acks['provider:openai'] = OnlinePrivacyAcknowledgement(
      noticeVersion: 1,
      acknowledgedAt: DateTime.utc(2026),
      recipientHost: 'api.openai.com',
    );
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    expect(find.text('saved'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.saved.single.clear, isTrue);
    expect(c.keys, isEmpty);
  });

  testWidgets('removal is confirmed first', (tester) async {
    final c = _FakeController([_openAi()]);
    await tester.pumpWidget(_page(c));
    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('The key is deleted too.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.removed, isEmpty);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(c.removed, ['provider:openai']);
    expect(find.text('No sources'), findsOneWidget);
  });

  testWidgets('dismissing the notice counts as declining', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = showOnlinePrivacyNoticeDialog(
      context,
      notice: const OnlinePrivacyNotice(
        version: 1,
        recipientHost: 'h',
        sent: [],
      ),
      labels: _labels,
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  _uiV2Tests();
}

// ---------------------------------------------------------------------------
// Online UI v2: template picker, models, two panes, icons.
// ---------------------------------------------------------------------------

/// Sets the test window explicitly and restores it afterwards.
void _setWindow(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Drops RenderFlex overflow reports for this test only.
///
/// The picker's fixed 104px cells overflow for a local template with a
/// two-line name (see the skipped Regression (fixed in 0.6.0) test); other tests are not about that.
VoidCallback _ignoreOverflow([String marker = 'overflowed']) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains(marker)) return;
    previous?.call(details);
  };
  void restore() => FlutterError.onError = previous;
  addTearDown(restore);
  return restore;
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Widget _pageWith(_FakeController c, {NavigatorObserver? observer}) =>
    MaterialApp(
      navigatorObservers: [?observer],
      home: MyAppsOnlineSourcesPage(
        title: 'Online',
        editorTitle: 'Edit',
        controller: c,
        labels: _labels,
        fields: _fields,
      ),
    );

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // Lists build lazily: scroll until the widget exists before revealing it.
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final _dialogSave = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.text('Save'),
);

void _uiV2Tests() {
  group('template picker', () {
    testWidgets('shows a grid with the custom template last', (tester) async {
      _setWindow(tester, 800, 600);
      _ignoreOverflow();
      final registry = OnlineProviderTemplateRegistry.chat();
      final c = _FakeController([], templates: registry);
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add a source'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      final first = registry.templates.first;
      expect(find.text('From ${first.name}'), findsOneWidget);

      // Scroll to the very end; the last card is the custom template.
      await tester.drag(find.byType(GridView), const Offset(0, -100000));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: find.byType(Card), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(texts.last, 'From ${openAiCompatibleTemplate.name}');
      expect(
        registry.templates.last.id,
        openAiCompatibleTemplateId,
        reason: 'registry order puts the custom template last',
      );
    });

    testWidgets('search filters by name', (tester) async {
      _setWindow(tester, 800, 600);
      _ignoreOverflow();
      final c = _FakeController(
        [],
        templates: OnlineProviderTemplateRegistry.chat(),
      );
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alibaba');
      await tester.pumpAndSettle();
      expect(find.text('From Alibaba Cloud Model Studio'), findsOneWidget);
      expect(find.text('From OpenAI'), findsNothing);
      expect(find.text('From OpenRouter'), findsNothing);
    });

    testWidgets('tapping a template opens the editor for a new record', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      _ignoreOverflow();
      final c = _FakeController(
        [],
        templates: OnlineProviderTemplateRegistry.chat(),
      );
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alibaba');
      await tester.pumpAndSettle();
      await tester.tap(find.text('From Alibaba Cloud Model Studio'));
      await tester.pumpAndSettle();

      expect(find.byType(MyAppsOnlineSourceEditorPage), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Alibaba Cloud Model Studio'),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove'), findsNothing, reason: 'new record');
      expect(c.saved, isEmpty);
    });
  });

  group('sources page', () {
    testWidgets('lists each provider with its models indented beneath', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final provider = _openAi(model: null).copyWith(
        models: const [
          OnlineModel(modelName: 'gpt-4o-mini', alias: 'Fast one'),
          OnlineModel(modelName: 'o3-pro', displayName: 'Deep one'),
        ],
      );
      final c = _FakeController([provider]);
      await tester.pumpWidget(_pageWith(c));
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Fast one'), findsOneWidget);
      expect(find.text('gpt-4o-mini'), findsOneWidget);
      expect(find.text('Deep one'), findsOneWidget);
      expect(find.text('o3-pro'), findsOneWidget);

      final modelTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Fast one'),
          matching: find.byType(ListTile),
        ),
      );
      final providerTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('OpenAI'), matching: find.byType(ListTile)),
      );
      expect(
        (modelTile.contentPadding! as EdgeInsetsDirectional).start,
        greaterThan(
          (providerTile.contentPadding ?? const EdgeInsets.all(16))
              .resolve(TextDirection.ltr)
              .left,
        ),
      );
    });

    testWidgets('a wide window opens the editor in the right pane', (
      tester,
    ) async {
      _setWindow(tester, 1400, 900);
      final observer = _PushCounter();
      final c = _FakeController([_openAi()]);
      await tester.pumpWidget(_pageWith(c, observer: observer));
      final before = observer.pushes;
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();

      expect(observer.pushes, before, reason: 'no route pushed');
      expect(find.byType(MyAppsOnlineSourceEditorPage), findsNothing);
      expect(find.byType(MyAppsOnlineSourceEditor), findsOneWidget);
      final editor = tester.getTopLeft(find.byType(MyAppsOnlineSourceEditor));
      expect(editor.dx, greaterThanOrEqualTo(360), reason: 'beside the list');
      // The list is still visible next to it.
      expect(find.textContaining('api.openai.com · Missing'), findsOneWidget);
    });
  });

  group('editor models', () {
    const entryA = OnlineModelEntry(
      'a-1',
      displayName: 'Acme: Alpha',
      contextTokens: 128000,
    );
    const entryB = OnlineModelEntry('b-2', displayName: 'Acme: Beta');

    testWidgets('fetch, choose, Done, then save passes the models', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: null)]);
      c.acks['provider:openai'] = _ack('api.openai.com');
      c.fetchResult = [entryA, entryB];
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      expect(find.text('No models yet'), findsOneWidget);

      await _tapVisible(tester, find.text('Fetch models'));
      expect(c.fetchCalls, hasLength(1));
      expect(find.text('Before you enable'), findsNothing);
      expect(find.text('Select models'), findsOneWidget);
      expect(find.text('Acme: Alpha'), findsOneWidget);
      expect(find.text('a-1  ·  128000 tokens'), findsOneWidget);

      // Choose in reverse order; the list keeps the source's order.
      await tester.tap(find.text('Acme: Beta'));
      await tester.tap(find.text('Acme: Alpha'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Select models'), findsNothing);
      expect(find.text('Acme: Alpha'), findsOneWidget);
      expect(find.text('Acme: Beta'), findsOneWidget);
      expect(find.text('No models yet'), findsNothing);

      await _tapVisible(tester, find.text('Save'));
      final saved = c.saved.single.provider;
      expect(saved.models.map((m) => m.modelName), ['a-1', 'b-2']);
      expect(saved.modelId, 'a-1');
      expect(saved.models.first.origin, OnlineModelOrigin.fetched);
      expect(saved.models.first.contextTokens, 128000);
    });

    testWidgets('fetching asks for the privacy notice first', (tester) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: null)]);
      c.fetchResult = [entryA];
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Fetch models'));
      expect(find.text('Before you enable'), findsOneWidget);
      expect(c.fetchCalls, isEmpty);
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
      expect(c.fetchCalls, hasLength(1));
      expect(find.text('Select models'), findsOneWidget);
    });

    testWidgets('a failed fetch offers the catalog with its note', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: null)]);
      c.acks['provider:openai'] = _ack('api.openai.com');
      c.fetchError = Exception('boom');
      c.catalog = [entryA];
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Fetch models'));

      expect(find.text('Select models'), findsOneWidget);
      expect(
        find.textContaining('Shown from the built-in catalog'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed: Exception: boom'), findsOneWidget);
      expect(find.text('Acme: Alpha'), findsOneWidget);

      await tester.tap(find.text('Acme: Alpha'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Save'));
      expect(
        c.saved.single.provider.models.single.origin,
        OnlineModelOrigin.template,
      );
    });

    testWidgets('a failed fetch with no catalog shows the failure inline', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: null)]);
      c.acks['provider:openai'] = _ack('api.openai.com');
      c.fetchError = Exception('boom');
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Fetch models'));
      expect(find.text('Select models'), findsNothing);
      expect(find.text('Failed: Exception: boom'), findsOneWidget);
    });

    testWidgets('tapping a model opens the alias dialog with the raw id', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: 'gpt-4o-mini')]);
      c.acks['provider:openai'] = _ack('api.openai.com');
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();

      // The model row of the editor (the list underneath is offstage).
      await _tapVisible(tester, find.text('gpt-4o-mini'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Alias'), findsOneWidget);
      expect(find.text('Original: gpt-4o-mini'), findsOneWidget);
      // The test ends with the dialog open: closing it currently trips the
      // disposed-controller bug (see the skipped test in 'known bugs').
    });
  });

  group('regressions', () {
    testWidgets('the endpoint dropdown fits a phone-width editor', (
      tester,
    ) async {
      _setWindow(tester, 360, 640);
      final registry = OnlineProviderTemplateRegistry.chat();
      final c = _FakeController([
        registry.byId('dashscope')!.create(id: 'provider:ds'),
      ], templates: registry);
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('Alibaba Cloud Model Studio'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Skipped: editor.dart (DropdownButtonFormField around line 462) has
      // no isExpanded: true, so the item Text's ellipsis never applies and
      // 'International (Singapore) · dashscope-intl.aliyuncs.com' overflows
      // the row on narrow widths. Fix: add isExpanded: true.
    }, skip: false);

    testWidgets('saving an alias changes the shown name', (tester) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi(model: 'gpt-4o-mini')]);
      c.acks['provider:openai'] = _ack('api.openai.com');
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('gpt-4o-mini'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'My mini',
      );
      await tester.tap(_dialogSave);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('My mini'), findsOneWidget);
      await _tapVisible(tester, find.text('Save'));
      expect(c.saved.single.provider.models.single.alias, 'My mini');
      // Skipped for the same reason as the test below: after the dialog
      // closes the whole tree is replaced by an error widget.
    }, skip: false);

    testWidgets(
      'closing the alias dialog does not use a disposed controller',
      (tester) async {
        _setWindow(tester, 800, 600);
        final c = _FakeController([_openAi(model: 'gpt-4o-mini')]);
        await tester.pumpWidget(_pageWith(c));
        await tester.tap(find.text('OpenAI'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('gpt-4o-mini'));
        await tester.tap(_dialogSave);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      // Regression (fixed in 0.6.0): editor.dart _textDialog ends with .whenComplete(c.dispose); the
      // future completes at pop, but the dialog route still builds its
      // TextField during the exit animation, so the disposed controller is
      // used (assertion in debug). Fix: dispose in a StatefulWidget dialog
      // body, or after the route is gone.
      skip: false,
    );

    testWidgets(
      'a local template with a long name fits its picker cell',
      (tester) async {
        _setWindow(tester, 360, 640);
        final c = _FakeController(
          [],
          templates: OnlineProviderTemplateRegistry([
            OnlineProviderTemplateRegistry.chat().templates.firstWhere(
              (t) => t.local && t.name.startsWith('llama'),
            ),
          ]),
        );
        await tester.pumpWidget(_pageWith(c));
        await tester.tap(find.byTooltip('Add'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      // Regression (fixed in 0.6.0): template_picker.dart (GridView mainAxisExtent: 104) - the cell
      // content is 32 icon + 8 gap + up to 2 label lines (~40) + the "local"
      // badge (~16) = 96 > 80 available, so a local template whose name wraps
      // ("llama.cpp server" on a phone) overflows by 16px. Fix: raise
      // mainAxisExtent to ~120 or limit the label to one line when the badge
      // is shown.
      skip: false,
    );
  });

  group('endpoint dropdown', () {
    testWidgets('lists the template endpoints and sets the field', (
      tester,
    ) async {
      // A wide window: the dropdown's items are not constrained (see the
      // skipped Regression (fixed in 0.6.0) test), so give them room. Opens in the right pane.
      _setWindow(tester, 1400, 900);
      final registry = OnlineProviderTemplateRegistry.chat();
      final dashscope = registry.byId('dashscope')!;
      final c = _FakeController([
        dashscope.create(id: 'provider:ds'),
      ], templates: registry);
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('Alibaba Cloud Model Studio'));
      await tester.pumpAndSettle();

      const intl = 'International (Singapore) · dashscope-intl.aliyuncs.com';
      expect(find.text(intl), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('endpoint')))
            .controller!
            .text,
        'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
      );

      await tester.tap(find.text(intl));
      await tester.pumpAndSettle();
      await tester.tap(find.text('China (Beijing) · dashscope.aliyuncs.com'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('endpoint')))
            .controller!
            .text,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
    });

    testWidgets('a template without endpoints shows no dropdown', (
      tester,
    ) async {
      _setWindow(tester, 800, 600);
      final c = _FakeController([_openAi()]);
      await tester.pumpWidget(_pageWith(c));
      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });
  });

  group('MyAppsProviderIcon', () {
    testWidgets('renders an svg for a bundled key', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MyAppsProviderIcon(iconKey: 'openai', name: 'OpenAI'),
          ),
        ),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('falls back to initials for an unknown key', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MyAppsProviderIcon(iconKey: 'nope', name: 'Acme Corp'),
                MyAppsProviderIcon(iconKey: null, name: 'zeta'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(CircleAvatar), findsNWidgets(2));
      expect(find.text('AC'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
    });
  });

  group('model picker', () {
    Future<void> open(
      WidgetTester tester, {
      required List<OnlineModelEntry> entries,
      Set<String> enabled = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOnlineModelPicker(
                context,
                entries: entries,
                enabled: enabled,
                labels: _labels,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    const chat = OnlineModelEntry('chat-1', displayName: 'Acme: Chat');
    const embed = OnlineModelEntry(
      'embed-1',
      displayName: 'Acme: Embed',
      chat: false,
    );

    testWidgets('hides non-chat models until show all is on', (tester) async {
      await open(tester, entries: [chat, embed]);
      expect(find.text('Acme: Chat'), findsOneWidget);
      expect(find.text('Acme: Embed'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Acme: Embed'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Acme: Embed'), findsNothing);
    });

    testWidgets('an already enabled non-chat model stays visible', (
      tester,
    ) async {
      await open(tester, entries: [chat, embed], enabled: {'embed-1'});
      expect(find.text('Acme: Embed'), findsOneWidget);
    });

    testWidgets('search filters by name and id', (tester) async {
      await open(tester, entries: [chat, embed]);
      await tester.enterText(find.byType(TextField), 'chat-1');
      await tester.pumpAndSettle();
      expect(find.text('Acme: Chat'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Acme: Chat'), findsNothing);
    });
  });
}
