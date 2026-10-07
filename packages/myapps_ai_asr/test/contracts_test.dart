/// Engine contract helpers: result collection, diarization labels, token
/// grouping, host rules, tested-route table and the native worker.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_asr/myapps_ai_asr.dart';
import 'package:myapps_ai_asr/testing.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

/// Purpose: Worker handler for the isolate test.
/// Inputs: [request]. Returns: Doubled int, or throws.
/// Side effects: None. Notes: Top-level so it can cross isolates.
Object? _double(Object? request) {
  if (request == 'boom') throw StateError('boom');
  return (request as int) * 2;
}

void main() {
  group('a window result', () {
    final route = fakeAsrRoute(adapterId: 'a', modelId: 'm', artifactId: 'x');
    const manifest = ArtifactManifest(
      artifactId: 'x',
      modelId: 'm',
      backendId: 'a',
      format: ArtifactFormat.ggml,
      revision: 'r',
      files: [],
      licenseId: 'MIT',
    );

    Future<Stream<AsrEvent>> run(FakeAsrEngine engine, String job) async {
      final session = await engine.prepare(
        AsrPrepareRequest(
          route: route,
          manifest: manifest,
          artifactDir: Directory.systemTemp,
        ),
      );
      return engine.transcribe(
        AsrRequest(
          jobId: job,
          sessionId: session.sessionId,
          pcmWindow: File('assets/jfk.wav'),
          windowSeconds: 11,
        ),
      );
    }

    test('collects segments, placement and timestamps', () async {
      final engine = FakeAsrEngine(adapterId: 'a', routes: [route]);
      final result = await AsrResult.collect(await run(engine, 'j'));
      expect(result.text, 'window 0');
      expect(result.placement, PlacementKind.cpu);
      expect(result.hasRealTimestamps, isTrue);
    });

    test('rethrows an error event', () async {
      final engine = FakeAsrEngine(
        adapterId: 'a',
        routes: [route],
        script: (_, _) => const FakeAsrWindow(
          error: AsrException(AsrErrorCode.deviceLost, 'gone'),
        ),
      );
      await expectLater(
        AsrResult.collect(await run(engine, 'j')),
        throwsA(
          isA<AsrException>().having(
            (e) => e.code,
            'code',
            AsrErrorCode.deviceLost,
          ),
        ),
      );
    });

    test('a cancel completes only after the window stopped', () async {
      final engine = FakeAsrEngine(
        adapterId: 'a',
        routes: [route],
        script: (_, _) => const FakeAsrWindow(delay: Duration(seconds: 5)),
      );
      final events = <AsrEventType>[];
      final done = (await run(engine, 'j')).forEach((e) => events.add(e.type));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await engine.cancel('j');
      await done;
      expect(events.last, AsrEventType.cancelled);
      expect(
        [for (final e in events) e],
        [AsrEventType.started, AsrEventType.cancelled],
      );
    });
  });

  group('speaker labels', () {
    AsrSegment seg(double start, double end) =>
        AsrSegment(startSeconds: start, endSeconds: end, text: 'x');

    test('each segment takes the speaker it overlaps most', () {
      final labelled = labelSegments(
        [seg(0, 4), seg(4, 10)],
        const [
          SpeakerTurn(start: 0, end: 5, speaker: 0),
          SpeakerTurn(start: 5, end: 10, speaker: 1),
        ],
      );
      expect(labelled.map((s) => s.speaker), ['S1', 'S2']);
    });

    test('overlap is summed per speaker across turns', () {
      final labelled = labelSegments(
        [seg(0, 10)],
        const [
          SpeakerTurn(start: 0, end: 3, speaker: 0),
          SpeakerTurn(start: 3, end: 7, speaker: 1),
          SpeakerTurn(start: 7, end: 10, speaker: 0),
        ],
      );
      expect(labelled.single.speaker, 'S1');
    });

    test('a segment no turn touches keeps no speaker', () {
      final labelled = labelSegments(
        [seg(20, 25)],
        const [SpeakerTurn(start: 0, end: 5, speaker: 0)],
      );
      expect(labelled.single.speaker, isNull);
      expect(labelled.single.text, 'x');
    });

    test('a failing diarizer leaves the window unlabelled', () async {
      final segments = [seg(0, 1)];
      expect(await labelWindow(null, 'x.wav', segments), same(segments));
      expect(
        await labelWindow(_FailingDiarizer(), 'x.wav', segments),
        same(segments),
      );
    });
  });

  group('timed tokens', () {
    test('cut at sentence ends and keep token and word times', () {
      final lines = sentencesFromTokens(const [
        TimedToken('▁Hel', 0.0, 0.2),
        TimedToken('lo', 0.2, 0.4),
        TimedToken('▁world', 0.4, 0.8),
        TimedToken('.', 0.8, 0.9),
        TimedToken('▁How', 1.2, 1.4),
        TimedToken('▁are', 1.4, 1.5),
        TimedToken('▁you', 1.5, 1.7),
        TimedToken('?', 1.7, 1.8),
      ]);
      expect(lines.map((s) => s.text), ['Hello world.', 'How are you?']);
      expect(lines.first.startSeconds, 0.0);
      expect(lines.first.endSeconds, 0.9);
      expect(lines.first.words.map((w) => w.text), ['Hello', 'world.']);
      expect(lines.first.words.first.endSeconds, 0.4);
      expect(lines.last.startSeconds, 1.2);
    });

    test('drop control tokens and cut a long sentence at a word', () {
      final lines = sentencesFromTokens([
        const TimedToken('<unk>', 0, 0),
        for (var i = 0; i < 30; i++) TimedToken('▁w$i', i.toDouble(), i + 0.5),
      ]);
      expect(lines, hasLength(2));
      expect(lines.first.text, startsWith('w0 '));
      expect(lines.last.startSeconds, greaterThan(maxSentenceSeconds));
    });

    test('text without times spans the window; silence gives nothing', () {
      final one = segmentsFromTimedText(' Hello. ', const [], 30);
      expect(one.single.text, 'Hello.');
      expect(one.single.endSeconds, 30);
      expect(segmentsFromTimedText('  ', const [], 30), isEmpty);
    });
  });

  group('the host', () {
    test('device classes follow the support matrix', () {
      expect(
        asrDeviceClass(
          platform: 'windows',
          architecture: 'arm64',
          processor: 'Qualcomm Oryon',
        ),
        'windows-arm64-qualcomm',
      );
      expect(
        asrDeviceClass(platform: 'windows', architecture: 'x64'),
        'windows-x64',
      );
      expect(
        asrDeviceClass(platform: 'linux', architecture: 'x64'),
        'linux-x64',
      );
      expect(asrDeviceClass(platform: 'ios', architecture: 'arm64'), 'ios');
    });

    test('thread counts match MyTranscribe', () {
      expect(asrDefaultThreads(8, mobile: true), 4);
      expect(asrDefaultThreads(8, mobile: false), 6);
      expect(asrDefaultThreads(4, mobile: false), 3);
      expect(asrDefaultThreads(32, mobile: false), 8);
      expect(asrDefaultThreads(1, mobile: false), 1);
    });

    test('the tested-route table flags only its rows', () {
      const table = TestedRouteTable(
        deviceClass: 'macos-arm64',
        rows: [(deviceClass: 'macos-arm64', adapterId: 'a', backend: 'metal')],
      );
      final metal = fakeAsrRoute(
        adapterId: 'a',
        modelId: 'm',
        artifactId: 'x',
        backend: 'metal',
      );
      final cpu = fakeAsrRoute(adapterId: 'a', modelId: 'm', artifactId: 'x');
      expect(table.apply(metal).testedHere, isTrue);
      expect(table.apply(cpu).testedHere, isFalse);
    });
  });

  test('the native worker answers in order and never throws across', () async {
    final worker = await NativeWorker.spawn(_double);
    try {
      expect(await Future.wait([worker.call(1), worker.call(2)]), [2, 4]);
      expect(await worker.call('boom'), isA<NativeWorkerFailure>());
      expect(await worker.call(3), 6);
    } finally {
      worker.close();
    }
  });

  test('similarity ignores case and punctuation', () {
    expect(
      textSimilarity(
        'And so, my fellow Americans: ask not.',
        'and so my fellow americans ask not',
      ),
      1,
    );
    expect(textSimilarity('one two three four', 'one two four'), 0.75);
    expect(asrSelfTestMinSimilarity, 0.8);
  });
}

class _FailingDiarizer implements AsrDiarizer {
  @override
  Future<bool> available() async => true;

  @override
  Future<List<SpeakerTurn>> diarize(String pcmWindow) => throw StateError('x');
}
