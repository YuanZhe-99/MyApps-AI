/// whisper.cpp adapters (Whisper and Parakeet) implementing `myapps_ai_asr`,
/// over pinned prebuilt libraries delivered by this package's build hook.
library;

export 'src/engine.dart';
export 'src/native/whisper.dart' show WhisperDevice;
