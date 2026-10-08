/// Purpose: Where the router keeps its device-local choices.
/// Inputs: Application configuration callbacks.
/// Returns: [AiSourceStore], [CallbackAiSourceStore] and the keys it uses.
/// Side effects: None at import.
/// Notes: The values are per device and must never be synced.
library;

/// Key of the [AiSourceSelection] JSON.
const aiSourceSelectionKey = 'aiSourceSelection';

/// Key of the compute preference name (`cpuOnly` or `auto`).
const aiComputePreferenceKey = 'aiComputePreference';

/// Key of the map of GPU failures, by `LlamaCppBackend.gpuFailureKey`.
const aiGpuFailuresKey = 'aiGpuFailures';

/// Key of the list of custom model manifests added from Hugging Face.
const aiCustomModelsKey = 'aiCustomModels';

/// Key of the map of user names for local models, by model id.
const aiModelAliasesKey = 'aiModelAliases';

/// Device-local storage for the router's choices.
abstract interface class AiSourceStore {
  /// Purpose: Read every stored value. Inputs: None.
  /// Returns: A map containing at least the router's keys when stored.
  /// Side effects: Reads storage. Notes: May contain unrelated keys.
  Future<Map<String, dynamic>> read();

  /// Purpose: Store [values], keeping every other key.
  /// Inputs: [values]. Returns: Completion. Side effects: Writes storage.
  /// Notes: None.
  Future<void> write(Map<String, dynamic> values);
}

/// An [AiSourceStore] over an application's whole configuration map.
class CallbackAiSourceStore implements AiSourceStore {
  /// Purpose: Bind the application's configuration.
  /// Inputs: [readConfig], [writeConfig], which replaces the whole map.
  /// Returns: Store. Side effects: None.
  /// Notes: [write] reads first so other settings are never lost.
  CallbackAiSourceStore({required this.readConfig, required this.writeConfig});

  /// Reads the application's configuration.
  final Future<Map<String, dynamic>> Function() readConfig;

  /// Replaces the application's configuration.
  final Future<void> Function(Map<String, dynamic>) writeConfig;

  @override
  Future<Map<String, dynamic>> read() => readConfig();

  @override
  Future<void> write(Map<String, dynamic> values) async {
    final config = Map<String, dynamic>.of(await readConfig());
    config.addAll(values);
    await writeConfig(config);
  }
}
