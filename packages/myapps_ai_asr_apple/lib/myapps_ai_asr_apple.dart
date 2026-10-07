/// Apple adapters implementing `myapps_ai_asr`: FluidAudio Parakeet on the
/// Neural Engine and the on-device system recogniser, over a prebuilt bridge
/// delivered by this package's build hook. macOS and iOS only.
library;

export 'src/engines.dart';
export 'src/native/apple.dart' show AppleToken;
