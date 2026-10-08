/// Capability-neutral model artifacts: manifests, resumable verified
/// downloads, atomic installs, leases, status, device-local engine state and
/// self-test contracts. No native runtimes, state management or app storage.
library;

export 'src/downloader.dart';
export 'src/engine_state.dart';
export 'src/engine_state_store.dart';
export 'src/hugging_face.dart';
export 'src/failure.dart' show ArtifactFailure, ArtifactException, diskFullOr;
export 'src/management.dart';
export 'src/manager.dart';
export 'src/manifest.dart';
export 'src/naming.dart';
export 'src/self_test.dart';
export 'src/storage.dart';
