# W79 — Settings docked in a sidebar: the mechanical gaps (B127; Haiku, max effort)

**Base.** Branch `feat/s32-combined` (contains W77 = PR #58). First: `git fetch origin && git log --oneline -1
origin/feat/s32-combined`; if your HEAD does not contain it, `git reset --hard origin/feat/s32-combined` (fresh worktree).

**Goal.** Close B127's mechanical gaps (K146). Not the hover hold, not the sidebar→dock key, no QML.
1. **Doctor.** `runtime.settings` in `crates/kurashid/src/doctor.rs` `KNOWN_DOCS` (as the other runtime docs are listed).
2. **Mock parity.** `crates/kurashi-mock`: the `runtime.settings` document (with `dock` absent) and the `settings.dock`
   action (`{output,x,y,width,height}` sets `dock`, `{}` removes it), as the daemon answers (read `config.rs` around
   `actions.register("settings.dock"` and `settings_daemon.rs` for the shape).
3. **Double start.** A `settings.open` and a `settings.dock` arriving while the other's process still starts must not
   start two Settings processes (`config.rs`, the Settings app's `open` / dock-ensure paths and `reap`): one in-flight
   start guarded (a mutex / a "starting" state the second call waits on or joins). Unit/integration test in
   `crates/kurashid/tests/settings_daemon.rs` (two calls racing → one spawn; use the test's existing fake `qs` pattern).
4. **Crash clears dock.** When the Settings process exits (crash or quit) while `dock` is set, the daemon removes `dock`
   from `runtime.settings` (the frontend's well then stops showing "Opening Settings…"). Test: the fake process exits →
   the document has no `dock`.
5. **Merge set.** `tools/test-suites.sh`: `settings/test-dock.sh` in `MERGE_SET` (a short name, e.g. `settings-dock`, and
   its case in `path_of`). Do not run the suite yourself.

**Owned paths.** `crates/kurashid/src/doctor.rs`; in `crates/kurashid/src/config.rs` only the Settings app code (the
`settings.open` / `settings.dock` actions and the process start/reap helpers); `crates/kurashid/tests/settings_daemon.rs`;
`crates/kurashi-mock/**`; `tools/test-suites.sh` (the MERGE_SET line and `path_of` only).
**Frozen.** `crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, `crates/kurashi-core`, all QML, `settings/**`,
`frontend/**`. The `runtime.settings` shape is already decided (K146) — do not change it.
**Acceptance.** `timeout 900 nix develop -c cargo test -p kurashid --test settings_daemon` and `-p kurashi-mock` green;
`cargo clippy -p kurashid -p kurashi-mock --all-targets -- -D warnings`; `cargo fmt --check`.
**Build dir.** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w79 CARGO_BUILD_JOBS=8`.
Common rules: `docs/tasks/README.md`. Report in its format, terse.
