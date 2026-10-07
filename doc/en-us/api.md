# Public API

`MyAppsAiPreference` constructor/build owns common enablement and model preference
switches with labels, values and callbacks. `MyAppsAiModelNotes` constructor/build
owns download/storage explanations and optional diagnostic presentation. Together
with capability status tiles they support independent-feature settings adapters.
Builds never query services, download models or persist preferences.

`MyAppsAiCapabilityTile` and its constructor/build render an independently
reported capability using injected title, status, icon, optional diagnostics and
action. Build makes no backend calls. Capability adapters own enablement,
availability queries, download serialization and diagnostic visibility.

## Backend

| Declaration | Contract |
|---|---|
| `platformMayHaveOnDeviceModel` | Coarse Android/iOS/macOS gate; false on web |
| `GenAiFeature` | Independent prompt and Japanese keyboard proofreading capabilities |
| `GenAiStatus`, `GenAiFailure`, `GenAiException` | Readiness and typed failures; unknown status stays unknown |
| `GenAiStatusReport`, `GenAiCoreInfo` | Platform diagnostics, model variants, limits and locale support |
| `GenAiBackend` | Existing prompt status/info/download/generate/choose/prewarm/cancel contract |
| `CapabilityGenAiBackend` | Adds capabilityReport, downloadCapability and proofread; unsupported default for proofreading |
| `MethodChannelGenAiBackend` | In `myapps_ai_platform`; injectable MethodChannel; shared plugin uses com.yuanzhe.myapps_ai/genai |

Backend declarations other than `MethodChannelGenAiBackend` live in `myapps_ai_core`
and are re-exported by `myapps_ai`. Use the shared plugin channel in production; tests may inject a channel.
Apple proofreading reports unsupported without invoking the channel. Android
choice generation uses the validated line parser; Apple uses native constrained
generation. Callers continue validating choices against their own business rules.

## Runtime

`AiInsightCoordinator<K, R>` owns cache loading, per-key request coalescing, stale
result rejection, failure retry policy and clearing. Inject key/fingerprint/model,
generation, skipped-entry and persistence callbacks. `ensure`, `stateOf` and
`clearAll` expose the workflow. Clearing/disposal invalidates outstanding results.
`AiInsightState` and `AiInsightPhase` describe presentation state.

`AiExecutionGate` provides a single-flight lock for feature-specific adapters.
`run` checks enabled before acquiring the lock, passes a current-generation check
to the operation, applies a timeout and waits for cancellation cleanup before
releasing occupancy. `invalidate` prevents obsolete results from publishing;
`busy` and `generation` expose occupancy and the status publication token.
Consumers supply their existing failure types, notification and backend callbacks.

`OnDeviceAiService` retains the existing prompt-facing interface: enabled,
preferFast, report, coreInfo, downloadProgress, downloading, busy, pausedUntil,
quotaReachedToday and canGenerate. Methods are setEnabled, setPreferFast,
refreshStatus, download, generate, choose, prewarm, cancelBackground, start,
handleLifecycle and dispose. The constructor requires `backend`; the runtime has no
default backend and no shared singleton. Applications own singletons, test
replacement and provider registration.

`GenAiDownload` represents bytes and an optional fraction when total is known.
`AiPriority` distinguishes interactive and background requests. The runtime
serializes inference, checks status before use, pauses outside resumed lifecycle,
backs off busy background work and stops background work for the local quota day.

The request timeout remains 45 seconds and now requests backend cancellation
before advancing the queue. Enable/preference changes invalidate late replies.
Status refresh stops before further queries if disabled while waiting. Download
completion never re-queries a disabled backend. Dispose invalidates results and
fails queued requests. Native cancellation remains best effort; mock validation
does not establish whether a system model actually stops immediately.

## Output utilities

The `myapps_ai_ui` package exports `MyAppsAiInsightCard`, `AiInsightSection` and
`AiInsightLabels` for grouping, collapsed preview, stale text, progress, errors and
generated attribution. `MyAppsAiSettings` receives localized text, status wording,
preferences and actions. Consumers handle feature gating, routing, cache clearing,
time boundaries, locale changes and domain-specific presentation.

`generateWithFallback` accepts consumer facts, generation and usability callbacks.
It attempts fallback once after guardrail refusal or an unusable parsed result.
Other failures propagate. Consumers decide whether fallback differs from primary.
`AiInsightEntry` and `AiInsightStatus` provide cache entry fields, UTC timestamps,
tolerant parsing and slot grouping. Module maps,
paths, atomic writes, fingerprints and domain parsers remain consumer-owned.

`parseChoiceReply` returns validated unique candidates and parse validity.
`stripMarkdown`, `matchesScript` and `cleanSentence` retain the consumers' existing
cleaning, script ratio and length checks. Domain prompts and parsers stay in apps.

## Model artifacts

`myapps_ai_models` serves ASR and LLM alike and carries no native runtime.

| Declaration | Contract |
|---|---|
| `ArtifactManifest`, `ArtifactFile`, `InstalledFile` | Artifact, logical model and backend ids, files with URL/SHA-256/size, format, quantization, revision, licence, compatible runtimes and platform/ABI filters; unknown JSON fields kept |
| `ArtifactFormat`, `ArchiveKind`, `EstimateSource`, `ModelPlatform` | Open format names, zip/tar.bz2 unpacking, memory-estimate source, target platform and ABI |
| `ArtifactDownloader`, `DownloadCancelToken`, `hashFile` | Injected HTTP client; range resumption, SHA-256 check, progress, cancellation, connect/stall timeouts |
| `ArtifactManager`, `ModelStorageRoot` | Staged atomic install with rollback, verify, remove, leases, coalesced installs, disk usage and per-artifact `watch` status |
| `ArtifactFailure`, `ArtifactException`, `ArtifactState`, `ArtifactStatus` | Typed failures (including `diskFull`, `hashMismatch`, `leased`) and notInstalled/downloading/verifying/installed/failed/corrupt |
| `LocalEngineStateStore`, `LocalEngineState`, `InFlightMarker` | Per-device JSON with serialised atomic writes, crash markers and unknown fields kept |
| `HealthFingerprint`, `SelfTestRecord`, `SelfTestFixture`, `SelfTestRunner` | Self-tests keyed by runtime, model hash, OS, driver, device and precision; capabilities supply fixture and evaluation |
| `ModelCatalogEntry`, `ModelManagementState`, `ModelAction`, `ModelManagementController` | Settings view model: sizes, state, progress and the actions available now |

The application supplies the models root, the HTTP client and the state file
location, and excludes all three from sync and backup. Downloads contact only the
manifest URL and start only from an explicit action. Under the root, artifacts live
in `<artifactId>/` with `manifest.json`; partial downloads live in
`.downloads/<artifactId>/<name>.<sha256 prefix>.part`; and installs are staged in
`.downloads/<artifactId>.staging`. A folder without a readable manifest counts as
not installed. A wrong hash deletes the partial, and a cancel or network failure
keeps it for resumption. A failed rename restores the previous version.
A second install request for the same artifact returns the running future.

The state file keeps self-test records under `smokeTests` and the marker under
`inFlight`. Every other top-level field is preserved verbatim. A lenient `load`
reads unreadable content as empty and renames nothing. The next `update` renames
the file to `<name>.unreadable-<UTC stamp>` before writing. I/O errors are thrown
and never treated as content. A record is reused only when its fingerprint matches
exactly. `recoverFromCrash` turns a leftover marker into a `crashed` record.
A throwing fixture becomes a `failed` record. System-managed catalog entries list
only the actions the platform supports; `pauseResume` appears only when the source
supports it.

## Source selection and unified settings

`AiSourceOption` describes a registered source by id, `AiSourceKind` (auto, system,
local, online), `AiSourceReadiness` and served features. `AiSourceSelection` holds one
global source id plus per-feature overrides; `sourceFor` applies an override only
for features the application declares overridable, and JSON keeps unknown fields.
`featuresWithChangedSource` lists features whose source changed so the application
can ask once whether to clear content generated by the previous source.

`MyAppsAiSettingsSkeleton` orders the master switch, source, features, device,
model management, diagnostics and data sections; while disabled only the master
switch and data actions render. `MyAppsAiSourcePicker` selects an option and, for
one needing download or configuration, calls `onResolve` for navigation instead of
acting silently. `MyAppsAiDiagnostics` groups untranslated lines per backend.
`confirmClearAfterSourceChange` returns false on dismissal. `MyAppsAiManagementEntry`
opens application-owned management routes.

## Text LLM

`LlmBackend` exposes id, declared `LlmAbility` values, status, load, unload,
streamed `generate` and `cancel`, which completes after native work exits.
`LlmRequest` carries `LlmMessage` values and `LlmSampling`. Streams emit `LlmDelta`
events and one `LlmDone` with `LlmFinish` and measured `LlmMetrics`, whose device is
reported by the runtime. `collectLlm` joins a stream. `LlmGenAiBackend` adapts an
LLM to the prompt contract; proofreading stays unsupported and download refuses,
because model files are managed through model management.

## Online sources

An `OnlineProvider` stores endpoint, model, auth scheme and headers, preserves unknown
JSON fields and never stores an API key; applications supply keys through
`OnlineSecretReader`. Template ids `openai`, `openrouter` and `openaiCompatible` and
seeded record ids are compatibility contracts. `OpenAiCompatibleLlmBackend`
implements `LlmBackend` with streamed `/chat/completions`, cancellation, timeouts and
error classification, reporting `device: remote`. `status()` checks configuration and
sends nothing; `testConnection()` contacts the server only on explicit request.
`OnlineTranscriptionClient` keeps existing transcription request formats. Requests go
only to the configured endpoint and only for a source the user selected. Before
enabling a source, applications show an `OnlinePrivacyNotice`; the device-local
acknowledgement is checked by `needsOnlinePrivacyAcknowledgement`, which also asks
again when the recipient host changes.

## Local model management UI

`MyAppsLocalModelsPage` and `MyAppsLocalModelList` render Settings → AI → Local models
from a `ModelManagementController`. Applications inject `MyAppsLocalModelLabels`, a byte
formatter and `MyAppsLocalModelGroup` capability sections; only registered capabilities
appear. Entries show size, state, progress, errors and only offered actions
(`visibleModelActions`). System-managed entries never offer verify or remove. Removal
is confirmed and states that only downloaded files are removed while records and
history remain. `initialEntryId` scrolls to and highlights an entry; `onInstalled`
fires once per transition to installed so callers can resume configuration.

## Speech recognition

An `AsrEngine` probes `AsrRoute` values for installed manifests, prepares an
`AsrSession`, streams `AsrEvent` values for one 16 kHz mono PCM window, cancels and
releases. Route keys are `adapterId:artifactId:backend`; each route carries a
`HealthFingerprint` and `AsrCapabilities`. `cancel` completes after the native call
and the window's stream have finished, so it must not be awaited from that stream's
own listener. `AsrRouter` filters routes and falls back only through steps of the
application's `AsrFallbackPolicy`; model-independent routes, such as the system
recogniser, are reachable only through `ModelIndependentFallback`. `AsrCrashGuard`
marks in-flight native work so a crashed route is not chosen again under the same
fingerprint. `AsrDiarizer` and `labelWindow` add optional window-local speaker labels.

`WhisperCppEngine` runs Whisper or Parakeet with CPU and discovered GPU routes,
mid-window cancellation and progress. `SherpaOnnxEngine` runs Qwen3-ASR on the CPU
as one untimed segment per window; `SherpaDiarizer` reads models located by the
application. `FluidAudioEngine` runs Parakeet on the Neural Engine with `mixed`
placement; `SystemRecognizerEngine` exposes the on-device recogniser as a
model-independent route. Sherpa and Apple windows finish before a cancel takes effect.
On Android the whisper engine opens ggml by soname and registers the best CPU variant
and any GPU backend of its set by name, so it works whether or not the application
extracts native libraries.

## Online sources UI

`MyAppsOnlineSourcesPage` lists configured providers with readiness from
`configurationGaps` and adds providers from registered templates; a seeded id is
used once, later copies get `newProviderId`. `MyAppsOnlineSourceEditorPage` edits
name, endpoint, model and key, runs the connection test only on tap, and pops `true`
after saving or removing so callers can resume. Applications implement
`OnlineSourcesController` for records, secrets and device-local acknowledgements,
supply `MyAppsOnlineLabels`, and pass MyApps-UI input widgets through
`MyAppsOnlineFieldBuilders`, so this package does not depend on MyApps-UI. Saving
calls `ensureOnlinePrivacyAcknowledged`, which shows
`showOnlinePrivacyNoticeDialog` for an unconfirmed version or host; declining or
dismissing saves nothing. Removal is confirmed first.

## llama.cpp

`LlamaCppBackend` runs one GGUF file on a worker isolate that owns the model. It
applies the model's chat template, decodes the prompt in chunks of `batchTokens`,
samples greedily when temperature is zero or top-k is one, streams UTF-8-safe deltas,
and ends at end of turn, the token limit or a stop string, which is never emitted.
Cancellation is a native flag checked between prefill chunks and tokens; `cancel`
completes after native work returns. `status` reports `modelMissing` without loading.
Metrics report the device layers were assigned to: `CPU`, or the GPU's ggml name.
`compute` is `LlmComputePreference.cpuOnly` by default, which keeps every layer,
buffer and operation on the CPU. With `auto` the model goes to the first GPU ggml
lists; a failed load, or a failed first generation before any text, moves it to the
CPU and records the reason in `gpuFailures` (`MemoryLlamaGpuFailures` by default;
applications keep it in unsynced device state) under `gpuFailureKey`, so the next
load goes straight to the CPU. `loadedModel.gpuFailure` reports that reason.
`devices` lists ggml's devices; `gpuSelectable` is true only when a GPU device exists
and the platform is in `llamaGpuVerifiedPlatforms` (Linux). Android loads its
libraries by soname and its CPU variant by name, because they are mapped from inside
the APK; `status` names the variant it chose. `llamaModelPath` resolves a manifest's GGUF file and `llamaCppBackendId`
names the backend in manifests. Binaries, headers and bindings come from one upstream
release per package version and change together with the model list.

`llamaModelCatalog` lists the supported text models as single-file GGUF manifests
pinned to a repository commit with SHA-256: Qwen3.5 0.8B and 2B (Q4_K_M) and Gemma 4
E2B instruction-tuned (Google QAT Q4_0). Applications register these with model
management; the backend loads only installed files. Each entry stores
`llamaMinimumBuild`, the first llama.cpp build carrying its architecture;
`llamaCatalogFor(build)` lists the entries a build can load, and tests require the
pinned build to support the whole catalog.

Runtime refreshStatus asks the injected backend on every platform; system eligibility is enforced by the platform backend.
