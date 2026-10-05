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
| `MethodChannelGenAiBackend` | Injectable MethodChannel; default com.yuanzhe.myapps_ai/genai reserved for future plugin |

Use an explicit existing application channel until a native plugin is published.
Apple proofreading reports unsupported without invoking the channel. Android
choice generation uses the validated line parser; Apple uses native constrained
generation. Callers continue validating choices against their own business rules.

## Runtime

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

`parseChoiceReply` returns validated unique candidates and parse validity.
`stripMarkdown`, `matchesScript` and `cleanSentence` retain the consumers' existing
cleaning, script ratio and length checks. Domain prompts and parsers stay in apps.
