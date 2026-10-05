# Public API

## Backend

| Declaration | Contract |
|---|---|
| `platformMayHaveOnDeviceModel` | Coarse Android/iOS/macOS gate; false on web |
| `GenAiFeature` | Independent prompt and Japanese keyboard proofreading capabilities |
| `GenAiStatus`, `GenAiFailure`, `GenAiException` | Readiness and typed failures; unknown status stays unknown |
| `GenAiStatusReport`, `GenAiCoreInfo` | Platform diagnostics, model variants, limits and locale support |
| `GenAiBackend` | Existing prompt status/info/download/generate/choose/prewarm/cancel contract |
| `CapabilityGenAiBackend` | Adds capabilityReport, downloadCapability and proofread; unsupported default for proofreading |
| `MethodChannelGenAiBackend` | Injectable MethodChannel; shared plugin uses com.yuanzhe.myapps_ai/genai |

Use the shared plugin channel in production; tests may inject a channel.
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
handleLifecycle and dispose. Applications own singletons and provider registration;
pass their channel backend explicitly when constructing the service.

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
