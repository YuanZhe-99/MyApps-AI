import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai/myapps_ai.dart';

/// Purpose: Check coalescing and clear invalidation. Inputs: None. Returns: None.
/// Side effects: Fake storage writes. Notes: Keys and requests represent app-owned data.
void main() {
  test('clear prevents running answer from repopulating cache', () async {
    final reply = Completer<AiInsightEntry?>();
    var saves = 0;
    final store = AiInsightCoordinator<String, String>(
      keyOf: (_) => 'card',
      fingerprintOf: (request, _) => request,
      modelOf: () => 'model',
      canGenerate: () => true,
      load: () async => {},
      save: (_) async {
        saves++;
      },
      clear: () async {},
      answer: (_, _, _, _) => reply.future,
      skippedEntry: (_, fp, _) => AiInsightEntry(
        fingerprint: fp,
        lines: [],
        status: AiInsightStatus.skipped,
        generatedAt: DateTime.utc(2026),
        language: 'en',
        promptVersion: 1,
      ),
    );
    final running = store.ensure('old');
    await pumpEventQueue();
    await store.clearAll();
    reply.complete(
      AiInsightEntry(
        fingerprint: 'old',
        lines: ['old'],
        status: AiInsightStatus.ok,
        generatedAt: DateTime.utc(2026),
        language: 'en',
        promptVersion: 1,
      ),
    );
    await running;
    expect(saves, 0);
    expect(store.stateOf('card').entry, isNull);
    store.dispose();
  });
}
