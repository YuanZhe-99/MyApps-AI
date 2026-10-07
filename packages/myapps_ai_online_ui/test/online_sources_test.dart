import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';
import 'package:myapps_ai_online_ui/myapps_ai_online_ui.dart';

class _FakeController implements OnlineSourcesController {
  _FakeController(this.providers);

  @override
  List<OnlineProvider> providers;

  final keys = <String, String>{};
  final acks = <String, OnlinePrivacyAcknowledgement>{};
  final saved = <({OnlineProvider provider, String? key, bool clear})>[];
  final removed = <String>[];
  final tested = <({OnlineProvider draft, String? key})>[];
  final _changes = ChangeNotifier();
  var _next = 0;

  @override
  Listenable get changes => _changes;

  @override
  final templates = OnlineProviderTemplateRegistry.builtIn();

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
    expect(find.text('Ready'), findsOneWidget);
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
}
