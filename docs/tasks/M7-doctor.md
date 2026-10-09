# Card M7-doctor — `kurashi doctor` (honest health report)

**Goal.** One command that tells the user what works and what doesn't, and why — in the spirit of
Shōjiki: every degraded feature names its cause and a fix.

**Owned paths:** `crates/kurashid/src/doctor.rs` (new), `crates/kurashi/src/` (CLI), and exactly
one line `pub mod doctor;` in `crates/kurashid/src/lib.rs`. Do **not** edit `crates/kurashid/src/main.rs`
— put the one-line registration call in your report; the lead adds it. Common rules:
`docs/tasks/README.md`.

**Read:** `crates/kurashid/src/{lib.rs,main.rs,wiring.rs,config.rs,services.rs,workspaces.rs}`,
`docs/PROTOCOL.md` §6 (query), `crates/kurashi/src/lib.rs`.

**Build:**
1. `doctor::register(daemon: &mut Daemon, facts: DoctorFacts)` adds a query provider
   `kind:"doctor"` returning `[{id, status: ok|warn|fail|n/a, summary_key, detail, fix_key?}]`.
   `DoctorFacts` is a small struct the lead fills at startup (compositor socket present, session /
   system bus reachable, notification name owned?, fc-list worked?, data dir found, config
   diagnostics count). Add live checks the daemon can answer cheaply: documents registered,
   subscribers per doc, config diagnostics (via `ConfigStore` — add a `pub fn diagnostics()` there
   only if missing; that one addition to `config.rs` is allowed), protocol version, instance.
2. `kurashi doctor [--json]`: connects, runs the query, prints a table with ✔/⚠/✘, details and
   fixes; exit 0 when no `fail`, 1 otherwise; when the daemon is unreachable, run client-side checks
   (socket path, `$XDG_RUNTIME_DIR`, `$WAYLAND_DISPLAY`, `$NIRI_SOCKET`) and exit 3.
3. i18n keys `doctor.*` in `i18n/{en,ja}/doctor.toml` (you own these two files too).

**Acceptance (one command):** `cargo test -p kurashi -p kurashid` green including a doctor test
against an in-process daemon (temp socket, `Paths::rooted`) with facts producing ok/warn/fail rows,
and the unreachable-daemon path exiting 3. Clippy `-D warnings`.
