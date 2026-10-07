/// Ported from MyTranscribe's pcm_window_test.dart: the window header check
/// and the similarity rule; the route check is in self_test_test.dart.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:path/path.dart' as p;

/// Purpose: Build a WAV file's bytes.
/// Inputs: The [samples], and the header fields to vary.
/// Returns: The bytes.
/// Side effects: None.
/// Notes: [extraChunk] inserts a `LIST` chunk before the samples, which is
/// what an FFmpeg build writes unless told to be bit-exact.
Uint8List wav(
  List<int> samples, {
  int rate = 16000,
  int channels = 1,
  int bits = 16,
  int format = 1,
  bool extraChunk = false,
}) {
  final builder = BytesBuilder();
  void u32(int v) => builder.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => builder.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );
  final list = extraChunk ? [..._list] : <int>[];
  builder.add('RIFF'.codeUnits);
  u32(36 + list.length + samples.length * 2);
  builder.add('WAVE'.codeUnits);
  builder.add('fmt '.codeUnits);
  u32(16);
  u16(format);
  u16(channels);
  u32(rate);
  u32(rate * channels * bits ~/ 8);
  u16(channels * bits ~/ 8);
  u16(bits);
  builder.add(list);
  builder.add('data'.codeUnits);
  u32(samples.length * 2);
  for (final s in samples) {
    u16(s & 0xffff);
  }
  return builder.toBytes();
}

/// A `LIST` chunk of the kind FFmpeg writes: an odd-sized body, padded.
final _list = [
  ...'LIST'.codeUnits,
  ...[9, 0, 0, 0],
  ...'INFOISFT\x00'.codeUnits,
  0,
];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytranscribe_pcm_');
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) =>
      File(p.join(root.path, name))..writeAsBytesSync(bytes);

  group('a PCM window', () {
    test('reads its header and samples', () async {
      final window = await readPcmWindow(
        write('a.wav', wav([0, 16384, -32768, 32767])),
      );
      expect(window.sampleRate, 16000);
      expect(window.sampleCount, 4);
      expect(window.dataOffset, 44);
      expect(window.seconds, 4 / 16000);
      final samples = await window.readSamples();
      expect(samples, [0.0, 0.5, -1.0, 32767 / 32768]);
    });

    test('finds the samples past a chunk it does not use', () async {
      final window = await readPcmWindow(
        write('b.wav', wav([1, 2, 3], extraChunk: true)),
      );
      expect(window.sampleCount, 3);
      expect(window.dataOffset, 44 + _list.length);
    });

    test('is refused in any other format', () async {
      for (final bad in [
        wav([1], rate: 44100),
        wav([1], channels: 2),
        wav([1], bits: 8),
        wav([1], format: 3),
        Uint8List.fromList('not a wav at all'.codeUnits),
      ]) {
        await expectLater(
          readPcmWindow(write('bad.wav', bad)),
          throwsA(isA<PcmFormatException>()),
        );
      }
    });
  });

  group('the words a check compares', () {
    test('ignore case and punctuation', () {
      expect(
        textSimilarity(
          'And so, my fellow Americans: ask not.',
          'and so my fellow americans ask not',
        ),
        1,
      );
    });

    test('count a dropped or invented word against the expected ones', () {
      expect(textSimilarity('one two three four', 'one two four'), 0.75);
      expect(textSimilarity('one two', 'something else entirely'), 0);
      expect(textSimilarity('', ''), 1);
      expect(textSimilarity('', 'noise'), 0);
    });
  });

  test('the bundled clip is a valid window of the stated length', () async {
    final window = await readPcmWindow(File('assets/jfk.wav'));
    expect(window.seconds, closeTo(asrSmokeClipSeconds, 0.1));
  });
}
