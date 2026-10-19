# Card W18-peeks — peeks on every bar edge, fade-out, state shots, test recipes (I67; K35; row 98)

**Decision (lead, session 7; contract row 98, on main):** `ui.peek` takes optional `edge` (`top`, `bottom`, `left`,
`right`; absent = top) and, for a side bar, the widget's `y` and `h`; `runtime.ui.peek` carries them (PROTOCOL §8,
kurashid and mock done; fixture `snap_runtime_ui_peek_side.json`). The keyboard path into bar widgets is not in this
card (a separate design, I67).
**Briefs:** `docs/ux/island.md`, `docs/ux/sysmon.md` (peek), `docs/ux/weather.md` §5 (peek), DESIGN-SYSTEM §9 (motion).

**Read first:** `docs/tasks/README.md` (rules), K35, PROTOCOL §8 `runtime.ui`, I67 in `docs/BACKLOG.md`,
`docs/tasks/W16-peek-frontend.md` (what exists), `frontend/surfaces/{Stage,Bar,BarConfig}.qml`,
`frontend/core/{Peeks,PeekSource}.qml`, `frontend/test-peek.sh`, `frontend/test-mods-live.sh`, `justfile`,
`mods/weather/qml/Peek.qml`, `mods/sysmon/qml/Peek.qml` (read only), `mods/sysmon/test-states.sh` (fixture states).

**Owned paths:** `frontend/surfaces/Stage.qml`, `frontend/surfaces/Bar.qml` (peek plumbing only),
`frontend/core/{Peeks,PeekSource}.qml`, `frontend/test-peek.sh`, `frontend/test-mods-live.sh`,
`frontend/shots/peek/**`, `justfile`, `mods/weather/qml/Peek.qml`, `i18n/{en,ja}/frontend.toml` (append a block marked
`# W18-peeks`). Not yours: `frontend/components/QuickPanel.qml`, `frontend/components/quick/**`,
`frontend/components/SlotHost.qml` (W18-quick-tiles), `mods/sysmon/**` (W18-sysmon — ask in your report if its
`Peek.qml` needs a change), `crates/**`.

**Do:**
1. **Edges:** the bar sends `edge` (and `y`/`h` on side bars) with its peeks; the Stage places the peek under a top bar,
   above a bottom bar, right of a left bar and left of a right bar, aligned to the widget and clamped to the output with
   the theme gap (as the K35 lead fix does for x). Tray tooltips, the island and mod peeks all follow.
2. **Fade-out:** leaving fades the peek out (≤ 120 ms, DESIGN-SYSTEM §9) and then the Stage is back to 0 frames; with
   motion off (theme `none`), no animation in or out. A new peek during the fade replaces it at once.
3. **State shots** (`frontend/test-peek.sh`): weather peek — no place, loading, offline, stale; sysmon peek — paused,
   unavailable, the top-process line (sysmon's fixture states, `KURASHI_SYSMON_ROOT`, real daemon in the sandbox); peeks
   on a bottom, a left and a right bar; reduced motion.
4. **Recipes and test hygiene:** `just peek` runs `frontend/test-peek.sh`; `frontend/test-mods-live.sh` derives the
   expected `qml` keys from each manifest's `provides` (every kind the daemon maps), not from a fixed list.

**Acceptance:** `timeout 1200 just peek` green with the shots above in `frontend/shots/peek/`; `just mods-live` green
(no QML warnings, no i18n misses); `frontend/test-stage.sh` still green; 0 Wayland commits for 10 s with no peek (as
in W16). Report the measured fade frame count.
