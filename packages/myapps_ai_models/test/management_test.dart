import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'support.dart';

/// Purpose: Verify management actions per state. Inputs: None.
/// Returns: None. Side effects: None. Notes: Pure values.
void main() {
  final manifest = manifestOf('m', [
    const ArtifactFile(path: 'a', bytes: 100, sha256: 'x', sourceUrl: 'u'),
  ]);

  ModelCatalogEntry entry(
    ArtifactState state, {
    bool leased = false,
    bool pause = false,
    InstallProgress? progress,
  }) => ModelCatalogEntry.forArtifact(
    manifest: manifest,
    status: ArtifactStatus('m', state, progress: progress),
    platform: testPlatform,
    capability: 'asr',
    leased: leased,
    supportsPauseResume: pause,
  );

  test('actions follow install state', () {
    expect(entry(ArtifactState.notInstalled).actions, {ModelAction.download});
    expect(entry(ArtifactState.failed).actions, {
      ModelAction.download,
      ModelAction.remove,
    });
    final busy = entry(
      ArtifactState.downloading,
      progress: const InstallProgress(InstallStage.downloading, 25, 100),
    );
    expect(busy.actions, {ModelAction.cancel});
    expect(busy.progress, 0.25);
    expect(busy.downloadBytes, 100);
    expect(entry(ArtifactState.installed).actions, {
      ModelAction.verify,
      ModelAction.remove,
    });
    expect(entry(ArtifactState.verifying).actions, isEmpty);
  });

  test('lease withholds remove; pauseResume only when supported', () {
    expect(
      entry(ArtifactState.installed, leased: true).can(ModelAction.remove),
      isFalse,
    );
    expect(
      entry(ArtifactState.downloading).can(ModelAction.pauseResume),
      isFalse,
    );
    expect(
      entry(
        ArtifactState.downloading,
        pause: true,
      ).can(ModelAction.pauseResume),
      isTrue,
    );
  });

  test('system models expose only supported actions', () {
    final system = ModelCatalogEntry.system(
      modelId: 'system:gemini-nano',
      capability: 'llm',
      state: ModelInstallState.notInstalled,
      supported: {ModelAction.download},
    );
    expect(system.systemManaged, isTrue);
    expect(system.artifactId, isNull);
    expect(system.can(ModelAction.remove), isFalse);
    expect(system.can(ModelAction.download), isTrue);

    final state = ModelManagementState(
      entries: [system, entry(ArtifactState.downloading)],
    );
    expect(state.anyBusy, isTrue);
    expect(state.forCapability('llm'), [system]);
    expect(state.entryFor('local:m')?.capability, 'asr');
  });
}
