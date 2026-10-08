# MyApps-AI

Shared AI infrastructure for My Apps: system AI, local models and online sources.

Applications can adopt the packages independently according to their required
capabilities. Each application retains its business prompts, facts, decisions,
settings and independent data. Record application-specific usage in that
application's documentation.

`myapps_ai_core` holds backend-neutral contracts and output utilities without any
native code. `myapps_ai` provides shared prompt execution over an injected
backend. The optional `myapps_ai_platform` plugin provides the system AI backend
on Android, iOS and macOS; consumers depend on it explicitly.
The optional myapps_ai_ui package renders cards and settings with app-owned labels.

Optional capability packages: `myapps_ai_models` (model artifacts),
`myapps_ai_llm` with the `myapps_ai_llm_llama` backend, `myapps_ai_asr` with the
whisper.cpp, sherpa-onnx and Apple backends, `myapps_ai_online`, and
`myapps_ai_sources`, which routes an application's AI to the chosen source, plus the
`myapps_ai_local_ui` and `myapps_ai_online_ui` settings pages. Native backends use
pinned upstream prebuilt binaries; nothing is compiled in a consumer build.

- [Architecture and contracts](doc/en-us/architecture.md)
- [Verification](doc/en-us/verification.md)
- [Public API](doc/en-us/api.md)
- [中文文档](doc/zh-cn/architecture.md)

Run `python3 tool/check_docs.py` to validate the documentation mirror and links.

Licensed under GNU GPL version 3; see [LICENSE](LICENSE).
