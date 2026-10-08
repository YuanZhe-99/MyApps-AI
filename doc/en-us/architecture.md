# Architecture

## Scope and current state

MyApps-AI provides reusable infrastructure for system-provided on-device text
generation and proofreading. Applications select the packages and capabilities
they need; eligibility depends on platform support and runtime availability.

`myapps_ai` provides shared prompt execution, capability-aware channel contracts,
output utilities and a feature execution gate. The shared native plugin supports
Android, iOS and macOS. The optional
UI package renders insight cards and common prompt settings with injected labels
and callbacks. Apps keep their own routes, providers and teaching presentation.

## Package boundaries

| Package | Responsibility |
|---|---|
| `myapps_ai_core` | Backend-neutral capability types, backend contracts, execution gate, fallback generation, cache entries and output validation; no plugin or native runtime |
| `myapps_ai` | Scheduling, lifecycle, cancellation and optional generation/cache orchestration over an injected backend |
| `myapps_ai_models` | Capability-neutral model artifacts: manifests, resumable SHA-256-verified downloads, atomic installs with rollback, leases, status, device-local engine state and self-test contracts; storage root and HTTP client injected; no native runtime |
| `myapps_ai_llm` | Text LLM messages, sampling, streaming events, metrics, declared abilities and the `GenAiBackend` adapter; no native runtime |
| `myapps_ai_llm_llama` | Optional llama.cpp `LlmBackend` over upstream release binaries fetched by URL and SHA-256 in a build hook; CPU by default, GPU offload opt-in |
| `myapps_ai_asr` | Speech recognition contracts, routes, policy-driven fallback, crash isolation, diarization protocol and ASR self-test fixture; no native runtime |
| `myapps_ai_asr_whisper`, `myapps_ai_asr_sherpa`, `myapps_ai_asr_apple` | Optional ASR backends: whisper.cpp (Whisper, Parakeet), sherpa-onnx (Qwen3-ASR, diarization) and Apple (FluidAudio, system recogniser); prebuilt native libraries fetched by URL and SHA-256 in build hooks, never compiled in a consumer build |
| `myapps_ai_online` | Online provider records without keys, templates, OpenAI-compatible streaming LLM backend, online transcription client and online privacy notice model; pure Dart over `package:http` |
| `myapps_ai_platform` | Optional Flutter native bridge and `MethodChannelGenAiBackend` for Android ML Kit GenAI/AICore and Apple Foundation Models |
| `myapps_ai_ui` | Capability status, downloads, model preferences, diagnostic details and generated-content states |
| `myapps_ai_local_ui` | Optional local model management page driven by `ModelManagementController`; depends only on `myapps_ai_models` |
| `myapps_ai_sources` | Application source routing: one global source routed to system AI, a llama.cpp model or an injected online model; local and custom Hugging Face model catalog, aliases, GPU choice and failures, and complete technical details; never depends on `myapps_ai_online` |
| `myapps_ai_online_ui` | Optional online sources pages: provider list, editor, key entry, explicit connection test and privacy notice; storage, wording and MyApps-UI input widgets injected by the application |

Dependencies point one way: `myapps_ai_ui → myapps_ai → myapps_ai_core`, and
`myapps_ai_platform → myapps_ai_core`. `myapps_ai_models` depends on no other
MyApps-AI package, application storage or state management. Neither the runtime nor the UI depends on
the platform plugin. Consumers that want system AI depend on `myapps_ai_platform`
explicitly and pass its backend to `OnDeviceAiService`; consumers that do not
link no native AI code. `tool/check_dependencies.py` enforces this.

Consumers use the shared com.yuanzhe.myapps_ai/genai channel. `GenAiBackend` retains
the prompt contract; `CapabilityGenAiBackend` adds independent capability queries,
downloads and proofreading. The initial runtime schedules prompt requests only.
The platform plugin registers the shared channel on Android, iOS and macOS.
Android supports independent Prompt and Japanese keyboard proofreading; Apple
supports generation and constrained choices and reports proofreading unsupported.
Capability adapters can use the shared execution gate. Domain task ordering and
bounded retries remain application-owned.

See [public API](api.md) for current declarations and behavior.

The runtime receives its backend from the consumer. The optional UI package uses the runtime
and standard Flutter Material widgets, inheriting the application's theme.
Keep native AI dependencies out of MyApps-UI's base package.
The initial Android plugin bundles both clients, created lazily. This preserves
independent capabilities without installing a second handler on the same channel.
The plugin supplies AICore package visibility and R8 consumer rules. Its minimum
Android API is 26 and Java target is 17. Native dependencies are pinned to
genai-prompt 1.0.0-beta4 and genai-proofreading 1.0.0-beta1.

Engine detach closes clients. Cancellation retains the busy slot until the native
task exits and rejects a result produced after cancellation. Apple keeps isolated
sessions and Foundation Models weak linking in CocoaPods and SwiftPM packaging.

## Application ownership

Applications retain business facts, prompts and prompt versions, deterministic
decisions, domain parsers, provider registrations, routes, persisted preferences
and storage adapters. Existing settings and cache formats stay compatible during
initial migration. Shared code does not share application data or sessions.

Classification, ranking, fact boundaries, fallback selection, scoring and task
validation remain application-owned. The library does not decide how generated
content participates in a domain workflow.

## Capability and execution contracts

- Prompt and proofreading have independent availability and downloads.
- Candidate selection reports whether it uses native constrained generation or
  generation followed by validation; these implementations are not assumed equivalent.
- Disabled means no backend calls, including status queries. Disabling during work
  allows cancellation cleanup but prevents further requests and result publication.
- Detect availability before each use; preserve unknown and unreachable states.
- Runtime availability comes from the injected backend on every platform; only
  the system backend applies the system-AI platform gate.
- Downloads begin only through an explicit user action and are system-managed.
- Inference remains on-device. No cloud fallback is part of this repository.
- Serialize execution within each application; interactive requests take priority.
  Background retry and yielding policies preserve each consumer's behavior.
- Timeout and cancellation must handle native work and late replies, rather than
  merely completing a Dart future. Model changes invalidate obsolete results.
- Apple requests use isolated sessions and preserve weak linking on older systems.
- Report language support per capability. Conversion and output validation do not
  imply that every model supports every application language.
- Generated content remains labelled and subject to application validation.
- Persistence is optional and app-local. Generated caches are excluded from sync
  and backup by application module registration.
- Diagnostics may include statuses and model identifiers, but never prompt contents.

## Consumer and release contracts

Applications may independently adopt native capabilities, execution gates, insight
orchestration, cards or settings through adapters. Each application owns its data
and determines its supported platforms. Record package usage, domain policies and
platform restrictions in the application's documentation.

Publish a tagged shared dependency to Gitea and GitHub before updating consumers.
Package and third-party license notices must accompany consumer integration.

Native backends consume upstream release binaries pinned by URL and SHA-256; each
package version pins one upstream release, and its headers, bindings and model list
move with it. One process loads one ggml set. An application bundling both
`myapps_ai_asr_whisper` and `myapps_ai_llm_llama` must align them on the same ggml
version, binding their updates; it may pin either package to an older release to do
so. When llama.cpp is pinned older, offer only `llamaCatalogFor(build)`: every
catalog entry records the first llama.cpp build carrying its architecture, and a
model that build cannot load is removed from that application's list. Record the
aligned versions and the resulting model list in the application's documentation.
