import 'package:myapps_ai_models/myapps_ai_models.dart';

import 'engine.dart';
import 'route.dart';

/// Where the registry finds installed artifacts.
///
/// Implemented by [ArtifactManager] through [AsrArtifactSource.manager]; tests
/// pass a list.
abstract interface class AsrArtifactSource {
  /// Purpose: List installed manifests.
  /// Inputs: None. Returns: Manifests. Side effects: Reads storage.
  /// Notes: None.
  Future<List<ArtifactManifest>> installedAll();

  /// Purpose: Build a source over an [ArtifactManager].
  /// Inputs: [manager]. Returns: A source. Side effects: None. Notes: None.
  factory AsrArtifactSource.manager(ArtifactManager manager) = _ManagerSource;

  /// Purpose: Build a source over a fixed list.
  /// Inputs: [manifests]. Returns: A source. Side effects: None.
  /// Notes: For tests and examples.
  factory AsrArtifactSource.fixed(List<ArtifactManifest> manifests) =
      _FixedSource;
}

class _ManagerSource implements AsrArtifactSource {
  /// Purpose: Wrap a manager. Inputs: [manager]. Returns: A source.
  /// Side effects: None. Notes: Internal.
  _ManagerSource(this.manager);

  final ArtifactManager manager;

  @override
  Future<List<ArtifactManifest>> installedAll() => manager.installedAll();
}

class _FixedSource implements AsrArtifactSource {
  /// Purpose: Wrap a list. Inputs: [manifests]. Returns: A source.
  /// Side effects: None. Notes: Internal.
  _FixedSource(this.manifests);

  final List<ArtifactManifest> manifests;

  @override
  Future<List<ArtifactManifest>> installedAll() async => manifests;
}

/// The ASR adapters an application registered, and their routes here.
///
/// No state management: applications hold one instance however they like.
/// Only explicitly registered adapters exist, so an adapter not compiled in
/// is absent, never "disabled".
class AsrEngineRegistry {
  /// Purpose: Create a registry.
  /// Inputs: Registered [engines], installed [artifacts], device [state].
  /// Returns: A new registry. Side effects: None until [routes].
  /// Notes: None.
  AsrEngineRegistry({
    required List<AsrEngine> engines,
    required this.artifacts,
    required this.state,
  }) : engines = List.unmodifiable(engines);

  /// Purpose: Registered adapters, in order.
  /// Inputs: None. Returns: List. Side effects: None. Notes: None.
  final List<AsrEngine> engines;

  /// Purpose: Installed artifacts.
  /// Inputs: None. Returns: [AsrArtifactSource]. Side effects: None.
  /// Notes: None.
  final AsrArtifactSource artifacts;

  /// Purpose: Device-local self-test state.
  /// Inputs: None. Returns: [LocalEngineStateStore]. Side effects: None.
  /// Notes: None.
  final LocalEngineStateStore state;

  List<AsrRoute>? _probed;

  /// Purpose: Ids of registered adapters.
  /// Inputs: None. Returns: Set. Side effects: None.
  /// Notes: Feed to [AsrRoutingRequest.builtAdapters].
  Set<String> get builtAdapters => {for (final e in engines) e.adapterId};

  /// Purpose: Find an adapter by id.
  /// Inputs: [adapterId]. Returns: The adapter, or null.
  /// Side effects: None. Notes: None.
  AsrEngine? engine(String adapterId) {
    for (final engine in engines) {
      if (engine.adapterId == adapterId) return engine;
    }
    return null;
  }

  /// Purpose: List every route here with current health attached.
  /// Inputs: [refresh] to probe again.
  /// Returns: Routes.
  /// Side effects: Probes adapters on first call, after [refresh] or
  /// [invalidate]; reads the state file every time.
  /// Notes: An adapter whose probe throws contributes no routes rather than
  /// hiding the others.
  Future<List<AsrRoute>> routes({bool refresh = false}) async {
    if (refresh || _probed == null) {
      final installed = await artifacts.installedAll();
      final probed = <AsrRoute>[];
      for (final engine in engines) {
        final mine = [
          for (final manifest in installed)
            if (manifest.backendId == engine.adapterId) manifest,
        ];
        try {
          probed.addAll(await engine.probe(mine));
        } catch (_) {
          // A broken adapter is reported by its absence.
        }
      }
      _probed = probed;
    }
    final current = await state.load();
    return [
      for (final route in _probed!)
        route.copyWith(
          health: RouteHealth.fromRecord(
            current.selfTestFor(route.fingerprint),
          ),
        ),
    ];
  }

  /// Purpose: Forget cached probe results.
  /// Inputs: None. Returns: None. Side effects: Next [routes] probes again.
  /// Notes: Call after installing or removing an artifact.
  void invalidate() => _probed = null;
}
