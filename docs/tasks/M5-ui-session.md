# Card M5-ui-session — session menu surface + brightness OSD face

**Goal.** A calm session menu (lock · suspend · log out · reboot · power off) and a brightness face
for the island OSD, both pure views over daemon state (rules 1, 5).

**Owned paths:** new `frontend/surfaces/SessionMenu.qml`, new `frontend/components/faces/BrightnessFace.qml`,
`frontend/surfaces/Stage.qml`, `frontend/surfaces/qmldir`, `frontend/components/faces/qmldir`,
`i18n/{en,ja}/frontend.toml`, `frontend/test-real.sh` (add steps only). Do NOT edit `Bar.qml`,
`Island.qml` or `core/` (another card owns them). Common rules: `docs/tasks/README.md`.

**Contracts (on main):** `runtime.ui.panel === "session"` opens it (action `session.menu`, toggles;
`ui.close` closes). Actions `session.lock` (no args) and `session.{suspend,logout,reboot,poweroff}`
which fail with error code `session.confirm_required` unless called with `{confirm: true}`.
Island face name `brightness` with value in doc `svc.brightness` (read `crates/kurashi-services/src/brightness.rs`
for its shape; daemon side lands in parallel, card M5-osd-session-daemon).

**Read:** `frontend/README.md`, `frontend/surfaces/Stage.qml`, `frontend/components/faces/VolumeFace.qml`,
`frontend/components/faces/FaceBase.qml`, `frontend/surfaces/NotificationCenter.qml` (panel pattern).

**Build:**
1. `SessionMenu.qml` rendered in the Stage when `panel === "session"`; keyboard navigable (arrows,
   Enter, Esc → `ui.close`). Destructive entries: first press arms the button ("Press again to …",
   i18n) for 3 s via a Timer that only runs while armed; second press sends `{confirm: true}`.
   Show the daemon's error text if an action fails. Theme tokens only, no theme-name branches.
2. `BrightnessFace.qml` modelled on `VolumeFace.qml`; register it wherever faces are mapped by name.
3. Extend `frontend/test-real.sh`: open via `kurashi act session.menu`, screenshot
   `frontend/shots/real/session-menu.png`, close via `ui.close`. Never press a destructive entry with
   confirm in tests (the sandbox has no logind; still, don't).

**Acceptance:** `nix develop -c frontend/test-real.sh` passes and the session-menu screenshot shows the
menu (Read the PNG to check); idle with menu closed = 0 frames (no running timers/animations).
