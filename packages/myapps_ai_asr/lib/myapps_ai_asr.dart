/// Backend-neutral speech recognition: engine/session/request/event/result
/// contracts, capability and route descriptors, generic route filtering with
/// application-supplied fallback policy, crash isolation, an optional
/// diarization protocol and the ASR self-test fixture. No native runtimes,
/// state management or application storage.
library;

export 'src/capability.dart';
export 'src/diarization.dart';
export 'src/engine.dart';
export 'src/errors.dart';
export 'src/host.dart';
export 'src/isolation.dart';
export 'src/pcm.dart';
export 'src/registry.dart';
export 'src/route.dart';
export 'src/router.dart';
export 'src/self_test.dart';
export 'src/tokens.dart';
