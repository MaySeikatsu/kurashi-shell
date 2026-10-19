# Card W18-quick-tiles — mod tiles look native in quick settings; mock parity for quick states (I52, row 76, I50)

**Decision (lead, session 6; contract row 76):** a `quick.tiles` contribution is a tile of **160 × 56 px** (the core
`QuickTile`'s implicit size) with `glyph`, `label`, `subtitle`; the quick grid sizes every contribution to its cell ×
56 px. A contribution gets the native look by importing `qs.components.quick` and being a `QuickTile`.
**Brief:** `docs/ux/quick-settings.md` (tiles, states, keyboard), `docs/ux/COMPOSITION.md` §5 (slots).

**Read first:** `docs/tasks/README.md` (rules), contract row 76 and I50/I51/I52 in `docs/BACKLOG.md`, K28, PROTOCOL §8
`runtime.slots`, `frontend/components/SlotHost.qml`, `frontend/components/QuickPanel.qml`,
`frontend/components/quick/QuickTile.qml`, `mods/wallpaper/qml/slots/quick.tiles.qml`,
`crates/kurashid/tests/data/mods/hello/qml/slots/quick.tiles.qml`, `crates/kurashi-mock/src/{state,documents}.rs`,
`frontend/test-quick.sh`, `frontend/test-quick-sections.sh`.

**Owned paths:** `frontend/components/SlotHost.qml`, `frontend/components/QuickPanel.qml`,
`frontend/components/quick/**`, `mods/wallpaper/qml/slots/quick.tiles.qml`,
`crates/kurashid/tests/data/mods/hello/qml/slots/quick.tiles.qml`, `crates/kurashi-mock/**`,
`frontend/test-quick.sh`, `frontend/test-quick-sections.sh`, `frontend/shots/{quick,quick-sections,quick-sections-ja}/**`,
`docs/ux/COMPOSITION.md` (§5: write the tile contract down), `i18n/{en,ja}/frontend.toml` (append a block marked
`# W18-quick-tiles`). Not yours: `frontend/surfaces/Stage.qml`, `frontend/surfaces/Bar.qml` (W18-peeks).

**Do:**
1. **Host sizing:** the quick grid lays every `quick.tiles` contribution out in a 160 × 56 cell (the same flow as the core
   tiles, in contribution order after them); a contribution that is not a `QuickTile` is clipped to its cell, never
   grows the grid; a not-ready contribution takes no cell (K28).
2. **Mod tiles:** the wallpaper tile becomes a `QuickTile` (glyph, label "Wallpaper", subtitle: the current picture's
   name or "Next" action, click = `wallpaper.next`, secondary/right = open the picker panel) and the hello test tile a
   `QuickTile`; both keyboard-reachable like core tiles, a11y names set.
3. **Mock parity (I50):** `brightness.set`; a `quick.tiles` contribution in `runtime.slots` (the hello tile) so mock
   runs show a mod tile; a battery scenario (`svc.power` `present: true` with charge/time); a mock-only control to make
   a service `unavailable` or a key forced on demand (tile-level states), with unit tests.
4. **Tile on-state token (I51 open part):** if `QuickTile` still hard-codes the tonal on-state, read it from component
   tokens (`quick.tile.on.*`) when the theme document has them, else today's look — report whether kurashi-theme needs
   the token (do not edit kurashi-theme).

**Acceptance:** `timeout 900 frontend/test-quick.sh` and `timeout 900 frontend/test-quick-sections.sh` green (mock,
sandbox) with new shots: grid with the wallpaper-style and hello contributions next to core tiles (same size), a
contribution that is not a tile (clipped), battery present, a tile unavailable, a tile forced, ja; keyboard: Tab/arrows
reach the contributed tiles. `cargo test -p kurashi-mock`, `cargo clippy -p kurashi-mock --all-targets -- -D warnings`.
No QML warnings in the logs.
