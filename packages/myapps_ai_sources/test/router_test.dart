import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';
import 'package:myapps_ai_llm_llama/myapps_ai_llm_llama.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';
import 'package:myapps_ai_sources/myapps_ai_sources.dart';
import 'package:path/path.dart' as p;

class _Store implements AiSourceStore {
  final Map<String, dynamic> config = {'unrelated': 'keep'};
  @override
  Future<Map<String, dynamic>> read() async => Map.of(config);
  @override
  Future<void> write(Map<String, dynamic> values) async =>
      config.addAll(jsonDecode(jsonEncode(values)) as Map<String, dynamic>);
}

class _System extends CapabilityGenAiBackend {
  int cancels = 0;
  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) async => const GenAiStatusReport(
    GenAiStatus.available,
    code: 0,
    variant: 'nano-v2',
  );
  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async =>
      const GenAiCoreInfo(platform: 'android', installed: true, sdk: 35);
  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async => 'system';
  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> prewarm() async {}
  @override
  Future<bool> download({void Function(int, int)? onProgress}) async => false;
  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async => [];
}

class _Online implements AiOnlineSources {
  final notifier = ValueNotifier(0);
  int releases = 0;
  bool acknowledged = false;
  @override
  Listenable get changes => notifier;
  @override
  Future<void> initialize() async {}
  @override
  List<AiSourceOption> get sourceOptions => const [
    AiSourceOption(id: 'online:model:s:m', kind: AiSourceKind.online),
  ];
  @override
  bool owns(String id) => id.startsWith('online:');
  @override
  String? sourceName(String id) => owns(id) ? 'Vendor: M' : null;
  @override
  String? sourceDetail(String id) => owns(id) ? 'My source' : null;
  @override
  Future<GenAiBackend> resolve(String id) async {
    if (!acknowledged) {
      throw const GenAiException(GenAiFailure.unavailable, 'privacyNotice');
    }
    return _System();
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> release() async => releases++;
  @override
  Future<List<AiDiagnosticSection>> diagnostics() async => [
    AiDiagnosticSection('online:s', 'My source', [
      AiDiagnosticRow('host', 'example.com'),
      AiDiagnosticRow('apiKey', 'sk-secret'),
    ]),
  ];
}

Future<AiSourceRouter> _router(
  Directory dir,
  _Store store, {
  AiOnlineSources? online,
  List<ArtifactManifest>? catalog,
}) async {
  final router = AiSourceRouter(
    store: store,
    system: _System(),
    models: CallbackModelStorageRoot(
      () async => Directory(p.join(dir.path, 'ai_models')),
    ),
    online: online,
    catalog: catalog,
    appInfo: const {'app': 'Test 1.0.0'},
  );
  await router.initialize();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('router'));
  tearDown(() => dir.delete(recursive: true));

  test('a missing local model is unavailable, says why, downloads nothing '
      'and keeps other settings', () async {
    final store = _Store();
    final router = await _router(dir, store);
    expect(router.sourceOptions.map((o) => o.kind), [
      AiSourceKind.auto,
      AiSourceKind.system,
      AiSourceKind.local,
      AiSourceKind.local,
      AiSourceKind.local,
    ]);
    await router.select('local:qwen3.5-0.8b');
    final report = await router.statusReport();
    expect(report.status, GenAiStatus.unavailable);
    expect(report.detail, 'modelNotInstalled');
    expect(report.baseModelName, 'local:qwen3.5-0.8b');
    expect(store.config['unrelated'], 'keep');
    expect(await Directory(p.join(dir.path, 'ai_models')).exists(), isFalse);

    final restored = await _router(dir, store);
    expect(restored.selection.global, 'local:qwen3.5-0.8b');
    expect(
      restored.sourceName('local:qwen3.5-0.8b'),
      'Qwen: Qwen3.5 0.8B (Q4_K_M)',
    );
  });

  test('automatic and system use the system backend unchanged', () async {
    final router = await _router(dir, _Store());
    expect((await router.statusReport()).variant, 'nano-v2');
    expect(await router.generate(instructions: '', prompt: 'x'), 'system');
    await router.select('system');
    expect((await router.statusReport()).variant, 'nano-v2');
  });

  test(
    'online models are offered, named and refused until acknowledged',
    () async {
      final online = _Online();
      final router = await _router(dir, _Store(), online: online);
      expect(router.sourceOptions.last.id, 'online:model:s:m');
      expect(router.sourceName('online:model:s:m'), 'Vendor: M');
      expect(router.sourceDetail('online:model:s:m'), 'My source');
      await router.select('online:model:s:m');
      expect(online.releases, 1, reason: 'switching releases clients');
      final refused = await router.statusReport();
      expect(refused.status, GenAiStatus.unavailable);
      expect(refused.detail, 'privacyNotice');
      online.acknowledged = true;
      final report = await router.statusReport();
      expect(report.status, GenAiStatus.available);
      expect(report.variant, 'online:model:s:m', reason: 'identity is the id');
      var notified = 0;
      router.sourceChanges.addListener(() => notified++);
      online.notifier.value++;
      expect(notified, 1);
    },
  );

  test('the GPU choice and GPU failures persist on the device', () async {
    final store = _Store();
    final router = await _router(dir, store);
    expect(router.gpuAllowed, isFalse);
    await router.setGpuAllowed(true);
    expect(store.config['aiComputePreference'], 'auto');
    expect((await _router(dir, store)).gpuAllowed, isTrue);
    expect(await router.gpuSelectable(), isA<bool>());
  });

  test('diagnostics list every section and hide keys', () async {
    final router = await _router(dir, _Store(), online: _Online());
    final report = await router.diagnostics();
    expect(report.sections.map((s) => s.id), [
      'app',
      'selection',
      'systemAi',
      'llama.cpp',
      'localModels',
      'online:s',
    ]);
    final text = report.toPlainText();
    expect(text, contains('app: Test 1.0.0'));
    expect(text, contains('sdk: 35'));
    expect(text, contains('ggml: $llamaGgmlVersion'));
    expect(text, contains('Qwen: Qwen3.5 0.8B (Q4_K_M)'));
    expect(text, contains('apiKey: present'));
    expect(text, isNot(contains('sk-secret')));

    final without = await (await _router(dir, _Store())).diagnostics();
    expect(without.sections.last.rows, isEmpty);
    expect(without.toPlainText(), endsWith('[Online sources]\nnot included'));
  });

  final model = Platform.environment['LLAMA_TEST_MODEL'];
  test('an installed local model generates and reports its session', () async {
    final file = File(model!);
    final manifest = ArtifactManifest(
      artifactId: 'test-gguf',
      modelId: 'local:test',
      backendId: llamaCppBackendId,
      format: ArtifactFormat.gguf,
      revision: 'r',
      quantization: 'q4_k_m',
      files: [
        ArtifactFile(
          path: p.basename(file.path),
          bytes: file.lengthSync(),
          sha256: '0' * 64,
          sourceUrl: 'u',
        ),
      ],
      licenseId: 'Apache-2.0',
      extraJson: const {artifactVendorKey: 'Test', artifactNameKey: 'Tiny'},
    );
    final artifact = Directory(
      p.join(dir.path, 'ai_models', safeArtifactName(manifest.artifactId)),
    )..createSync(recursive: true);
    Link(p.join(artifact.path, p.basename(file.path))).createSync(file.path);
    File(p.join(artifact.path, artifactManifestFileName)).writeAsStringSync(
      jsonEncode(
        manifest.asInstalled([
          InstalledFile(
            path: p.basename(file.path),
            bytes: file.lengthSync(),
            sha256: '0' * 64,
          ),
        ], DateTime.now()).toJson(),
      ),
    );
    final router = await _router(dir, _Store(), catalog: [manifest]);
    await router.select('local:test');
    expect((await router.statusReport()).status, GenAiStatus.available);
    final text = await router.generate(
      instructions: 'Answer briefly.',
      prompt: 'What is the capital of France?',
      maxOutputTokens: 16,
    );
    expect(text.toLowerCase(), contains('paris'));
    final rows = (await router.diagnostics()).toPlainText();
    expect(rows, contains('device: CPU'));
    expect(rows, contains('lastTokensPerSecond'));
    expect(rows, isNot(contains('capital')), reason: 'no prompt text');
    await router.select('auto');
  }, skip: model == null ? 'set LLAMA_TEST_MODEL' : false);
}
