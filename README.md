# MyApps-AI

Shared infrastructure for system-provided on-device AI in My Apps.

Initial consumers: MyAnime, MyDay, MyDevice and MyNihongo. MyTranscribe is
outside this project's scope. Each application retains its business prompts,
facts, decisions, settings and independent data.

The `myapps_ai` package provides shared prompt execution, capability-aware channel
contracts and output utilities. Existing application native channels remain in use;
the shared native plugin now passes Android, iOS and macOS release build checks.
The optional myapps_ai_ui package renders cards and settings with app-owned labels.

- [Architecture and contracts](doc/en-us/architecture.md)
- [Verification](doc/en-us/verification.md)
- [Public API](doc/en-us/api.md)
- [中文文档](doc/zh-cn/architecture.md)

Run `python3 tool/check_docs.py` to validate the documentation mirror and links.

Licensed under GNU GPL version 3; see [LICENSE](LICENSE).
