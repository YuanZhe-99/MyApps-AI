# Verification

## Repository checks

Run `python3 tool/check_docs.py`. CI checks matching documentation paths, heading
levels, table row counts and identical code blocks, plus local Markdown links.
The checker does not verify translation meaning; review both languages together.

## Implementation acceptance

Native CI generates an ephemeral Flutter host and builds an Android ARM64 release
APK plus unsigned iOS and macOS release apps. Apple bundles are inspected with
`tool/check_weak_link.sh`. These checks validate compilation, plugin inclusion and
linking; old-system launch and model inference still require devices/simulators.

When packages are introduced, add formatting, analysis and meaningful tests to CI.
Use injected backends and clocks to check independent capabilities, the disabled
gate, availability refresh, unknown statuses, download progress with unknown totals,
queue ordering, retry limits, foreground transitions, cancellation, timeouts and
late results. Check cache compatibility and obsolete-result rejection where used.

Validate Android release builds with R8 and native plugin registration. Validate
Apple builds with Foundation Models weak-link inspection and old-system launch
checks. Linux-only verification cannot establish Apple binary compatibility.

Consumer regression checks preserve deterministic decisions, fact boundaries and
MyNihongo's scoring and generated-question rules. Verify all four UI languages and
license notices. Record hardware, OS, model and tested capability for device checks;
mock tests and cloud stand-ins do not establish on-device inference quality.
