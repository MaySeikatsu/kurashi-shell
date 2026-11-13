# W78 — the web dock's Local mode, and desktop apps as an experiment (I499; the user's 3c, 3g)

**Goal.** A switch in the dock's strip between **Online** (the site pins, as today) and **Local** (shell content: notes,
tasks, timer, lyrics, any mod panel or desk card, the launcher — the sections a sidebar can host since session 30, I501),
so the dock can be a local, shell-integrated dock. Pins already take `mod:<id>:<panel>` targets (view pins): the mode
filters the strip and the "+" offers the local choices. **Experimental** (an advanced setting, off): a desktop app as a
pin — its window held in the card's frame by the compositor (niri: a floating window moved and sized to the card's rect
by IPC, raised while the card shows, hidden on a workspace of its own while it does not); say plainly where that cannot
work (other compositors, apps that resize themselves, focus rules).

**Owned paths.** `mods/webdock/**`, `crates/kurashi-mod-webdock/**`, its i18n, `docs/ux/webdock.md` ("Local mode",
"Desktop apps (experimental)" first). The niri IPC for the experiment goes through the daemon's compositor adapter
(`crates/kurashi-compositor`, read-only for you: CONTRACT-CHANGE row).
**Acceptance.** `mods/webdock/test/test-card.sh` part "local": the switch, a view pin opened in Local mode, the "+" offering
local content; unit tests for the mode and the filter; shots light and dark.

**The user's scope (session 32).** Build **Local mode** as above (done = the acceptance above, shots light and dark,
the UX brief's states). The **desktop apps are an evaluation, not a build**: in `docs/ux/webdock.md` "Desktop apps
(experimental)", compare what is possible on Wayland/niri, with an honest verdict and cost per option, and a recommended
first spike. The user's own lead: "it should be possible to use an OS-installed browser instead of the embedded one, so
other apps too?" Cover at least: (a) compositor placement — niri IPC moves/sizes a floating window onto the card's rect,
raises/hides it (what niri's IPC offers today, focus, workspaces, resizes, other compositors); (b) a nested compositor
in the shell (QtWayland Compositor in QML: apps run on our own `WAYLAND_DISPLAY` and their surfaces draw inside the
card — clipboard, IME, portals, dmabuf, popups, XWayland); (c) the system browser in app mode (`chromium --app=…`,
Firefox) placed by (a), vs the embedded engine; (d) a live view only (toplevel capture, ext-image-copy-capture /
screencopy of one window) with input staying in the real window; (e) anything else you find (xdg-foreign, …). A tiny
read-only probe on nested niri (`tools/bench/niri-sandbox.sh`, e.g. `niri msg` moving a floating `foot`) is allowed and
welcome; no product code for apps.
**Base.** `feat/s32-combined`: if your HEAD does not contain `origin/feat/s32-combined`, `git reset --hard
origin/feat/s32-combined` first. **Not yours:** the paths in `crates/kurashi-mod-webdock/src/dock.rs` that set the dock's
`output` and `mods/webdock/test/test-dock.sh` (the lead fixes B128 there now) — touch dock.rs only where the mode needs
it, and say where. Build dir `~/.cache/kurashi-agents-target/w78`. Time box: report by 11:40 with what is done.
