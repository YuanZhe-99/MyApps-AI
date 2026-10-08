/// Purpose: Route an application's AI requests to the chosen source.
/// Inputs: Application storage callbacks, the system backend, a models
/// directory and optional online sources.
/// Returns: [AiSourceRouter] and [AiSourceStore].
/// Side effects: None at import.
/// Notes: Online support is injected; an application without it never
/// resolves `myapps_ai_online`.
library;

export 'src/router.dart';
export 'src/store.dart';
