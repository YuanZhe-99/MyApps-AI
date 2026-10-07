import 'package:flutter/foundation.dart';

import 'engine.dart';

/// One SentencePiece-style token with times, in seconds.
///
/// `▁` marks the start of a word. Produced by Parakeet runtimes and the
/// Apple bridge; neutral so no adapter borrows another adapter's types.
@immutable
class TimedToken {
  /// Purpose: Raw piece. Inputs: None. Returns: String. Side effects: None.
  /// Notes: None.
  final String piece;

  /// Purpose: Start. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double start;

  /// Purpose: End. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double end;

  /// Purpose: Create a token.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const TimedToken(this.piece, this.start, this.end);
}

/// The longest a sentence runs before it is cut at the next word.
const maxSentenceSeconds = 20.0;

const _sentenceEnds = ['.', '?', '!', '。', '？', '！'];

/// Purpose: Join timed tokens into sentence segments with word times.
/// Inputs: [tokens] in order.
/// Returns: One segment per sentence, trimmed; empty ones dropped.
/// Side effects: None.
/// Notes: A sentence ends at a sentence mark, or at the next word once it ran
/// [maxSentenceSeconds]. `<...>` pieces are control tokens. Same grouping as
/// MyTranscribe's `sentences`, so segment text and times are unchanged.
List<AsrSegment> sentencesFromTokens(List<TimedToken> tokens) {
  final segments = <AsrSegment>[];
  final text = StringBuffer();
  final words = <AsrWord>[];
  final word = StringBuffer();
  double? start;
  double? wordStart;
  var wordEnd = 0.0;
  var end = 0.0;

  void flushWord() {
    final w = word.toString().trim();
    if (w.isNotEmpty && wordStart != null) {
      words.add(
        AsrWord(startSeconds: wordStart!, endSeconds: wordEnd, text: w),
      );
    }
    word.clear();
    wordStart = null;
  }

  void flush() {
    flushWord();
    final line = text.toString().trim();
    final from = start;
    if (line.isNotEmpty && from != null) {
      segments.add(
        AsrSegment(
          startSeconds: from,
          endSeconds: end,
          text: line,
          words: List.unmodifiable(words),
        ),
      );
    }
    text.clear();
    words.clear();
    start = null;
  }

  for (final token in tokens) {
    final piece = token.piece;
    if (piece.startsWith('<') && piece.endsWith('>')) continue;
    final from = start;
    if (piece.startsWith('▁') &&
        from != null &&
        token.start - from > maxSentenceSeconds) {
      flush();
    }
    if (piece.startsWith('▁')) flushWord();
    start ??= token.start;
    wordStart ??= token.start;
    end = token.end;
    wordEnd = token.end;
    text.write(piece.replaceAll('▁', ' '));
    word.write(piece.replaceAll('▁', ''));
    final trimmed = piece.trimRight();
    if (_sentenceEnds.any(trimmed.endsWith)) flush();
  }
  flush();
  return segments;
}

/// Purpose: Turn text plus optional timed tokens into segments.
/// Inputs: [text], [tokens], the window's [seconds].
/// Returns: Sentences from tokens, or one segment spanning the window when
/// there are no tokens; empty for blank text.
/// Side effects: None.
/// Notes: The caller reports `hasRealTimestamps` only when tokens existed.
List<AsrSegment> segmentsFromTimedText(
  String text,
  List<TimedToken> tokens,
  double seconds,
) {
  if (tokens.isEmpty) {
    final trimmed = text.trim();
    return trimmed.isEmpty
        ? const []
        : [AsrSegment(startSeconds: 0, endSeconds: seconds, text: trimmed)];
  }
  return sentencesFromTokens(tokens);
}
