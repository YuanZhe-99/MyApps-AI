import 'dart:io';

/// Supplies the directory model artifacts live in.
///
/// Applications implement this over their own storage hub (for example
/// MyTranscribe's `TranscribeStorage.modelsDir()`), so the shared layer never
/// reads an application's storage singleton or data-module registry. The
/// directory must be excluded from sync and backup by the application.
abstract interface class ModelStorageRoot {
  /// Purpose: Resolve the models root directory.
  /// Inputs: None. Returns: The directory, which may not exist yet.
  /// Side effects: Implementation-defined; should not create files.
  /// Notes: Called before every operation, so a changed custom storage path
  /// takes effect without recreating the manager.
  Future<Directory> modelsDir();
}

/// A [ModelStorageRoot] over a fixed directory or a resolver callback.
class CallbackModelStorageRoot implements ModelStorageRoot {
  /// Purpose: Create a root from a resolver.
  /// Inputs: [resolve]. Returns: A new root. Side effects: None.
  /// Notes: Convenient for tests and simple adapters.
  const CallbackModelStorageRoot(this.resolve);

  /// Purpose: Create a root over one fixed directory.
  /// Inputs: [directory]. Returns: A new root. Side effects: None.
  /// Notes: None.
  factory CallbackModelStorageRoot.fixed(Directory directory) =>
      CallbackModelStorageRoot(() async => directory);

  /// Purpose: The resolver this root delegates to.
  /// Inputs: None. Returns: Future of a directory. Side effects: Caller's.
  /// Notes: None.
  final Future<Directory> Function() resolve;

  /// Purpose: Resolve the models root.
  /// Inputs: None. Returns: The directory. Side effects: Caller's resolver.
  /// Notes: None.
  @override
  Future<Directory> modelsDir() => resolve();
}

/// Name of the folder inside the models root holding partial downloads and
/// staging folders. Same as MyTranscribe's `modelDownloadsDirName`.
const modelDownloadsDirName = '.downloads';

/// Name of the manifest inside an installed artifact folder.
const artifactManifestFileName = 'manifest.json';
