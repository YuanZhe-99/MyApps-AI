/// The low-level synchronous whisper.cpp FFI API. Every call blocks; run it
/// on a worker isolate. Most consumers use `WhisperCppEngine` instead.
library;

export 'src/native/whisper.dart';
