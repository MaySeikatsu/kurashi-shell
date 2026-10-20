# Card W20-webdock-host — new tabs in the dock, home and history, card polish, hover reports (K40; I78)

**Decision (user, session 8):** links that want a new tab or window **stay in the dock** by default (`new_tabs =
dock`: the link loads in the pin's own view, Back returns); `new_tabs = browser` sends them to the default browser
(today's behaviour). The header gets back and forward, a **home** button once the page has left the pin's address,
and **"Replace pin with this page"** (`webdock.retarget`). The card reports hover and focus so the daemon's state
machine can hide it (W20-webdock-daemon, parallel); the shell's strip is W20-webdock-shell (parallel).
**Brief:** `docs/ux/webdock.md` ("User decisions (session 8)", "Layout per edge" → Header, "Sites", "Motion",
"Keyboard and a11y", "Definition of done"); BACKLOG I78 (card polish).

**Read first:** `docs/tasks/README.md` (rules), DECISIONS K40, K38, K39, MODS.md "Web dock" (document fields
`new_tabs`, `engaged`, `geometry.grace`, `geometry.strip`; actions `webdock.hover`, `webdock.engage`,
`webdock.retarget`) and "Host (QML)", `fixtures/ipc/server/snap_mod_webdock.json`, `mods/webdock/host/*.qml`,
`mods/webdock/test/test-host.sh`, BACKLOG I78.

**Owned paths:** `mods/webdock/host/**` (not the `core` link), `mods/webdock/test/{test-host.sh,ipc.py,pins.py,netlog.py,pages/**}`,
new `mods/webdock/shots/host-*.png` (you may replace the existing host shots), new
`i18n/{en,ja}/mod-webdock-host.toml`. Not yours: `mods/webdock/{qml,mod.toml}`, `mods/webdock/test/test-real.sh`,
`frontend/`, `crates/**`, other i18n files (read `mod-webdock.toml`'s existing keys). Sandbox names start with `w20-host-`.

**Do:**
1. **New tabs:** `onNewViewRequested`/`onNewWindowRequested` for tab, background tab and window destinations:
   `new_tabs = dock` → load the requested URL in the same pin's view (history kept, Back returns);
   `browser` → `webdock.host.new_window` as today. Dialog destinations stay sheets.
2. **Header** (title first; I78): back, forward (engine history), title (elides), **home** (visible only when the
   page's URL differs from the pin's `target`, ignoring a trailing slash and the fragment; loads `target`), reload,
   mobile/desktop and phone/large as quiet controls (tonal or icon toggles with tooltips, not two accent-filled
   segmented bars), an overflow menu: open in browser, **replace pin with this page** (shown with home →
   `webdock.retarget {pin, url}`), collapse. At 360 px the title keeps ≥ 120 px.
3. **I78 polish:** the page is clipped to the card's radius (rounded bottom corners); a keyboard path into the header
   (Tab from the page's last element or a shortcut, FocusRing); reduced motion: fade only; no white flash (skeleton
   until first paint, as today).
4. **Hover and focus reports:** the card's layer surface is grown by `geometry.grace` px of transparent, input-taking
   margin on its sides; pointer enter/leave of that area → `webdock.hover {part: "card", inside, output}`; the window
   gaining/losing keyboard focus → `webdock.engage {on}`. When `engaged` and the card is extended and front, request
   keyboard focus so the first keystroke reaches the page. Use `geometry.strip` for the strip margin.
5. Copy in your own i18n file (en + ja): forward, home, replace pin, the overflow menu's name, any tooltip.

**Acceptance:** `timeout 1200 bash mods/webdock/test/test-host.sh` green against `kurashi-mock` with new cases: a
fixture page with a `target=_blank` link and a `window.open()` → with `new_tabs` dock (patch via `mock.webdock`) the
link loads in the same card and Back returns to the pin page; with `browser` → `webdock.host.new_window` is sent; after
in-page navigation home is visible, clicking it returns to `target`; replace-pin sends `webdock.retarget` with the
current URL (if the mock does not know the action yet, assert the intent was sent and report it); hover/engage intents
are sent on enter/leave/focus; the net-log privacy test stays green. Shots `host-{phone-header,large-header,
navigated-home,overflow-menu,new-tab-in-dock,rounded-bottom,ja}.png`. I78 items: met / not met.
