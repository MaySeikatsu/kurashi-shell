# Web dock (mod `webdock`) — UX brief
Status: draft (lead, session 7, 2026-10-19) — the user's decisions are in; the state machine and sizes below wait for
the user's review, then the contract freezes (CONTRACT-CHANGE rows 88–94) and cards follow. K38, K39.

## Job
Keep a few web apps and kurashi views one hover away at a screen edge: a click opens one in a phone-sized panel,
another click puts it away, and nothing costs anything while the dock is unused. It is not a browser — the user's browser stays
the browser, and the dock hands pages to it. Lives at one screen edge (right by default), driven by hover, a keybind and
a bar widget; configured in Settings › Web dock.

## User decisions (session 7)
- **Engine:** Chromium (QtWebEngine) in its own on-demand process on a patched Quickshell (K38, K39), **ungoogled by
  configuration** (see "Privacy"): ungoogled-chromium itself cannot be dropped in, and an ungoogled QtWebEngine build is
  not worth its cost while the engine provably sends nothing on its own. Gecko cannot be embedded.
- **Browser bridge:** the user's **default browser** (whatever `xdg-open` opens — Zen on the user's machine, never
  hard-coded): "open in browser", links for a new tab, clipboard, drag and drop. Browser bookmarks as a pin source and a
  per-pin hybrid (a pin that opens in the browser's own window) are later (I70, I75).
- **Pins:** kurashi's own pins (Settings, Nix); a pin is a **site** or a **kurashi view** (a mod panel). Like Zen's
  Essentials or Edge's sidebar apps.
- **Modes:** hidden (a small indicator) → compact (the icon strip) → extended (the pin, phone format by default, can
  grow to almost the whole screen). **Mobile/desktop view** toggle per site.
- **Edge:** right by default; left, right, top or bottom. Hover reveals; the dock can be **pinned open** and unpinned.
- **Cost:** the mod is off by default (Ma); the web engine loads on the first web open and **unloads after 1 h**
  unused (setting).
- **Later, designed now:** a browse/search section and "pin this page".
- **Name:** `webdock` · "Web dock" / 「ウェブドック」.

## References (research 2026-10-19)
- **Floorp** panel sidebar — the closest model: a container (own cookie jar) per panel, "Use mobile user agent" per
  panel (docs warn it does not always take), width per panel (0 = global), "unload when closing panel", **open on
  mouse hover** (closes on leave, a click keeps it open; turns on "display over the page").
  https://docs.floorp.app/docs/features/panel-sidebar
- **Vivaldi** web panels: a second click on the icon closes the panel and keeps the icon bar; users dislike
  auto-close hiding the icons (two clicks to reopen) — keep icons reachable. Panels keep using resources (hibernation
  only requested). https://help.vivaldi.com/?p=67 · https://forum.vivaldi.net/topic/59788/keep-panel-icons-visible/9 ·
  https://forum.vivaldi.net/topic/74241/a-deep-dive-into-panels/21
- **Edge** sidebar: always on / auto hidden / off; panel min width 376 px, sites may ask for `preferred_width`
  (480); desktop client hints, no mobile UA. **Being removed** (sidebar apps gone in Edge 149) — the model is not
  sacred. https://learn.microsoft.com/en-us/microsoft-edge/progressive-web-apps/how-to/sidebar
- **Opera**: messengers pinned from the panel; the panel splits the window; disabled messengers reappear when their
  site opens — never add pins on your own. https://blogs.opera.com/tips-and-tricks/?p=378
- **Zen** compact mode: hide sidebar (hover the side edge) / toolbar / both; users report it collapsing too quickly;
  Twilight added hysteresis (stays while the pointer is near the edge). https://docs.zen-browser.app/user-manual/compact-mode ·
  https://piunikaweb.com/2026/08/04/zen-browser-twilight-compact-mode-window-dragging/ — **Firefox** 136 hover-expand
  sidebar stuck after rapid enter/leave (bug 2054033): drive hover from a state machine, not raw enter/leave.
- **Auto-hide conventions:** Dash to Dock show 250 ms / hide 200 ms, pressure barrier, "limit pressure to slow
  speeds" so a flick crosses to the next monitor; KDE reveals on contact and has a long tail of shared-edge bugs
  (bugs.kde.org 351175, 374805). Accidental reveals come from scroll bars of maximised windows at that edge.
- **Quickshell shells:** sidebars are keybind-driven (end-4-style rices: Super+A/N; Noctalia: IPC binds); hover is an
  extra. **Google** blocks OAuth in embedded webviews and points to the system browser
  (https://developers.googleblog.com/en/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/).

## Beyond the basic job
- **Kurashi views as pins:** any enabled mod panel (`mod:<id>:<panel>`: weather, sysmon, wallpaper picker, later
  notes/tasks/LLM chat from ROADMAP v0.3) opens in the same card, drawn by the shell, no web engine involved.
- **Browser bridge:** "open in browser" for the current page; links that want a new tab go to the default browser;
  drag a link from the browser onto the strip to pin it (v1.x). Later: bookmarks from the user's browser as an "add
  pin" source, a browser extension + native messaging for "send this tab to the dock" (I70), and the hybrid pin that
  opens in the browser's own window, docked by the compositor (I75).
- **Composition:** pins as a launcher provider ("WhatsApp → open in dock"); an unread count from a page title
  ("(3) Inbox") as a badge on the icon and an Island signal; web notifications into kurashi notifications; a web
  player's media into the media face — all later (I71, I73), each behind a per-pin allowlist.
- **Calm:** no autoplaying reveal, no badges unless asked, no pins added by sites.

## Design
### Modes and transitions (daemon-owned state machine, `mod.webdock`)
State: `mode` (hidden | compact | extended), `shown` (the pin the extended card shows, kept while hidden), `pinned`
(bool, a setting the strip toggles), `engaged` (the user clicked into the dock: it has keyboard focus).

| From | Event | To |
|---|---|---|
| hidden | pointer rests on the edge zone ≥ reveal delay (250 ms; 500 ms on an edge shared with another output) | compact; extended(`shown`) as well when `shown` is set and *reopen last* is on (default) |
| hidden | keybind / bar widget | as above, with keyboard focus on the strip (or the page) |
| compact | click a pin P | extended(P), `shown` = P |
| extended(P) | click P again | compact, `shown` cleared (P stays loaded) |
| extended(P) | click Q | extended(Q), `shown` = Q |
| compact / extended | pointer leaves strip + card (24 px hysteresis) ≥ hide delay (400 ms), not pinned, not engaged | hidden (`shown` kept) |
| engaged | keyboard focus leaves (click elsewhere), keybind, Escape on the dock's chrome | hidden (pinned: stays) |
| any | pin toggle | `pinned` flips; pinned ignores leave; unpinned returns to the rules above |
| extended | size toggle | phone ↔ large |

Escape inside a page belongs to the page; on the strip or header it steps back (extended → compact → hidden). A drag,
resize or open menu never hides the dock. One dock at a time: it reveals on the output whose edge is hovered (keybind:
the focused output) and stays there while open (latched, like the Stage).

### Layout per edge
- **Indicator** (hidden): a 4 × 48 px pill centred on the edge, `Theme` outline colour at low contrast; off by setting
  (hover still works). Hover zone 2 px wide along the whole edge (input region only, transparent).
- **Strip** (compact): 56 px (icon 32 + padding; setting 40/48/56/64), vertical on left/right, horizontal on top/bottom.
  Pins in order (site icon from its cached favicon, else a letter tile in a token colour; a dot = loaded), a divider,
  view pins, then at the end: **pin-dock toggle**, **+ add**, **settings**. Overflow scrolls (wheel), never shrinks icons.
- **Card** (extended): next to the strip, `Theme` card style. Phone: `width` 412 px (setting 360..720) × min(2 ×
  width, output − 2 gaps), centred on the strip (left/right) or under the clicked icon (top/bottom, clamped). Large:
  `large` 90 % of the output (setting 50..95 %), full available height. **Header** (36 px): back, title (page title or
  pin name), reload, **mobile/desktop** segmented toggle (sites only), phone/large, open in browser, collapse. Body:
  the page or the view.
- Pinned + *reserve space* (setting, off): the strip claims its width as an exclusive zone; the card always overlays.

### Sites
- **Mobile view** (default for new pins: setting `default_view`): mobile user agent + phone width; **desktop view**:
  the engine's own user agent; switching reloads the page and is saved on the pin (undoable). Desktop at phone width
  shows a hint chip "Desktop pages may need the large size". Some sites ignore the user agent — the toggle says
  "view: mobile" (what was sent), not "the site is mobile".
- **Sign-in:** each pin has its own profile (cookies, storage) unless pins share a named profile ("google" for Mail +
  Calendar). Popups with an opener (sign-in windows) open as a sheet inside the card; links for a new tab or window go
  to the browser. If a site refuses sign-in in an embedded engine, the card says so and offers "open in browser" — no
  user-agent tricks (K38).
- **Permissions** (camera, microphone, location, notifications, screen, clipboard read, downloads): refused in v1; the
  header shows a chip "Blocked: camera" with the reason (I71).

### Privacy (ungoogled by configuration, K38)
QtWebEngine is Chromium's content layer with Google's services stripped (Safe Browsing, sync, translation, Google
geolocation: https://wiki.qt.io/QtWebEngine). The host turns off what is left and adopts the ungoogled-chromium
defaults that apply to an embedded engine: push service off (it would use Google's FCM), DNS prefetch off, hyperlink
auditing (`<a ping>`) off, WebRTC on public interfaces only, spell check from local dictionaries only, no Chrome
extensions in v1, Chromium switches `--disable-background-networking --disable-component-update
--disable-domain-reliability --no-pings`. **Proof, not promise:** the host test records Chromium's net log while local
fixture pages are open and fails on any request the pages did not make (Phase 0: 45 s, zero requests; the same log
records a page's own request). If that test ever sees engine traffic, an ungoogled QtWebEngine build is back on the
table (I76).

### Keyboard and a11y
Keybind `webdock.toggle` (HM default `Mod+B`; editable keybinds in Settings: I72). On reveal by key the strip takes
focus: arrows move between pins, Enter opens, Space toggles pin-dock, Escape steps back, Tab enters the card. Focus
rings for keyboard focus only (FocusRing). Every icon has an accessible name (pin title, state: "loaded", "shown").

### Motion (DESIGN-SYSTEM §9)
Strip slides from the edge (`Theme.motion` standard, 180 ms), card follows 40 ms later; collapse reverses; reduced
motion: fade only. The web card's first frame waits for the page's first paint (a skeleton until then), never a
white flash.

### Copy (i18n `mod-webdock`)
`mods.webdock.*` setting labels; `webdock.empty` "Pin a site or a view to keep it one hover away", `webdock.add.url`,
`webdock.view.mobile` / `.desktop`, `webdock.size.phone` / `.large`, `webdock.open_browser`,
`webdock.loading`, `webdock.host.starting` "Starting the web engine…", `webdock.host.missing` "The web engine is not
installed (programs.kurashi.webdock)", `webdock.error.load`, `webdock.error.crashed`, `webdock.signin_refused`,
`webdock.blocked.<permission>`, `webdock.pin.dock` / `.undock`. ja: 「モバイル表示」「デスクトップ表示」「ブラウザで開く」.

## States
- **Empty** (no pins): the strip shows only + and settings; the card shows `webdock.empty` with "Add a site" (URL +
  name).
- **Cold engine:** the first web open shows the card frame with "Starting the web engine…" (drawn by the shell) until
  the host's surface maps; a site loading: skeleton + thin progress line in the header.
- **Unloaded pin** (discarded or engine unloaded): icon without the loaded dot; opening reloads it; sign-in kept.
- **Error:** load failed (name, code, retry, open in browser); renderer crashed ("The page stopped", reload); host
  crashed (restart once, then "The web engine stopped" with the log path).
- **Offline:** the page's own offline state; the header shows a no-network chip from `svc.network`.
- **Unavailable:** host not installed (mod page says why, sites inert, view pins still work); no default browser
  ("open in browser" disabled with the reason).
- **Forced/inert** (Nix-set pins or edge): provenance chips; the strip's pin toggle disabled with the reason.
- **Many pins:** strip scrolls; 30 pins tested. **Tiny output** (≤ 768 px high): phone height clamps, large = 95 %.
- **Several outputs:** reveal per output edge, shared edges need the longer dwell; the card never spans outputs.
- **ja copy length:** header actions are icons with tooltips; the title elides.

## Fit and constraints
- **Ma:** mod off → nothing. Mod on, never used → one transparent edge surface per output (input strip + indicator,
  0 frames idle) and no daemon task; no engine process. Hidden pages are frozen (Chromium lifecycle `Frozen`) unless
  audible; the unload timer exists only while the host runs.
- **Budgets:** the shell side counts against K16/K19 (edge surface ≤ +1 MiB per output, 0 commits idle — measured).
  The web host is its own process: measured with 0, 1 and 5 sites shown (BENCH), reported, and gone after unload.
- **Daemon vs view:** the daemon owns the mode/shown/pinned state machine, pins (config), the host's lifecycle and
  "open in browser"; the shell and the host render `mod.webdock` and send intents; the host never decides modes.
- **Security:** web content is untrusted: no bridge into the shell (QWebChannel not loaded), Chromium sandbox on, the
  host's daemon connection restricted to `mod.webdock`, `theme`, `i18n` and `webdock.host.*` intents (row 92).
- **Contracts touched:** rows 88 (mod `surface:` provide), 89 (`records` setting type), 90 (`mod.webdock`), 91
  (actions), 92 (host role), 93 (capabilities), 94 (sandbox: K37 amendment for Chromium's zygote).

## Definition of done
- [ ] Every transition in the table has a daemon unit test; hover from a state machine with grace and hysteresis.
- [ ] Screenshots (sandbox, `file://` fixture sites — no network, K37): hidden indicator, compact, extended phone and
      large, mobile vs desktop (the page prints its user agent), empty, cold engine, load error, blocked chip, pinned,
      each edge (right, left, top, bottom), ja.
- [ ] Two pins keep separate storage; two pins on one named profile share it.
- [ ] Typing reaches the page on reveal by click and by keybind (first keystroke included); Escape rules as above.
- [ ] Unload: the host exits after `unload_after` (test with seconds), the icons stay, reopening reloads.
- [ ] Idle: 0 commits with the mod on and the dock hidden; host memory for 0/1/5 shown sites in BENCH.
- [ ] niri: verified in a nested niri (layer surfaces, on-demand keyboard focus) before "UX ✅".
- [ ] "Open in browser" runs the configured command (default: the system's default browser via `xdg-open`).
- [ ] Privacy: the net-log test sees no request the fixture pages did not make; push service off.

## Implementation steps (each step's report carries a Learn block: concept, minimal example, one exercise)
1. **Contract + records setting** (rows 88–93): `records` type in kurashi-mods/config, Settings records editor, Nix
   pins. *Accept:* a bad URL in `mods.webdock.pins` is refused with its field path; Settings adds, edits, reorders,
   removes a pin; a Nix-set list shows as forced.
2. **Daemon mod** `crates/kurashi-mod-webdock`: state machine, `mod.webdock`, actions, host supervisor (start, restricted
   hello, unload, restart once). *Accept:* transition tests; fake host started/stopped; 0 tasks while hidden.
3. **Shell side** `mods/webdock/qml`: edge surface, indicator, strip, card frame, view pins, keyboard. *Accept:* the
   screenshot list above for views; idle 0 commits; PSS per output.
4. **Web host** `webdock-host/` + `nix/patches/quickshell-webengine.patch`: views per pin, profiles, user agents,
   freeze, sheets, permission chips, new tabs → browser, privacy settings. *Accept:* fixture sites, typing, storage
   separation, net-log privacy test, memory.
5. **Nix:** `packages.kurashi-webdock` (patched Quickshell + QtWebEngine) apart from `kurashi` (no QtWebEngine in the
   base closure), HM/NixOS `programs.kurashi.webdock.{enable,pins}`. *Accept:* closure check, module eval.
6. **Docs + UX review:** MODS.md, PROTOCOL, BENCH, this brief → "done (UX)".

## Later
Browse/search section and "pin this page" (I69); browser bookmarks + extension bridge (I70); permissions allowlist,
web notifications, downloads (I71); editable keybinds (I72); badges, launcher provider, web media (I73); drag-resize
and per-pin width (I74); hybrid pins in the browser's own window (I75); an ungoogled QtWebEngine build only if the
privacy test finds traffic (I76); several docks (ROADMAP "multi-instance").
