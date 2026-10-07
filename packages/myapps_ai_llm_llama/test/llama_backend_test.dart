import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm/myapps_ai_llm.dart';
import 'package:myapps_ai_llm_llama/myapps_ai_llm_llama.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

LlmRequest _ask(String text, {LlmSampling sampling = const LlmSampling()}) =>
    LlmRequest(
      messages: [
        const LlmMessage(LlmRole.system, 'You are a helpful assistant.'),
        LlmMessage(LlmRole.user, text),
      ],
      sampling: sampling,
    );

void main() {
  group('manifest', () {
    final manifest =
        jsonDecode(File('native/binaries.json').readAsStringSync())
            as Map<String, dynamic>;

    test('every entry is pinned by hash and ships its entry library', () {
      final sets = <Map<String, dynamic>>[
        ...(manifest['targets'] as Map).values.cast(),
        for (final v in (manifest['variants'] as Map).values)
          ...(v as Map).values.cast<Map<String, dynamic>>(),
      ];
      for (final set in sets) {
        expect(set['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(set['url'], startsWith('https://github.com/ggml-org/'));
        expect(set['url'], contains('/$llamaUpstreamTag/'));
        final names = [
          for (final f in set['files'] as List)
            (f['as'] ?? (f['from'] as String).split('/').last) as String,
        ];
        expect(names, contains(set['entry']));
        expect(
          names.where((n) => n.contains('common') || n.contains('mtmd')),
          isEmpty,
          reason: 'only llama and ggml are bundled',
        );
      }
    });

    test('the ggml version matches the bindings', () {
      expect(manifest['upstream']['tag'], llamaUpstreamTag);
      expect(manifest['upstream']['ggml'], llamaGgmlVersion);
    });
  });

  test('the model path is the GGUF entry of the manifest', () {
    ArtifactManifest manifest(String path) => ArtifactManifest(
      artifactId: 'a',
      modelId: 'local:a',
      backendId: llamaCppBackendId,
      format: ArtifactFormat.gguf,
      revision: 'r',
      files: [ArtifactFile(path: path, bytes: 1, sha256: 'x', sourceUrl: 'u')],
      licenseId: 'Apache-2.0',
    );
    final dir = Directory('/models/a');
    expect(
      llamaModelPath(manifest('Model.Q4.GGUF'), dir),
      '/models/a/Model.Q4.GGUF',
    );
    expect(llamaModelPath(manifest('model.bin'), dir), isNull);
  });

  test('the catalog lists the supported 4-bit models, pinned', () {
    expect(llamaModelCatalog.map((m) => m.modelId), [
      'local:qwen3.5-0.8b',
      'local:qwen3.5-2b',
      'local:gemma-4-e2b-it',
    ]);
    for (final m in llamaModelCatalog) {
      expect(m.backendId, llamaCppBackendId);
      expect(m.format, ArtifactFormat.gguf);
      expect(m.quantization, startsWith('q4'));
      final file = m.files.single;
      expect(file.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(file.sourceUrl, contains('/resolve/${m.revision}/'));
      expect(m.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(llamaModelPath(m, Directory('/m')), '/m/${file.path}');
      expect(
        ArtifactManifest.fromJson(m.toJson()).files.single.sha256,
        file.sha256,
      );
    }
  });

  test('the pinned build supports every catalog model', () {
    expect(llamaPinnedBuild, 11457);
    for (final m in llamaModelCatalog) {
      expect(llamaMinimumBuild(m), lessThanOrEqualTo(llamaPinnedBuild));
    }
    expect(llamaCatalogFor(), llamaModelCatalog);
    expect(llamaCatalogFor(8000).map((m) => m.modelId), [
      'local:qwen3.5-0.8b',
      'local:qwen3.5-2b',
    ], reason: 'an older build drops models it cannot load');
    expect(llamaCatalogFor(7000), isEmpty);
    expect(
      llamaMinimumBuild(
        ArtifactManifest.fromJson(llamaModelCatalog.last.toJson()),
      ),
      8637,
      reason: 'the field survives installed manifests',
    );
  });

  test('the prebuilt library loads with a CPU device', () {
    expect(LlamaLibrary.load(), llamaGgmlVersion);
    expect(LlamaLibrary.devices().map((d) => d.type), contains(0));
  });

  test('a missing model is unavailable and never loads', () async {
    final backend = LlamaCppBackend(modelPath: '/nonexistent/model.gguf');
    addTearDown(backend.dispose);
    final report = await backend.status();
    expect(report.status, GenAiStatus.unavailable);
    expect(report.detail, 'modelMissing');
    await expectLater(
      backend.load(),
      throwsA(
        isA<GenAiException>().having(
          (e) => e.failure,
          'failure',
          GenAiFailure.unavailable,
        ),
      ),
    );
    await expectLater(
      backend.generate(_ask('hi')).toList(),
      throwsA(isA<GenAiException>()),
    );
  });

  test('the compute preference reads back, unknown as CPU only', () {
    for (final v in LlmComputePreference.values) {
      expect(LlmComputePreference.parse(v.name), v);
    }
    expect(LlmComputePreference.parse('gpu'), LlmComputePreference.cpuOnly);
    expect(LlmComputePreference.parse(null), LlmComputePreference.cpuOnly);
    expect(
      LlamaCppBackend(modelPath: '/m/a.gguf').compute,
      LlmComputePreference.cpuOnly,
    );
    expect(
      LlamaCppBackend(modelPath: '/m/a.gguf').gpuFailureKey,
      'llama.cpp $llamaUpstreamTag|a.gguf',
    );
  });

  final model = Platform.environment['LLAMA_TEST_MODEL'];
  group('with a model', () {
    late LlamaCppBackend backend;
    setUpAll(() async {
      backend = LlamaCppBackend(modelPath: model!, contextTokens: 2048);
      await backend.load();
      await backend.load();
    });
    tearDownAll(() => backend.dispose());

    test('a GPU that failed before is skipped and the reason kept', () async {
      final failures = MemoryLlamaGpuFailures();
      final auto = LlamaCppBackend(
        modelPath: model!,
        contextTokens: 512,
        compute: LlmComputePreference.auto,
        gpuFailures: failures,
      );
      addTearDown(auto.dispose);
      await failures.record(auto.gpuFailureKey, 'decode: test');
      final (text, done) = await collectLlm(auto.generate(_ask('Say hi.')));
      expect(text, isNotEmpty);
      expect(done.metrics.device, 'CPU');
      expect(auto.loadedModel!.gpuFailure, 'decode: test');
    });

    test('a GPU that fails to load moves the model to the CPU', () async {
      final failures = MemoryLlamaGpuFailures();
      final auto = LlamaCppBackend(
        modelPath: model!,
        contextTokens: 512,
        compute: LlmComputePreference.auto,
        gpuFailures: failures,
      )..debugFailGpuLoad = true;
      addTearDown(auto.dispose);
      await auto.load();
      expect(auto.loadedModel!.device, 'CPU');
      expect(auto.loadedModel!.gpuFailure, 'load: debugFailGpuLoad');
      expect(
        await failures.reasonFor(auto.gpuFailureKey),
        'load: debugFailGpuLoad',
      );
    });

    test(
      'lists the CPU device; a GPU is offered only where verified',
      () async {
        final devices = await backend.devices();
        expect(devices.where((d) => d.type == 0), isNotEmpty);
        if (!llamaGpuVerifiedPlatforms.contains(Platform.operatingSystem)) {
          expect(await backend.gpuSelectable(), isFalse);
        }
        expect(llamaGpuVerifiedPlatforms, isNot(contains('android')));
      },
    );

    test('status is available once loaded', () async {
      final report = await backend.status();
      expect(report.status, GenAiStatus.available);
      expect(report.detail, 'loaded');
      expect(backend.loadedModel!.device, 'CPU');
      expect(backend.loadedModel!.contextTokens, 2048);
    });

    test('streams a deterministic reply with measured metrics', () async {
      final events = await backend
          .generate(_ask('What is the capital of France? Answer briefly.'))
          .toList();
      final deltas = events.whereType<LlmDelta>().toList();
      final done = events.last as LlmDone;
      final text = deltas.map((d) => d.text).join();
      expect(text.toLowerCase(), contains('paris'));
      expect(text, isNot(contains('<think>')), reason: 'thinking is off');
      expect(text, text.trimLeft());
      expect(done.finish, LlmFinish.stop);
      expect(done.metrics.device, 'CPU');
      expect(done.metrics.promptTokens, greaterThan(5));
      expect(done.metrics.outputTokens, greaterThan(0));
      expect(done.metrics.firstToken, isNotNull);

      final again = await collectLlm(
        backend.generate(
          _ask('What is the capital of France? Answer briefly.'),
        ),
      );
      expect(again.$1, text, reason: 'greedy decoding is deterministic');
    });

    test('a longer reply arrives as several deltas', () async {
      final events = await backend
          .generate(
            _ask(
              'Name three colors, one per line.',
              sampling: const LlmSampling(maxOutputTokens: 40),
            ),
          )
          .toList();
      expect(events.whereType<LlmDelta>().length, greaterThan(1));
      expect(events.last, isA<LlmDone>());
    });

    test('the token limit ends with length', () async {
      final (text, done) = await collectLlm(
        backend.generate(
          _ask(
            'Count from one to fifty in words.',
            sampling: const LlmSampling(maxOutputTokens: 5),
          ),
        ),
      );
      expect(done.finish, LlmFinish.length);
      expect(done.metrics.outputTokens, 5);
      expect(text, isNotEmpty);
    });

    test('a stop string ends the reply before it', () async {
      final (text, done) = await collectLlm(
        backend.generate(
          _ask(
            'What is the capital of France? Answer briefly.',
            sampling: const LlmSampling(stop: ['Paris']),
          ),
        ),
      );
      expect(done.finish, LlmFinish.stop);
      expect(text, isNot(contains('Paris')));
    });

    test('cancel stops native work and the next request runs', () async {
      final events = <LlmEvent>[];
      final stream = backend.generate(
        _ask(
          'Write a long story about a dragon.',
          sampling: const LlmSampling(maxOutputTokens: 400),
        ),
      );
      final first = Completer<void>();
      final sub = stream.listen((e) {
        events.add(e);
        if (e is LlmDelta && !first.isCompleted) first.complete();
      });
      await first.future;
      await backend.cancel();
      await sub.asFuture<void>();
      final done = events.last as LlmDone;
      expect(done.finish, LlmFinish.cancelled);
      expect(done.metrics.outputTokens, lessThan(400));

      final (text, after) = await collectLlm(backend.generate(_ask('Say hi.')));
      expect(after.finish, isNot(LlmFinish.cancelled));
      expect(text, isNotEmpty);
    });

    test('cancelling the subscription also stops the work', () async {
      final sub = backend
          .generate(
            _ask(
              'Write a long story about a ship.',
              sampling: const LlmSampling(maxOutputTokens: 400),
            ),
          )
          .listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      final (text, _) = await collectLlm(backend.generate(_ask('Say hi.')));
      expect(text, isNotEmpty);
    });

    test('a second request while one runs is busy', () async {
      final first = collectLlm(
        backend.generate(
          _ask(
            'Tell me about cats.',
            sampling: const LlmSampling(maxOutputTokens: 40),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await expectLater(
        backend.generate(_ask('hi')).toList(),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'failure',
            GenAiFailure.busy,
          ),
        ),
      );
      await first;
    });

    test('a prompt longer than the context is tooLong', () async {
      await expectLater(
        backend.generate(_ask('word ' * 5000)).toList(),
        throwsA(
          isA<GenAiException>().having(
            (e) => e.failure,
            'failure',
            GenAiFailure.tooLong,
          ),
        ),
      );
    });

    test('works through the prompt contract and after reload', () async {
      final adapter = LlmGenAiBackend(backend);
      final answer = await adapter.generate(
        prompt: 'What is the capital of France? Answer briefly.',
        instructions: 'You are a helpful assistant.',
      );
      expect(answer.toLowerCase(), contains('paris'));
      await backend.unload();
      await backend.unload();
      expect(backend.loadedModel, isNull);
      final (text, _) = await collectLlm(backend.generate(_ask('Say hi.')));
      expect(text, isNotEmpty);
    });
  }, skip: model == null ? 'set LLAMA_TEST_MODEL to a GGUF model' : false);
}
