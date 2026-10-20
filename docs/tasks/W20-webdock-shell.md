# Card W20-webdock-shell — the dock's edge, strip, view card and bar widget (W17.4; K40; row 88)

**Decision (user, session 8):** see K40 and `docs/ux/webdock.md` "User decisions (session 8)". The shell draws the
indicator, the hover zone, the icon strip, the card of a **view pin** (a mod panel) and the add/empty/cold-engine
states; the web host draws the card of a site (W20-webdock-host, parallel). The daemon decides every mode
(W20-webdock-daemon, parallel): you send `webdock.*` intents and render `mod.webdock`, nothing else.
**Brief:** `docs/ux/webdock.md` — "Layout per edge", "Keyboard and a11y", "Motion", "States", "Fit and constraints",
"Definition of done" (the screenshot list for the shell's parts).

**Read first:** `docs/tasks/README.md` (rules; rule 10 UX bar), DECISIONS K40, K38, K19, K16, MODS.md "Web dock"
(document, the "Shell side" paragraph) and "Contributions" (`surface:`), `fixtures/ipc/server/snap_mod_webdock.json`,
`mods/webdock/mod.toml`, `frontend/shell.qml`, `frontend/core/{mods.js,ModLoader.qml,Store.qml,Theme.qml}`,
`frontend/surfaces/Bar.qml` (how a mod widget is hosted, `vertical`), one mod widget (`mods/weather/qml/Widget.qml`),
`mods/webdock/host/WebCard.qml` (where the web card sits, so the strip lines up), `frontend/test-peek.sh` (sandbox
test pattern), DESIGN-SYSTEM §9 (motion).

**Owned paths:** `frontend/shell.qml` (only: one `Variants` that creates every enabled mod's `surface:*` per screen),
`frontend/core/mods.js` (add `surfaces(doc)`), new `mods/webdock/qml/**` (`surfaces/dock.qml`, `Widget.qml`, its
components), new `i18n/{en,ja}/mod-webdock-dock.toml`, new `mods/webdock/test/test-dock.sh`, new
`mods/webdock/shots/dock-*.png`, the `webdock` recipe in `justfile` (add your test). Not yours:
`frontend/surfaces/*`, `frontend/components/*`, `mods/webdock/host/`, `crates/**`, the other i18n files (read
`mod-webdock.toml`'s existing `webdock.*` keys; new copy goes in your own file). Sandbox names start with `w20-shell-`.

**Do:**
1. **`surface:` instantiation:** for each enabled mod whose `qml` map has `surface:<name>`, one instance per screen
   (required property `screen`), created and destroyed with the mod (no polling; the `mods` document drives it).
2. **`surfaces/dock.qml`** (layer-shell, at `edge` of its screen): hidden → a transparent 2 px input zone along the
   whole edge + the 4 × 48 indicator pill (`indicator`), **0 frames idle**; compact/extended (on `output` only) → the
   strip (`geometry.strip`, vertical on left/right, horizontal on top/bottom): pins in order (favicon `icon`, else a
   letter tile in a token colour; a dot when `loaded`; a ring when shown), a divider, view pins, then pin-dock toggle,
   + add, settings; overflow scrolls. Input regions add `geometry.grace`. `reserve && pinned` → exclusive zone = strip.
3. **Intents:** pointer enter/leave of the edge zone, the strip and the shell's own card → `webdock.hover {part,
   inside, output: screen.name, shared}` (`shared` when another screen touches that edge); focus in/out →
   `webdock.engage`; a pin click → `webdock.select`; pin toggle → `webdock.pin`; + → the add form (URL + name →
   `webdock.add`); settings → the mod's Settings page (the existing `settings.open` action); right-click/menu on a pin:
   move up/down (`webdock.move`), remove (`webdock.remove`).
4. **Keyboard** (brief): when `engaged` and the strip is the front part, take keyboard focus (on-demand layer focus);
   arrows move, Enter selects, Space toggles pin-dock, Escape → `webdock.back`, Tab into the card. FocusRing for
   keyboard focus only; every icon has an accessible name with its state.
5. **View card** (extended + `shown` is a `view` pin): the card frame next to the strip, phone/large sizes from
   `geometry`, header (title, phone/large, collapse), body = the mod's `panel:<panel>` through ModLoader.
6. **States:** empty (strip with + and settings only; the card with `webdock.empty` and "Add a site"), cold engine
   (extended web pin while `host.state` is `off`/`starting` or the pin is not yet `loaded`: the card frame with
   `webdock.host.starting`, drawn by you; it goes when the host's card is up), host `missing`/`failed` (reason, view
   pins still work), forced pins (provenance; edit controls inert with the reason), 30 pins (scroll), ja.
7. **Motion:** strip slides 180 ms (`Theme.motion` standard), card 40 ms later; reduced motion: fade only.
8. **`Widget.qml`** (`widget:webdock`): one bar button, `webdock.toggle {output}`, shows open/pinned state, a11y
   name, `vertical` form.

**Acceptance:** `timeout 900 bash mods/webdock/test/test-dock.sh` green in a sandbox against `kurashi-mock`: it
drives states with `mock.webdock {…}` patches and the new actions (the daemon card's mock parity lands in parallel —
where an action is still unknown to the mock, assert the intent was sent and list it in your report), and writes the
shots `dock-{hidden-indicator,compact,view-phone,view-large,empty,add,cold,missing,pinned,edge-left,edge-top,edge-bottom,30-pins,ja}.png`.
Also measured and reported: 0 commits/frames over 10 s with the dock hidden; PSS delta per output with the mod on vs
off (budget ≤ +1 MiB per output, K16/K19). Every definition-of-done item of the brief that is the shell's: met / not met.
