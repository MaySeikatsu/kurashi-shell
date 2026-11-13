# Right-click menus everywhere — UX brief (session 33, card W82)
Status: v1. Test `frontend/test-context-menus.sh` (desktop, bar background, keyboard; nested niri for the look),
`mods/webdock/test/test-page-menu.sh` (the web page), `frontend/test-module-menu.sh` (a module's menu, unchanged).
Extends `docs/ux/module-menu.md` (I408): that brief stays the authority for a module's rows.

## Job
The user (session 33): "if the right click menu gets implemented it should be prepared to work everywhere, like on the
desktop for wallpaper and related toggles/settings, on bar for bar related settings, on module background for related
settings etc." — and the web dock's pages show no menu at all. One right click, anywhere the shell draws, gives the
options of the thing under the pointer, in one look and one keyboard path.

## How others do it
- **GNOME**: the desktop (Desktop Icons NG) — New Folder, Paste, Change Background…, Display Settings, Settings; the top
  bar has none. GTK 4 context menus are popovers at the pointer; Menu and Shift+F10 open them at the focus.
- **KDE Plasma**: the desktop — Add Widgets…, Enter Edit Mode, Configure Desktop and Wallpaper…, Next Wallpaper Image (a
  slideshow), Lock, Leave; an empty part of a panel — Add Widgets…, Add Spacer, Show Panel Configuration; a widget —
  Configure <widget>…. Every menu ends in "Configure …", the dialog of that thing.
- **COSMIC**: the desktop (cosmic-files) — New Folder, Change Wallpaper…, Display Settings…, Desktop View Options; panel
  applets carry their own popups, the panel's options live in Settings.
- **macOS**: the desktop — New Folder, Change Wallpaper…, Edit Widgets…, Use Stacks, Sort By ›, Show View Options; the
  Dock's divider — Turn Hiding On, Magnification, Position on Screen ›, Dock Settings…: options change in place, and the
  last row leaves for Settings. The model for the bar's menu.
- **Windows 11**: the desktop — View ›, Sort by ›, Refresh, New ›, Display settings, Personalize; the taskbar's empty part —
  Task Manager, Taskbar settings.
- **Quickshell shells** (Caelestia, end-4, DankMaterialShell, Noctalia): per-widget menus on the bar (a tray item's, a
  widget's settings); the desktop is left to the wallpaper tool. Kurashi goes further: the desktop and the bar's empty
  part answer too.
- **Browsers** (a page): Back, Forward, Reload; a link — Open link in new tab / window, Copy link address; an image — Copy
  image, Copy image address; a selection — Copy, Search for…; a text field — Undo, Cut, Copy, Paste, Select all. A page
  that handles `contextmenu` itself (a map, an editor) shows its own menu and the browser's stays away.

## Model: a target, a provider, one drawer
- **Target**: what was right-clicked, a string.

  | Target | Where | Drawn by |
  |---|---|---|
  | `module:<id>` | a bar module, an edge group's module (I408, unchanged) | the Stage's `tray` panel |
  | `desktop` · `desktop:<output>` | the wallpaper, the desktop widgets | the Stage's `tray` panel, at the pointer |
  | `bar:<output>/<edge>` | an empty part of a bar | the Stage's `tray` panel, at the pointer |
  | `page:<pin>` | a web dock page (edge card, bar card, sidebar) | the web host (its own process), at the pointer |

  The first three ride `runtime.ui.tray` through `tray.menu.open {id}` — the id is opaque to the daemon, so one panel at
  a time, the same toggle (the same target again closes it), click-away and Esc hold with no new daemon state
  (CONTRACT-CHANGE row 780 records the scheme). `page:<pin>` never leaves the host: the request, the page's actions
  (`triggerWebAction`) and the pointer all live in the `qs-webengine` process.
- **Provider**: turns a target into rows, `frontend/components/menus/`: `ModuleMenu` (a module), `DesktopMenu`, `BarMenu`,
  and the host's `PageMenu`. Shared code in `menus/rows.js`: a schema row → a menu entry (toggle → check mark; choice →
  submenu of radio rows; range → submenu of steps, the value in effect among them; a list to pick from → check marks), the
  inert reason, the output's own entry, choosing (`{key, value}` set, `{action, args}` sent, `{ops}` applied, `{open}`
  Settings). Nothing lists keys by hand (rule 3): a provider names the schema's own groupings.
- **Drawer**: `TrayMenu` everywhere — the same card, rows, marks, keys and look (`MenuStyle`, `MenuRowFace`); the host
  links the same files.

## Rows per place
- **Desktop** (`DesktopMenu`):
  1. Wallpaper, while the wallpaper mod is on: *Next wallpaper* (`wallpaper.next {output}`), *Choose wallpaper…* (its
     picker, `mod.panel.open`). Mod off: no rows (never a row that does nothing).
  2. *Dark mode* — a check mark that shows the scheme in effect (`theme.appearance`), a press writes
     `theme.colors.scheme` dark or light (as the darkmode module does). The scheme's other modes (follow the system, the
     wallpaper) stay in Settings › Appearance.
  3. The desktop page's rows (`page = "desktop"` in the schema: widgets on this output, their side, how they are posted,
     each card's switch); the rows another one holds stay grey with the reason (Shōjiki).
  4. *Desktop settings…* (`settings.open {page: desktop}`), *Appearance…* (`settings.open {page: appearance}`).
  "Display settings…" is not offered: outputs are the compositor's (niri), kurashi has no such page — a row there
  would lead nowhere.
- **Bar background** (`BarMenu`): the edge's own rows (`edges.<edge>.*`: the bar, visibility, keep space, draw mode — the
  module lists stay in Settings), then the bar's (`bar.*`: thickness, cards open, on hover, cards follow the pointer, the
  card limits; the per-module lists stay in Settings), every `per_output` row on this output's entry where it has one;
  *Edit layout…* (`settings.open {page: layout}`, where the zones and groups are dragged, W80). Moving a bar to another
  edge is the layout page's job (its lists), not a row here.
- **Web page** (`PageMenu`), from what the request offers:
  - always: *Back*, *Forward* (grey when there is no history that way), *Reload*;
  - a link: *Open link in browser* (`webdock.open_external`, as the card's own button), *Copy link*;
  - an image: *Copy image address*;
  - a selection: *Copy*; a text field: *Cut*, *Copy*, *Paste*, *Select all* (grey where the engine says it cannot);
  - last: *Open page in browser*. The browser takes web addresses only (K38): for a `file:` page or link the browser rows
    are grey and one line says "Web addresses only".
  The page's own menu wins: a page that calls `preventDefault()` on `contextmenu` raises no request.

## Placement and outputs
- `module:` — as I408: out of its module (under a top or bottom bar, beside a side one).
- `desktop`, `bar:` — at the pointer: the card's corner at the press, turned left or up where it would leave the output,
  kept clear of the bars and the frame (the Stage's `placed` path, as a mod panel's `panel_place`). On the output that was
  pressed (`IslandGeom.notePress`); opened by key (no press in the last 1.5 s): centred on the focused output.
- `page:` — at the pointer inside the page's window, turned and kept inside it.

## States
- **Inert** (rule 2): a row another setting holds stays visible and grey, with one line saying what it needs (I408's).
- **Forced**: a row a layer above the user holds (`_managed.enforce`, a Nix value) is grey with "forced: <who>" under it.
- **Empty**: the desktop's and a bar's menus always have rows (Dark mode; the edge's own); a module without options says
  "No options of its own" (I408). A page's menu always has Back, Forward, Reload.
- **Loading**: until the schema document arrives (the first frames of the first open) the fixed rows stand alone; the
  schema's rows follow and the card grows in place.
- **Error**: an action refused (the daemon's answer) shows nothing new — the document is the truth and the row keeps
  showing the value in effect.
- **Offline / daemon gone**: the daemon names the open menu, so without it no desktop, bar or module menu opens (as no
  card does); the page menu's navigation and clipboard rows work without it, *Open … in browser* needs it.

## Keyboard and a11y
- **Open**: a module — the Menu key on its tab stop (I408). A web page — the Menu key or Shift+F10 in the page (Chromium
  raises the same request, at the focus). Desktop and bar have no tab stop (I67): the action opens them,
  `kurashi act tray.menu.open '{"id":"desktop"}'` or `{"id":"bar:<output>/<edge>"}`, bindable in the compositor; centred
  then (above).
- **In the menu**: TrayMenu's path — Up/Down (Tab/Shift+Tab) over the rows that can be chosen, Right/Left open and close a
  submenu, Enter chooses, Esc closes. A menu opened at the pointer holds the keyboard at once (no click first).
- **Names**: rows are `MenuItem`s, checkable where they check; the card's title names the target ("Desktop", "Bar",
  the page's title).

## Motion
No new motion: the Stage's card reveal (its form for a placed card), cut with reduced motion; the host's menu fades with
`Theme`'s short duration, none with reduced motion. A change applies at once and the menu stays for the next one;
Settings rows and page actions close it.

## Budget (Ma)
- Closed: nothing watched, nothing drawn. The providers watch `schema.settings` (and `mods`, `theme` for the desktop) only
  while their menu is open.
- The desktop needs a surface under the pointer where the wallpaper is (the wallpaper is awww's, swww's or swaybg's,
  and takes no input): one empty background-layer window per output (`menus/DeskCatch.qml`). Measured (session 33, nested
  niri, 1920×1080, live toggle in one shell, 4 pairs): **+4.8 / +3.9 / +4.7 / +5.3 MiB PSS per output** — inside BENCH's
  +6 MiB per extra output, but most of it; **0 commits in 15 s idle** (WAYLAND_DEBUG, its surface). A fresh-start pair
  read +15 MiB (two full-output buffers): the method BENCH warns about. Under the desktop widgets (bottom layer) and over
  the wallpaper; swaybg mapped after it on niri still lets the click through.
- The host's menu exists only while it is open (a Loader).

## Fit
- **Island / Stage**: the desktop and bar menus are Stage panels, so a menu replaces any open card and the island's pill
  stays put.
- **Quick settings / Settings**: every menu ends in the Settings page of its target; rows are the schema's, so Settings
  and the menu never disagree.
- **Web dock**: the page menu is inside the page's window, so it follows the page into the edge card, the bar card and the
  sidebar, and the strip's pin menu (W76) stays the pin's.

## Definition of done
- [x] One system: targets → providers → TrayMenu; the module menu runs on it and `test-module-menu.sh` passes.
- [x] Desktop: a right click on the wallpaper opens its menu at the pointer on that output; a toggle applies and the menu
      stays; wallpaper rows only while the mod is on (the rows not seen with the mod on: no awww in the sandbox).
- [x] Bar: a right click on an empty part opens the bar's menu at the pointer; a right click on a module still opens the
      module's.
- [x] Web page: the menu at the pointer with the request's rows; Copy link copies (pasted back into a field); Back works;
      the page's own menu wins; edge card, bar card and sidebar.
- [x] Keyboard: arrows, Enter, Esc work right after a right click (sway and niri); the action opens desktop and bar menus
      without a pointer. [ ] The page's Menu key / Shift+F10: Chromium's own path, not driven (the test keyboard has no
      such key).
- [x] States: inert and forced rows say why; loading; shots light and dark. [ ] Several outputs: not run (one output
      in the sandboxes).
- [x] Seen on nested niri (desktop light and dark, bar); the suites in the merge set.

## Later
- A compositor binding for the desktop menu in the default keys (`keys.toml`) once the lead decides the chord.
- Desktop "Edit widgets…" (the desk's edit mode, K48) as a row.
- A right click elsewhere while a menu is open closes it (the click-away layer, I279) rather than moving it there.
- A marker for the bar's and the desktop's menu rows if the namespace selection proves too long (CONTRACT-CHANGE 781).
- Window menus on the window list stay their own (I408).
