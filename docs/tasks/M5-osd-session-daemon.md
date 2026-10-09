# Card M5-osd-session-daemon — brightness/volume key actions with island OSD, lock safety

**Goal.** Compositor keybinds (`kurashi act brightness.up`, …) change brightness/volume and the
island shows a transient OSD face; locking refuses honestly when PAM cannot unlock.

**Owned paths:** `crates/kurashid/src/{wiring.rs,main.rs,island.rs}`, `crates/kurashi-services/src/brightness.rs`,
`crates/kurashi-auth/`, `i18n/{en,ja}/{session,island,lock}.toml`. Common rules: `docs/tasks/README.md`.

**Read:** `crates/kurashid/src/wiring.rs` (AudioProvider: how the `volume` transient face is signalled;
`lock`/`session_with`), `crates/kurashid/src/island.rs`, `crates/kurashi-services/src/brightness.rs`,
`crates/kurashid/src/main.rs` (brightness provider registration), `crates/kurashi-auth/src/lib.rs`.

**Build:**
1. Actions `brightness.up` / `brightness.down` (args optional `{step: 0..1}`, default 0.05) and intent
   `brightness.set` (0..1). Write via the existing logind `SetBrightness` path, re-read sysfs once per
   call (no polling, no permanent subscription), update `svc.brightness` if it is live, and signal an
   island transient face `brightness` exactly like `volume` (transient-only, never cyclable).
   No backlight device → `ActionError` with an i18n key, no OSD.
2. Actions `audio.volume.up` / `audio.volume.down` / (step as above) reusing the existing volume path so
   the `volume` OSD shows. Unavailable audio → error, no panic.
3. Lock safety: if the PAM service `kurashi` is missing (`/etc/pam.d/kurashi`; make the dir injectable
   for tests), `session.lock` returns an error with key `error.lock.no_pam` and `runtime.lock` never
   becomes locked (otherwise the user could not unlock). The K20 marker logic is unchanged.
4. i18n en+ja for every new action/error key.

**Acceptance:** `cargo test -p kurashid -p kurashi-services -p kurashi-auth` green with new tests:
brightness.up against a fake sysfs dir signals the `brightness` transient; volume.up with the existing
fake audio path signals `volume`; lock without PAM file errors and stays unlocked. clippy clean.
