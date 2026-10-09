# Contract change requests

Subagents never edit frozen contracts (`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`,
schema types). They append a request here; the lead decides, implements, and records a K-id.

| # | Date | Requester (task) | Contract | Requested change | Reason | Decision |
|---|---|---|---|---|---|---|
| 1 | 2026-10-09 | M1-config | i18n (`config` domain, en + ja) | Add keys emitted by `kurashi-config`: `config.diag.{parse,io,unknown_key,not_per_output,invalid,newer_schema,migration_missing,migration_failed}`, `config.error.{unrepresentable,user_file_unreadable}`, `config.forced.nix_enforced` | Diagnostics / op errors / forced reasons carry these keys (rule 8); nothing renders them yet | |
