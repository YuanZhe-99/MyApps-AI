import 'dart:io';

import 'package:myapps_ai_asr/myapps_ai_asr.dart';

import 'native/sherpa.dart';

/// Where a diarizer finds its two model files.
///
/// Applications own which artifact holds them and when it is installed; this
/// package only reads the files.
typedef SherpaDiarizerModels =
    Future<({String segmentation, String embedding})?> Function();

/// Offline speaker diarization through sherpa-onnx: pyannote segmentation,
/// a speaker embedding and clustering, on a worker isolate of its own.
///
/// Speaker numbers are local to one window; joining them across windows is
/// application work.
class SherpaDiarizer implements AsrDiarizer {
  /// Purpose: Create a diarizer.
  /// Inputs: [models] locates the installed files; [threads] (host default).
  /// Returns: A new diarizer; the worker starts on first use.
  /// Side effects: None.
  /// Notes: Use [findDiarizerModels] inside [models] for the published
  /// archive layout.
  SherpaDiarizer({required this.models, int? threads})
    : threads = threads ?? AsrHost.current().threads;

  /// Purpose: Locates the installed model files.
  /// Inputs: None. Returns: [SherpaDiarizerModels]. Side effects: None.
  /// Notes: None.
  final SherpaDiarizerModels models;

  /// Purpose: CPU threads for both models.
  /// Inputs: None. Returns: int. Side effects: None. Notes: None.
  final int threads;

  NativeWorker? _worker;

  @override
  Future<bool> available() async => await models() != null;

  @override
  Future<List<SpeakerTurn>> diarize(String pcmWindow) async {
    final files = await models();
    if (files == null) {
      throw const AsrException(
        AsrErrorCode.modelMissing,
        'The speaker-label models are not on this device.',
      );
    }
    final worker = _worker ??= await NativeWorker.spawn(
      _diarizerWorker,
      debugName: 'speaker-labels',
    );
    final answer = await worker.call(
      _Diarize(files.segmentation, files.embedding, pcmWindow, threads),
    );
    if (answer is! List<SherpaSpeakerTurn>) {
      throw AsrException(AsrErrorCode.deviceUnavailable, '$answer');
    }
    return [
      for (final turn in answer)
        SpeakerTurn(start: turn.start, end: turn.end, speaker: turn.speaker),
    ];
  }

  /// Purpose: Stop the worker.
  /// Inputs: None. Returns: None.
  /// Side effects: Kills the isolate, freeing the models with it.
  /// Notes: For tests and tools.
  void dispose() {
    _worker?.close();
    _worker = null;
  }
}

/// Purpose: Find the two diarization model files in an installed folder.
/// Inputs: The artifact [dir].
/// Returns: Their paths, or null when either is missing.
/// Side effects: Lists the folder recursively.
/// Notes: Same layout rule as MyTranscribe's speaker-labels package: the
/// segmentation archive unpacks into a folder of its own name holding
/// `model.onnx`; the embedding file name contains `campplus`.
({String segmentation, String embedding})? findDiarizerModels(Directory dir) {
  if (!dir.existsSync()) return null;
  String? segmentation;
  String? embedding;
  for (final entry in dir.listSync(recursive: true)) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    if (name == 'model.onnx' && entry.path.contains('segmentation')) {
      segmentation = entry.path;
    } else if (name.contains('campplus') && name.endsWith('.onnx')) {
      embedding = entry.path;
    }
  }
  if (segmentation == null || embedding == null) return null;
  return (segmentation: segmentation, embedding: embedding);
}

class _Diarize {
  /// Purpose: Ask to diarize a window. Inputs: All fields.
  /// Returns: A request. Side effects: None. Notes: Internal.
  const _Diarize(this.segmentation, this.embedding, this.wavPath, this.threads);
  final String segmentation;
  final String embedding;
  final String wavPath;
  final int threads;
}

SpeakerDiarizer? _diarizer;
String? _loadedFrom;

/// Purpose: Diarization worker handler.
/// Inputs: A [_Diarize] request. Returns: The turns.
/// Side effects: Loads the models once (again when their paths change).
/// Notes: Internal; runs on the worker isolate only.
Future<Object?> _diarizerWorker(Object? request) async {
  if (request is! _Diarize) {
    return const NativeWorkerFailure('Unknown request.');
  }
  final key = '${request.segmentation}\n${request.embedding}';
  if (_diarizer == null || _loadedFrom != key) {
    _diarizer?.release();
    _diarizer = SpeakerDiarizer.load(
      segmentation: request.segmentation,
      embedding: request.embedding,
      threads: request.threads,
    );
    _loadedFrom = key;
  }
  final window = await readPcmWindow(File(request.wavPath));
  return _diarizer!.process(await window.readSamples());
}
