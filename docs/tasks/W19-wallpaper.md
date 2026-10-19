# Card W19-wallpaper — wallpaper picker polish that is not about colour (I83, I86 part, I32)

**Decision (lead):** fix what the UX review found, except colours (design pass with the user, I63). The picker may ask
for a card up to 720 px wide (row 66, `cardWidth`).
**Brief:** `docs/ux/wallpaper.md` (picker, preview, states, DoD).

**Read first:** `docs/tasks/README.md` (rules), I83, I86 and I32 in `docs/BACKLOG.md`, `docs/ux/wallpaper.md`, contract
row 66 (`cardWidth`), `mods/wallpaper/qml/Panel.qml`, `crates/kurashi-mod-wallpaper/src/**` (read; change only if a
point needs data), `mods/wallpaper/test/**` and `mods/wallpaper/shots/` (how the real shots are made),
`i18n/{en,ja}/mod-wallpaper.toml`.

**Owned paths:** `mods/wallpaper/qml/Panel.qml` and new components under `mods/wallpaper/qml/` (not `slots/`),
`crates/kurashi-mod-wallpaper/**`, `mods/wallpaper/test/**`, `mods/wallpaper/shots/**`, `i18n/{en,ja}/mod-wallpaper.toml`.
Not yours: `mods/wallpaper/qml/slots/**` (W18 tile, done), `frontend/**`.

**Do:**
1. **Width:** the picker asks for a wider card (640–720 px, `cardWidth`) and shows 3–4 thumbnail columns; the preview
   area uses the width (thumbnail beside the theme diff); smaller outputs still fit (clamped by the Stage).
2. **Outputs:** the output chips have no empty leading area (a real per-output thumbnail of the current picture, or no
   slot at all); "Span · not yet" says plainly that spanning is not available yet (or is hidden until it is).
3. **Layout:** "Clear thumbnails" leaves the main view (a small overflow menu in the header, with the cache size); the
   theme diff swatches are at least 14 px with their role labels; one primary action stays (Apply).
4. **Strings:** remove the keys the W18 tile no longer uses (`mod-wallpaper.tile.random|pause|resume|rotating`) if
   nothing else uses them.
5. **Not drawn yet (I32):** keyboard grid navigation and `/` search are exercised by the test (wl_keys can now type
   `/`); Shift+Enter (every output) and Ctrl+Enter (wallpaper only) too.

**Acceptance:** the wallpaper real-shot test (`mods/wallpaper/test/`, real daemon + fake backend, sandbox) green with
re-shot picker states (grid at 640–720 px, preview, empty, onboarding, backend down/missing, folder missing, search,
looks) and the keyboard paths above; `cargo test -p kurashi-mod-wallpaper` if the crate changed; no QML warnings.
