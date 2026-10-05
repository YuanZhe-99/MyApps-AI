# Architecture

## Scope and current state

MyApps-AI consolidates system-provided on-device text generation and proofreading
for MyAnime, MyDay, MyDevice and MyNihongo. MyTranscribe is excluded. MyVidComp
currently has no corresponding implementation to migrate.

`myapps_ai` provides shared prompt execution, capability-aware channel contracts,
output utilities and a feature execution gate. All four consumers use the shared
native plugin; its Android, iOS and macOS release checks have passed. The optional
UI package renders insight cards and common prompt settings with injected labels
and callbacks. Apps keep their own routes, providers and teaching presentation.

## Package boundaries

| Package | Responsibility |
|---|---|
| `myapps_ai` | Capability types, scheduling, lifecycle, cancellation and optional generation/cache orchestration |
| `myapps_ai_platform` | Flutter native bridge for Android ML Kit GenAI/AICore and Apple Foundation Models |
| `myapps_ai_ui` | Capability status, downloads, model preferences, diagnostic details and generated-content states |

Consumers use the shared com.yuanzhe.myapps_ai/genai channel. `GenAiBackend` retains
the prompt contract; `CapabilityGenAiBackend` adds independent capability queries,
downloads and proofreading. The initial runtime schedules prompt requests only.
The platform plugin registers the shared channel on Android, iOS and macOS.
Android supports independent Prompt and Japanese keyboard proofreading; Apple
supports generation and constrained choices and reports proofreading unsupported.
MyNihongo uses the shared execution gate through its feature adapter; its practice
ordering and bounded retries remain app-owned.

See [public API](api.md) for current declarations and behavior.

The runtime uses the platform bridge. The optional UI package uses the runtime
and MyApps-UI. Keep native AI dependencies out of MyApps-UI's base package.
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

MyAnime retains classification gaps and recommendation ranking. MyDay and MyDevice
retain fact boundaries and fallback facts. MyNihongo retains teaching prompts,
per-task validation, its existing typed-answer acceptance rule and the exclusion
of generated questions from spaced-repetition scheduling.

## Capability and execution contracts

- Prompt and proofreading have independent availability and downloads.
- Candidate selection reports whether it uses native constrained generation or
  generation followed by validation; these implementations are not assumed equivalent.
- Disabled means no backend calls, including status queries. Disabling during work
  allows cancellation cleanup but prevents further requests and result publication.
- Detect availability before each use; preserve unknown and unreachable states.
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

All four consumers retain thin application adapters and independent data.
MyDay/MyDevice share insight orchestration and card presentation. MyAnime shares
prompt settings but retains classification and recommendation workflows.
MyNihongo shares native capabilities and execution gates while retaining its
teaching UI and practice ordering. It remains Android-only for AI.

Publish a tagged shared dependency to Gitea and GitHub before updating consumers.
Package and third-party license notices must accompany consumer integration.
