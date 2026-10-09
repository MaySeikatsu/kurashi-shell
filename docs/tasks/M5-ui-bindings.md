# Card M5-ui-bindings — frontend dispatches input by slot (bindings doc)

**Goal.** Clicks/scrolls on the island and bar go through `input.dispatch {component, slot}` so the
user's config decides what they do; no hardcoded actions in QML (rule 1).

**Owned paths:** `frontend/components/Island.qml`, `frontend/surfaces/Bar.qml`, `frontend/core/` (only
if a helper is needed), new `frontend/test-bindings.sh`. Do NOT edit `Stage.qml`, faces, `shell.qml`.
Common rules: `docs/tasks/README.md`.

**Contracts (on main):** document `bindings` = `{ "<component>": { "<slot>": {action, source, forced_by?} } }`,
component for the island is `island.main`, slots `left right middle hover scroll_up scroll_down
shift_scroll_up shift_scroll_down`; unbound slots are absent. Action `input.dispatch {component, slot}`
invokes the bound action (error if unbound). See `crates/kurashid/src/bindings.rs`.

**Read:** `frontend/README.md` (Core API: `Watch`, `Store.act`), `frontend/surfaces/Bar.qml`,
`frontend/components/Island.qml`, `crates/kurashid/src/bindings.rs`.

**Build:**
1. Island/Bar watch `bindings` (only while visible) and map mouse buttons, wheel (with Shift) and hover to
   slots → `Store.act("input.dispatch", {component: "island.main", slot})`. A slot absent from the doc
   does nothing (no pointer cursor for unbound left click). Replace the `probe.popup.toggle` /
   `island.pin` / `island.prev|next` calls.
2. `frontend/test-bindings.sh` (pattern: `frontend/test-real.sh`): real kurashid in a sandbox,
   `kurashi cfg set island.main.input.left notifications.center`, click the island with
   `swaymsg seat - cursor set X Y; swaymsg seat - cursor press button1; … release button1`, assert
   `kurashi sub runtime.ui --count 0` shows `panel":"notifications"`; reset and assert the default
   opens `island`.

**Acceptance:** `nix develop -c frontend/test-bindings.sh` exits 0; `frontend/test-real.sh` still passes.
