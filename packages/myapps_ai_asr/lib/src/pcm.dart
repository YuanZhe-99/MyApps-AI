import 'dart:io';

import 'package:flutter/foundation.dart';

/// The sample rate every local engine takes.
const asrPcmSampleRate = 16000;

/// A window file that is not 16 kHz mono 16-bit PCM WAV.
class PcmFormatException implements Exception {
  /// Purpose: What is wrong.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String message;

  /// Purpose: Create a format failure.
  /// Inputs: [message]. Returns: A new exception. Side effects: None.
  /// Notes: None.
  const PcmFormatException(this.message);

  /// Purpose: Render for a log.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  @override
  String toString() => 'PcmFormatException: $message';
}

/// A checked PCM window file.
@immutable
class PcmWindow {
  /// Purpose: The WAV file. Inputs: None. Returns: File. Side effects: None.
  /// Notes: None.
  final File file;

  /// Purpose: Samples per second; [asrPcmSampleRate] once checked.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int sampleRate;

  /// Purpose: Channels; one once checked.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int channels;

  /// Purpose: Bits per sample; 16 once checked.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int bitsPerSample;

  /// Purpose: Byte offset of the samples.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int dataOffset;

  /// Purpose: Sample count.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int sampleCount;

  /// Purpose: Create a window description.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: Use [readPcmWindow] rather than constructing directly.
  const PcmWindow({
    required this.file,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.sampleCount,
  });

  /// Purpose: Length in seconds.
  /// Inputs: None. Returns: double. Side effects: None. Notes: None.
  double get seconds => sampleRate == 0 ? 0 : sampleCount / sampleRate;

  /// Purpose: Read the samples as floats from -1 to 1.
  /// Inputs: None. Returns: [Float32List] of [sampleCount].
  /// Side effects: Reads the file.
  /// Notes: The form whisper.cpp, sherpa-onnx and the Apple bridge take.
  Future<Float32List> readSamples() async {
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes, dataOffset);
    final samples = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }
}

/// Purpose: Read and check the header of a 16 kHz mono 16-bit WAV.
/// Inputs: [file]. Returns: A [PcmWindow].
/// Side effects: Reads the file.
/// Notes: Walks RIFF chunks rather than assuming a 44-byte header. Throws
/// [PcmFormatException] for any other format, because an engine fed the wrong
/// rate transcribes nonsense without an error.
Future<PcmWindow> readPcmWindow(File file) async {
  final bytes = await file.readAsBytes();
  Never bad(String why) => throw PcmFormatException(
    'The audio window is not 16 kHz mono 16-bit PCM: $why.',
  );

  if (bytes.length < 12) bad('the file is too short');
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') bad('it is not a WAV file');

  int? format, channels, rate, bits, dataOffset, dataBytes;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = tag(at);
    final size = data.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      final left = bytes.length - body;
      dataBytes = size == 0 || size > left ? left : size;
      break;
    }
    at = body + size + (size.isOdd ? 1 : 0);
  }

  if (format != 1) bad('the encoding is $format, not PCM');
  if (channels != 1) bad('it has $channels channels');
  if (rate != asrPcmSampleRate) bad('it runs at $rate Hz');
  if (bits != 16) bad('it has $bits bits per sample');
  if (dataOffset == null || dataBytes == null) bad('it has no samples');

  return PcmWindow(
    file: file,
    sampleRate: rate!,
    channels: channels!,
    bitsPerSample: bits!,
    dataOffset: dataOffset,
    sampleCount: dataBytes ~/ 2,
  );
}
