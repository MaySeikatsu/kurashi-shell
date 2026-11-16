# Backlog, sorted into batches

<<<<<<< HEAD
Every open row of `docs/BACKLOG.md` (467 on 2026-11-16), each in exactly one batch: rows that share files, a
||||||| 05c9da09
Every open row of `docs/BACKLOG.md` (469 on 2026-11-16), each in exactly one batch: rows that share files, a
=======
Every open row of `docs/BACKLOG.md` (464 on 2026-11-16), each in exactly one batch: rows that share files, a
>>>>>>> feat/s36-polish
design decision or a review round, so that they are cheaper done together. The backlog stays the source: a row's
full text and status are there; this file only groups the ids. `U` marks a row that came from the user. A row
that is closed stays in its batch, marked done. Sizes are the lead's guess at its own working time, not measured
(S: under an hour of edits, builds and suite runs; M: one to three hours; L: longer, or a brief first).

Written by `python3 tools/backlog-batches.py .`, which holds the batches and fails when an open row is in no
batch or in two: give a new row its batch there, then run it again.

| Section | Batch | Done | Size |
|---|---|---|---|
| 1 | Launcher, small | 2 of 3 | S |
<<<<<<< HEAD
| 1 | Web dock in the bar | 1 of 9 | S–M |
| 1 | Settings, fixes | 0 of 9 | S–M |
||||||| 05c9da09
| 1 | Web dock in the bar | 0 of 9 | S–M |
| 1 | Settings, fixes | 0 of 9 | S–M |
=======
| 1 | Web dock in the bar | 0 of 9 | S–M |
| 1 | Settings, fixes | 5 of 9 | S–M |
>>>>>>> feat/s36-polish
| 1 | Mods page and Mod Editor | 0 of 7 | S–M |
| 1 | Quick settings, small | 7 of 9 | S–M |
| 1 | Wallpaper picker | 0 of 5 | S–M |
| 1 | Icons and glyph sizes | 2 of 5 | M |
| 1 | Media, small | 1 of 3 | S–M |
| 2 | Settings, structure | 0 of 10 | M–L |
| 2 | Settings, theming pages | 0 of 7 | M |
| 2 | Settings docked in a sidebar | 0 of 3 | M |
| 2 | Applying a style | 0 of 3 | M |
| 2 | Bars and layout | 0 of 13 | M–L |
| 2 | Sidebars | 0 of 7 | M |
| 2 | Edit mode and groups | 0 of 6 | L |
| 2 | Peeks | 0 of 6 | M |
| 2 | Island | 0 of 6 | M–L |
| 2 | Cards and scrolling | 1 of 6 | M |
| 2 | Notifications | 0 of 2 | M–L |
| 2 | Desk | 0 of 2 | S–M |
| 2 | Lock and greeter | 0 of 3 | M |
| 2 | Web dock, card and host | 0 of 17 | M–L |
| 2 | Bundled mods, follow-ups | 0 of 13 | M |
| 2 | Fonts and handwriting | 0 of 5 | M |
| 3 | Audio control | 0 of 3 | M–L |
| 3 | Quiet time | 0 of 3 | L |
| 3 | niri config from Settings | 0 of 3 | L |
| 3 | Windows and previews | 0 of 4 | M–L |
| 3 | One search and quick capture | 0 of 2 | L |
| 3 | AI mod | 0 of 2 | L |
| 3 | Any module on any surface | 0 of 12 | L |
| 3 | Module variants (K72) | 0 of 7 | L |
| 3 | Web dock, engine | 0 of 10 | L |
| 3 | Mod catalogue | 0 of 3 | L |
| 3 | Gestures | 0 of 2 | L |
| 3 | Standalone features | 0 of 5 | L each |
| 4 | Looks and chrome, fixes | 0 of 16 | M–L |
| 4 | Style families | 0 of 8 | L |
| 4 | Joins | 0 of 4 | M–L |
| 4 | Frame | 0 of 5 | M |
| 4 | Motion, fixes | 0 of 23 | M–L |
| 4 | Motion, new | 0 of 7 | L |
| 4 | Text effects | 0 of 4 | L |
| 4 | Light, texture and effects | 0 of 11 | L |
| 4 | Wallpaper, ideas | 0 of 3 | L |
| 4 | Theme in other apps and compositors | 0 of 12 | M–L |
| 5 | Memory and performance | 0 of 34 | L |
| 5 | Structure: the core and the mods | 0 of 15 | L |
| 5 | Mod API additions | 0 of 10 | M |
| 5 | Daemon, schema, adapters | 0 of 11 | M |
| 5 | Suites and test tools | 0 of 71 | L |
| 5 | Mock parity | 0 of 3 | S |
| 5 | Nix | 0 of 3 | S |
| 5 | Docs and process | 0 of 6 | S–M |
| 6 | Rows whose status is behind | 0 of 17 | S |
| 6 | Review with you | 0 of 3 | — |

## 1. Quick polish (hours to a day each, user-facing)

### Launcher, small

Shares: the launcher's prefix handling and its rows; one suite, one niri look. Also the inbox line `> note <text>` (tasks; no row). Size: S. Needs you: —.

| Row | | What |
|---|---|---|
| I539 | U | **done** — With the terminal mod off (not enabled in Home-Manager), `!` in the launcher silently searches apps. It should say the … |
| I572 |  | **done** — A `>` command that needs words shows nothing until they are typed (`> task` alone lists no row). A hint row ("Add task … |
| I138 |  | Launcher: a `launcher.keys` bind in `docs/niri-binds.kdl` and HM defaults; mock parity for the new actions; paste after … |

### Web dock in the bar

Shares: the dock's bar widget and the mod's `[[menu]]` rows; the five suite rows are one failure (a click on the widget does not ask for the card). Size: S–M. Needs you: I600: one module per pinned site, or one module listing them.

| Row | | What |
|---|---|---|
| I599 | U | **done** — Web dock: a site's icon has no right-click menu: refresh, unload, pin the page it shows now, and so on (the shell's one … |
| I600 | U | Web dock: a site pinned to the bar as an icon that opens the page or the dock from there (a module per pinned site, or … |
| I69 | U | Web dock: a browse/search section to find sites, and "pin this page" while on a site (not required for v1). |
| I73 |  | Web dock composition: pins as a launcher provider; unread count from a page title as a badge and an Island signal; a … |
| B131 |  | `mods/webdock/test/test-dock.sh` "bar widget: a click asks for the dock's card (mod.panel.open)" fails on the session … |
| B123 |  | `mods/webdock/test/test-dock.sh`: "bar widget: a click asks for the dock's card" fails on the base too; its growth … |
| B69 |  | `mods/webdock/test/test-dock.sh`: "bar widget: a click sends webdock.toggle for the output the bar is on" fails on … |
| I403 |  | webdock `test-dock`: the bar widget is not in the bar during the "bar widget: a click sends webdock.toggle" step (shot … |
| I434 |  | `mods/webdock/test/test-dock.sh` (outside the merge set) fails, on `main` and on 31686f73 before session 24: "bar … |

### Settings, fixes

Shares: the Settings app's own code (search, reconnect, the sheet host, `Label`); one screenshot round. Size: S–M. Needs you: —.

| Row | | What |
|---|---|---|
| I597 | U | **done** — Settings' search is slow and stutters, the typing above all; and it jumps to one matching entry instead of showing and … |
| I334 | U | **done** — The Settings window does not reconnect when kurashid restarts: it keeps "Daemon not reachable: showing the last known … |
| I361 |  | **done** — `SettingsPages.qml:300` TypeError "Property 'flash' of FormPicker is not a function" when a search/keyboard jump lands … |
| I352 |  | Settings' sheet host: the sidebar's Mods and Profiles entries spill below the sheet (the shared host, not the Motion … |
| I351 |  | **done** — Under reduce motion (or a profile that does not move) every motion row is inert, so a motion setting the user changed … |
| I601 |  | **done** — Settings › Power › Location, the rest: the section shows the switch and two sliders, not the place in effect — add a … |
| I589 |  | 65 `Text` blocks in `settings/components` are not on `Label`: 27 lack the hinting line (`ColorPicker`, … |
| I81 |  | Records editor follow-ups: Alt+Up/Down, Delete, Up/Down between rows and Enter-to-edit are wired but unverified (an … |
| B59 |  | Settings run from the worktree (`kurashi-settings-s26`) averaged 5.4 % CPU over almost 3 hours while it should idle. … |

### Mods page and Mod Editor

Shares: the Mods page and the `mods` document (one contract change for I605 and I593). Size: S–M. Needs you: —.

| Row | | What |
|---|---|---|
| I604 |  | The skip error names no variant. `kurashi_mods::editor::error_key` keeps only the text before the colon, so … |
| I605 |  | The `mods` document carries no folder path. The Mod Editor's "Open the folder" and a folder line on the Mods page need … |
| I593 |  | Host programs: what the design names and W93 did not build. (1) The Mods page asks once before the first enable of a … |
| I592 |  | A mod that waits for a required use (`mods.uses.missing`, K158) has not been seen on niri: no bundled mod requires … |
| I575 |  | An action a mod registers and does not declare is only logged at enable. The static list of the bundled mods' actions … |
| I215 |  | Island faces follow-ups 2: mod face labels in Settings' faces offers are the manifest name in English under ja … |
| I195 |  | Mods outside the repo cannot ship their own strings (desk titles `mod-<id>.desk.<name>`, any `mod-<id>` key): decide … |

### Quick settings, small

Shares: the quick card and the control modules. Size: S–M. Needs you: —.

| Row | | What |
|---|---|---|
| I586 |  | **done** — `frontend/components/quick/QuickTile.qml`'s compact label is a `Text` without the look's render block, so in pixel … |
| I204 |  | Quick settings follow-ups: the accent badge on its on-state container is 2.39:1 in dark wa-iro (3.16 light), below 3:1 … |
| I108 |  | **done** — Quick settings greeting row: a user-name source (only `$USER`'s first letter today) and an avatar (AccountsService … |
| B71 |  | **done** — `modules/Volume.qml`'s WheelHandler has no `acceptedDevices` (the control modules needed `Mouse \/ TouchPad` to hear … |
| B72 |  | **done** — `Stage.qml` `ownKey`: the quick card comes out under any module pressed in the last 1.5 s, not only a control module; … |
| B73 |  | **done** — Control centre loose ends: `PhoneFrame` is still instantiated (invisible) in card style (Ma: should be a Loader); an … |
| B75 |  | **done** — `docs/ux/control-centre-modules.md` "Others": written from memory, no other shell was looked up (GNOME quick settings, … |
| I484 |  | Controls, round two. A parts-sheet row for every slider and switch face in every state (I326); vertical faces drawn for … |
| I326 |  | **done** — Sliders never seen in shots: the sandbox has no audio or brightness, so `slider/Fluent`, `slider/Classic` and the … |

### Wallpaper picker

Shares: the picker's card (I538 and I83 are the same wish: more room for the pictures). Size: S–M. Needs you: —.

| Row | | What |
|---|---|---|
| I538 | U | The Wallpaper & Theming menu's wallpaper selection needs more space for the pictures (a larger grid / bigger … |
| I83 |  | Wallpaper picker: the card is 360 px with two thumbnail columns although mod panels may ask for up to 720 px (row 66, … |
| I32 |  | Wallpaper not yet to brief: keyboard grid/search not exercised, grow origin from tile, drag-and-drop, folder … |
| I135 |  | Wallpaper picker shows "Theme not applied yet (no source)" after applying with theme in the sandbox (also in the … |
| B88 | U | The wallpaper is a little behind the shell in a change of colour (its grade and material are recoloured by their own … |

### Icons and glyph sizes

Shares: `Icon.qml` and the bar's glyph metrics. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| B61 | U | Bar glyphs are not one size: on the user's bar they run from 12 to 20 px tall (tray icons most), two sit 1.5 to 2 px … |
| B52 |  | **done** — Island faces other than media keep their own sizes (notifications at fs+4, the media pause icon at fs+3) and are not … |
| B62 |  | Icon tint (K110, session 27 rework), not seen: a notification's app icon (a test notification gave no popup in the … |
| B70 |  | **done** — `QML Icon at components/modules/ControlModule.qml: Binding loop detected for property "drawFamily"` when the look … |
| I214 |  | Icon follow-ups: the fallback tier is measured, not known — a name of one letter, or a family whose missing-glyph is … |

### Media, small

Shares: the media face and Dynamic Media Color. Size: S–M. Needs you: I398: which option.

| Row | | What |
|---|---|---|
| I133 |  | Media: a config key for fetching http covers (env `KURASHI_MEDIA_ART_FETCH=0` today); `art_colors` and … |
| I398 | U | **done** — An option for the Now Playing card under Dynamic Media Color (K87): today it keeps its own cover colours and changes at … |
| B89 |  | After K125: Dynamic Media Color's wheel blends (`media.blend = wheel_*`) still step every colour in JS and will stutter … |

## 2. Passes over one area (one to a few days each)

### Settings, structure

Shares: the pages' order and sections; I474 and I151 belong here because the Sidebar page and the sidebar's toggles change together. Size: M–L. Needs you: design questions up front (I595, I596, I598 are your reports).

| Row | | What |
|---|---|---|
| I595 | U | Settings › Sidebar is a mess: "some options don't make sense as they are right now, mainly 'the quick settings opens … |
| I596 | U | Settings' menu, sorted again: a better overview in the sidebar's list, and the advanced options behind "Advanced" so … |
| I598 | U | Settings › Layout is a mess: "options are partially duplicated and not visually clear. Needs a major overhaul with … |
| I464 | U | Settings: sub-sections, and a place for every option. Appearance is very long. The sidebar keeps Appearance; a click … |
| I479 | U | Settings sections: decided (`docs/ux/settings-sections.md`). (1) Try scroll resistance: a click shows the section … |
| I104 |  | Settings app: section cards (rows grouped in blocks), a live preview of the chrome/decor choice, icons per row type; … |
| I573 |  | The Settings sidebar shows no icon for a mod's page (its state mark stands there, K25); the manifest's icon shows on … |
| I251 |  | Settings › Layout states not shot: several outputs with different layouts, side-edge bars, a mod switched off while in … |
| I474 |  | The sidebar and the control modules. `sidebar.sections` has its own vocabulary and … |
| I151 |  | Extract the quick tiles' values/requests into a shared `components/quick/QuickState.qml` for the quick card and the … |

### Settings, theming pages

Shares: the palette, profile and recipe lists in Settings. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I147 |  | Palettes have no category (Settings shows them flat) and no light/dark hint; group them (by family or by the styles … |
| I153 |  | Settings keeps two display maps naming keys (`packCompanions`: scheme with palette; `Store.styleRecommends`: scheme) … |
| I335 |  | Idea: "Save profile" could leave the appearance keys out (or ask), since a style now releases them anyway; Settings' … |
| I359 |  | A user pack holding only recipes or curves shows in the profile gallery as a profile (expressive-equivalent); the "Save … |
| I360 |  | A duplicate recipe id's diagnostic reaches only the theme notes, not Settings' recipe list. |
| I343 |  | The Settings preview of elevation draws one card; with K82 the sheet, the bars, the desk cards, blocks and icons cast … |
| I369 |  | Settings hint for targets with no include line: Vesktop (enable in Vencord → Themes), Obsidian (link the file into a … |

### Settings docked in a sidebar

Shares: the dock's focus and watching of the Settings process. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| B127 |  | Settings docked in a sidebar, open: a hover-opened sidebar closes when the pointer rests on the docked Settings (it … |
| B129 |  | An on-demand layer cannot keep a keyboard it was handed. Tried: `settings.dock_focus` raising `runtime.settings.focus`, … |
| B130 |  | Settings dock, after W79: a Settings process found through the `current` probe (started by hand, or alive across a … |

### Applying a style

Shares: how a style, a profile's own theme entries and run-time packs layer (I280 is your report: "picking a style does nothing"). Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I280 | U | "Picking a style does nothing." Reproduced with the user's config + active profile `default-v1` (sandbox): … |
| I146 |  | A loaded profile's own `theme.*` entries (profile layer) beat the theme layer, and `theme.style.apply` resets only user … |
| I294 |  | Looks, styles, palettes at run time: kurashi-theme embeds `looks/`, `styles/`, `palettes/` with include_str! (and … |

### Bars and layout

Shares: the layout document, zones and holders, side bars. Size: M–L. Needs you: —.

| Row | | What |
|---|---|---|
| I85 |  | Side bars: the bar widgets keep their horizontal layout on a vertical bar — sysmon's "CPU % · RAM" overflows the ~32 px … |
| I221 |  | Several bars on one edge; a bar thickness per edge (K71 keeps one `bar.height`). |
| I250 |  | A hidden bar brought out by key: "a click elsewhere" closes it only once it has had focus; keyboard focus on map is not … |
| I266 |  | The non-morph tray menu beside a side bar still hangs from BarConfig's bar; the frame band's rule arcs under a joined … |
| B51 |  | Side bars: no full allocation of a column; a start zone of fixed modules taller than half the bar can still reach the … |
| B97 |  | `bar.popups_follow`: the launcher and the notification centre do not follow, and neither do the mods' own cards … |
| B121 |  | The bar's layer namespace is Quickshell's default (`quickshell`); `kurashi-bar` would let niri layer rules and suites … |
| B139 |  | The terminal's bar widget measures an elided label by its `implicitWidth` (0 there), so the bar fit's rounded-down room … |
| I237 |  | Fullscreen state per output (`svc.workspaces`, the adapters) folded into `runtime.layout` (band 0, holder none) so the … |
| I240 |  | `layout.toggle` without `output` reads the focused output from svc.workspaces; use main's `FocusedOutputFn`. `actions` … |
| I264 |  | `holder: module` — the frontend picks the first non-empty zone's group as the zone holder; the daemon could name it. … |
| I265 |  | The web dock's DockWindow is a second zone holder on its edge; `modules/Island.qml` `where()` is 8 px off under a … |
| I271 |  | A top edge with module groups (no bar) and a docked left/right bar: the side bar's window is placed inside the top … |

### Sidebars

Shares: the sidebar's window and sections. Size: M. Needs you: I607: a brief for top and bottom sidebars; I465: how a hover-opened sidebar closes.

| Row | | What |
|---|---|---|
| I607 | U | Sidebars on the top and bottom edges, with size options: the full width, or a centred part of it (about two thirds of … |
| I500 | U | Sidebars: width per output (a resize on one monitor leaves the other); tabs in one clean row (no wrapping); a "+" to … |
| I152 |  | Sidebar: click outside to close (niri has no layer-surface focus grab); measure 20 open/close cycles for USS growth … |
| I465 |  | Open on hover: the sidebar buttons stay click only, because a sidebar is not closed by `ui.close` and a hover-opened … |
| I150 |  | Sidebar header uptime (a daemon value, e.g. `svc.session.boot_ms`) and a mic slider (`audio.source.volume` intent). |
| I149 |  | `wiring::ui` should get the adapter's focused output so `sidebar.toggle` from a key stores `sidebar_output` … |
| I255 | U | Optional setting: a floating bar shortens on its side while a sidebar is out (the bar's inset there grows by the … |

### Edit mode and groups

Shares: dragging things into place on the screen: modules, desk cards, groups. Size: L. Needs you: a UX brief first (I220).

| Row | | What |
|---|---|---|
| I220 | U | Redesign edit mode (SekaiPop `assets/shot-edit-desktop.png`): rearrange modules on bars, edges and the desk by dragging … |
| I222 | U | Desk cards placed freely (not only in the left/right columns), once the redesign mode exists (I220). |
| I101 |  | Desktop widgets v2: drag to place and resize (SekaiPop "Edit Desktop"), to-do and notes cards (needs a daemon … |
| I502 | U | Groups on the bar and in sidebars: named groups (a list entry `group:<id>` with members and options such as an … |
| I508 | U | Groups round two (I502): asked where the drag happens, the user found both "the list in Settings, a drop joins, group … |
| B74 |  | Control modules, not covered by a suite: drag re-sort in the centre's edit mode (the virtual pointer has no … |

### Peeks

Shares: the Stage's peek sources (`ui.peek`); I257 and I602 are the same clock peek. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I67 |  | Peek follow-ups: side bars (ui.peek carries x only — add y/edge); the bar surface never takes keyboard focus, so focus … |
| I602 |  | The clock's peek, served, with the mods' lines: `ClockPeek.qml` was never shown (`Clock.qml` `peekServed: false`: … |
| I257 |  | The clock's own peek (`ClockPeek.qml`: day, ISO week, next agenda item, nearest timer) is built but not served: … |
| I258 |  | Edge modules: the peek overlaps a framed or floating group (the peek needs its host's clearance); the dock and an edge … |
| I466 |  | Peeks beside a side bar still float (the look's balloon or a card): the join of K113 is for top and bottom bars. |
| I47 |  | Island peek as a Stage-hosted tooltip (B9) instead of the inline tail; screenshots for locked redaction, no-seek track, … |

### Island

Shares: the island's surface, faces and card. Size: M–L. Needs you: I1: the model.

| Row | | What |
|---|---|---|
| I1 | U | Island model, three levels (see "Island" below): island *placements* (a bar module as today, or a standalone island … |
| I112 |  | Satellites: OSD bubbles beside the island (Capsule `satellite/`) instead of widening the pill. |
| I113 |  | Squash and stretch mid-morph (Capsule option), behind `springOn`; a rounded mini-art crop in the media pill. |
| I212 |  | Island faces follow-ups: a card open on a face the list drops stays open (row 451); a list that names only mods that … |
| I256 |  | The island card does not grow out of the standalone island, and a card opened from an edge module opens under the … |
| I260 |  | The island's own pill outline shows inside the standalone island's group; the frame's side strips start below the … |

### Cards and scrolling

Shares: the Stage's cards (where and how large they open) and the shared scroll host. Size: M. Needs you: I606: the list of placements.

| Row | | What |
|---|---|---|
| I606 | U | **done** — A large card joined to the bar's centre as a place any module's card can open at. The user likes the size and place of … |
| I494 | U | Content cut by a scroll edge blends out: a short progressive blur and fade toward the edge instead of a hard cut, only … |
| I504 | U | Cards have a maximum size and scroll beyond it (settings for both); floating cards keep one even gap to the nearest … |
| I505 | U | Notification cards and OSD follow the style system; the launcher opened at the edge follows the theme and its edges … |
| I332 |  | Japanese and modern families, gaps: ScrollHost covers only the launcher list; the sidebar and notification lists need … |
| I324 |  | luna/aero leftovers: scroll-bar parts (no caller hosts `ScrollStyle`, so `scroll.thumb` keys are inert in every look — … |

### Notifications

Shares: the notification service and centre. Size: M–L. Needs you: I529: which parts first.

| Row | | What |
|---|---|---|
| I529 | U | Notifications, round two: inline reply and actions, image previews, per-app rules (mute, priority, where they show), a … |
| I205 |  | Daemon follow-ups: `notifications.dnd` is read only at start — a runtime change does nothing (Shōjiki gap; follow the … |

### Desk

Shares: the desk surface and its cards. Size: S–M. Needs you: —.

| Row | | What |
|---|---|---|
| I196 |  | Desk follow-ups: Return on a focused card key presses it instead of Done (shared Button/IconButton take Return first); … |
| I125 |  | Mods' desk cards and the tasks panel use a few `Theme.keycap` (now `ringW > 0`) checks; move them to … |

### Lock and greeter

Shares: the lock, the greeter and its cache. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I142 |  | Greeter: record the cache file format as a contract; an explicit offline mode in `Store`; Caps Lock warning, … |
| I416 |  | The font mix on the greeter and lock: the lock follows the shell's Theme; the greeter has its own copy of the look … |
| B67 |  | The greeter's cache wears a palette draft (it should take the saved colours, as the theme export does: CONTRACT-CHANGE … |

### Web dock, card and host

Shares: the dock's card, the host process and its settings. Size: M–L. Needs you: —.

| Row | | What |
|---|---|---|
| I78 |  | Web card polish: at phone width the title gets ~30 px ("cam…") because two accent-filled segmented controls … |
| I79 |  | Favicons: QtWebEngine 6.11 gives the favicon URL, not its bytes, and the host turns engine icon loading off (the … |
| I97 |  | Web card offline chip: the host scope cannot read `svc.network`; serve a daemon-owned `online` on `mod.webdock` instead. |
| I106 |  | Web dock phone status row: battery (svc.power) and network marks once the host scope allows them (row 116/118: only … |
| I431 |  | Web dock host: `PhoneFrame` loads `../Relief.qml` when the theme has a texture, and the host has no such link, so the … |
| I207 |  | Web dock follow-ups: a reserved top/bottom card is sized to the output height (covers the top bar / runs past the … |
| I159 |  | Web dock in the sidebar: Ctrl+PageUp/PageDown go to the page while it has the keyboard instead of switching sidebar … |
| I74 |  | Web dock: drag-resize of the extended card and a per-pin width (Floorp: 0 = global); several docks (ROADMAP … |
| I92 |  | "Open in browser" always runs `xdg-open`; the brief's DoD wants a configured command (setting `browser_command`, … |
| I94 |  | Web dock: `webdock.open`/`select`/`back` from the CLI show the dock with no pointer or focus report, so it stays until … |
| I91 |  | `mod.webdock` carries no forced marker for `pinned` (or the other dock settings), so the strip's pin-dock toggle is … |
| B122 |  | Web dock round three, open: a `kurashi undo` sent at once after "Unpin but keep open" twice left the row back while the … |
| B107 |  | Web dock, after W73: a hover reveal of the edge dock takes the page from an open bar card or sidebar ("last opened … |
| B117 |  | Web dock, after W74: with `hover_takes_page` off the bar card's case cannot be reached on screen — while a Stage card … |
| B94 |  | niri: a change of keyboard interactivity on a mapped layer surface takes no effect (None → Exclusive never got focus), … |
| B95 |  | Web dock bar card, not measured: HiDPI (fractional scale), a second output, a left bar; no shot of "engine missing"; … |
| I80 |  | Web dock on niri: a nested niri inside the sandbox (layer surfaces, on-demand keyboard focus, the card at each edge) … |

### Bundled mods, follow-ups

Shares: one visit per mod: weather (I57 I82 I88 I66), calendar (I89 I203), sysmon (I84), tasks (I120 I121), timer (I229 I236), lyrics (I129), easter eggs (I286). Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I57 |  | Weather not verified in the real shell: places search/preview/save/move/remove click-through, stale aside in the real … |
| I82 |  | Weather panel: the hourly rain marks are unlabeled 3-px dashes under the temperature line (no scale, no %; unreadable) … |
| I88 |  | Weather follow-ups: the places preview is not verified in the sandbox — a click on the Stage's search field does not … |
| I66 |  | Test gaps: name lookups inside the no-network sandbox still reach the host nscd (unix socket); weather's fetch-failure … |
| I89 |  | Calendar polish: rows with day marks crowd the next row (cells keep their height, the number moves up); week numbers … |
| I203 |  | Calendar/clock follow-ups: the calendar widget falls back to `island.expand {}` when `{face: "clock"}` is refused (row … |
| I84 |  | Sysmon leftovers: container/VM cgroup limits (brief state) not built; the screen-reader check of the sparkline text and … |
| I120 |  | `tasks.notes.set {base}` refuses when the note changed on disk meanwhile (today last write wins). |
| I121 |  | Tasks: Todoist/TickTick backends, several lists and notes, reminders at a due time, a Japanese-locale run of … |
| I229 |  | Timer follow-ups: a stopwatch; alarms at a clock time; "focus until the next event" from the calendar; sounds of our … |
| I236 |  | Timer: a suspend that passes an end is noticed at the next tick (the job sleeps on the monotonic clock) — wake on … |
| I129 |  | Polkit: a real `pkexec` round trip in a sandbox with a private polkitd; lyrics: a "back to the line" key, the bar … |
| I286 |  | Build the `easter-eggs` mod (MODS.md: seasonal touches in the clock and the Island, `action:easter.*`, frequency … |

### Fonts and handwriting

Shares: the font list, the mix and the handwriting mod. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I440 |  | A font that crashes Qt puts the frontend in a crash loop with no way out but the config: the restart loads the same … |
| I444 |  | Fonts installed after the daemon started are not seen until it restarts (`FcList::query` once at start): a handwritten … |
| I419 |  | Handwriting mod after the prototype: pen pressure from a stylus (the box takes it as a plain pointer now); kerning from … |
| I446 | U | Idea: the handwriting mod also makes a monospaced version of a font (each letter fitted to one width, centred), so a … |
| I415 | U | A "handwritten fonts" plugin: the user makes their own fonts in several iterations, and the font mix (I176) mixes them … |

## 3. Larger features (several days each; a UX brief first)

### Audio control

Shares: PipeWire devices and streams in the quick card, the sidebar and the island. Size: M–L. Needs you: —.

| Row | | What |
|---|---|---|
| I524 | U | Audio control: output/input device switching and per-app volume (PipeWire) in the quick settings card; a mini player in … |
| I111 |  | Media face level bars are decorative: drive them from a real audio level (PipeWire peak, refcounted) and bench the 10 … |
| I20 |  | "Usual output" for the OSD device name is the first default the daemon saw; make it a config key or learn it. |

### Quiet time

Shares: one mechanism: hold notifications and summarise them after. Size: L. Needs you: the brief.

| Row | | What |
|---|---|---|
| I520 | U | Focus mode (間, Ma): one switch hides the bars until hover, holds notifications and summarises them after, dims the … |
| I534 | U | Breaks and wind-down: gentle break reminders (20-20-20, stretch), a wind-down hour that warms the colours and quiets … |
| I530 | U | Day rituals: a morning briefing card on login or unlock (weather, today's calendar, tasks, unread) and an evening … |

### niri config from Settings

Shares: one writer of niri config with a live preview and a revert countdown. Size: L. Needs you: the brief.

| Row | | What |
|---|---|---|
| I528 | U | Displays page: arrange outputs, scale, refresh rate, VRR and rotation through niri's IPC, with a live preview and a … |
| I535 | U | Window rules in Settings: a niri window-rules editor (float, opacity, output, size, block from screencasts) with the … |
| I533 | U | Workspace identity: names, icons, and an optional wallpaper or palette per workspace, shown in the workspace mark … |

### Windows and previews

Shares: the window list, the previews and a switcher. Size: M–L. Needs you: I414: the default for previews.

| Row | | What |
|---|---|---|
| I521 | U | A window switcher: Alt+Tab with live previews (the previews already exist), type to filter, "recently closed" to bring … |
| I197 |  | Window list follow-ups: the peek joins Peeks' arbitration (a `task:<id>` source kind in the Stage); `window.move` that … |
| I413 |  | Hover previews on sway and Hyprland: the workspace's still works, windows have no crop. Both adapters know a window's … |
| I414 |  | Hover previews are on by default because the user asked for them. They keep pictures of the screen in the runtime dir … |

### One search and quick capture

Shares: the launcher's ranking over more sources; capture to the vault is one more sink. Size: L. Needs you: the brief.

| Row | | What |
|---|---|---|
| I518 | U | One search for everything: without a prefix the launcher also ranks files, the web dock's history and bookmarks, notes, … |
| I532 | U | Quick capture to Obsidian: a launcher prefix (or the bar's field) that appends a note, a task or the clipboard to the … |

### AI mod

Shares: the AI mod and its launcher mode. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I525 | U | The AI mod, put to work: notification digests, "ask" in the launcher, summarise the selection or a clipboard entry — … |
| I141 |  | Mods adding launcher rows (`launcher:` provide is parsed, not implemented) → the AI `!` mode; a `font.family_mono` … |

### Any module on any surface

Shares: a module's forms for bar, sidebar, card, web dock; other windows hosted by the shell. Size: L. Needs you: the model (I501).

| Row | | What |
|---|---|---|
| I501 | U | Any module on any surface: every module (notes, tasks, …) can be hosted by bar, sidebar, card and web dock in a fitting … |
| I490 | U | Other kinds of surfaces in the web dock: notes, now playing, lyrics, a timer and so on beside sites; for a start a … |
| I499 | U | Web dock: Online / Local mode: a switch between websites and shell content (notes, tasks, other modules) as pins; … |
| I509 |  | Web dock Local mode, open ends: (1) done (session 32, the user: sites only — Online lists the sites, `strip` in the … |
| I510 | U | Desktop apps in the web dock (docs/ux/webdock.md "Desktop apps (experimental)"): only niri placement (a floating window … |
| I513 | U | An embedded terminal ("or something similar — that would be very cool"). |
| I372 | U | Shell-hosted app windows (prototype one day): dock any app's window into a shell surface — a terminal in a sidebar or a … |
| I385 | U | The web dock in niri-window mode (`mods/webdock/host/SideWindow.qml`) does not attach to the shell (frame, bar, joins); … |
| I409 | U | "Maybe": open the launcher in a sidebar when a sidebar hosts it. Needs the launcher's body as a sidebar section … |
| I468 | U | Web dock styles. Half of an opened spiral notebook with its own opening animation (picture 7); the phone (extended, it … |
| I476 | U | Web dock styles, round two (answers to #37). (1) Binding on the dock's side: yes; the pin section should look more … |
| I144 | U | Sidebar style "paper notebook": a classic notebook that opens from the side (pages, binding, paper — fits washi). Idea … |

### Module variants (K72)

Shares: a glance, a peek, a tile and a desk card for the core modules; the control centre as modules. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I223 |  | Variant gaps, core *clock*: no peek of its own (island peek only), no quick tile; retrofit as the K72 proof card (W45). |
| I224 |  | Variant gaps, core *media*: no bar/edge glance (only the island face), no peek outside the island, no quick tile. |
| I225 |  | Variant gaps, core *notifications*: no glance (bell + count), no desk card. |
| I226 |  | Variant gaps, core *volume / brightness*: no peek; brightness and microphone have no glance; neither has a desk card. |
| I227 |  | Variant gaps, core *bluetooth / network / power*: no glance, no peek, no desk card (they live in quick settings and … |
| I228 |  | Variant gaps, mods: sysmon (no desk card, no quick tile), weather (its desk card is core, not a `desk:` provide; no … |
| I469 | U | Control centre as modules. Each of its sub-modules and options becomes a module of its own, thought through, that can … |

### Web dock, engine

Shares: the web engine and what a page may do; I391 and I394 wait for the overhaul (I402). Size: L. Needs you: I371: the engine.

| Row | | What |
|---|---|---|
| I498 | U | WhatsApp Web does not work in the web dock. Find out why (engine version or user agent); if it needs a new engine and … |
| I371 | U | Reconsider the web dock's engine: the user wants real uBlock Origin, mainly for YouTube (its ads are first-party, only … |
| I373 |  | Web dock ad blocking is blocked on QtWebEngine 6.11.2: full uBlock Origin (MV2) is refused ("Unsupported manifest … |
| I377 |  | Re-probe extension DNR on every QtWebEngine bump (load/install a minimal extension with a manifest-enabled ruleset; … |
| I71 |  | Web dock site permissions: a per-pin allowlist (camera, microphone, location, notifications, screen, clipboard read), … |
| I70 | U | Browser bridge v2, for whatever the default browser is (never a fixed one): its bookmarks as an "add pin" source (Gecko … |
| I75 | U | Web dock hybrid pins: a pin opens in the default browser's own window instead of the dock's engine (shared logins, … |
| I402 | U | The web dock may need a whole overhaul at some point; its motion bugs (I391, I394) wait for that instead of being … |
| I391 |  | The web pin's card in the host process (`mods/webdock/host/WebCard.qml`) still opens on its own `slideAnim`; the host … |
| I394 |  | Web dock choreography: the strip leaves on `fast` while the card is still closing, so a closing genie pours into a tile … |

### Mod catalogue

Shares: the index and installing from it (W98 steps 2–7). Size: L. Needs you: read the brief.

| Row | | What |
|---|---|---|
| I526 | U | Mod catalogue: browse and install community mods from a git index, their capabilities shown before installing (MODS.md … |
| I570 | U | How a mod is distributed, and the catalogue. Today: a Rust mod is linked into `kurashid` (part of the binary; nothing … |
| I564 | U | A visual designer for mods: only with the portable tier's declarative UI vocabulary (MODS.md "Tiers"), where a layout … |

### Gestures

Shares: motion that follows the finger. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I531 | U | Gestures that follow the finger: touchpad gestures for workspaces, the overview, sidebars and the launcher where the … |
| I346 |  | Gesture-driven motion on the W59 Driver's `track/release`: drag a toast to dismiss (a toss with velocity → its close … |

### Standalone features

Shares: nothing shared: each is its own card (a lightweight mode, screen tools, phone link, config timeline, accessibility pack). Size: L each. Needs you: which, if any.

| Row | | What |
|---|---|---|
| I608 | U | A lightweight / performance mode: one switch (and an automatic one) that makes the shell use as little as it can — to … |
| I522 | U | Screen tools in one place: screenshot, recording, colour picker and OCR from the launcher or a bar module; annotate a … |
| I523 | U | Phone link: KDE Connect in a sidebar section — phone notifications and replies, sending files, find my phone. |
| I536 | U | Config timeline (改善, Kaizen): every config change as a timeline with a visual diff and "restore to here", grouped by … |
| I537 | U | Accessibility pack: a screen magnifier, a high-contrast look, a keyboard-only audit of every surface, screen-reader … |

## 4. The visual system (looks, motion, light)

### Looks and chrome, fixes

Shares: the chromes, shadows and corner shapes. Size: M–L. Needs you: B79 (Glow) is your report.

| Row | | What |
|---|---|---|
| B79 | U | The Glow chrome does not glow: "just seems to draw an unfinished outline around surfaces, it doesn't glow at all". On … |
| B81 |  | The bundled Dracula's light scheme is not light: `palettes/dracula.toml` `[light]` has `surface = "#222330"` and a dark … |
| B86 |  | Painted and Ripped paper, not yet seen: a toast (the sandbox had no notification sender), tooltips, Settings' own … |
| I122 |  | Soft chrome: the session menu, tray menu and peek cards (slide-ins, not morphs) cast no soft shadow — the Stage window … |
| I123 |  | Glass: soft shadows show through translucent fills and darken them (draw the shadow outside the shape only, or mask it). |
| I160 |  | Island under line chrome: on translucent looks the card's head over the bar is a darker tone than its body (two layers … |
| I161 |  | A view with its own chrome (the phone) fades the island shape out before handing the pill back; during that fade the … |
| I188 |  | Plain `paper` on dark (sumi) still reads a little busy: judge on a dark contact sheet, lower its fibre relief if so. |
| I269 | U | Concentric radii for nested controls: `inner = outer − inset` for buttons, toggles, tiles inside cards and panels, the … |
| I288 |  | Squircle leftovers: the Rectangle-drawn rounded corners outside Block and the path shapes keep circles — the Stage's … |
| I310 | U | Elevation drop shadows for the bar, the frame, sidebars, the dock, cards and other overlays, static (by hand) or … |
| I471 | U | Chrome options. (a) Glow: glowing edges and chrome. (b) Water paint: edges and chrome painted by a watercolour brush … |
| I489 | U | The corner shape is for every corner of the sheet, not only the joins ("those are funny but look stupid alone. If those … |
| I492 |  | Corner shape, what still keeps its rounding. The blocks inside a card (tiles, keys, fields) and the desktop widgets … |
| I103 |  | More decor packs as recipes (`kurashi_theme::decor_recipe`): a glass pack after Vitreus/pleamar (material glass, calm … |
| I470 | U | Materials. Textured metal: steel tread plate (picture 8). Old paper or dirty canvas: browned, unevenly discoloured, as … |

### Style families

Shares: one family at a time, with you (I336), each against its inspiration (I289). Size: L. Needs you: a review session per family.

| Row | | What |
|---|---|---|
| I336 | U | A dedicated style-review session: the user goes through every style family in detail on their own niri, gives a verdict … |
| I289 | U | Rework the styles to look like their inspiration on every surface (Windows 95/98, XP, 7, 10/11, macOS, SNES, PS2, …), … |
| I325 |  | fluent leftovers: the 6-tile quick grid that pages the rest, a tile editor (the 11 edit key), notifications flyout that … |
| I327 |  | aqua/vibrancy leftovers: bold focused-app name in the menu bar (needs Contracts 8), sheets from a window's caption (not … |
| I328 |  | snes/ps2 leftovers: an opt-in desk ground drawn from the look (the PS2 void, the SNES black) since the shell draws no … |
| I381 |  | `styles/yorha.toml` does not pick `display`: recipes cannot be scheme-conditional, and the style is light. A dark yorha … |
| I117 | U | Style "isekai" and/or "mirai" (the user meant mirai — 未来 — and may want both): a cyberpunk feel (neon on deep night, … |
| B82 |  | A faint hard-edged rectangle about 12 px round the fluent flyout's body on niri at scale 1.25 (the agent's shot … |

### Joins

Shares: the two join builders (`ColumnShape`, `MorphShape`) become one, then the open join cases. Size: M–L. Needs you: —.

| Row | | What |
|---|---|---|
| I588 | U | Two join builders. Sidebars and the dock draw through `components/sidebar/ColumnShape.qml`, the cards through … |
| I483 |  | Connections, round two. The head-and-neck shape (a card on a narrow neck from its module) as a choice under any chrome: … |
| I491 |  | Bridge, round two. The launcher (`BarMorph` has its own `joined`), toasts and peeks keep the chrome's form; the neck's … |
| I245 |  | Bars on adjacent edges without a frame meet with square inner corners; in dynamic mode the inner corner could take the … |

### Frame

Shares: `Frame.qml` and its strips. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I132 |  | Frames on the island card and the quick panel (not Blocks today) and on the bar strip under flat chrome; frames in … |
| I230 |  | Frame ornaments in the corners (seasonal, easter eggs); the light's sheen round the band; KDE's floating bar that … |
| I239 |  | Frame follow-ups: the pen draws a piece of the rule per strip, not one closed line; blur covers the band rectangles, … |
| I268 |  | `Frame.qml` logs "Binding loop detected for property acrossMade" (the strips' Scope, also before session 15's changes) … |
| I304 |  | Layer stacking on one layer follows map order (niri): edge groups map before the frame strips and lie under the band, … |

### Motion, fixes

Shares: the motion engine and the forms; B80 (paint forms) is your report. Size: M–L. Needs you: judge in motion (B96).

| Row | | What |
|---|---|---|
| B80 | U | The paint forms (splat, brush, snake) are below the quality bar: "the new animations aren't really to the quality … |
| B90 |  | The start of an opening under a motion form is still slow: with a sheet form (the user's `splat`) the sidebar's first … |
| B91 |  | `SurfaceForm.extent` (a longer form on a large surface, K126) is wired for the sidebar only: the dock, the launcher at … |
| B98 |  | Still owed from session 27, not started: B90's three motion points (the neighbour window repainting while a sidebar … |
| B102 |  | From the key to the first moving frame a sidebar takes about 360 ms (nested niri: 177 ms to make the window and its … |
| B104 |  | While a card opens or closes, the bar redraws for five to eight frames (the module's key lights and fades); on nested … |
| B112 |  | The same change of face under a sheet form wherever the form's picture is not a window-aligned layer: the Stage's card … |
| B115 |  | A sheet form's ink is cut straight at its surface's box: a drop of `splat` that lands near the column's inner edge ends … |
| B32 |  | Once (early, not reproduced in 12 later runs) test-stage caught the morph stuck at ~55 % height with no content; … |
| I180 |  | The carried sheet carries translation only: the launcher's 0.96→1 scale and the morph card's 0.98→1 scale still let the … |
| I186 |  | Panels opened from the bar have no origin (`grow` from the output point that opened them): in hand with W34 morph … |
| I199 |  | Motion follow-ups: the first spring step lands ~3 frames (~40 ms) after the shape's first frame on every surface (Qt … |
| I273 |  | The expressive profile's surfaces still on springs: the island's own morphs (kept by design, K42 — revisit if the user … |
| I315 |  | Kami: the sidebar's first opening after a theme change starts late (test-sidebars at 40 ms: p 0.66 calm / 0.72 lively … |
| I354 |  | Lively's neck fillets at rest differ 8 px from motion off (main too); test-motion allows it (`MOTION_OFF_SLACK`). |
| I363 |  | Sheet forms draw a translucent card solid while they run (brief §5), so a translucent style visibly steps to solid at … |
| I387 |  | Shape forms (expand, iris, stamp, outline) on the launcher's and centre's non-morph reveal (BarMorph without a morph: … |
| I388 |  | A launcher opened by key (no start or launcher button in the bar) has no origin: genie pours from the card's top … |
| I389 |  | Drop's first frames: the island's pill empties (its face goes to the sheet) a frame or two before the ink covers it; … |
| I472 | U | Transitions between all states (colour themes, layouts): a bar moved from top to bottom can part in the middle and … |
| I478 | U | Transitions: decided (`docs/ux/transitions.md`). The travelling still for a bar move is fine (clicks dropped for about … |
| I486 |  | Layout moves, round two. A still of the bar's content on the traveller (gate the layout document as ColorBlend gates … |
| I487 |  | Colour flow, round two. A suite: frames only while it runs, none at rest, none with the flow off; Chase as a light that … |

### Motion, new

Shares: new forms and where motion can go next. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I348 |  | Sound per form (svc.sound, off by default): a paper rustle on fold/crumple, a soft tick per step under stepped, a CRT … |
| I349 |  | Share motion: export the preview as a short WebP/GIF and a motion pack as one file (copy/paste into Settings); later … |
| I350 |  | More forms to consider after W59.8: paper plane (Compiz "Airplane": a toast folds into a plane and flies off), shoji … |
| I347 |  | Mod forms (custom styles tier 2): a QML-tier mod registers a motion form component plus precompiled `.qsb` shaders; … |
| I448 | U | Idea: the style's animations for the workspace switch too: the current workspace freezes, plays the style's form (fold, … |
| I412 |  | niri forms: a window hangs from its own top edge, and genie's mouth is the top's middle, whatever the bar's edge or the … |
| I368 | U | Compositor animations closer to the shell: Hyprland/MangoWM get the continuous curve and standard duration only; niri's … |

### Text effects

Shares: `TextFx` and text spawn. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I485 |  | Text effects, round two. `TextFx` on body text (settings pages, lists, the launcher's rows, lyrics), stroke-order … |
| I473 | U | Written down for later: font effects (glow, sparkle, CRT glow, candle, each letter its own colour, animated letters) … |
| I425 | U | Spawn animations for text and drawn components: text typed out, written by pen, glyphs that resolve into text, Japanese … |
| I503 | U | Text spawn on all text (an option, not only headings); the opening's face blends into the final one (patterns, … |

### Light, texture and effects

Shares: the texture's light, screen effects, the cursor. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I173 | U | Light rays and a shadow system. (a) A faint light shaft / flare (and optional lens flare) with a slight bloom, falling … |
| I313 | U | Lighting (the texture's light, the pointer light, the spotlight, light-following shadows) as a module (mod) in the end; … |
| I312 | U | An effects sheet: ripples on a click, a cursor trail, waves — an input-transparent overlay made only while an effect … |
| I317 | U | Per-style cursor personality: a stylised cursor theme (compositor cursor theme via a kurashid-written include) and a … |
| I165 | U | Screen filters as their own idea, apart from textures: pixelate, CRT (curvature, mask), scanlines and similar shader … |
| I384 | U | Texture `display`, true pixelation: the image under a textured surface (the wallpaper, the blurred sheet behind glass) … |
| I380 |  | Texture `display` on light palettes: the black matrix is capped (≈9 % darker gaps on yorha light) by the 4.5:1 text … |
| I182 |  | Shots still missing for wave 32's DoD: the Stage card carried vs fixed mid-slide (only the sidebar is shot) and a … |
| I450 | U | Idea: an audio-reactive, oscilloscope-like border shader (seen on r/unixporn for the umbriel compositor, OP posted the … |
| I461 | U | Idea (future, after I460): animated colour across the shell: colour travelling in a spiral, moving blobs (bubbles, … |
| I462 | U | Idea (future): drawings or pictures as a pattern for the shell's background — the chrome's ground filled with a picture … |

### Wallpaper, ideas

Shares: the wallpaper as a live or derived picture. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I519 | U | Seasons and time of day (旬, Shun, VISION): palette and wallpaper drift through the day (warmer evenings, a calmer night … |
| I401 | U | Idea, later: a live wallpaper shader in the shell, for what a bake cannot do: the colour wheel blend in step with the … |
| I323 | U | Wallpaper-derived relief: normals from the picture itself, not only the material tile. (a) Impasto, static: high-pass … |

### Theme in other apps and compositors

Shares: the theme export's targets. Size: M–L. Needs you: —.

| Row | | What |
|---|---|---|
| I480 | U | The other apps keep their own palette too (after I454/K123, which covers terminals and terminal tools): GTK, Qt and … |
| I454 | U | Palette overhaul (d): a switch "apps keep their own tuned palette": instead of tinting apps (starship, terminals, … |
| I366 | U | VSCode follows the theme: a generated theme extension (`~/.vscode/extensions/kurashi-theme/`: `package.json` + theme … |
| I367 | U | Anki, Steam, Signal and Helium/Chromium browsers: no theme file the app reads without an add-on or installer (Anki: … |
| I443 | U | Idea: live theme updates in Zen, and hot reloading in general wherever an app allows it, without restarting the app. … |
| I442 | U | Idea: the font mix in GTK and Qt apps, not only the base family. The mix file lives in the shell's cache and is rebuilt … |
| I429 |  | Rio 0.5.28's `window.background-image` draws over its text (opacity 1 hides it, lower dims it, the window goes black … |
| I202 |  | Ghostty material follow-ups: `texture.kind`/`wrinkles`/`cracks`/`crack_style` tokens in the theme document so … |
| I421 | U | Idea: generate terminal shaders from the shell's animations and a user's recipes too, as I418 does for niri's windows. |
| I370 |  | Titlebars on niri/MangoWM: neither draws server-side titlebars; the apps' own (CSD) follow GTK/Qt. A sway-like titlebar … |
| I481 | U | The Painted and Ripped chromes as window decorations on Hyprland ("port that chrome as windows decoration for hyprland … |
| I164 | U | Hyprland adapter: use `decoration:screen_shader` for the texture scope `everything` — a true blend over apps … |

## 5. Parked: the structure and performance session

### Memory and performance

Shares: B156 first; one soak and one bench run serve most rows. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| B156 |  | The frontend still grows about 200 MiB an hour under continuous use (211 → 514 MiB in the hour; budget 2 MiB an hour), … |
| B153 |  | The bench gate is red on `main` and was at 0.2.0: frontend PSS 198 MiB at one output (budget 150), +55 MiB per further … |
| B149 |  | The gate's pass C counted 363 and 105 frontend syscalls a second at idle on 0.3.0 against 8 on 0.2.0. Traced for 100 s: … |
| B148 |  | The frontend grows while panels open and close. The gate's row "PSS growth over 20 panel cycles" (limit 2 MiB): 0.2.0 … |
| B35 |  | Frontend memory over budget without any texture: 178 MiB PSS at one output (budget 150) and +10.5 MiB per extra output … |
| B119 |  | Any QML animation that starts draws a frame in every window of the shell (Qt's threaded render loop): a lyric line's … |
| B120 |  | Pinned sidebars cost ~11 ms of CPU per frame (mostly the render thread's swap) and are 17–19 % of what is left while … |
| B101 |  | A Block costs 1.26 ms to make (100 Blocks: 126 ms after this session, 155 before; a bare one 0.26, a Rectangle 0.01): … |
| B114 |  | Keep loaded, round two. The Stage's cards (its window stays; the view is made at each opening: a quick card is about 45 … |
| I493 | U | Cards kept loaded like sidebars, with a toggle; cards open at their predicted size (the spawn animation starts from the … |
| B100 |  | Warm start, the surfaces not wired: toasts, a bar that shows and hides, the polkit dialog, the peek, and the web dock's … |
| B57 |  | Idle frames on the default look, `05b47e2c`: pass b counted 1.73 and 1.8 commits/s in both rounds where `c5d728eb` gave … |
| B58 |  | Idle wakeups with the gradient on, intermittent: kami with linear 26.2/s and watercolour 29.8/s at 0.6 % CPU in round … |
| B84 |  | For the performance pass (the user: "note it for performance testing, but don't do it now"): the cost of Painted and … |
| B56 |  | `perf(pen)` (`3d141df5`, branch `perf/s26-pen`, not in PR #26) is unverified: the machine hung during its suite run. … |
| I463 |  | Performance pass, to restart (user: after other features). Measured so far, `c5d728eb` against `05b47e2c`, two rounds … |
| I417 |  | Any document's patch reassigns `Store.docs`, which re-evaluates every binding on it, and every surface of the shell … |
| I10 |  | `QSG_RENDER_LOOP=basic` measured on machine B iGPU: −1.0 MiB per output (bare PanelWindow 3.6 → 2.6) and −5 MiB @1 out, … |
| I11 |  | Quickshell's own cost per layer surface is ~3.0–3.6 MiB anon (bare `PanelWindow` + Text, threaded loop), i.e. most of … |
| I22 |  | Measure the Bar's per-output PSS after mod widgets moved to ModLoader (bench-gate on a quiet machine). |
| I238 |  | Frame cost: four windows per output (+2…5.6 MiB untextured, +9.5…22.5 with the material, BENCH "W43 frame"). Scheduled … |
| I254 |  | Frame on, washi + paper: +14.8 / +8.0 / +13.1 MiB per output, over the ≤ +12 MiB allowance in two pairs of three (main … |
| I272 |  | PSS with the frame on, kanso, one debug-build pair: +2.98 MiB (two frontends) / +5.20 MiB (toggled) — over the +2 MiB … |
| I342 |  | K82's depth costs memory: with the frame on, washi + paper measured +22–26 MiB PSS against frame off (two frontends; … |
| I261 |  | PSS of the first shown edge group in a fresh frontend is +5.5–7 MiB (one layer window's floor + the timer widget), over … |
| I344 |  | Ma at rest per style (BENCH 2026-11-01): aqua, glass, luna, ps2, vibrancy and win95 wake ~12×/s with no frame drawn (a … |
| I587 |  | 77 notifications a second for three minutes took the 0.3.0 daemon to 564 MiB and the frontend to 449 (the history is … |
| I211 |  | Build/memory follow-ups: frames beyond Paper are expensive per Block (kami 0.8 ms, snes 0.75 ms); a lighter QuickTile … |
| I216 |  | Shadow/test follow-ups 2: the first launcher open of a fresh frontend commits 37–43 frames in 5 s (79 once; cold … |
| I218 |  | Quick card / Block cost follow-ups: washi quick card 21–22 ms warm (target ≤ 18) — the paper frame costs ~0.5 ms per … |
| I158 |  | Measure the web host's memory/PSS with the sidebar window mapped and record it in BENCH (332 MiB with 1 kept site, 367 … |
| I404 |  | Budgets on Qt 6.12, webdock `test-dock`: 20 reveal cycles add 1.9 to 4.5 MiB USS on this branch and 7.6 on main's … |
| I178 |  | While a block resizes with pen pressure on, its outline Canvas repaints every frame (as kami's Sketch always did): … |
| I320 |  | Ma: with paper on the shell, a quickshell surface made 8 commits during test-shadows' pointer sweep when it started … |

### Structure: the core and the mods

Shares: W92 rows 4–6, W95, and what the code repeats. Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| I571 |  | Key binds from declarations (K154 step 4): `[[action]] bind = "<name>"` offering a `keys.*` slot, so `keys.rs`'s … |
| I574 |  | `mod check`'s notes on the bundled mods (colour literals in the timer's ring and the web dock's frames, pixel font … |
| I555 |  | The core names mods (drift: K28 "the core never names a mod", MODS.md "everything beyond the core is a mod"). Rust — … |
| I556 |  | Extension points are hand-kept in three places (the slot list in `kurashi-mods/src/manifest.rs:88`, the `SlotHost { … |
| I557 |  | Mods import the shell's whole component library (`import qs.components` in 52 mod files, plus `.faces`, `.island`, … |
| I560 | U | The contract has no one place and actions are untyped. `kurashi-ipc` and `fixtures/ipc/client` pin the envelope well. … |
| I565 |  | `kurashi-services` depends on `kurashi-theme` only for the cover's colours (`media.rs:603`), so every theme edit … |
| I566 |  | `kurashi-mod-wallpaper` has `kurashid` as a dev-dependency (`tests/kurashid_wiring.rs`), against "a mod crate never … |
| I77 |  | `kurashid/src/native/hosts.rs` keeps the scope table, the host registry and the test seam `HostEnv` in process-wide … |
| I590 |  | The sessions mod still asks the shell for the other mods' parts of a desk just saved (`collect` → the chooser reads … |
| B39 |  | `mods/media/mod.toml` declares `widget:`, `island-face:` and `panel:` but the mod has no `qml/` directory: it ships … |
| B40 |  | `slot:lock.aside` is in the manifest SLOTS list but neither Lock.qml nor LockContent.qml hosts it; … |
| I548 |  | Most document shapes are hand-built `json!`, once in the daemon and again in the mock (outside tests: about 106 in … |
| I558 |  | The mock re-implements mods (`kurashi-mock/src/webdock.rs` 1278 lines beside `kurashi-mod-webdock/src/dock.rs`; tasks, … |
| I550 |  | Rust repeats (1 % of lines overall, in few places): the private `dbus-daemon` test bus in 9 files … |

### Mod API additions

Shares: `ModCtx` and the manifest (I231 and I591 are one: a mod posts a notification through the daemon). Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| I231 |  | Mods post notifications through the daemon (`ModCtx::notify`, buttons routed back) instead of their own session-bus … |
| I591 |  | The timer's end notification is its own D-Bus call; a core action `notify.send` (CONTRACT-CHANGE, the row after 819) … |
| I233 |  | A mod face that is steady relevance *and* raises an interrupting transient with its own TTL (`FaceHandle::flash`); the … |
| I234 |  | Hub: a provider-backed document's first snapshot can be its enable-time value, before the provider's first publish … |
| I235 |  | An `ints` mod setting type (list of whole numbers with a range); the timer's presets are a comma-separated string today. |
| I134 |  | A secret setting type (stored outside `config.toml`, via libsecret; never in the `config` document) for API keys — … |
| I118 |  | A capability for files the user names in a setting (`fs:user`), shown on the Mods page; `tasks` declares `fs:scoped` … |
| I145 |  | Mods' `decor:` provide (manifest `Provide::Decor`) predates K53: replace it with `look:` and `style:` provides that add … |
| I24 |  | Mod-provided custom Settings controls (e.g. weather place search on its Settings page instead of only in the panel). |
| I554 |  | Capabilities are shown but not held (a gap, not drift: MODS.md promises "declared, shown, checked by the validator"; … |

### Daemon, schema, adapters

Shares: the daemon's own gaps. Size: M. Needs you: —.

| Row | | What |
|---|---|---|
| B41 | U | The socket file vanished under a running kurashid. kurashid (pid since 12:25:08) kept serving the clients it already … |
| B66 |  | `config::watch`: a palettes event is dropped when a config event lands in the same 150 ms burst. |
| I358 |  | kurashid does not watch `$XDG_CONFIG_HOME/kurashi/motion/`: an edited motion pack (curves, recipes) shows only after a … |
| I139 |  | Adapters: fold the extra features into `Capabilities` and publish them; specific refusal reasons for compositor … |
| I143 | U | MangoWM adapter: later, once most of the shell is done (K52 has niri, Hyprland, Sway). |
| I208 |  | Keys follow-ups: a `#[kurashi(control = "shortcut")]` derive attribute replaces generate.rs's `keys.` prefix stand-in … |
| I15 |  | Unverified: `include "kurashi-binds.kdl"` relative to a `config.kdl` that is a store symlink (niri-flake / HM-managed … |
| I42 |  | A `path` type in the schema so profile export drops machine-local paths by type, not by value heuristics. |
| I95 |  | `_managed.enforce` is all-or-nothing: Nix-set dock pins show as Nix-layer values but as forced only with … |
| I177 |  | Numeric comparisons in schema `requires` (`theme.texture.cracks > 0`), so the crack pattern row is inert with its … |
| I353 |  | A schema attribute for "this lowest value means the profile's" (`inherit = -1`) so Settings' "From the profile (…)" … |

### Suites and test tools

Shares: W96 and the suites' tooling; several rows are one failure seen twice (I87 = I580, B85 = I406, B68 = I318, I162 = I287). Size: L. Needs you: —.

| Row | | What |
|---|---|---|
| B145 |  | Six suites outside the merge set are red on `main`, alone (I546: nothing runs them before a merge). … |
| I594 |  | W96, what is done and what is not. Done: `frontend/test-launcher.sh` (the Settings page is `layout`), … |
| I603 |  | `test-modqml` and `test-mods-live`, where they stand. Both expected things the shell changed on purpose: a mod's panel … |
| I584 |  | `frontend/test-controls.sh` is red on `main` (7 checks: the quick card's relief on kami and leather, the gallery on … |
| I585 |  | `just golden` fails five states on machine A on `main`: the references are another machine's. Per-machine references … |
| B154 |  | `frontend/test-toasts.sh` is red on `main`, alone: "sekai lively bottom" and "kami calm bottom": "the close control … |
| B155 |  | `settings/test-sheet.sh` is red on the integration branch, alone and under load, with one of two checks in turn: "Tab … |
| B76 |  | Three suites fail on `main` (52e92417) and the same way on the stack, so nothing merges them: `test-controls` (4 … |
| B87 |  | Three suites outside the merge set are red on `main` (2431be17 and later) and on the control-centre round-two branch: … |
| B83 |  | Control centre round two, left open: the recorder is always on the bar now and `volume` changed shape, so suites that … |
| B92 |  | `test-quick-modules` failed once on `main` after #47 ("a click on recorder did not open its card on the recorder page … |
| I578 |  | Three suites failed under load and passed alone in the gate's run (`webdock/test-card`: a pixel read right after an … |
| I580 |  | `test-peek.sh` with the shared IPC client (`tools/testkit/ipc.py`) fails its PSS budget (hover cycles +3.9 to +7.2 MiB … |
| I87 |  | `test-peek.sh`'s PSS-growth check is flaky under load: one gate run measured hover −9.95 MiB and retarget +10.75 MiB … |
| I582 |  | `mods/webdock/test/test-dock.sh`'s cost check is a difference (mod on − off, per output) against 10 MiB. On this branch … |
| I13 |  | No automated test that the unavailable slider ignores keyboard, pointer and wheel (now possible with … |
| I107 |  | `host-tooltip` shot shows no tooltip: the sandbox pointer never triggers hover on the host's buttons (already so at … |
| B30 |  | `kurashid --test hosts` `a_scoped_connection_reaches_its_own_mod_and_nothing_else` failed once under heavy parallel … |
| I179 |  | `tools/bench/sandbox.sh stop` leaves the runtime dir (`/tmp/kurashi-sb-<name>`) with its XDG state, so a reused sandbox … |
| I181 |  | `tools/bench/measure.py` cannot take a config, so `just bench` cannot measure a textured shell (relief shadows on/off, … |
| I213 |  | Bench tooling: `tools/bench/measure.py` ignores `CARGO_TARGET_DIR` (an agent must copy its binaries into … |
| I217 |  | Memory/env follow-ups: the frontend tests start `qs -p` and bypass `launch.sh` (plugin filter, `MALLOC_CONF`, EGL pin) … |
| I241 |  | Sandbox/test infra: the idle lock after 300 s blanks long sandbox runs and a reused sandbox name starts locked … |
| I243 |  | settings/test.sh starts kurashid before sway's IPC socket exists, so the daemon falls back to the niri adapter: the … |
| I246 |  | Deferred test: a reveal's first frame ≤ 16.7 ms (bar, dock, sidebar, edge module) is not measured yet … |
| I247 |  | The sekai default top bar differs from main by 9 px, one channel unit, in one column at the left sidebar button's … |
| I248 |  | `KURASHI_BAR_DROP=1` is a bench-only switch left in Bar.qml (re-measuring the hidden window); drop it after the next … |
| I249 |  | test-sidebars.sh's USS check now takes the smallest of its last five samples (the allocator swings ~40 MiB); record a … |
| I252 |  | Settings' tracked shots outside `layout/` churn between runs (regenerated, restored); `0-undo-on-open.png` still shows … |
| I262 |  | Test scripts leave their sandbox dirs: `sandbox.sh stop` kills the script before its `rm` (test-edge-modules.sh removes … |
| I263 |  | test-peek.sh: two checks fail on main too — "the island's peek is drawn under the top bar / above the bottom bar (real … |
| I267 |  | Deferred suites to rerun on main after wave 45 (each was green on its branch before the last merges): test-frame, … |
| I274 |  | test-morph: the sysmon panel's first open holds at its gate (`gate=true`, content 0) and "the sysmon widget's origin is … |
| I275 |  | test-bars `reveal` alone (BARS_PARTS=reveal, one decor): "the bar went and came back while the pointer rested on the … |
| I287 |  | test-tray-bt's Bluetooth steps fail on main too ("no card in the shot"): written for a centred quick card with a Close … |
| I162 |  | `frontend/test-tray-bt.sh` (not in the regular suite list) is stale since the phone-shaped quick card: its Bluetooth … |
| I308 |  | test-pen "idle, pen on, bar only" once counted 21 commits in 10 s (1 of 4 runs; main and three later runs 0): likely … |
| I314 |  | settings/test-sheet.sh: "the spotlight does not follow the pointer over the sheet" (relief under the pointer ≈ away … |
| I318 |  | `wiring::tests::brightness_set_intent_writes_the_level_and_drops_out_of_range_values` failed once under heavy load (two … |
| B68 |  | `kurashid` test `wiring::tests::brightness_set_intent_writes_the_level_and_drops_out_of_range_values` failed once under … |
| I321 |  | W55 left: fewer restarts (frame's shot scenes need doc patches that can remove keys), a rest log line for Stage cards … |
| I333 |  | Test flakes: `test-styles.sh`: the first style sometimes shoots an empty launcher (a race on first open); The volume ⊘ … |
| I355 |  | test-morph: the sandbox idle-locks before the glass case (lock screen in the glass shots; main the same). Set … |
| I356 |  | test-sidebars: kami-calm "open 40 ms" reads p ≈ 1.0 under load (passes alone); settings/test.sh's pick-list reorder … |
| I357 |  | test-edge-modules needs `mods/timer/shots/` to exist — gone from git since I345 (shots untracked). Suites must `mkdir … |
| I364 |  | `MOTION_SURFACE=sidebar tools/motion-previews.sh` films the user's login name in the sidebar header (the sandbox still … |
| I365 |  | `MOTION_SURFACE=toast tools/motion-previews.sh drop crumple` films no toast (4 KB WebPs): the Notify from `niri-env.sh` … |
| I382 |  | `frontend/test-sidebars.sh`: three open-progress timing checks (p ≈ 1.0 at 40 ms) fail under suite load and pass alone … |
| I383 |  | Tile budget: `a_tile_generates_within_the_budget` is release-only and ignored, so `display` has not been timed in … |
| I395 |  | Suites outside the merge set fail on W64's base too (not caused by it): test-peek (7 checks), test-texture (6, incl. … |
| I405 |  | `test-texture` "k61: the bar's relief does not match shade_at": mean error 3.7 of 255 over the relief-changed pixels … |
| I406 |  | `test-island-join`, case terminal-bottom-mid, is flaky: "double line: the rule runs on under the card" on a varying … |
| B85 |  | `test-island-join` fails for `terminal-bottom-mid` ("double line: the rule runs on under the card", a mid-morph frame) … |
| I411 |  | Suites outside the merge set that also fail on the frontend before I407/I408 (same binaries, a4e38ae9's QML): … |
| I432 |  | Suites leave sandboxes behind: after session 24's runs, kurashid, quickshell and nested niri from `/tmp/kurashi-sb-*` … |
| I583 |  | Suites and bench runs leave their sandboxes: 42 `/tmp/kurashi-sb-*` dirs and 14 sway, niri and kurashid processes hours … |
| B77 |  | The suites leave their sandboxes behind: 374 directories `/tmp/kurashi-sb-*`, 146 G, and the disk hit 100 % during the … |
| B49 |  | Sidebar test logs: `sidebar-tabkey`/`sidebar-pin` give x = −420 (−the column's width) at rest while the frame is at x = … |
| B50 |  | `frontend/test-sidebars.sh` morph part: 2 checks fail on `main` b7dffcb5 too (right column, kami-lively, open at 40 ms). |
| B54 |  | `frontend/test-launcher.sh` fails 7 checks offline on `c5d728eb` too (before session 26): the clipboard thumbnails (3 … |
| B55 |  | `frontend/test-sidebar-panel.sh` "idle: the pinned sidebar committed 2 frames in 5 s" is intermittent: failed once on … |
| B60 |  | Machine A hung and rebooted at 23:03 while suites ran: `NVRM: Xid 56` and `Flip event timeout on head 0` as the session … |
| B63 |  | Quickshell crashed twice on a hot reload of the live frontend while Stage.qml and Peeks.qml were edited (it restarted … |
| B64 |  | `frontend/test-previews.sh` is intermittent under load: once `w-2-4.png` was not there when the suite read it, once "a … |
| B43 |  | `kurashid` tests `keys::tests::keys_hyprland_config_verifies_the_written_file` and … |
| I542 |  | `just check`'s test step: `cargo test --workspace` 542 s and 551 s (two runs, each including about 100 s to rebuild the … |
| I544 |  | The merge set's wall time (38 min, 8036 suite-seconds, `-j 4` on 12 cores) is floored by its longest suites: … |
| I546 |  | Suites the runner cannot reach, and suites in no set. `tools/test-suites.sh` globs `mods/*/test/*.sh`, so the nine at … |
| I549 |  | No static check for QML (75 k lines; `just check` covers Rust, the launch script and icon names only). Try `qmllint` … |
| I307 | U | Faster suites: (1) parallel runner with a failure re-run alone and (6) `--changed` — done S17.3 … |
| I362 |  | `tools/bench/niri-sandbox.sh start` does not fail closed (a failed start leaves the previous run's env files) and uses … |

### Mock parity

Shares: `kurashi-mock`'s documents. Size: S. Needs you: —.

| Row | | What |
|---|---|---|
| I157 |  | The mock does not keep `scheme_before` (always `null`), so the Settings test cannot exercise "Back to …"; the daemon … |
| I306 |  | The mock's theme document (crates/kurashi-mock documents.rs) has no shape.squircle_k / frame.outline / chrome tokens; … |
| I581 |  | The mock's `mods` document carries no `icon` or `menus` (K154), so on `just mock` the desktop's menu shows no wallpaper … |

### Nix

Shares: the flake and the Home-Manager module. Size: S. Needs you: —.

| Row | | What |
|---|---|---|
| I316 | U | The flake pins niri `main` for cursor sessions (W58). Check niri releases now and then; once a release with … |
| I378 |  | `nix/hm-module.nix` keeps `webdockSettingKeys` by hand — a parallel list (rule 3): generate it from … |
| B65 |  | `nix build --impure -f nix/tests/hm-eval.nix` fails on `main` at "docs/niri-binds.kdl has every default bind line" … |

### Docs and process

Shares: the docs themselves; I568 is the backlog triage with you. Size: S–M. Needs you: I568.

| Row | | What |
|---|---|---|
| I449 | U | Cleanup of the prompting notes: the files written for agents and sessions (`CLAUDE.md`, `docs/HANDOVER.md`, … |
| I559 |  | Small inconsistencies: `docs/HANDOVER.md` holds 8 entries against its own "keep the last 5"; BACKLOG rows use statuses … |
| I568 |  | BACKLOG has 217 rows at `new` and statuses outside its own list (I559): a triage pass with the user — reject, merge … |
| I379 |  | `docs/ux/terminal-texture.md` lists the ghostty approximation per kind: add the `display` line (the recipe exists in … |
| D1 | U | Bevy as a candidate in the next framework re-test (complex graphics, animations, minigame mechanics, complex surface … |
| D2 |  | Long idea pool: `docs/ROADMAP.md` "v0.2", "v0.3", "Later" (not duplicated here). |

## 6. Check and close first (probably done, or decided)

### Rows whose status is behind

Shares: each was built or decided, by its own text or by session 35: verify, then set the status. Size: S. Needs you: —.

| Row | | What |
|---|---|---|
| I127 |  | A native mod's read-only feed of a core document (`ctx.follow("svc.media")`), refcounted; the lyrics mod then follows … |
| I232 |  | Capability-gated calls of core actions from a mod (`ModCtx::call`, e.g. `action:notify.dnd`) — the timer's `focus_dnd` … |
| I96 |  | The mock serves no `mods` document; test-dock.sh relays one. Serve it from kurashi-mock so shell tests drop the relay. |
| I569 |  | After the sweep 191 GB of `target/` is younger than seven days. Ask the user: a size cap as well (`cargo sweep … |
| I545 |  | `just suites --changed` runs the whole merge set for any change under `crates/` or `i18n/`, so every Rust edit costs 38 … |
| I551 |  | QML repeats: the text block `renderType/antialiasing/hintingPreference` by `Theme.pixelType` 481 times in 136 files (no … |
| B113 |  | `test-launcher` is red on `main` and depends on files that are not in the repo. One check fails on `main` and on the … |
| I547 |  | The suites repeat their harness (7.9 % of 25 k lines are cross-file clones): the IPC client heredoc `ipc.py` in 16 … |
| I552 | U | Mod contract, the consuming side is missing. `ModCtx` registers what a mod provides and offers nothing to read or call. … |
| I563 | U | Mod Editor page in Settings over the same generator and check (docs/ux/mod-editor.md). |
| I576 | U | A mod's own program without a crate. `host:` needs a linked `NativeMod` today (B15), so a mod someone downloads can be … |
| I577 | U | A version bump rebuilds every dependency under Nix. With `cargo` in the dev shell a bump recompiles the workspace's own … |
| I579 |  | From W89's baseline: `test-media` and `mods/lyrics/test-lyrics.sh` need example binaries the runner does not build … |
| B147 | U | The running shell holds 1.9 GiB. `kurashid` 641 MiB PSS, 637 MiB of it anonymous, its high-water mark equal to its … |
| I475 | U | Control centre, round two (answers to #38). (1) The centre is a normal surface that joins as the others do; never the … |
| I477 | U | Chrome edges: decided (`docs/ux/chrome-edges.md`). (1) A chrome sets everything, the edge included; the edge can then … |
| I506 |  | Choices for the user on the colour flow while music plays (nothing removed, Shōjiki): a slower step while music plays … |

### Review with you

Shares: only you can judge these, on your own session. Size: —. Needs you: a sitting.

| Row | | What |
|---|---|---|
| B96 |  | None of session 28's seven features was judged by the user in motion (B80's lesson): surface lines, control faces, … |
| I219 | U | Live-session check of kurashi as the niri shell after the NixOS rebuild: bar, notifications, polkit, lock — the user … |
| I482 | U | The web dock's page inside its bar card ("make the webdock actually appear in the corner it opens from on hover … … |
