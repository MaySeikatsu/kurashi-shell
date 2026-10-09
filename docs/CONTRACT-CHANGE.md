# Contract change requests

Subagents never edit frozen contracts (`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`,
schema types). They append a request here; the lead decides, implements, and records a K-id.

| # | Date | Requester (task) | Contract | Requested change | Reason | Decision |
|---|---|---|---|---|---|---|
| 1 | 2026-10-09 | M1.5-frontend | PROTOCOL (docs) | Serve an `i18n` document (`i18n.strings`: flat key to string for the active locale, subscribable) | Frontend `I18n.tr` currently returns the key; strings live in `i18n/{en,ja}/frontend.toml` and must reach the view without a parallel list | |
