# Card W23-system — idle, keep-awake, night light, keyboard layouts, recorder and screenshots (K47)

**User (session 10):** "get the desktop shell as complete and usable as possible … take actual code snippets, concepts
… from Caelestia, Noctalia, DMS, illogical-impulse, shellseikatsu, WormShell if they solve a problem already. Don't
reinvent it." Work efficiently: prototype QML against placeholder data first, write Rust in one go, compile/test a few
times at the end.

**References (read, copy what solves it; MIT/GPL-compatible ideas and snippets, note the source in a comment):**
- DMS: `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad/insp/DankMaterialShell/quickshell/Services/{IdleService,NightModeService,KeyboardLayoutService,SessionService}.qml`
- Noctalia: `~/Downloads/github/quickshell/noctalia-shell/Services/{NightLightService,ScreenRecorderService,IdleInhibitorService,KeyboardLayoutService}.qml`
- ii (illogical-impulse): `~/.config/quickshell/ii/services/{Idle,Hyprsunset}.qml`
- shellseikatsu: `~/Documents/projects/quickshell/shellseikatsu/Services/{GammaService,NiriBackend}.qml`

**Read first:** `CLAUDE.md`; DECISIONS **K47** (+ K16 budgets, K24 quick settings); PROTOCOL rows `svc.idle`,
`svc.nightlight`, `svc.keyboard`, `svc.recorder` (the shapes are the contract); schema `crates/kurashi-schema/src/v1.rs`
`Idle`, `NightLight`, `Recorder`; `crates/kurashid/src/wiring.rs` (how a refcounted service registers: `brightness`,
`audio`, `tray`), `crates/kurashid/src/workspaces.rs` and `crates/kurashi-compositor/src/niri.rs` (event stream, actions),
`crates/kurashi-services/src/{session,brightness}.rs`, `frontend/components/QuickPanel.qml` + `quick/QuickTile.qml`,
`frontend/surfaces/Bar.qml` (widgets), `docs/ux/quick-settings.md`.

**Owned paths:** new modules under `crates/kurashi-services/src/` (`idle.rs`, `nightlight.rs`, `recorder.rs`) or a new
crate `crates/kurashi-idle` if the Wayland part wants its own; `crates/kurashi-compositor/**` (keyboard layouts,
power-off-monitors, screenshot actions); `crates/kurashid/src/wiring.rs` and `main.rs` (registration only, append your
functions at the end); `crates/kurashi-mock/**` (parity for the four documents and actions); new QML
`frontend/components/quick/{CaffeineTile,NightTile,RecordTile}.qml` or QuickTile instances in `QuickPanel.qml`; bar
widgets in `frontend/surfaces/Bar.qml` **only** inside new `component` blocks you add (keyboard layout, recording dot)
plus their registration lines; `i18n/{en,ja}/{power,frontend}.toml` (append); `nix/hm-module.nix` + `nix/nixos-module.nix`
(runtime deps `wlsunset`, `gpu-screen-recorder` optional, `wf-recorder`); `docs/ux/power.md` (new UX brief: idle,
caffeine, night light, recorder — how GNOME, KDE, macOS, DMS, Noctalia, Caelestia, ii do it; states incl. missing
program, compositor without idle-notify, locked; keyboard; multi-output); new test scripts `frontend/test-power.sh`.
**Not yours:** `frontend/components/{Block,Icon,…}.qml` primitives (use them), `settings/**`, `frontend/core/**`,
schema (lead), other surfaces. Contract needs → `docs/CONTRACT-CHANGE.md` row. Sandbox names `w23-sys-`.

**Do:**
1. **svc.idle:** `ext-idle-notify-v1` via wayland-client (+ `wayland-protocols` staging feature), one notification per
   stage timeout (re-armed when the config changes); stages dim (brightness to ~30 % of current via the brightness
   service, restored on resume), lock (`session.lock` action path), screens off (niri `power-off-monitors`, on via any
   input — niri turns them on itself), suspend (logind). Inhibitors: caffeine (action), media playing
   (`idle.inhibit_while_media`, from svc.media), logind idle inhibitors (ListInhibitors, `What` contains `idle`). The
   service runs while `idle.enabled` (not refcounted: it is a policy, like the notification server — say so in the doc
   comment). Compositor without the protocol → `stage` stays active and the doc says why (`reason`).
2. **svc.nightlight:** supervise `wlsunset` (Noctalia's command line: `-t night -T day`, `-l lat -L lon` for sun,
   `-S`/`-s` HH:MM for manual; always = `-S 00:00 -s 23:59`-equivalent or `-t T -T T+1`), restart on setting change,
   stop when disabled; `active` computed from the schedule. Sun schedule: lat/lon from `mod.weather`'s place if any.
3. **svc.keyboard:** niri `KeyboardLayoutsChanged` / `KeyboardLayoutSwitched`; actions `keyboard.next/set`. Bar widget:
   the short name (e.g. `us`, `jp`), click = next; hidden while only one layout exists.
4. **svc.recorder:** supervise `gpu-screen-recorder -w <output> -f 60 -a default_output -o <file>` (Noctalia's flags) or
   `wf-recorder -o <output> -f <file> [--audio]`; SIGINT to stop; a notification with the file when it ends (via the
   notify service's own path or `notify-send`); bar dot while recording (click = stop). Screenshots: niri actions
   `screenshot`, `screenshot-screen`, `screenshot-window`.
5. Quick settings: tiles Caffeine, Night light (arrow → its page with the warmth slider and schedule), Record. They are
   `QuickTile`s bound to the documents; a missing program is a `reason`, never a dead tile.
6. Ma: no polling; wlsunset/recorder processes exist only while on; idle uses compositor events.

**Acceptance:** `nix develop -c cargo test -p <your crates>` and `cargo clippy --workspace -- -D warnings` green;
`frontend/test-power.sh` (sandbox, real kurashid): caffeine toggles `svc.idle.caffeine` and a tile shows it; with
`idle.dim_after = 2` and no input the stage goes `dimmed` within ~5 s (headless sway supports ext-idle-notify — check;
if not, assert the `reason`); night light with a fake `wlsunset` on PATH (a script that records its argv) gets the
right flags and is stopped on disable; recorder with a fake `wf-recorder` writes the doc and stops on `recorder.stop`;
keyboard doc from the fake compositor; screenshots: quick card with the three tiles under `theme.decor = "sekai"` and
`"none"`. Report (terse): what you built, docs as implemented, shots, failures quoted, follow-ups for the backlog.
