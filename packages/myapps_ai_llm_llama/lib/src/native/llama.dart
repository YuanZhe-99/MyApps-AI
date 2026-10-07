/// Purpose: llama.cpp as a small synchronous FFI API.
/// Inputs: A GGUF model path, chat messages and sampling settings.
/// Returns: [LlamaLibrary] and [LlamaSession].
/// Side effects: Loads native libraries and models; runs inference.
/// Notes: Every call blocks; the backend runs them on a worker isolate that
/// owns the model. Cancellation is a flag in native memory checked between
/// prefill chunks and between generated tokens; ggml's abort callback is not
/// used because ggml calls it from its own compute threads.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../ggml_bindings.g.dart';
import '../llama_bindings.g.dart';
import 'os.dart';

/// ggml version the vendored headers and bindings describe; the loaded
/// library must report exactly this, or its structs could differ.
const llamaGgmlVersion = '0.26.0';

/// Upstream release tag the binaries and headers come from.
const llamaUpstreamTag = 'b11457';

/// Why a llama.cpp call failed.
class LlamaException implements Exception {
  /// Purpose: Create a failure. Inputs: [kind], [message].
  /// Returns: Exception. Side effects: None. Notes: None.
  const LlamaException(this.kind, this.message);

  /// Purpose: Failure class: `notBuilt`, `version`, `load`, `tooLong`,
  /// `decode`. Inputs: None. Returns: String. Side effects: None.
  /// Notes: Plain string so it crosses isolates.
  final String kind;

  /// Purpose: Detail. Inputs: None. Returns: String. Side effects: None.
  /// Notes: None.
  final String message;

  /// Purpose: Render. Inputs: None. Returns: String. Side effects: None.
  /// Notes: None.
  @override
  String toString() => 'LlamaException($kind): $message';
}

/// One compute device ggml found.
class LlamaDevice {
  /// Purpose: Describe a device. Inputs: ggml [name], [description], [type]
  /// (0 CPU, 1 GPU, 2 integrated GPU, 3 accelerator).
  /// Returns: Value. Side effects: None. Notes: None.
  const LlamaDevice(this.name, this.description, this.type);

  /// Purpose: ggml name such as `CPU`, `Vulkan0`, `MTL0`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String name;

  /// Purpose: Human description. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String description;

  /// Purpose: ggml device type. Inputs: None. Returns: int.
  /// Side effects: None. Notes: None.
  final int type;

  /// Purpose: Whether this is a discrete or integrated GPU.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isGpu => type == 1 || type == 2;
}

/// The native library: whether it loads, its version and devices.
class LlamaLibrary {
  /// Purpose: Prevent instantiation. Inputs: None. Returns: Nothing.
  /// Side effects: None. Notes: None.
  const LlamaLibrary._();

  static bool _loaded = false;

  /// Purpose: Load the library and ggml's backends once per isolate group.
  /// Inputs: None.
  /// Returns: The ggml version, or null when this target has no library.
  /// Side effects: Loads native code; registers ggml backends.
  /// Notes: Throws [LlamaException] (`version`) when the library is not the
  /// one the bindings describe; nothing is called after that.
  static String? load() {
    try {
      llama_print_system_info();
    } on ArgumentError {
      return null;
    }
    final bindings = ggml();
    final version = bindings.ggml_version().cast<Utf8>().toDartString();
    if (version != llamaGgmlVersion) {
      throw LlamaException(
        'version',
        'ggml $version does not match the bindings ($llamaGgmlVersion).',
      );
    }
    if (!_loaded) {
      // Apple's binary has its backends linked in; elsewhere the CPU variants
      // are libraries beside llama's. Another isolate may have registered
      // them already, and registering twice lists every device twice.
      final dir = llamaLibraryDirectory();
      if (dir != null &&
          !Platform.isMacOS &&
          !Platform.isIOS &&
          !_hasCpuDevice(bindings)) {
        final native = dir.toNativeUtf8();
        try {
          bindings.ggml_backend_load_all_from_path(native.cast());
        } finally {
          calloc.free(native);
        }
      }
      llama_backend_init();
      _loaded = true;
    }
    return version;
  }

  /// Purpose: Whether ggml already has a CPU device in this process.
  /// Inputs: [bindings]. Returns: bool. Side effects: None. Notes: Internal.
  static bool _hasCpuDevice(GgmlBindings bindings) {
    for (var i = 0; i < bindings.ggml_backend_dev_count(); i++) {
      if (bindings.ggml_backend_dev_type$1(bindings.ggml_backend_dev_get(i)) ==
          ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU) {
        return true;
      }
    }
    return false;
  }

  /// Purpose: List ggml's devices. Inputs: None. Returns: Devices.
  /// Side effects: None. Notes: Call [load] first.
  static List<LlamaDevice> devices() {
    final b = ggml();
    return [
      for (var i = 0; i < b.ggml_backend_dev_count(); i++)
        () {
          final d = b.ggml_backend_dev_get(i);
          return LlamaDevice(
            b.ggml_backend_dev_name(d).cast<Utf8>().toDartString(),
            b.ggml_backend_dev_description(d).cast<Utf8>().toDartString(),
            b.ggml_backend_dev_type$1(d).value,
          );
        }(),
    ];
  }

  /// Purpose: llama.cpp's system-info line. Inputs: None. Returns: String.
  /// Side effects: None. Notes: Diagnostics; call [load] first.
  static String systemInfo() =>
      llama_print_system_info().cast<Utf8>().toDartString();
}

/// Sampling for one generation, as plain values.
typedef LlamaSampling = ({
  int maxTokens,
  double temperature,
  int topK,
  double? topP,
  int? seed,
});

/// Why a generation ended.
enum LlamaStop {
  /// The model ended its turn.
  endOfTurn,

  /// The token limit was reached.
  length,

  /// The cancel flag was set.
  cancelled,
}

/// A loaded model and its context.
class LlamaSession {
  LlamaSession._(this._model, this._ctx, this._vocab, this.device);

  Pointer<llama_model> _model;
  Pointer<llama_context> _ctx;
  final Pointer<llama_vocab> _vocab;

  /// Purpose: The device the model's layers were assigned to: `CPU` or the
  /// GPU's ggml name. Inputs: None. Returns: String. Side effects: None.
  /// Notes: Assigned explicitly at load, never inferred afterwards.
  final String device;

  /// Purpose: Load a GGUF model and create its context.
  /// Inputs: [path]; [contextTokens] (capped at the model's training length);
  /// [batchTokens] per prefill chunk; [threads]; [gpu] to offload every
  /// layer to the first GPU ggml lists.
  /// Returns: The session.
  /// Side effects: Reads the file; allocates model and context memory.
  /// Notes: Throws [LlamaException] (`load`). Without [gpu], or without a
  /// GPU, no layer is offloaded.
  static LlamaSession load(
    String path, {
    int contextTokens = 4096,
    int batchTokens = 256,
    required int threads,
    bool gpu = false,
  }) {
    final gpuDevice = gpu
        ? LlamaLibrary.devices().where((d) => d.isGpu).firstOrNull
        : null;
    final mparams = llama_model_default_params()
      ..n_gpu_layers = gpuDevice == null ? 0 : 999;
    final native = path.toNativeUtf8();
    final Pointer<llama_model> model;
    try {
      model = llama_model_load_from_file(native.cast(), mparams);
    } finally {
      calloc.free(native);
    }
    if (model == nullptr) {
      throw LlamaException('load', 'The model at $path did not load.');
    }
    final trained = llama_model_n_ctx_train(model);
    final cparams = llama_context_default_params()
      ..n_ctx = trained > 0 && trained < contextTokens ? trained : contextTokens
      ..n_batch = batchTokens
      ..n_ubatch = batchTokens
      ..n_threads = threads
      ..n_threads_batch = threads;
    final ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
      llama_model_free(model);
      throw LlamaException('load', 'No context for the model at $path.');
    }
    return LlamaSession._(
      model,
      ctx,
      llama_model_get_vocab(model),
      gpuDevice?.name ?? 'CPU',
    );
  }

  /// Purpose: Context length in tokens. Inputs: None. Returns: int.
  /// Side effects: None. Notes: None.
  int get contextTokens => llama_n_ctx(_ctx);

  /// Purpose: Model description from llama.cpp. Inputs: None.
  /// Returns: e.g. `llama 135M Q4_K - Medium`. Side effects: None.
  /// Notes: None.
  String get description {
    final buf = calloc<Char>(256);
    try {
      final n = llama_model_desc(_model, buf, 256);
      return n <= 0 ? '' : buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  /// Purpose: Render chat messages with the model's own template.
  /// Inputs: [messages] as (role, content). Returns: The prompt text.
  /// Side effects: None.
  /// Notes: Falls back to ChatML when the model carries no template; the
  /// assistant turn is opened so generation answers. For a template with a
  /// thinking switch (`enable_thinking` and `<think>`), the empty think block
  /// is pre-filled, as the template itself does with thinking off.
  String applyTemplate(List<(String, String)> messages) {
    final arena = Arena();
    try {
      final builtIn = llama_model_chat_template(_model, nullptr);
      final source = builtIn == nullptr
          ? ''
          : builtIn.cast<Utf8>().toDartString();
      final thinkingOff =
          source.contains('enable_thinking') && source.contains('<think>')
          ? '<think>\n\n</think>\n\n'
          : '';
      final tmpl = builtIn == nullptr
          ? 'chatml'.toNativeUtf8(allocator: arena).cast<Char>()
          : builtIn;
      final chat = arena<llama_chat_message>(messages.length);
      var total = 0;
      for (var i = 0; i < messages.length; i++) {
        final (role, content) = messages[i];
        chat[i].role = role.toNativeUtf8(allocator: arena).cast();
        chat[i].content = content.toNativeUtf8(allocator: arena).cast();
        total += utf8.encode(role).length + utf8.encode(content).length;
      }
      var size = total * 2 + 256;
      for (var attempt = 0; attempt < 2; attempt++) {
        final buf = arena<Char>(size);
        final n = llama_chat_apply_template(
          tmpl,
          chat,
          messages.length,
          true,
          buf,
          size,
        );
        if (n < 0) {
          throw const LlamaException('load', 'The chat template failed.');
        }
        if (n <= size) {
          return utf8.decode(
                buf.cast<Uint8>().asTypedList(n),
                allowMalformed: true,
              ) +
              thinkingOff;
        }
        size = n;
      }
      throw const LlamaException('load', 'The chat template kept growing.');
    } finally {
      arena.releaseAll();
    }
  }

  /// Purpose: Tokenize [text].
  /// Inputs: [text]. Returns: Token ids.
  /// Side effects: None.
  /// Notes: Special tokens in the rendered template are parsed as such.
  List<int> tokenize(String text) {
    final bytes = utf8.encode(text);
    final arena = Arena();
    try {
      final native = arena<Uint8>(bytes.length + 1);
      native.asTypedList(bytes.length).setAll(0, bytes);
      var capacity = bytes.length + 16;
      for (var attempt = 0; attempt < 2; attempt++) {
        final tokens = arena<Int32>(capacity);
        final n = llama_tokenize(
          _vocab,
          native.cast(),
          bytes.length,
          tokens,
          capacity,
          true,
          true,
        );
        if (n >= 0) return tokens.asTypedList(n).toList();
        capacity = -n;
      }
      throw const LlamaException('tooLong', 'The prompt did not tokenize.');
    } finally {
      arena.releaseAll();
    }
  }

  /// Purpose: Generate a reply to a rendered prompt.
  /// Inputs: [prompt] tokens; [sampling]; [cancel], an `Int32` flag in native
  /// memory; [onPiece] receives each token's raw UTF-8 bytes; [onFirst] once
  /// prefill finished and the first token is sampled.
  /// Returns: Why generation stopped and how many tokens were produced.
  /// Side effects: Clears the context's memory; runs inference.
  /// Notes: Throws [LlamaException] (`tooLong`, `decode`). The prompt is
  /// decoded in chunks of the context's batch size, so a cancel waits for at
  /// most one chunk or one token.
  ({LlamaStop stop, int tokens}) generate(
    List<int> prompt, {
    required LlamaSampling sampling,
    required Pointer<Int32> cancel,
    required void Function(List<int> bytes) onPiece,
    void Function()? onFirst,
  }) {
    final n = contextTokens;
    if (prompt.isEmpty) {
      throw const LlamaException('tooLong', 'The prompt is empty.');
    }
    if (prompt.length >= n) {
      throw LlamaException(
        'tooLong',
        'The prompt has ${prompt.length} tokens; the context holds $n.',
      );
    }
    llama_memory_clear(llama_get_memory(_ctx), true);
    final sampler = _sampler(sampling);
    final batch = llama_n_batch(_ctx);
    final tokens = calloc<Int32>(prompt.length > 1 ? prompt.length : 1);
    final piece = calloc<Char>(256);
    try {
      tokens.asTypedList(prompt.length).setAll(0, prompt);
      for (var at = 0; at < prompt.length; at += batch) {
        if (cancel.value != 0) return (stop: LlamaStop.cancelled, tokens: 0);
        final count = prompt.length - at < batch ? prompt.length - at : batch;
        _decode(llama_batch_get_one(tokens + at, count));
      }
      var produced = 0;
      var position = prompt.length;
      final next = calloc<Int32>();
      try {
        while (true) {
          if (cancel.value != 0) {
            return (stop: LlamaStop.cancelled, tokens: produced);
          }
          if (produced >= sampling.maxTokens) {
            return (stop: LlamaStop.length, tokens: produced);
          }
          if (position >= n) {
            return (stop: LlamaStop.length, tokens: produced);
          }
          final token = llama_sampler_sample(sampler, _ctx, -1);
          if (produced == 0) onFirst?.call();
          if (llama_vocab_is_eog(_vocab, token)) {
            return (stop: LlamaStop.endOfTurn, tokens: produced);
          }
          final length = llama_token_to_piece(
            _vocab,
            token,
            piece,
            256,
            0,
            false,
          );
          if (length > 0) {
            onPiece(piece.cast<Uint8>().asTypedList(length).toList());
          }
          produced++;
          next.value = token;
          _decode(llama_batch_get_one(next, 1));
          position++;
        }
      } finally {
        calloc.free(next);
      }
    } finally {
      calloc.free(tokens);
      calloc.free(piece);
      llama_sampler_free(sampler);
    }
  }

  /// Purpose: Decode one batch. Inputs: [batch]. Returns: None.
  /// Side effects: Runs the model. Notes: Throws [LlamaException] (`decode`).
  void _decode(llama_batch batch) {
    final status = llama_decode(_ctx, batch);
    if (status != 0) {
      throw LlamaException('decode', 'llama_decode returned $status.');
    }
  }

  /// Purpose: Build the sampler chain. Inputs: [s]. Returns: The chain.
  /// Side effects: Allocates it. Notes: Greedy when temperature is zero or
  /// top-k is one, which keeps prompts deterministic.
  Pointer<llama_sampler> _sampler(LlamaSampling s) {
    final chain = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    if (s.temperature <= 0 || s.topK == 1) {
      llama_sampler_chain_add(chain, llama_sampler_init_greedy());
      return chain;
    }
    if (s.topK > 0) {
      llama_sampler_chain_add(chain, llama_sampler_init_top_k(s.topK));
    }
    if (s.topP case final p?) {
      llama_sampler_chain_add(chain, llama_sampler_init_top_p(p, 1));
    }
    llama_sampler_chain_add(chain, llama_sampler_init_temp(s.temperature));
    llama_sampler_chain_add(
      chain,
      llama_sampler_init_dist(s.seed ?? 0xFFFFFFFF),
    );
    return chain;
  }

  /// Purpose: Free the context and model.
  /// Inputs: None. Returns: None. Side effects: Frees native memory.
  /// Notes: Safe to call more than once; never while generating.
  void release() {
    if (_ctx != nullptr) llama_free(_ctx);
    if (_model != nullptr) llama_model_free(_model);
    _ctx = nullptr;
    _model = nullptr;
  }
}
