# AGENTS.md

Read `doc/en-us/architecture.md` and `doc/en-us/verification.md` before changing
implementation. Keep the English and Chinese documentation mirrors aligned.

- Fetch relevant remotes before editing; understand divergence before proceeding.
- Preserve unrelated local changes and application-owned behavior.
- Scope excludes MyTranscribe's AI implementation.
- Document changed contracts and public declarations in the same change.
- Every added function must explain Purpose, Inputs, Returns, Side effects and Notes.
- Validate the final change set after the last edit.
- Publish shared dependencies to both remotes before updating consumer pointers.
- Use relative sibling repository URLs in submodules.
- Attribute only materially participating agents using their actual identity.
- Never commit credentials, generated outputs, user data or machine-specific addresses.
- Do not create release tags for documentation or repository scaffolding alone.
- Remove temporary milestone plans after completion; retain formal contracts.

Run `python3 tool/check_docs.py` for repository documentation changes. Add package
and platform checks as executable implementations are introduced; see verification docs.
