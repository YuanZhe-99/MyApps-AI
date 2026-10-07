/// Purpose: sherpa-onnx as a small synchronous FFI API over
/// its C API — for Qwen3-ASR.
/// Inputs: A model folder's files and 16 kHz mono float samples.
/// Returns: `SherpaLibrary` and `QwenAsrModel`.
/// Side effects: Loads native libraries and models; runs inference.
/// Notes: Every call here blocks; the app's adapter runs them on a worker
/// isolate that owns the model (decision D16 of the local-models plan). The
/// libraries are sherpa-onnx's own prebuilt ones, bound through bindings
/// generated from that version's header (decisions D21 and D22). The C API
/// decodes a window in one call and has no abort hook, so a cancel takes
/// effect when the window ends.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'sherpa_bindings.g.dart';

/// The sherpa-onnx version the bindings were generated from; the library must
/// report exactly this.
const sherpaVersion = '1.13.8';

/// Why a sherpa-onnx call failed.
class SherpaException implements Exception {
  /// What happened.
  final String message;

  /// Purpose: Create a failure.
  /// Inputs: [message].
  /// Returns: A new exception.
  /// Side effects: None.
  /// Notes: None.
  const SherpaException(this.message);

  /// Purpose: Render the failure.
  /// Inputs: None.
  /// Returns: `String`.
  /// Side effects: None.
  /// Notes: None.
  @override
  String toString() => 'SherpaException: $message';
}

/// The native library: whether it loads, and which version it is.
class SherpaLibrary {
  /// Purpose: Prevent instantiation; every entry point is static.
  /// Inputs: None.
  /// Returns: Nothing.
  /// Side effects: None.
  /// Notes: None.
  const SherpaLibrary._();

  /// Purpose: Load the library and check its version.
  /// Inputs: None.
  /// Returns: The version, or null when this build or target has no library.
  /// Side effects: Loads native code.
  /// Notes: The config structs are passed by pointer and read by the library
  /// with its own layout, so a library of another version than the bindings
  /// could misread every field; a mismatch throws [SherpaException] and the
  /// library is not used. A target without the library — iOS — has no code
  /// asset; the first call then throws [ArgumentError], reported as null.
  static String? load() {
    final String version;
    try {
      version = SherpaOnnxGetVersionStr().cast<Utf8>().toDartString();
    } on ArgumentError {
      return null;
    }
    if (version != sherpaVersion) {
      throw SherpaException(
        'sherpa-onnx $version does not match its bindings ($sherpaVersion); '
        'it is not used.',
      );
    }
    return version;
  }
}

/// The files of a Qwen3-ASR package, as sherpa-onnx publishes it.
class QwenAsrFiles {
  /// The convolutional front end.
  final String convFrontend;

  /// The audio encoder.
  final String encoder;

  /// The text decoder, with its KV cache.
  final String decoder;

  /// The tokenizer folder (holding `vocab.json`).
  final String tokenizer;

  /// Purpose: Name the files.
  /// Inputs: All fields, as absolute paths.
  /// Returns: A new immutable value.
  /// Side effects: None.
  /// Notes: None.
  const QwenAsrFiles({
    required this.convFrontend,
    required this.encoder,
    required this.decoder,
    required this.tokenizer,
  });
}

/// A loaded Qwen3-ASR model.
class QwenAsrModel {
  QwenAsrModel._(this._recognizer, this._arena);

  Pointer<SherpaOnnxOfflineRecognizer> _recognizer;

  /// The config's strings, which must outlive the recognizer.
  final Arena _arena;

  /// Purpose: Load a Qwen3-ASR package.
  /// Inputs: Its [files]; the [threads]; optional [hotwords], words the
  /// decoder should prefer.
  /// Returns: The loaded model.
  /// Side effects: Reads the files; allocates the model's memory.
  /// Notes: Greedy decoding at a near-zero temperature, as sherpa-onnx's own
  /// example does; [maxNewTokens] bounds the text of one window. Throws
  /// [SherpaException] when the files do not load.
  static QwenAsrModel load(
    QwenAsrFiles files, {
    int threads = 4,
    List<String> hotwords = const [],
  }) {
    SherpaLibrary.load();
    final arena = Arena();
    Pointer<Char> text(String value) =>
        value.toNativeUtf8(allocator: arena).cast();
    final config = arena<SherpaOnnxOfflineRecognizerConfig>();
    config.ref
      ..decoding_method = text('greedy_search')
      ..model_config.num_threads = threads
      ..model_config.provider = text('cpu')
      ..model_config.qwen3_asr.conv_frontend = text(files.convFrontend)
      ..model_config.qwen3_asr.encoder = text(files.encoder)
      ..model_config.qwen3_asr.decoder = text(files.decoder)
      ..model_config.qwen3_asr.tokenizer = text(files.tokenizer)
      ..model_config.qwen3_asr.max_total_len = maxTotalTokens
      ..model_config.qwen3_asr.max_new_tokens = maxNewTokens
      ..model_config.qwen3_asr.temperature = 1e-6
      ..model_config.qwen3_asr.top_p = 0.8
      ..model_config.qwen3_asr.seed = 42
      ..model_config.qwen3_asr.hotwords = text(
        hotwords.map((w) => w.replaceAll(',', ' ').trim()).join(','),
      );
    final recognizer = SherpaOnnxCreateOfflineRecognizer(config);
    if (recognizer == nullptr) {
      arena.releaseAll();
      throw SherpaException('The model at ${files.encoder} did not load.');
    }
    return QwenAsrModel._(recognizer, arena);
  }

  /// The longest sequence, audio and text together, the exported decoder
  /// takes — sherpa-onnx's own example's value.
  static const maxTotalTokens = 512;

  /// The most text tokens one window may produce.
  static const maxNewTokens = 128;

  /// Purpose: Transcribe samples.
  /// Inputs: 16 kHz mono [samples] from -1 to 1.
  /// Returns: The text, trimmed; empty for silence.
  /// Side effects: Runs the model.
  /// Notes: Blocks until done; Qwen3-ASR gives no timestamps, so the caller
  /// spreads the text over the window.
  String transcribe(Float32List samples) {
    if (_recognizer == nullptr) throw const SherpaException('Released.');
    final stream = SherpaOnnxCreateOfflineStream(_recognizer);
    final buffer = calloc<Float>(samples.length);
    try {
      buffer.asTypedList(samples.length).setAll(0, samples);
      SherpaOnnxAcceptWaveformOffline(stream, 16000, buffer, samples.length);
      SherpaOnnxDecodeOfflineStream(_recognizer, stream);
      final result = SherpaOnnxGetOfflineStreamResult(stream);
      try {
        final text = result.ref.text;
        return text == nullptr ? '' : text.cast<Utf8>().toDartString().trim();
      } finally {
        SherpaOnnxDestroyOfflineRecognizerResult(result);
      }
    } finally {
      calloc.free(buffer);
      SherpaOnnxDestroyOfflineStream(stream);
    }
  }

  /// Purpose: Free the model.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Frees native memory.
  /// Notes: Safe to call more than once; only after a transcription returned.
  void release() {
    if (_recognizer == nullptr) return;
    SherpaOnnxDestroyOfflineRecognizer(_recognizer);
    _recognizer = nullptr;
    _arena.releaseAll();
  }
}

/// One speaker turn: who spoke from when to when, in seconds.
typedef SherpaSpeakerTurn = ({double start, double end, int speaker});

/// Offline speaker diarization (L8 of the local-models plan): pyannote's
/// segmentation model finds where speech changes hands, a speaker-embedding
/// model tells voices apart, and clustering groups them.
class SpeakerDiarizer {
  SpeakerDiarizer._(this._native, this._arena);

  Pointer<SherpaOnnxOfflineSpeakerDiarization> _native;
  final Arena _arena;

  /// Purpose: Load the two models.
  /// Inputs: The pyannote [segmentation] model and the speaker [embedding]
  /// model, as paths; the [threads]; the [speakers] when known, or null to
  /// let clustering decide by [threshold].
  /// Returns: The loaded diarizer.
  /// Side effects: Reads the models.
  /// Notes: The durations are sherpa-onnx's own example values: a turn
  /// shorter than 0.3 s is dropped, and a gap shorter than 0.5 s joins two
  /// turns of one speaker. Throws [SherpaException] when the models do not
  /// load.
  static SpeakerDiarizer load({
    required String segmentation,
    required String embedding,
    int threads = 4,
    int? speakers,
    double threshold = 0.5,
  }) {
    SherpaLibrary.load();
    final arena = Arena();
    Pointer<Char> text(String value) =>
        value.toNativeUtf8(allocator: arena).cast();
    final config = arena<SherpaOnnxOfflineSpeakerDiarizationConfig>();
    config.ref
      ..segmentation.pyannote.model = text(segmentation)
      ..segmentation.num_threads = threads
      ..segmentation.provider = text('cpu')
      ..embedding.model = text(embedding)
      ..embedding.num_threads = threads
      ..embedding.provider = text('cpu')
      ..clustering.num_clusters = speakers ?? -1
      ..clustering.threshold = threshold
      ..min_duration_on = 0.3
      ..min_duration_off = 0.5;
    final native = SherpaOnnxCreateOfflineSpeakerDiarization(config);
    if (native == nullptr) {
      arena.releaseAll();
      throw SherpaException(
        'The speaker models at $segmentation did not load.',
      );
    }
    return SpeakerDiarizer._(native, arena);
  }

  /// Purpose: Find who spoke when.
  /// Inputs: 16 kHz mono [samples].
  /// Returns: The turns, sorted by start; speakers numbered from zero within
  /// this call.
  /// Side effects: Runs the models.
  /// Notes: Blocks. Speaker numbers mean nothing across calls: the app's
  /// speaker unifier joins them across windows.
  List<SherpaSpeakerTurn> process(Float32List samples) {
    if (_native == nullptr) throw const SherpaException('Released.');
    final buffer = calloc<Float>(samples.length);
    try {
      buffer.asTypedList(samples.length).setAll(0, samples);
      final result = SherpaOnnxOfflineSpeakerDiarizationProcess(
        _native,
        buffer,
        samples.length,
      );
      if (result == nullptr) return const [];
      try {
        final count = SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(
          result,
        );
        final sorted = SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(
          result,
        );
        try {
          return [
            for (var i = 0; i < count; i++)
              (
                start: sorted[i].start,
                end: sorted[i].end,
                speaker: sorted[i].speaker,
              ),
          ];
        } finally {
          SherpaOnnxOfflineSpeakerDiarizationDestroySegment(sorted);
        }
      } finally {
        SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result);
      }
    } finally {
      calloc.free(buffer);
    }
  }

  /// Purpose: Free the models.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Frees native memory.
  /// Notes: Safe to call more than once.
  void release() {
    if (_native == nullptr) return;
    SherpaOnnxDestroyOfflineSpeakerDiarization(_native);
    _native = nullptr;
    _arena.releaseAll();
  }
}
