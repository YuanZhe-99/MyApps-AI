/// llama.cpp text generation implementing `myapps_ai_llm`, over upstream's
/// prebuilt libraries delivered by this package's build hook.
library;

export 'src/backend.dart';
export 'src/catalog.dart';
export 'src/gguf.dart';
export 'src/native/llama.dart'
    show LlamaDevice, LlamaLibrary, llamaGgmlVersion, llamaUpstreamTag;
