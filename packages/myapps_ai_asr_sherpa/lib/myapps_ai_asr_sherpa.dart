/// sherpa-onnx adapters implementing `myapps_ai_asr`: Qwen3-ASR transcription
/// and optional speaker diarization, over pinned prebuilt libraries delivered
/// by this package's build hook.
library;

export 'src/diarizer.dart';
export 'src/engine.dart';
export 'src/native/sherpa.dart' show QwenAsrFiles, sherpaVersion;
