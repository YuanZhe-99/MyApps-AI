# Verification

## Repository checks

Run `python3 tool/check_docs.py` and `python3 tool/check_dependencies.py`. The latter
resolves the neutral packages and fails if they reach a concrete backend or declare a plugin. CI checks matching documentation paths, heading
levels, table row counts and identical code blocks, plus local Markdown links.
The checker does not verify translation meaning; review both languages together.

Package checks run on the maintainers' Flutter (3.47.6), which binding generation
with ffigen 22 requires. `python3 tool/check_consumer_resolution.py <dir>` creates an
application depending on every package and resolves it on the consumers' Flutter
(3.44.2); dependency constraints are ranges so consumers can resolve them.

## Implementation acceptance

Native CI generates an ephemeral Flutter host and builds an Android ARM64 release
APK plus unsigned iOS and macOS release apps. Apple bundles are inspected with
`tool/check_weak_link.sh`. These checks validate compilation, plugin inclusion and
linking; old-system launch and model inference still require devices/simulators.

ASR backend package tests run each build hook, load the prebuilt library on the CI
host and check routes, fingerprints and errors without models. Live inference is
opt-in through environment variables: `LASR_TEST_MODEL` (a whisper GGML model) and
`QWEN_TEST_DIR` (an unpacked Qwen3-ASR package), transcribing the bundled JFK clip.
The Apple bridge loads only on macOS and iOS; elsewhere its routes are unavailable.
The `asr-native-prebuild` and `asr-apple-prebuild` workflows build only binaries
upstream does not publish, and run manually.

The llama.cpp package test checks its manifest, loads the upstream library and checks
a missing model without loading. `LLAMA_TEST_MODEL` (a small GGUF chat model) enables
streaming, determinism, token limits, stop strings, cancellation, busy, context limit
and reload checks. One application process must not load two different ggml sets;
packages that bundle ggml are not combined until their sets are aligned or isolated.

When packages are introduced, add formatting, analysis and meaningful tests to CI.
Use injected backends and clocks to check independent capabilities, the disabled
gate, availability refresh, unknown statuses, download progress with unknown totals,
queue ordering, retry limits, foreground transitions, cancellation, timeouts and
late results. Check cache compatibility and obsolete-result rejection where used.

Validate Android release builds with R8 and native plugin registration. Validate
Apple builds with Foundation Models weak-link inspection and old-system launch
checks. Linux-only verification cannot establish Apple binary compatibility.

Consumer regression checks preserve deterministic decisions, fact boundaries,
scoring and generated-content rules. Verify each application's supported UI
languages and license notices. Record hardware, OS, model and tested capability for device checks;
mock tests and cloud stand-ins do not establish on-device inference quality.
