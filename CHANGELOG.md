# Changelog

## 0.5.1 - 2026-10-06

Dependency ranges instead of exact pins in the ASR and model packages, so they
resolve on Flutter 3.44.2 used by consumer CI (`hooks 2.2.0` needed a newer SDK).

## 0.5.0 - 2026-10-06

Breaking: backend contracts, execution gate, cache entries and output utilities
move to the new `myapps_ai_core` package; `myapps_ai` re-exports them.
`MethodChannelGenAiBackend` moves to `myapps_ai_platform`, and neither
`myapps_ai` nor `myapps_ai_ui` depends on the plugin. `OnDeviceAiService`
requires an injected backend and no longer provides a shared `instance`.

New `myapps_ai_models` package: capability-neutral artifact manifests,
resumable SHA-256-verified downloads, atomic installs with rollback, leases,
per-artifact status, device-local engine state with crash markers and
fingerprinted self-tests, and the model-management view model. The storage root,
HTTP client and state file location are injected. On-disk layout and JSON field
names match MyTranscribe's local-model formats.

New `myapps_ai_llm` package: backend-neutral text LLM messages, sampling,
streamed events, measured metrics, declared abilities and `LlmGenAiBackend`,
which exposes any `LlmBackend` through the existing prompt contract.

`myapps_ai_core` adds `AiSourceSelection` (global choice with per-feature
overrides) and `featuresWithChangedSource`. `myapps_ai_ui` adds the unified
settings skeleton, source picker, grouped diagnostics, management entries and
the clear-after-source-change question.

New `myapps_ai_online` package: key-free provider records, OpenAI/OpenRouter/
compatible templates, a streaming OpenAI-compatible `LlmBackend`, the online
transcription client and online privacy notice acknowledgement.

New `myapps_ai_local_ui` package: the shared local model management page with
capability groups, offered actions only, confirmed removal, deep-link highlight
and an installed callback.

New `myapps_ai_asr` package: speech recognition contracts, routes, router with
application-supplied fallback policy, crash guard, diarization protocol and
self-test fixture, compatible with MyTranscribe route keys and fingerprints.
Optional backend packages `myapps_ai_asr_whisper`, `myapps_ai_asr_sherpa` and
`myapps_ai_asr_apple` with the existing prebuilt binaries, plus manual
`asr-native-prebuild` and `asr-apple-prebuild` workflows.

New `myapps_ai_llm_llama` package: llama.cpp `LlmBackend` over upstream b11457
release binaries (Linux, Windows, Android arm64, macOS and iOS) with streaming,
stop strings, chunked prefill, flag-based cancellation and assigned-device metrics.

New `myapps_ai_online_ui` package: online sources list and editor with key entry,
explicit connection test and the privacy notice before saving.

## 0.4.3

Shared AI preference switches and model download/storage explanations for prompt
and independent-capability settings adapters.

## 0.4.2

Shared capability settings tiles accept independent status, diagnostic visibility
and actions from application adapters.
