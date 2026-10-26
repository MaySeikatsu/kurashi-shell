# Card W44-settings — Settings › Layout: edges, zones, draw modes, frame (K71, K72; docs/ux/layout.md, edge-modules.md)

**Why:** user points 7, 10 (base placement), 12. W43 generated a plain Layout page from the schema (one row per key). The
briefs ask for a page a person can use: which edges have bars, what is in each zone, what `auto` resolved to, why a control
is inert, and moving a bar without emptying it.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K71, K72; `docs/ux/layout.md` (Design: "Bars on every edge",
"Visibility", Settings sentences), `docs/ux/edge-modules.md` ("Placement"), `docs/ux/settings.md`; PROTOCOL §3.1
(`unplaced`, `problems`, `*_source`, `reserve_reason`) and §6 (`layout.bar.move`); `settings/` (how a page is generated, the
pick-list control, the output picker, `settings/core/Store.qml`), `settings/test.sh`.

**Task:**
1. **Edges diagram:** at the top of the Layout page, a small screen drawing with the four edges as toggles (bar on/off per
   edge, for the output the picker selects); a radio-group per edge with names (a11y: not colour alone). Selecting an edge
   shows its section below (visibility, keep space, draw, the three zones).
2. **Zones:** each zone an ordered list with add (a menu of the `modules` choices the zone does not hold, with names from
   `i18n/*/layout.toml`), remove, move up/down (buttons and Alt+Up/Down); the pseudo entry "Other mods' widgets" (`mods`).
   `unplaced` modules offered back ("Not shown anywhere: Weather — add to …"); `problems` shown on their entries with the
   reason and a remove button.
3. **Move bar:** "Move bar to …" (the free edges) runs `layout.bar.move {from, to, output?}`; the page follows.
4. **Honesty:** `draw` and `reserve` show what `auto` resolved to from `runtime.layout` ("Automatic (dynamic)", "Automatic
   (keeps space)"); `reserve` under `hidden` is inert with the document's `reserve_reason`; the frame section (on, thickness,
   inner corners, keep windows inside) and the preset `layout.draw` with a one-line explanation of the three modes; the
   sidebar page's width row has a reset and names "drag the sidebar's inner edge" (i18n).
5. **Keys:** the Keys page offers `layout.toggle` targets for bindings where the schema's key list allows (if it does not,
   a CONTRACT row with the proposed `keys.*` entries).
6. Fix I241's Settings items: the output picker does not list the `"*"` alias; `settings.open {page: "bar"}` opens `layout`.
7. Tests in `settings/test.sh` (+ shots `settings/shots/layout/…`, washi and sekai, light and dark, ja once): toggle an edge,
   add/remove/reorder a module, move the bar, an unplaced module offered back, a problem entry removed, inert reserve.

**Owned paths:** `settings/**` (incl. its shots and test), `i18n/{en,ja}/layout.toml` and `i18n/{en,ja}/settings*.toml` (new
keys only), `crates/kurashid/src/` route of `settings.open` page aliases only. Not `frontend/`, not the schema.

**Acceptance:** `settings/test.sh` green with the new steps; shots listed; every string through i18n (en and ja key sets
equal); `just check` green.

**Contract rows:** CONTRACT-CHANGE rows 530–539 only. **Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w44-settings
CARGO_BUILD_JOBS=4`; sandbox names `w44-settings-…`; `idle.enabled = false` in sandbox configs. Model: haiku (max effort); the
lead reviews the page against the briefs and hands it back if it is below the bar.
