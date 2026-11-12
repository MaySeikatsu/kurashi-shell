# W76 — web dock, round three: resize, keep open, add and edit sites (I496, I497)

**Goal.** The user's points 3b, 3d, 3e of session 30 (docs/BACKLOG.md I496, I497), to the UX bar of `docs/ux/webdock.md`
(add a section "Round three (W76, session 30)" there first: how Arc, Zen, Edge's sidebar, Safari and Floorp do each
part, states, keyboard, a11y, motion, multi-output, definition of done).

1. **Resizable card (3b).** In the card size `dock` (the default, `mods.webdock.card_size`) the edge card and the bar
   card can be resized by dragging their free edge(s) (a grab zone along the edge away from the strip/bar, the resize
   cursor, Ctrl+arrow keys as the sidebar's width has them, a double click resets). The size is remembered (per output,
   in the mod's settings — a new setting, not a hand-kept list) and stays within the output. The fixed sizes (phone,
   tablet, wide) do not resize. Motion: the page follows the drag 1:1, no animation.
2. **Keep open (3d).** A small pin key in the card's toolbar keeps the edge dock's card open while focus is elsewhere,
   without reserving space (the dock's existing `webdock.pin` / `pinned`, made reachable on the card: lit while pinned,
   its name and state for a11y). In the bar's card the same key moves the page to the edge dock, pinned there, and
   closes the bar card (one place for "kept open": the edge) — unless the lead tells you otherwise.
3. **Add and edit sites (3e).** A "+" key at the end of the pin strip opens a URL/search field (in the card, where the
   title is): text that is a URL loads it, other text searches with the user's search engine (a setting; default
   DuckDuckGo), and the page is a temporary pin's view; a "Pin" key in the toolbar pins the page where the user is now
   (`webdock.add`), Esc or closing drops it. A click on the card's title turns it into the same field for the current
   pin (browse elsewhere; the pin stays at its address — after it unloads it opens at its pinned page again, its "home").
   The pin's context menu (`PinMenu.qml`) gains: Reload, Update pin to this page (`webdock.retarget`), Unpin but keep
   open (the page stays loaded until the dock unloads it by its rules; the pin is removed from the list at once) — keep
   what the menu has.

**Owned paths.** `mods/webdock/**` (qml, host, test, mod.toml), `crates/kurashi-mod-webdock/**`,
`i18n/{en,ja}/mod-webdock*.toml`, `docs/ux/webdock.md`. Read-only: everything else. Contracts frozen: a change to
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, or anything outside the owned paths → a row in
`docs/CONTRACT-CHANGE.md`, coded against a local stand-in.

**Acceptance.** `mods/webdock/test/test-card.sh` and `test-sidebar.sh` extended (resize by drag and by key, the pin key,
"+" → field → load a local test page → Pin → the pin is in `mods.webdock.pins`, the title field, the three menu entries)
and green on nested niri (`tools/bench/niri-sandbox.sh`; the sandbox is offline: use `mods/webdock/test/pages/`);
`cargo test -p kurashi-mod-webdock`, clippy `-D warnings`; screenshots of each state (light and dark) listed in the report.

**Build dir.** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w76`. Common rules: `docs/tasks/README.md`.
