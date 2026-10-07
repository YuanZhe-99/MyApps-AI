import 'package:flutter/foundation.dart';

import 'engine.dart';

/// One speaker turn, in window-local seconds.
@immutable
class SpeakerTurn {
  /// Purpose: Start. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double start;

  /// Purpose: End. Inputs: None. Returns: double. Side effects: None.
  /// Notes: None.
  final double end;

  /// Purpose: Speaker number from zero, local to one diarization call.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int speaker;

  /// Purpose: Create a turn.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: None.
  const SpeakerTurn({
    required this.start,
    required this.end,
    required this.speaker,
  });
}

/// Optional speaker diarization over one PCM window.
///
/// Labels are meaningful only within the window; joining speakers across
/// windows is application work.
abstract interface class AsrDiarizer {
  /// Purpose: Whether diarization can run (models installed, runtime built).
  /// Inputs: None. Returns: bool. Side effects: May read storage.
  /// Notes: None.
  Future<bool> available();

  /// Purpose: Find who spoke when in [pcmWindow].
  /// Inputs: Path to a 16 kHz mono 16-bit WAV.
  /// Returns: Turns sorted by start.
  /// Side effects: Loads and runs models.
  /// Notes: Throws on failure; [labelWindow] turns failure into "unlabelled".
  Future<List<SpeakerTurn>> diarize(String pcmWindow);
}

/// Purpose: Give each segment the speaker it overlaps most.
/// Inputs: [segments], [turns], both window-local.
/// Returns: Segments with `S1`, `S2`, ... or unchanged where no turn
/// overlaps.
/// Side effects: None.
/// Notes: Pure; overlap is summed per speaker across turns.
List<AsrSegment> labelSegments(
  List<AsrSegment> segments,
  List<SpeakerTurn> turns,
) => [
  for (final segment in segments)
    () {
      final overlap = <int, double>{};
      for (final turn in turns) {
        final shared =
            (segment.endSeconds < turn.end ? segment.endSeconds : turn.end) -
            (segment.startSeconds > turn.start
                ? segment.startSeconds
                : turn.start);
        if (shared > 0) {
          overlap[turn.speaker] = (overlap[turn.speaker] ?? 0) + shared;
        }
      }
      if (overlap.isEmpty) return segment;
      final best = overlap.entries.reduce((a, b) => b.value > a.value ? b : a);
      return segment.withSpeaker('S${best.key + 1}');
    }(),
];

/// Purpose: Label one window's segments with an optional diarizer.
/// Inputs: [diarizer] or null, [pcmWindow] path, [segments].
/// Returns: Labelled segments; unchanged when no diarizer, unavailable, or
/// failing.
/// Side effects: Runs the diarizer.
/// Notes: The transcript is the product; labels are a bonus, so a failure
/// never fails the window.
Future<List<AsrSegment>> labelWindow(
  AsrDiarizer? diarizer,
  String pcmWindow,
  List<AsrSegment> segments,
) async {
  if (diarizer == null || segments.isEmpty) return segments;
  try {
    if (!await diarizer.available()) return segments;
    return labelSegments(segments, await diarizer.diarize(pcmWindow));
  } catch (_) {
    return segments;
  }
}
