# Card W16-peek-frontend — the Stage shows peeks (K35, I55, B9, B22, I47)

**Decision (user, session 6):** K35 — peeks are drawn by the one Stage surface, never by a popup per widget (K19).
The daemon side is on main: `runtime.ui.peek` = absent or `{source, output, x, w}`; action `ui.peek {source, output,
x, w}` / `ui.peek {}`; refused over an open card (`ui.error.peek_under_card`) and for a mod without `peek:<name>`;
any panel removes it; `peek:<name>` → the mod's `qml/Peek.qml` in the `mods` document's `qml` map (PROTOCOL §8, MODS.md).
**Briefs:** `docs/ux/island.md` (peek line per core face), `docs/ux/sysmon.md` (peek: cores max/avg, load, PSI, top
process), `docs/ux/weather.md` §5 (place, feels-like, H/L, rain from, data age; "stale" in words), DESIGN-SYSTEM §9 motion.

**Read first:** `docs/tasks/README.md`, DECISIONS K19 + K35, PROTOCOL §8 `runtime.ui`, `frontend/surfaces/Stage.qml`,
`frontend/surfaces/Bar.qml`, `frontend/core/ModLoader.qml`, `frontend/components/{TrayIcon,Island}.qml`,
`mods/sysmon/qml/Widget.qml` (its `peekFacts()`; the facts are its a11y description today), `mods/weather/qml/Widget.qml`
(an inline peek drawn above the widget inside the bar window — clipped on a top bar, B22), `crates/kurashi-mock` (`ui.peek`).

**Owned paths:** `frontend/surfaces/Stage.qml`, `frontend/surfaces/Bar.qml` (hover → `ui.peek` plumbing only),
`frontend/components/TrayIcon.qml`, `frontend/components/Island.qml`, new `frontend/components/Peek*.qml`,
`frontend/core/**` (a small helper to send `ui.peek` with the widget's output-local x/w), `mods/sysmon/qml/{Widget,Peek}.qml`
+ `mods/sysmon/mod.toml` (add `peek:sysmon`), `mods/weather/qml/{Widget,Peek}.qml` + `mods/weather/mod.toml` (add
`peek:weather`), `mods/hello/**` (a `peek:hello` for the live test), `frontend/test-*.sh` (a new `test-peek.sh`),
`i18n/{en,ja}/{frontend,mod-sysmon,mod-weather}.toml` (append blocks marked `# W16-peek`).

**Do:** hover (≥ 300 ms intent delay) or keyboard focus on a widget sends `ui.peek` with its source and its
output-local x and width; leaving sends `ui.peek {}` after a 250 ms grace (moving onto the peek keeps it). The Stage,
while no card is open, shows the peek component of `runtime.ui.peek.source` on that output, anchored under (top bar) or
above (bottom bar) the widget, clamped to the output, sized to the content; 0 frames and no subscriptions while no
peek shows (Ma); motion per §9 (fade+slide ≤ 120 ms, none with reduced motion). Sources: mod peeks via ModLoader
(`peek:<name>`), tray tooltips (`tray:<item>`: title + tooltip lines), the island (`island:main`: the shown face's peek
line). Remove weather's inline peek and sysmon's `peekOpen` focus-only subscription (the Peek component subscribes to
`mod.sysmon.procs` itself while shown). A11y: the facts stay the widget's accessible description.
**Measure (K35 open item):** on machine B iGPU, PSS and frame count for: no peek (idle 0 fps), a peek shown, a peek on
the second output of a two-output sandbox (retarget), 20 hover cycles (no growth > 1 MiB). Report the numbers.
**Acceptance:** `frontend/test-peek.sh` (sandbox, mock or real daemon) screenshots: sysmon, weather, tray tooltip,
island peek on a top bar and on a bottom bar, a peek near the output's right edge (clamped), no peek while a card is
open; `just mods-live` green; `just golden` (machine B refs) unchanged or explained; numbers above.
