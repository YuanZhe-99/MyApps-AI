# MyApps-AI

Shared infrastructure for system-provided on-device AI in My Apps.

Initial consumers: MyAnime, MyDay, MyDevice and MyNihongo. MyTranscribe is
outside this project's scope. Each application retains its business prompts,
facts, decisions, settings and independent data.

This repository currently contains the ownership contract and repository checks.
Runtime packages and native plugins have not been implemented or released.

- [Architecture and contracts](doc/en-us/architecture.md)
- [Verification](doc/en-us/verification.md)
- [中文文档](doc/zh-cn/architecture.md)

Run `python3 tool/check_docs.py` to validate the documentation mirror and links.

Licensed under GNU GPL version 3; see [LICENSE](LICENSE).
