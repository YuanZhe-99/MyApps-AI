# Changelog

## 0.6.0 - 2026-10-08

Breaking: applications replace their own source routing with `AiSourceRouter` from
the new `myapps_ai_sources` package and their source controls with
`MyAppsAiSourceSection`; `OnlineSourcesController` moved to `myapps_ai_online`
(re-exported by `myapps_ai_online_ui`) and gained `fetchModels` and
`catalogModels`; `MyAppsOnlineLabels` gained the strings of the new pages.

Sources and settings: one router for system AI, llama.cpp models and online models,
with device-local selection, GPU choice and failure memory, aliases and custom
models; a resolution failure now says why. `MyAppsAiSourceSection` adds the GPU
switch, enabled only where verified. Technical details are a structured
`AiDiagnosticsReport` listing every included backend whatever is selected — app and
platform, system AI, llama.cpp library and devices, every local model and its last
session, every online source — with secrets reduced to present/absent, shown by
`MyAppsAiDiagnosticsView` with copy.

Online sources: a source holds several models (`OnlineModel`, ids as in
MyTranscribe); records stay readable by earlier builds and old selections keep
working. 31 templates in a flat, searchable list with provider icons (LobeHub Icons,
MIT, via `flutter_svg`) and endpoints labelled in each provider's own words; model
lists only on request, enriched from a bundled models.dev snapshot that also stands
in when a source cannot list; rule-based `Vendor: Model` names with user aliases;
`OnlineSourceManager` replaces each application's online storage class. The pages
list models under their source, open the editor beside the list on wide windows and
choose models from a grouped, searchable picker.

Local models: recommended models are named `Qwen: Qwen3.5 0.8B (Q4_K_M)` and
`Google: Gemma 4 E2B (Q4_0 QAT)`. Users may add a GGUF file from Hugging Face: the
file is pinned to the repository's commit and verified by its LFS SHA-256, its
header is read before downloading, and a warning naming the architecture (checked
against the pinned llama.cpp's list), size and license must be accepted first.

## 0.5.3 - 2026-10-07

Fix: local models never loaded on Android. Applications package native libraries
uncompressed inside the APK, where the llama library's reported path does not exist,
so ggml was never found. `myapps_ai_llm_llama` and `myapps_ai_asr_whisper` now open
ggml by soname on Android and register the best CPU variant by name (by its
`ggml_backend_score`, as ggml does for a directory). Load failures are reported with
their reason (`library`, `noCpuBackend`) in `status` instead of a bare `failed`.

`LlamaCppBackend` replaces `gpu` with `compute` (`LlmComputePreference.cpuOnly`,
the default, or `auto`). CPU only now passes an empty device list, so a registered
GPU backend no longer receives compute buffers or offloaded operations. `auto` falls
back to the CPU when the GPU fails to load the model or fails its first generation,
and remembers that in `gpuFailures`. New `devices`, `gpuSelectable` and
`llamaGpuVerifiedPlatforms` (Linux Vulkan, checked on an Intel iGPU).

## 0.5.2 - 2026-10-07

Runtime readiness now comes from the injected backend on every platform, enabling
local and online models on Windows/Linux. System eligibility remains in the
platform backend; the disabled gate is unchanged.

## 0.5.1 - 2026-10-06

Dependency ranges instead of exact pins in the ASR and model packages, so they
resolve on Flutter 3.44.2 used by consumer CI (`hooks 2.2.0` needed a newer SDK).
CI runs package checks on Flutter 3.47.6 (ffigen 22) and a new consumer-resolution
check on 3.44.2.

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
