# Card M5-daemon-polish — launcher watcher refcount, async doctor facts, session actions

**Owned paths:** `crates/kurashid/src/wiring.rs` (launcher + notifications + new session section
only), `crates/kurashid/src/doctor.rs`. Do not edit `main.rs` (report the calls). Common rules:
`docs/tasks/README.md`.

**Read:** `crates/kurashid/src/{wiring.rs,doctor.rs,services.rs,main.rs}`,
`crates/kurashi-launcher/src/lib.rs` (`watch`), `crates/kurashi-services/src/session.rs` (Commands).

**Build:**
1. Launcher index watcher refcounted on `runtime.ui.launcher` (start watching when the launcher opens
   the first time after a change… simplest honest version: watcher alive while `launcher == true`,
   plus one `reindex()` on open if the last index is older than the last watcher stop). No polling.
2. Doctor async facts: session/system bus reachability and notification name ownership reported by
   the tasks that already connect (update a shared `Arc<Mutex<DoctorFacts>>`), never guessed.
3. Session actions: `session.suspend`, `session.reboot`, `session.poweroff`, `session.logout`
   (logind; `logout` = TerminateSession of the current session) — each requires `{confirm: true}`
   in args, otherwise returns `invalid` with code `session.confirm_required` (the UI shows a confirm
   step). Tests use the private-bus fakes from `kurashi-services` — **never call these against the
   real system bus**.

**Acceptance:** `cargo test -p kurashid` green incl. confirm-required behaviour on a fake logind,
doctor facts flip from n/a to ok/warn when the tasks report, launcher watcher lifecycle test with a
temp applications dir; clippy clean.
