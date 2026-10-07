import 'dart:io';

/// Why an artifact could not be downloaded, installed, verified or removed.
///
/// Wire names match MyTranscribe's `ArtifactFailure` so persisted or logged
/// values keep their meaning.
enum ArtifactFailure {
  /// The server could not be reached, did not answer in time, or stalled.
  network,

  /// The server answered with an unusable HTTP status.
  httpError,

  /// The file arrived, but its size or SHA-256 differs from the manifest.
  hashMismatch,

  /// There is not enough free space for download, unpacking and install.
  diskFull,

  /// An archive would not unpack, or a non-space file-system error occurred.
  unpackFailed,

  /// The artifact is leased by running work and cannot be replaced or removed.
  leased,

  /// The manifest is not one this build can install.
  badManifest,

  /// The user or caller cancelled.
  cancelled,
}

/// A download, install or removal that did not finish.
class ArtifactException implements Exception {
  /// Purpose: The failure classification.
  /// Inputs: None. Returns: [ArtifactFailure]. Side effects: None.
  /// Notes: Use this, not [message], for decisions.
  final ArtifactFailure failure;

  /// Purpose: Human-readable detail for logs and diagnostics.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Never contains prompts, audio or credentials.
  final String message;

  /// Purpose: Create an artifact exception.
  /// Inputs: [failure], [message]. Returns: A new exception.
  /// Side effects: None. Notes: None.
  const ArtifactException(this.failure, this.message);

  /// Purpose: Render the failure for a log.
  /// Inputs: None. Returns: String. Side effects: None.
  /// Notes: Format matches MyTranscribe.
  @override
  String toString() => 'ArtifactException(${failure.name}): $message';
}

/// Purpose: Turn a file-system error into a disk-full failure where it is one.
/// Inputs: [error].
/// Returns: [ArtifactFailure.diskFull] for out-of-space codes, otherwise
/// [ArtifactFailure.unpackFailed].
/// Side effects: None.
/// Notes: POSIX ENOSPC (28); Windows ERROR_HANDLE_DISK_FULL (39) and
/// ERROR_DISK_FULL (112). This is the check of last resort when the free-space
/// probe has no figure.
ArtifactException diskFullOr(FileSystemException error) {
  final code = error.osError?.errorCode;
  if (code == 28 || code == 39 || code == 112) {
    return ArtifactException(
      ArtifactFailure.diskFull,
      'There is not enough free space: ${error.message}',
    );
  }
  return ArtifactException(
    ArtifactFailure.unpackFailed,
    '${error.message} (${error.path})',
  );
}

/// Purpose: Build the shared cancellation failure.
/// Inputs: None. Returns: [ArtifactException]. Side effects: None.
/// Notes: Library-internal helper.
ArtifactException cancelledFailure() =>
    const ArtifactException(ArtifactFailure.cancelled, 'Cancelled.');
