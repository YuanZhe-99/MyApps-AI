import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'capability.dart';

/// What adapters need to know about the host, injected so tests can drive
/// any platform and applications keep platform branching in one place.
@immutable
class AsrHost {
  /// Purpose: Platform id: `android`, `ios`, `macos`, `windows`, `linux`.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String platform;

  /// Purpose: Device class as the support matrix spells it, e.g.
  /// `windows-arm64-qualcomm`, `macos-arm64`, `android`, `linux-x64`.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Tested-route rows and evidence grades are keyed by it.
  final String deviceClass;

  /// Purpose: Operating-system version, part of every fingerprint.
  /// Inputs: None. Returns: String. Side effects: None. Notes: None.
  final String osVersion;

  /// Purpose: CPU threads a local model should use.
  /// Inputs: None. Returns: int ≥ 1. Side effects: None.
  /// Notes: See [asrDefaultThreads].
  final int threads;

  /// Purpose: Create a host description.
  /// Inputs: All fields. Returns: A new value. Side effects: None.
  /// Notes: Tests construct any combination.
  const AsrHost({
    required this.platform,
    required this.deviceClass,
    required this.osVersion,
    required this.threads,
  });

  /// Purpose: Describe the running process.
  /// Inputs: Optional [processorIdentifier] override.
  /// Returns: The current host.
  /// Side effects: Reads `defaultTargetPlatform`, `Abi.current()`, the
  /// processor count, OS version and `PROCESSOR_IDENTIFIER`.
  /// Notes: Same class rules as MyTranscribe's `localDeviceClass` and thread
  /// rule as `localEngineThreads`, so fingerprints and tested-route rows keep
  /// matching after migration.
  factory AsrHost.current({String? processorIdentifier}) {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
    final abi = Abi.current().toString();
    final arch = abi.contains('_') ? abi.substring(abi.indexOf('_') + 1) : abi;
    return AsrHost(
      platform: platform,
      deviceClass: asrDeviceClass(
        platform: platform,
        architecture: arch,
        processor:
            processorIdentifier ??
            Platform.environment['PROCESSOR_IDENTIFIER'] ??
            '',
      ),
      osVersion: Platform.operatingSystemVersion,
      threads: asrDefaultThreads(
        Platform.numberOfProcessors,
        mobile: platform == 'android' || platform == 'ios',
      ),
    );
  }

  /// Purpose: Whether this is a phone or tablet platform.
  /// Inputs: None. Returns: bool. Side effects: None. Notes: None.
  bool get isMobile => platform == 'android' || platform == 'ios';
}

/// Purpose: Name a device class the way the support matrix does.
/// Inputs: [platform], CPU [architecture], Windows [processor] identifier.
/// Returns: e.g. `windows-arm64-qualcomm`, `windows-x64`, `macos-arm64`,
/// `ios`, `android`, `linux-x64`.
/// Side effects: None.
/// Notes: Only what the OS states for certain goes into the class.
String asrDeviceClass({
  required String platform,
  required String architecture,
  String processor = '',
}) => switch (platform) {
  'windows' =>
    architecture == 'arm64' && processor.contains('Qualcomm')
        ? 'windows-arm64-qualcomm'
        : 'windows-$architecture',
  'macos' => 'macos-$architecture',
  'ios' => 'ios',
  'android' => 'android',
  'linux' => 'linux-$architecture',
  _ => platform,
};

/// Purpose: Choose how many CPU threads a local model uses.
/// Inputs: [processors] reported by the OS; whether the host is [mobile].
/// Returns: At least one.
/// Side effects: None.
/// Notes: Phones use at most four; desktops leave one or two cores free and
/// use at most eight, because ggml's spinning thread pool stalls when a
/// thread shares a core with the OS or the Dart VM.
int asrDefaultThreads(int processors, {required bool mobile}) => mobile
    ? processors.clamp(1, 4)
    : (processors - (processors > 4 ? 2 : 1)).clamp(1, 8);

/// Purpose: Evidence grade of a generic CPU route on [host].
/// Inputs: [host]. Returns: **E** on Android (SoC not distinguishable),
/// **B** elsewhere.
/// Side effects: None.
/// Notes: From the local-ASR support survey; the CPU is Auto's floor either
/// way, so this affects what diagnostics say, not what runs.
EvidenceLevel asrCpuEvidence(AsrHost host) => host.deviceClass == 'android'
    ? EvidenceLevel.experimental
    : EvidenceLevel.community;
