import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';
import 'package:path/path.dart' as p;

import 'native/llama.dart';

/// Backend id model manifests name for llama.cpp GGUF artifacts.
const llamaCppBackendId = 'llama.cpp';

/// Purpose: Find the GGUF file of an installed artifact.
/// Inputs: Its [manifest] and installed [artifactDir].
/// Returns: The absolute path, or null when the manifest lists no `.gguf`.
/// Side effects: None.
/// Notes: The first `.gguf` entry is the model; split models are not
/// supported yet.
String? llamaModelPath(ArtifactManifest manifest, Directory artifactDir) {
  for (final file in manifest.files) {
    if (file.path.toLowerCase().endsWith('.gguf')) {
      return p.join(artifactDir.path, file.path);
    }
  }
  return null;
}

/// llama.cpp text generation on this device.
///
/// One long-lived worker isolate owns the model and context; generation
/// streams deltas back to the caller. Model files come from model
/// management: this backend never downloads.
class LlamaCppBackend implements LlmBackend {
  /// Purpose: Create a backend for one GGUF file.
  /// Inputs: [modelPath]; [contextTokens]; [batchTokens] per prefill chunk;
  /// [threads] (half the processors, at least one, by default); [gpu] to
  /// offload every layer to the first GPU ggml lists; [id].
  /// Returns: A backend; nothing loads until [load] or [generate].
  /// Side effects: None.
  /// Notes: [gpu] is off by default: GPU routes ship only once verified.
  LlamaCppBackend({
    required this.modelPath,
    this.contextTokens = 4096,
    this.batchTokens = 256,
    int? threads,
    this.gpu = false,
    this.id = llamaCppBackendId,
  }) : threads =
           threads ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 8).toInt();

  /// Purpose: GGUF model file. Inputs: None. Returns: String.
  /// Side effects: None. Notes: None.
  final String modelPath;

  /// Purpose: Requested context length. Inputs: None. Returns: int.
  /// Side effects: None. Notes: Capped at the model's training length.
  final int contextTokens;

  /// Purpose: Prefill chunk size. Inputs: None. Returns: int.
  /// Side effects: None. Notes: Bounds cancel latency during prefill.
  final int batchTokens;

  /// Purpose: CPU threads. Inputs: None. Returns: int. Side effects: None.
  /// Notes: None.
  final int threads;

  /// Purpose: Whether to offload to a GPU. Inputs: None. Returns: bool.
  /// Side effects: None. Notes: Experimental until verified per device.
  final bool gpu;

  @override
  final String id;

  @override
  Set<LlmAbility> get abilities => const {LlmAbility.streaming};

  _Worker? _worker;
  _Loaded? _loaded;
  Future<_Loaded>? _loading;
  Completer<void>? _running;
  final Pointer<Int32> _cancel = calloc<Int32>();

  /// Purpose: Model facts after [load]: description, context length and the
  /// assigned device. Inputs: None. Returns: Record or null.
  /// Side effects: None. Notes: Diagnostics.
  ({String description, int contextTokens, String device})? get loadedModel =>
      switch (_loaded) {
        final l? => (
          description: l.description,
          contextTokens: l.contextTokens,
          device: l.device,
        ),
        null => null,
      };

  @override
  Future<GenAiStatusReport> status() async {
    if (!File(modelPath).existsSync()) {
      return const GenAiStatusReport(
        GenAiStatus.unavailable,
        detail: 'modelMissing',
      );
    }
    final answer = await (await _ensureWorker()).call(const _Info());
    return switch (answer) {
      String version => GenAiStatusReport(
        GenAiStatus.available,
        detail: _loaded == null ? 'notLoaded' : 'loaded',
        variant: 'ggml $version',
      ),
      _Failure(:final kind) when kind == 'notBuilt' => const GenAiStatusReport(
        GenAiStatus.unsupported,
      ),
      final _Failure f => GenAiStatusReport(
        GenAiStatus.unavailable,
        detail: f.kind,
      ),
      _ => const GenAiStatusReport(GenAiStatus.unknown),
    };
  }

  @override
  Future<void> load() async {
    if (_loaded != null) return;
    await (_loading ??= _doLoad().whenComplete(() => _loading = null));
  }

  /// Purpose: Load on the worker. Inputs: None. Returns: Loaded facts.
  /// Side effects: Allocates model memory on the worker.
  /// Notes: Internal; maps failures to [GenAiException].
  Future<_Loaded> _doLoad() async {
    if (!File(modelPath).existsSync()) {
      throw const GenAiException(
        GenAiFailure.unavailable,
        'The model file is not on this device.',
      );
    }
    final answer = await (await _ensureWorker()).call(
      _Load(modelPath, contextTokens, batchTokens, threads, gpu),
    );
    if (answer is _Loaded) return _loaded = answer;
    final failure = answer is _Failure ? answer : _Failure('load', '$answer');
    throw GenAiException(
      GenAiFailure.unavailable,
      '${failure.kind}: ${failure.message}',
    );
  }

  @override
  Future<void> unload() async {
    await cancel();
    await _loading?.catchError((_) => _Loaded.none);
    if (_loaded == null) return;
    await _worker?.call(const _Release());
    _loaded = null;
  }

  @override
  Stream<LlmEvent> generate(LlmRequest request) {
    late StreamController<LlmEvent> out;
    out = StreamController<LlmEvent>(
      onListen: () => _run(request, out),
      onCancel: () => cancel(),
    );
    return out.stream;
  }

  /// Purpose: Run one request into [out].
  /// Inputs: [request], [out]. Returns: None.
  /// Side effects: Loads if needed; runs inference on the worker.
  /// Notes: Internal. A second request while one runs fails with `busy`.
  Future<void> _run(LlmRequest request, StreamController<LlmEvent> out) async {
    if (_running != null) {
      out.addError(
        const GenAiException(GenAiFailure.busy, 'Generation is running.'),
      );
      await out.close();
      return;
    }
    final running = _running = Completer<void>();
    _cancel.value = 0;
    final watch = Stopwatch();
    try {
      await load();
      // Timings cover generation only; loading is reported by [load].
      watch.start();
      final loaded = _loaded!;
      if (_cancel.value != 0) {
        out.add(
          LlmDone(LlmFinish.cancelled, LlmMetrics(device: loaded.device)),
        );
        return;
      }
      final replies = ReceivePort();
      _worker!.send(
        _Generate(
          [for (final m in request.messages) (m.role.name, m.content)],
          (
            maxTokens: request.sampling.maxOutputTokens,
            temperature: request.sampling.temperature,
            topK: request.sampling.topK,
            topP: request.sampling.topP,
            seed: request.sampling.seed,
          ),
          request.sampling.stop,
          _cancel.address,
          replies.sendPort,
        ),
      );
      Duration? first;
      await for (final message in replies) {
        switch (message) {
          case String text:
            first ??= watch.elapsed;
            if (!out.isClosed) out.add(LlmDelta(text));
          case _Finished f:
            replies.close();
            if (out.isClosed) break;
            out.add(
              LlmDone(
                switch (f.stop) {
                  'cancelled' => LlmFinish.cancelled,
                  'length' => LlmFinish.length,
                  _ => LlmFinish.stop,
                },
                LlmMetrics(
                  device: loaded.device,
                  promptTokens: f.promptTokens,
                  outputTokens: f.outputTokens,
                  firstToken: first,
                  total: watch.elapsed,
                ),
              ),
            );
          case _Failure f:
            replies.close();
            if (!out.isClosed) {
              out.addError(
                GenAiException(
                  f.kind == 'tooLong'
                      ? GenAiFailure.tooLong
                      : GenAiFailure.failed,
                  f.message,
                ),
              );
            }
        }
      }
    } on GenAiException catch (e) {
      if (!out.isClosed) out.addError(e);
    } finally {
      _running = null;
      running.complete();
      if (!out.isClosed) await out.close();
    }
  }

  @override
  Future<void> cancel() async {
    final running = _running;
    if (running == null) return;
    _cancel.value = 1;
    await running.future;
  }

  /// Purpose: Free everything and stop the worker.
  /// Inputs: None. Returns: None.
  /// Side effects: Unloads; kills the isolate; frees the cancel flag.
  /// Notes: The backend is unusable afterwards.
  Future<void> dispose() async {
    await unload();
    _worker?.close();
    _worker = null;
    calloc.free(_cancel);
  }

  /// Purpose: Start the worker once. Inputs: None. Returns: The worker.
  /// Side effects: Spawns an isolate. Notes: Internal.
  Future<_Worker> _ensureWorker() async => _worker ??= await _Worker.spawn();
}

// ── Worker protocol ──

class _Info {
  /// Purpose: Ask for the library version. Inputs: None. Returns: Request.
  /// Side effects: None. Notes: Internal.
  const _Info();
}

class _Load {
  /// Purpose: Ask to load a model. Inputs: All fields. Returns: Request.
  /// Side effects: None. Notes: Internal.
  const _Load(this.path, this.context, this.batch, this.threads, this.gpu);
  final String path;
  final int context;
  final int batch;
  final int threads;
  final bool gpu;
}

class _Release {
  /// Purpose: Ask to free the model. Inputs: None. Returns: Request.
  /// Side effects: None. Notes: Internal.
  const _Release();
}

class _Generate {
  /// Purpose: Ask to generate, streaming to [reply]. Inputs: All fields.
  /// Returns: Request. Side effects: None. Notes: Internal.
  const _Generate(
    this.messages,
    this.sampling,
    this.stop,
    this.cancel,
    this.reply,
  );
  final List<(String, String)> messages;
  final LlamaSampling sampling;
  final List<String> stop;
  final int cancel;
  final SendPort reply;
}

class _Loaded {
  /// Purpose: Loaded model facts. Inputs: All fields. Returns: Value.
  /// Side effects: None. Notes: Internal.
  const _Loaded(this.description, this.contextTokens, this.device);
  static const none = _Loaded('', 0, '');
  final String description;
  final int contextTokens;
  final String device;
}

class _Finished {
  /// Purpose: End of a generation. Inputs: All fields. Returns: Value.
  /// Side effects: None. Notes: Internal.
  const _Finished(this.stop, this.promptTokens, this.outputTokens);
  final String stop;
  final int promptTokens;
  final int outputTokens;
}

class _Failure {
  /// Purpose: A failure answer. Inputs: [kind], [message]. Returns: Value.
  /// Side effects: None. Notes: Internal.
  const _Failure(this.kind, this.message);
  final String kind;
  final String message;
}

/// The main isolate's end of the worker.
class _Worker {
  _Worker._(this._isolate, this._send, this._receive) {
    _receive.listen((message) {
      final (id, result) = message as (int, Object?);
      _pending.remove(id)?.complete(result);
    });
  }

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final _pending = <int, Completer<Object?>>{};
  var _next = 0;

  /// Purpose: Start the worker. Inputs: None. Returns: Worker.
  /// Side effects: Spawns an isolate. Notes: Internal.
  static Future<_Worker> spawn() async {
    final handshake = ReceivePort();
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      handshake.sendPort,
      replies.sendPort,
    ), debugName: 'llama.cpp');
    final send = await handshake.first as SendPort;
    return _Worker._(isolate, send, replies);
  }

  /// Purpose: Send a request and await its answer. Inputs: [request].
  /// Returns: Answer. Side effects: Worker's. Notes: Serialised on the worker.
  Future<Object?> call(Object request) {
    final id = _next++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send.send((id, request));
    return completer.future;
  }

  /// Purpose: Send a streaming request whose answers go to its own port.
  /// Inputs: [request]. Returns: None. Side effects: Worker's.
  /// Notes: Serialised with [call] requests.
  void send(_Generate request) => _send.send((-1, request));

  /// Purpose: Kill the worker. Inputs: None. Returns: None.
  /// Side effects: Kills the isolate. Notes: Release the model first.
  void close() {
    _isolate.kill();
    _receive.close();
  }
}

/// Purpose: Worker entry point.
/// Inputs: Handshake and reply ports. Returns: None.
/// Side effects: Owns the library and model; serves requests one at a time.
/// Notes: Internal. Answers are values; no exception crosses isolates.
void _main((SendPort, SendPort) ports) {
  final (handshake, replies) = ports;
  final requests = ReceivePort();
  handshake.send(requests.sendPort);
  LlamaSession? session;

  Object? handle(Object request) {
    try {
      switch (request) {
        case _Info():
          return LlamaLibrary.load() ??
              const _Failure('notBuilt', 'llama.cpp is not built here.');
        case _Load():
          if (LlamaLibrary.load() == null) {
            return const _Failure('notBuilt', 'llama.cpp is not built here.');
          }
          session?.release();
          final s = session = LlamaSession.load(
            request.path,
            contextTokens: request.context,
            batchTokens: request.batch,
            threads: request.threads,
            gpu: request.gpu,
          );
          return _Loaded(s.description, s.contextTokens, s.device);
        case _Release():
          session?.release();
          session = null;
          return null;
        case _Generate():
          final s = session;
          if (s == null) return const _Failure('load', 'No model is loaded.');
          final prompt = s.tokenize(s.applyTemplate(request.messages));
          final text = _TextStream(request.stop, request.reply.send);
          final decoder = utf8.decoder.startChunkedConversion(text);
          final cancel = Pointer<Int32>.fromAddress(request.cancel);
          final result = s.generate(
            prompt,
            sampling: request.sampling,
            cancel: cancel,
            onPiece: (bytes) {
              if (!text.stopped) decoder.add(bytes);
              if (text.stopped) cancel.value = 2;
            },
          );
          decoder.close();
          final stop = text.stopped
              ? 'stop'
              : switch (result.stop) {
                  LlamaStop.cancelled => 'cancelled',
                  LlamaStop.length => 'length',
                  LlamaStop.endOfTurn => 'stop',
                };
          return _Finished(stop, prompt.length, result.tokens);
      }
    } on LlamaException catch (e) {
      return _Failure(e.kind, e.message);
    } catch (e) {
      return _Failure('failed', '$e');
    }
    return const _Failure('failed', 'Unknown request.');
  }

  requests.listen((message) {
    final (id, request) = message as (int, Object);
    final answer = handle(request);
    if (request is _Generate) {
      request.reply.send(answer);
    } else {
      replies.send((id, answer));
    }
  });
}

/// Turns decoded text into deltas, holding back text that could begin a stop
/// string and ending at the first stop string.
class _TextStream implements Sink<String> {
  /// Purpose: Create the filter. Inputs: [stops], [emit].
  /// Returns: Sink. Side effects: None. Notes: Internal.
  _TextStream(this.stops, this.emit)
    : _hold = stops.fold(0, (m, s) => s.length > m ? s.length : m);

  final List<String> stops;
  final void Function(Object?) emit;
  final int _hold;
  var _pending = '';
  var _lead = '';
  var _leading = true;

  static const _open = '<think>';
  static const _close = '</think>';

  /// Purpose: Whether a stop string was reached. Inputs: None.
  /// Returns: bool. Side effects: None. Notes: Internal.
  bool stopped = false;

  /// Purpose: Accept decoded text. Inputs: [chunk]. Returns: None.
  /// Side effects: Emits deltas. Notes: Internal.
  @override
  void add(String chunk) {
    if (stopped || chunk.isEmpty) return;
    if (_leading) {
      chunk = _skipReasoning(chunk);
      if (chunk.isEmpty) return;
    }
    _pending += chunk;
    for (final stop in stops) {
      final at = stop.isEmpty ? -1 : _pending.indexOf(stop);
      if (at >= 0) {
        if (at > 0) emit(_pending.substring(0, at));
        _pending = '';
        stopped = true;
        return;
      }
    }
    final keep = _hold > 1 ? _hold - 1 : 0;
    if (_pending.length > keep) {
      emit(_pending.substring(0, _pending.length - keep));
      _pending = _pending.substring(_pending.length - keep);
    }
  }

  /// Purpose: Drop a leading reasoning block and the whitespace after it.
  /// Inputs: [chunk]. Returns: Text to keep; empty while still deciding.
  /// Side effects: Buffers the start of the reply. Notes: Internal; only a
  /// block at the very start counts, so a reply that mentions the tag later
  /// is untouched.
  String _skipReasoning(String chunk) {
    _lead += chunk;
    final trimmed = _lead.trimLeft();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith(_open)) {
      final end = trimmed.indexOf(_close);
      if (end < 0) return '';
      final rest = trimmed.substring(end + _close.length).trimLeft();
      if (rest.isEmpty) {
        _lead = '';
        return '';
      }
      _leading = false;
      _lead = '';
      return rest;
    }
    if (_open.startsWith(trimmed)) return '';
    _leading = false;
    final kept = trimmed;
    _lead = '';
    return kept;
  }

  /// Purpose: Flush held text. Inputs: None. Returns: None.
  /// Side effects: Emits the rest. Notes: Internal.
  @override
  void close() {
    if (_leading &&
        _lead.trim().isNotEmpty &&
        !_lead.trimLeft().startsWith(_open)) {
      _pending += _lead.trimLeft();
    }
    if (!stopped && _pending.isNotEmpty) emit(_pending);
    _pending = '';
  }
}
