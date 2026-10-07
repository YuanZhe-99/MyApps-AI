import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Purpose: Verify global selection, overrides and change detection.
/// Inputs: None. Returns: None. Side effects: None. Notes: Pure logic.
void main() {
  test('features follow the global source unless overridable', () {
    const s = AiSourceSelection(
      global: 'system',
      overrides: {'proofread': 'local:qwen'},
    );
    expect(s.sourceFor('prompt'), 'system');
    expect(s.sourceFor('proofread'), 'system');
    expect(s.sourceFor('proofread', overridable: {'proofread'}), 'local:qwen');
  });

  test('json round trip keeps unknown fields and drops bad overrides', () {
    final s = AiSourceSelection.fromJson({
      'global': 'online:openai',
      'overrides': {'prompt': 'system', 'bad': 3},
      'future': [1, 2],
    });
    expect(s.global, 'online:openai');
    expect(s.overrides, {'prompt': 'system'});
    expect(s.toJson()['future'], [1, 2]);
    expect(
      AiSourceSelection.fromJson(null).global,
      AiSourceSelection.autoSourceId,
    );
    expect(AiSourceSelection.fromJson({'global': ''}).global, 'auto');
  });

  test('override edits and change detection', () {
    const before = AiSourceSelection(global: 'system');
    final after = before.withOverride('prompt', 'local:a');
    expect(after.withOverride('prompt', null), before);
    expect(
      featuresWithChangedSource(
        before,
        after,
        features: const ['prompt', 'proofread'],
        overridable: const {'prompt'},
      ),
      {'prompt'},
    );
    expect(
      featuresWithChangedSource(
        before,
        before.withGlobal('local:b'),
        features: const ['prompt', 'proofread'],
      ),
      {'prompt', 'proofread'},
    );
  });

  test('options report feature support', () {
    const all = AiSourceOption(id: 'system', kind: AiSourceKind.system);
    const some = AiSourceOption(
      id: 'local:a',
      kind: AiSourceKind.local,
      readiness: AiSourceReadiness.needsDownload,
      features: {'prompt'},
    );
    expect(all.supports('proofread'), isTrue);
    expect(some.supports('proofread'), isFalse);
  });
}
