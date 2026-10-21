# Card W28-ai — AI chat as a mod, local first (roadmap v0.3 "LLM chat (multi-provider, libsecret)")

**User (session 10):** "as complete and usable as possible … take actual code from ii, shellseikatsu, DMS." The
user runs a local Ollama server on this machine. **Sidebars are to be discussed with the user first (I116)**: the chat
is a Stage panel and a launcher mode, not a sidebar.

**References:** ii `~/.config/quickshell/ii/services/{Ai.qml,ai/**}` (providers, message model, streaming, tool
display) and `modules/ii/sidebarLeft/**` (the chat view: markdown, code blocks, copy); shellseikatsu
`~/Documents/projects/quickshell/shellseikatsu/Services/LlmService.qml`.

**Read first:** `CLAUDE.md`; DECISIONS K26/K28 (native mods), K44 (launcher modes); `docs/MODS.md`; the lyrics and
calendar mods as templates (network capability, HTTP from Rust, panels, launcher rows).

**Owned paths:** new `crates/kurashi-mod-ai/**`, new `mods/ai/**` (manifest, settings: provider `ollama` (default,
`http://127.0.0.1:11434`, model list from `/api/tags`), `openai`-compatible (base URL + model; key from an env var name
or `secret-tool lookup` — never stored in config.toml, see I134), `anthropic` (same key rule); a Stage `panel:ai`
(conversation list, streaming answer with markdown + code blocks + copy, stop, regenerate, model picker); a launcher
contribution `launcher:ai` if the manifest supports it, else a row filed as a contract request — the `!` prefix asks
and opens the panel), the workspace members line, one dependency + one registration line in kurashid,
`i18n/{en,ja}/mod-ai.toml`, `docs/ux/ai.md`, a test `mods/ai/test-ai.sh`. Contract rows ≥ 220. Sandbox `w28-ai-`.

**Do:** streaming from the daemon to the panel through the mod's document in coarse chunks (≤ 10 patches/s, the text
appended — no per-token churn), conversations saved as JSON under the mod's data dir, a clear "no provider reachable"
state, cancellation, Ma (no requests unless the user asks; no model list polling). Never send anything anywhere in
tests: a fake Ollama HTTP server on localhost.

**Acceptance:** crate tests (Ollama NDJSON stream parsing, OpenAI SSE parsing, key lookup without logging the key),
clippy; `mods/ai/test-ai.sh` (real kurashid, fake Ollama) with shots of the panel (empty, streaming, code block,
error) under sekai and none. Report (terse).
