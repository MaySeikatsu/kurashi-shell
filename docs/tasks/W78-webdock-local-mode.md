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
