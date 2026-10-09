# Card M1-cli — `kurashi get/set/why/reset/undo/redo/profile/doctor-lite`

**Goal.** The CLI half of M1's exit criteria: "`kurashi set/get/why/undo/profile` work",
speaking the frozen protocol v1 to a running `kurashid`.

**Owned paths:** `crates/kurashi/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `docs/PROTOCOL.md` (all), `crates/kurashi-ipc/src/lib.rs`, `crates/kurashi/src/main.rs`,
`crates/kurashid/src/config.rs` (profile.* action args/results), `crates/kurashid/tests/config.rs`
(how to start a daemon on temp paths in a test).

**Build:**
- `kurashi get <key> [--output O] [--json]` → value + provenance chip text, e.g.
  `bar.height = 40   (user)` / `theme.material.blur = false   (forced: capability — compositor lacks …)`.
- `kurashi set <key> <value> [--output O] [--dry-run]` — parse value as JSON, fall back to string;
  `--dry-run` prints the preview diff. Multiple `key=value` pairs = one transaction.
- `kurashi reset <key|section> [--output O]`, `kurashi undo`, `kurashi redo` (print rev + tx id).
- `kurashi why <key> [--output O]` → every layer, lowest first, winner marked, reasons shown.
- `kurashi profile list|preview <name> [--sections a,b]|load <name> [--sections]|save <name>`.
- `kurashi watch <doc>` (alias of `sub`), keep existing commands working (bench uses `act`,
  `mock`, `sub`).
- Errors: print `rejected` op errors with key + code + msg; non-zero exit codes (2 = rejected,
  3 = daemon unavailable). Human output by default, `--json` everywhere for scripts.
- Strings: CLI output is developer-facing English (no i18n needed), but show i18n *codes* as given.

**Acceptance (one command):** `cargo test -p kurashi` green with integration tests that start an
in-process `kurashid` server on a temp socket + `kurashi_config::Paths::rooted(tmp)` (see
`crates/kurashid/tests/config.rs`; add `kurashid`/`kurashi-config`/`kurashi-schema` as
dev-dependencies) and run the CLI's command functions against it: get→set→why→undo→redo,
dry-run, rejected batch exit code, profile save→list→preview→load. Clippy `-D warnings`.
Never point the CLI at the user's real socket in tests.
