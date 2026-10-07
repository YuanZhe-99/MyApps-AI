import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Purpose: Verify existing consumer cache compatibility. Inputs: None.
/// Returns: None. Side effects: None. Notes: Cache is rebuildable and device-local.
void main() {
  test('existing JSON fields and UTC timestamps round trip', () {
    final json = <String, dynamic>{
      'fingerprint': 'abc',
      'lines': ['summary'],
      'slots': ['costSummary'],
      'status': 'ok',
      'generatedAt': '2026-10-05T09:00:00+08:00',
      'language': 'zh_CN',
      'promptVersion': 4,
      'model': 'stable/fast',
    };
    final entry = AiInsightEntry.fromJson(json)!;
    expect(entry.toJson(), {
      ...json,
      'generatedAt': '2026-10-05T01:00:00.000Z',
    });
  });
  test('malformed entries drop and mismatched slots degrade to ungrouped', () {
    expect(AiInsightEntry.fromJson({'fingerprint': 'abc'}), isNull);
    final entry = AiInsightEntry.fromJson({
      'fingerprint': 'abc',
      'lines': ['one', 'two'],
      'slots': ['one'],
      'status': 'skipped',
      'generatedAt': '2026-10-05T00:00:00Z',
    })!;
    expect(entry.slots, isEmpty);
    expect(entry.status, AiInsightStatus.skipped);
  });
}
