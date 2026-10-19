import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

void main() {
  group('output validation', () {
    const options = ['romance', 'school', 'slice_of_life', 'comedy'];

    test('reads lists, lines, labels and Markdown', () {
      expect(parseChoiceReply('romance, school', options).ids, [
        'romance',
        'school',
      ]);
      expect(parseChoiceReply('- Romance\n- Slice of life', options).ids, [
        'romance',
        'slice_of_life',
      ]);
      expect(parseChoiceReply('Anime 1: comedy、school', options).ids, [
        'comedy',
        'school',
      ]);
      expect(parseChoiceReply('```\n**romance**\n```', options).ids, [
        'romance',
      ]);
    });

    test('drops unknown ids, duplicates and anything past the cap', () {
      final p = parseChoiceReply(
        'romance, horror, romance, school, comedy, slice_of_life',
        options,
      );
      expect(p.ids, ['romance', 'school', 'comedy']);
    });

    test('NONE is a valid empty answer; prose is invalid', () {
      final none = parseChoiceReply('NONE', options);
      expect(none.valid, isTrue);
      expect(none.none, isTrue);
      expect(none.ids, isEmpty);
      expect(parseChoiceReply('It is about love.', options).valid, isFalse);
      expect(parseChoiceReply('', options).valid, isFalse);
    });

    test('script checks follow the UI language', () {
      expect(matchesScript('和你喜欢的《孤独摇滚》同一工作室', 'zh'), isTrue);
      expect(matchesScript('Same studio as Bocchi', 'zh'), isFalse);
      expect(matchesScript('高評価した作品と同じスタジオです', 'ja'), isTrue);
      expect(matchesScript('和你喜欢的作品同一工作室', 'ja'), isFalse);
      expect(matchesScript('Same studio as 孤独摇滚', 'en'), isTrue);
      expect(matchesScript('同一工作室', 'en'), isFalse);
    });

    test('stripThinking removes reasoning before the answer', () {
      expect(
        stripThinking('<think>\n1: draft\n</think>\n1: Final answer.'),
        '1: Final answer.',
      );
      expect(
        stripThinking('<|think|>1: draft</|think|>1: Final.'),
        '1: Final.',
      );
      expect(
        stripThinking('<|channel>thought\n1: draft\n<channel|>1: Final.'),
        '1: Final.',
      );
      // A template that opened the block itself leaves only the closing tag.
      expect(stripThinking('1: draft\n</think>\n1: Final.'), '1: Final.');
      // Cut off while reasoning: there is no answer.
      expect(stripThinking('<think>\n1: draft never closed'), '');
      expect(stripThinking('1: Answer.\n<THINK>late reasoning'), '1: Answer.');
      expect(stripThinking('1: Plain answer.'), '1: Plain answer.');
    });

    test('stripMarkdown and parseChoiceReply skip reasoning', () {
      expect(stripMarkdown('<think>**x**</think>**Great**'), 'Great');
      expect(
        parseChoiceReply('<think>horror, comedy</think>romance', options).ids,
        ['romance'],
      );
      expect(cleanSentence('<|think|>no</|think|>Fine.'), 'Fine.');
    });

    test('cleanSentence drops over-long output', () {
      expect(cleanSentence('**Great** pick.\n'), 'Great pick.');
      expect(cleanSentence('x' * 141), isNull);
      expect(cleanSentence('  '), isNull);
    });
  });
}
