# W82 — Right-click menus everywhere: one system, the web page first (session 33; Opus)

**Base.** `main` (after #60). Branch from `origin/main`.
**The user (session 33):** "the webdock doesn't support the right click menu yet (if the right click menu gets implemented
it should be prepared to work everywhere), like on the desktop for wallpaper and related toggles/settings, on bar for bar
related settings, on module background for related settings etc."
**Today.** A bar module's right click opens its own menu (I408, `docs/ux/module-menu.md`, `frontend/components/ModuleMenu.qml`:
the schema's `#[kurashi(module = …)]` keys as a tree that `TrayMenu` draws on the Stage's `tray` panel, `runtime.ui.tray =
module:<id>`). Nothing else has one; the web dock's pages (QtWebEngine in `mods/webdock/host/`) show no menu at all.
**Goal.** One context-menu system the whole shell uses, then its first places:
1. **UX brief first** `docs/ux/context-menus.md`: how GNOME, KDE Plasma, COSMIC, macOS, Windows, Caelestia/end-4/DMS/
   Noctalia do desktop, panel and in-app menus; the model (a *target* → a provider that lists rows: actions, toggles from
   the schema, choices, separators, "Settings › …" leaves; one look and keyboard path, TrayMenu's); placement at the pointer
   and on the right output; states (inert rows with the reason, Shōjiki; forced; empty); keyboard (Menu key / Shift+F10,
   arrows, Esc) and a11y names; motion; Ma (nothing watched while closed); multi-output.
2. **Generalise** the module menu into that system (targets `module:<id>` stays as it is; add `desktop`, `bar:<output>/<edge>`,
   `page:<pin>` …). Prefer reusing `runtime.ui.tray` targets and TrayMenu over a new surface; a new target scheme or
   action is a CONTRACT-CHANGE row (lead decides).
3. **Web page menu** (the host): QtWebEngine's `contextMenuRequested` → the shell's menu with what the request offers:
   Back, Forward, Reload; Copy / Cut / Paste / Select all for editable or selected text; for a link: Open in the system
   browser (`webdock.open_external`), Copy link; for an image: Copy image address; "Open page in browser". The page's own
   menu (a site that handles `contextmenu`) wins as in a browser. Works in the edge card, the bar card and the sidebar.
4. **Desktop menu** (right click on the wallpaper, `frontend/surfaces/Desktop.qml`): next wallpaper / open the wallpaper
   picker (the wallpaper mod's actions if on), dark mode toggle, the desktop's own toggles from the schema, "Desktop
   settings…", "Display settings…".
5. **Bar background menu** (right click on an empty part of a bar): the bar's own settings from the schema (position,
   floating, the modules' layout "Edit layout…" → Settings › Layout), as the module menu lists a module's.
**Owned paths.** `frontend/components/ModuleMenu.qml`, `frontend/components/TrayMenu.qml`, new `frontend/components/menus/**`,
`frontend/surfaces/Desktop.qml`, `frontend/surfaces/Bar.qml` (only the background's right click), `frontend/surfaces/Stage.qml`
(only the menu panel), `mods/webdock/host/**`, `docs/ux/context-menus.md`, i18n domains you touch. Schema: if bar/desktop
keys need a `#[kurashi(menu = …)]`-style marker, a CONTRACT-CHANGE row first (rule 3: no hand list of keys).
**Acceptance.** A suite (e.g. `frontend/test-context-menus.sh`, nested niri where it shows something sway does not): a right
click on the desktop opens its menu at the pointer on that output, a toggle in it applies; a right click on the bar's
background opens the bar menu; the module menu still passes `frontend/test-module-menu.sh`; a web page's right click
(`mods/webdock/test/` with a file:// page, offline) shows the menu, Copy link copies, Back works; keyboard path; shots
light and dark. Add the new suite to the merge set (`tools/test-suites.sh`).
**Build dir** `~/.cache/kurashi-agents-target/w82`. Report when done or when blocked; terse.
