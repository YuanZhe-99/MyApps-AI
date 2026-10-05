# Architecture

## Scope and current state

MyApps-AI consolidates system-provided on-device text generation and proofreading
for MyAnime, MyDay, MyDevice and MyNihongo. MyTranscribe is excluded. MyVidComp
currently has no corresponding implementation to migrate.

The repository is initialized with contracts and documentation CI only. None of
the packages below exists yet. No application consumes this repository yet.

## Package boundaries

| Intended package | Responsibility |
|---|---|
| `myapps_ai` | Capability types, scheduling, lifecycle, cancellation and optional generation/cache orchestration |
| `myapps_ai_platform` | Flutter native bridge for Android ML Kit GenAI/AICore and Apple Foundation Models |
| `myapps_ai_ui` | Capability status, downloads, model preferences, diagnostic details and generated-content states |

The runtime uses the platform bridge. The optional UI package uses the runtime
and MyApps-UI. Keep native AI dependencies out of MyApps-UI's base package.
Packaging of the Android proofreading dependency will be decided through build
validation before a platform package is published.

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

## Migration constraints

Design the initial contract against all four consumers, including MyNihongo's
independent proofreading capability. Migrate consumers in the order MyDevice,
MyDay, MyAnime, MyNihongo, using thin application adapters. Native bridge extraction,
runtime extraction and optional UI/cache extraction each require behavior checks
before consumer rollout. A migration does not add Apple AI support to MyNihongo.

Publish a tagged shared dependency to Gitea and GitHub before updating consumers.
Package and third-party license notices must accompany consumer integration.
Repository initialization alone is not an implementation milestone or release.
