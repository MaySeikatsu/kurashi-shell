# Web dock (mod `webdock`) — UX brief
Status: decided (user review, session 8, 2026-10-20; K38, K39, K40) — the state machine, sizes and web rules below
are the user's; contract rows 88–94 and 109–111; cards W20-*.

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

## User decisions (session 8, review of the interpretations; K40)
- **Hover:** a rest on the edge shows the strip **and re-opens the last page**; a click on that page's icon puts it
  away and the next reveal shows only the strip; a click into the dock keeps it until focus leaves (Floorp).
- **Timing and sizes as proposed:** reveal 250 ms (500 ms on a shared edge), hide 400 ms + 24 px grace; strip 56 px,
  phone 412 × ≤ 2× width, large 90 % — all settings.
- **Pinned** overlays; *reserve space* is an option (off) and reserves only the strip.
- **Keybind** `Mod+B` (Home-Manager default). **Kurashi views** = mod panels in v1.
- **New tabs stay in the dock** by default (the link replaces the page, Back returns); a setting sends them to the
  default browser instead. Sign-in popups stay sheets; permissions and downloads stay refused with a chip.
- **Home and history:** the header has back and forward; once the page has left the pin's address a **home** button
  returns to it, and **"Replace pin with this page"** makes the current page the pin's address (undoable).
- The accent-colour design pass stays separate (later); the dock is built on today's tokens.

## Session 9 phone (W21-phone, K42)
**User:** "Let the 'Phone' sized sidebar browser actually be themed like a phone as shown in the preview, can be a
front view instead of the angled one." Reference: SekaiPop's phone (`modules/sekai/phone/PhoneBody.qml`, the flat 2D
face of its Quick Panel), iOS/Android phone browsers (Safari's and Chrome's bottom toolbars).
- **The phone size is a phone seen from the front** (`frontend/components/phone/PhoneFrame.qml`, linked into the host
  as `mods/webdock/host/PhoneFrame.qml`): body with bezel, rounded screen, a pill cut-out at the top, side buttons
  (volume rocker left, power right), a home indicator. Token-driven: keycap = outline in `line`, a rim in `ring`, a
  dark glass bezel, a hard shadow straight down; flat = a thin dark bezel with a hairline, no rim, no shadow. The card's
  geometry is unchanged (412 × ≤ 2× width); the page gets the phone's screen (396 CSS px wide in flat chrome, 382 in
  keycap at 412).
- **Screen layout (top → bottom):** status row (time; the page's host name; no network/battery glyphs in the host — its
  scope has no `svc.*`, so nothing it cannot know is drawn, Shōjiki; the time is a minute clock gated on the card being
  mapped), the **title in a pill** (load progress along its foot), the page, then the header's controls as a **bottom
  bar** spread evenly (back, forward, home, reload, view, size, more, collapse — same Tab order as before, Ctrl+L enters
  at Back), the home indicator. The overflow menu and the tooltips open above the bottom bar.
- **Large** stays the plain card with the header on top (the brief allows it); the page's corners are masked only there.
- **The shell's cards** (a view pin, the cold engine, the empty dock) are the same phone in phone size: status row with
  the time (`svc.clock`), the title in a pill with size and collapse, the body on the screen.
- **The strip's pins are keycap app icons:** a rounded-square Block per pin, the shown pin lit in `color.selected`, a
  letter tile's letter in a data colour (from the pin's id, `color.data.1..4`), the favicon otherwise; the dock's own
  controls are round keys (Material Symbols `push_pin`, `add`, `settings`). Positions and sizes are unchanged (48 px).
- **Motion:** the card rises on a spring (`Easing.OutBack`, `motion.spring.overshoot`, into the 24 px margin on the
  strip's side) and leaves without one; `motion.spring.on = false` and reduced motion keep the plain curve or the fade.
- Shots: `mods/webdock/shots/phone-{sekai,wa-iro}.png`, `phone-view-{sekai,wa-iro}.png`
  (`mods/webdock/test/test-phone.sh <tag> <config line>`), and test-host's `phone-right`, `host-phone-header`,
  `host-phone-footer`, `host-tooltip`.

## In the sidebar (W30, session 12)
**User (session 12):** "It should be able to be used in the sidebar but inside of it it fills the whole sidebar instead
of being phone shaped." The edge dock stays exactly as it is; the sidebar is a second place for the same pins and pages.

### How others do it (research 2026-10-21)
- **Vivaldi web panels:** a column of panel icons on the window's edge, the panel's page beside it at a width the user
  drags; a toolbar over the page (back, forward, reload, home, the address, "mobile" toggle); the page stays loaded when
  the panel closes (users ask for hibernation). https://help.vivaldi.com/?p=67 (and the forum threads in "References")
- **Edge sidebar apps** (removed in Edge 149): an icon column on the right, the app fills the pane's full height, a
  small header (title, open in a tab, close); min width 376 px. https://learn.microsoft.com/en-us/microsoft-edge/progressive-web-apps/how-to/sidebar
- **Opera panels:** messengers pinned in the sidebar's icon column; the panel is the site at full height, "pin" keeps
  it open beside the page. https://blogs.opera.com/tips-and-tricks/?p=378
- **Firefox sidebar** (136+ "sidebar revamp"): a launcher of tool icons, the open tool fills the sidebar under a
  header with its name and a switcher; the toolbar button closes it (from the product, not re-checked online for this
  card: the sandbox rule keeps agents off real sites).
- **Zen Essentials:** a row of pinned site tiles at the sidebar's top, the rest of the sidebar below (the user's
  browser; see "User decisions (session 7)").
- **Taken:** the page fills the pane at full height (Edge, Firefox), a slim navigation toolbar over the page (Vivaldi),
  pins as a **row of app keys on top** (Zen's Essentials row) rather than a side column of icons (Vivaldi, Edge,
  Opera): kurashi's sidebar is 320–640 px wide and a 48 px icon column would take 15 % of a 320 px pane, while the
  sidebar's own tab bar already sits on top. The page stays loaded when the panel closes (Vivaldi), but under the
  dock's own unload rules, so it does not keep resources forever.

### Design
- The dock provides a panel `panel:webdock` → the tab or section value **`mod:webdock:webdock`**, offered by
  `sidebar.tabs` (left) and `sidebar.sections` (right) while the mod is on.
- **Layout:** the pins as one row of 40 px app keys (the strip's PinTile: favicon or letter tile, the loaded dot, the
  shown pin lit), scrolling sideways when they do not fit, and a settings key at its end; under it the **page well**
  fills the rest of the pane edge to edge inside the sidebar's padding and takes the full height on offer
  (`fillHeight`; a right section without one is 560 px tall). No PhoneFrame, no phone aspect.
- **The page:** the web host maps a layer window over the well (Overlay layer, anchored like the sidebar: top + side,
  exclusive zone 0, so the compositor puts both in the same place): a 36 px navigation row (back, forward, title, home
  once the page left the pin's address, reload, mobile/desktop view, open in browser) and the page under it, masked to
  the well's radius. The view is the pin's `view` (mobile at that width is fine; `desktop` is honoured).
- **A view pin** (`mod:<id>:<panel>`) is drawn in the well by the shell (no engine), with the well's height as its
  `fillHeight`. The dock's own panel is never a view of itself.
- **One host, one page per pin (K38):** the page is the same WebPage the edge card shows; it moves between the edge
  card's window and the sidebar's (a reparent: the page is kept, no reload, measured in the spike). `max_loaded` and
  `unload_after` are unchanged; a site on screen in the sidebar counts as shown (the idle clock waits), and a site on
  screen at the edge and in the sidebar at once is kept even past the cap.
- **Both visible:** different pins show live in both places. The **same** pin: since W73 the place opened last shows the
  live page and the other says where it is, with "Show here" (see "Which place shows the page"). (W30 to W72: the sidebar
  always kept it, and the edge card said "This page is shown in the sidebar".)
- **Placement (contract row 250):** the sidebar hands a panel that declares `property var placement` its rect at rest
  in the sidebar window (`{output, side, inset, top, width, height}`; null while it slides, scrolls or is clipped —
  generic, no mod named, `frontend/components/sidebar/Placement.qml`). The panel adds the well's offset and reports
  `webdock.sidebar {on, output, side, inset, top, width, height}`; the daemon publishes `mod.webdock.sidebar {pin?,
  place?}` and the host follows it. A click on a pin is `webdock.sidebar_select {pin}` (the daemon's state; an open
  sidebar without a chosen pin shows the first).
- **Outside a sidebar** (the panel in a Stage card): W72 shows the page in the card's well too — see "In the bar's card".
  (Before W72 a click there showed the pin at the edge and the well said so with a "Show at the edge" button.)

### States
- **No pins:** the well says `webdock.empty` with "Add a site" (Settings › Web dock › pins).
- **Cold engine / host starting:** the well (drawn by the shell) says "Starting the web engine…"; the host's window
  maps once its page exists, with the skeleton until the first paint (no white flash).
- **Page loading:** the skeleton and the progress line along the navigation row's foot.
- **Load error:** code, Retry, Open in browser (as the card). **Renderer crashed:** "The page stopped", Reload.
- **Host missing / failed:** the well says why (`webdock.host.missing`, the failure's reason); view pins still work.
- **Offline:** the page's own offline state (the host has no `svc.network`; a chip is later, as at the edge).
- **Blocked permission:** the chips under the navigation row, as the card.
- **Mod off:** the tab is skipped and the sidebar's empty state names it (LeftColumn, Shōjiki).

### Keyboard, motion, outputs, budget
- **Keyboard:** the pin row's keys are Tab stops (Enter opens, the menu key opens the pins' settings); the sidebar's
  Ctrl+PageUp/PageDown switch its tabs while the column has the keyboard; a click on the page gives the host's window
  the keyboard (on demand) and keys go to the page — Esc inside a page is the page's, Esc on the navigation row returns
  to the page, Esc on the column closes the sidebar (Sidebar.qml). Known gap: with the page focused, Ctrl+PageUp/Down
  reach the page, not the tab bar (the host cannot drive the shell's tabs).
- **Motion:** the page appears 160 ms after the column stops moving (the sidebar's spring, a tile page, a scroll) and
  goes the moment it moves again — the well under it carries the slide, so the page never trails the column. Reduced
  motion: the column does not slide, the page appears after the same settle.
- **Multi-output:** the page is on the sidebar's output (`place.output`), one sidebar at a time (K54).
- **Ma / budget:** sidebar closed = the panel is destroyed, `webdock.sidebar {on: false}`, the host's sidebar window
  unmaps (0 frames) and the page is Frozen unless the edge card shows it; it unloads by the dock's rules. The host's
  window exists only while it is mapped; the panel's placement watch runs on the sidebar window's swapped frames only
  (none while idle). No new cost while the sidebar does not show the dock.
- **Done (W30):** `mods/webdock/test/test-sidebar.sh` (left tab, two `file://` pins, the page fills the well, pin switch,
  close = hidden and no frames), shots `mods/webdock/shots/sidebar-{washi,sekai}.png`.

## Page styles (W69, session 27; I468)
**User (2026-11-10):** "Add different style options for the web dock (like a half of an opened notebook, with the proper
animation), still the phone style (when extended morphs into a tablet shape sideways), simple one that just morphs out
of the surface showing the webpage without phone decoration." The user was away for this card: every choice below that
they may want otherwise is listed in the card's report ("questions for the user").

### How others frame a side page (from the products; not re-checked online for this card)
- **Vivaldi / Edge / Opera side panels:** no frame at all — the page fills a pane of the browser's own chrome, with a
  slim toolbar; the pane's edge is the window's. The frame is the app's, not a device's.
- **Arc's Little Arc:** a small floating window with a minimal title row (address, "open in Arc"); rounded, shadowed,
  the browser's own material; it grows out of nothing (a scale and fade), and "open in Arc" grows it into a full tab.
- **Zen's Glance:** a link opens in a card that rises over the page from the link's place (a scale from the origin), with
  side buttons (close, expand to a tab, split); the card is plain, the theme's radius and shadow — the closest model for
  **plain**: the page morphs out of what was clicked and has no decoration of its own.
- **GNOME / KDE widgets and previews with device frames:** device frames appear in previews and "responsive design" tools
  (Firefox and Chrome devtools draw a phone outline round the page, and rotate it to landscape on a press; KDE's
  Plasma Mobile previews), never on a live desktop widget — the frame says "this is the phone-sized view".
- **Android desktop mode (freeform windows):** a phone app's window rotates between portrait and landscape by resizing
  the window, not by swapping a picture; the caption bar stays on top in both.
- **iPadOS Safari** (the tablet the phone becomes): landscape, the toolbar on top (back, forward, address, actions in
  one row), a status row above it, the home indicator below, a thin even bezel and a small camera dot on the long top
  edge — no pill cut-out.
- **Notebooks as UI** (skeuomorphic note apps, iOS 6 Notes, GoodNotes' covers): a lined sheet, a binding, the cover's
  edge round the sheet; the page turn is the one motion people read at once.
- **Taken:** plain follows Glance and Little Arc (the page out of its origin, the theme's own card); phone keeps K42 and
  becomes a landscape tablet the way a freeform window rotates (one continuous resize of the frame); notebook draws a
  binding and a cover from the theme's tones and opens with a page turn about the binding.

### Design
- **Setting** `mods.webdock.page_style`: `phone` (default: what exists) | `notebook` | `plain`; Settings › Web dock,
  under the size settings. The daemon publishes it in `mod.webdock` as `page_style` (absent while `phone`, so documents
  that predate it read as phone; CONTRACT-CHANGE row). It applies to the web pin's card (the host) and to the shell's
  cards at the edge (a view pin, the cold engine, the empty dock), so the cold card and the page that replaces it wear
  the same frame. The sidebar's well (W30) is unchanged: it fills the sidebar in every style.
- **"Extended"** is the existing **size** (phone ↔ large; `webdock.size`), not a new state: the size button in the card's
  controls (pointer), Ctrl+L then Tab to it (keyboard; the button's accessible name says the size it is in). Every style
  has both sizes: phone width × ≤ 2× width, and large (90 % × full height).
- **One page, never re-made.** The web page lives in one well the frames place; a style or size change moves and
  resizes the well (and, at most, reflows the site once at the end of a morph). It never re-creates the page or reloads
  it (the test counts the host's load reports).

#### Phone (K42, kept) and its tablet
- Phone size: exactly W21's phone (PhoneFrame): status row, title pill, page, bottom bar, home indicator.
- **Large = a tablet lying sideways:** the same body, wider than tall, morphed continuously — corner radius (the phone's
  corners scale with its width, as PhoneFrame derives them), bezel, the cut-out (the pill narrows into a camera dot on
  the long top edge), the side buttons (they leave the long sides and the tablet's pair stands on its top edge), and the
  screen. The tablet's controls are one row on top under the status row (iPadOS Safari): back, forward, title, home,
  reload, view, size, more, collapse — the phone's bottom bar leaves while the frame turns and the top row arrives.
- The page keeps its pixels during the morph: it takes the larger of the two sizes at the start and is clipped by the
  screen, so the site reflows once (at the end of a shrink, at the start of a grow), not on every frame.

#### Notebook — one half of an opened spiral notebook
Anatomy (a right edge; a left edge mirrors it; a top or bottom edge binds along that edge, a pad bound at the top):
- **Binding on the dock's side:** a band (22 px) along the edge next to the strip holds the coil: **twin wire loops**
  through **punched slots** near the sheet's edge, a pair every 28 px (the two loops 7 px apart), each loop a short arc from its slot over the
  sheet's edge into the band. The wire is a metal tone from the theme (its `outline` colour lit toward `fg` along the
  loop, with a highlight in `fg` and a contact shadow in `line`). Drawn once as static paths (a Shape with SVG path
  strings built when the size changes): no Canvas, nothing per frame.
- **The cover:** a board a few px larger than the sheets on the three free sides (6 px), in a surface container tone
  (`surface_container_high` shaded toward `outline` and tinted with the accent), with the theme's outline.
- **The sheets:** the page's ground (`surface_container`, the web card's screen colour), ruled faintly (`outline`, every
  24 px) with a heading rule under the header in the accent; two sheets below it show as thin edges on the free side; a
  thin gutter shadow along the binding (`line`, fading over 14 px).
- **On the sheet:** the header row on the top band (back, forward, title written on the heading rule, home, reload, view,
  size, more, collapse — the large card's header), then the web page inside the sheet's margins (10 px sides, 14 px
  foot), its corners at `radius.sm`, a hairline in `outline`.
- The notebook keeps the theme's outline width and colour on cover and sheet; texture/material comes in where the
  shell's own cards have it (the shell's cards; the host's theme has no texture — see "Done").

#### Plain — the page alone
- The dock's own card (the view card's look: `surface_container`, `radius.lg`, the theme's outline), standing against
  the strip, the header on top and the page under it, its corners masked to the card's radius. No device.
- It opens and closes in the **panel form** of the motion profile (`theme.motion.form.panel`: expand, iris, stamp,
  outline, a sheet form, or the slide) through the shell's form system (SurfaceForm, FormHost, ShapeLayer — the same
  path as the shell's view card, CONTRACT-CHANGE row 694), from the strip's side.

### States (every style)
- **Loading:** the skeleton in the page's well (the frame is drawn at once, the page appears on its first paint).
- **Load error / renderer crashed:** the existing messages and buttons, centred in the well.
- **Offline:** the page's own offline state (unchanged).
- **No pin / cold engine / host missing:** the shell's card in the same style (Card.qml), its message in the well.
- **Forced:** a `page_style` set by Nix shows as forced in Settings (records of provenance, as every mod setting).

### Keyboard and a11y
- Unchanged paths: Ctrl+L enters the controls (Back first), Tab walks them (size among them), Tab from the last returns to
  the page; Escape on the chrome steps back. The notebook's binding, cover and sheets are decoration (no focus, no
  accessible role); the tablet's and phone's frame likewise. The size button names the size it is in.

### Motion (DESIGN-SYSTEM §9, K83)
- **Phone:** the rise with its spring (K42), as today.
- **Phone ↔ tablet:** the frame morphs on the profile's `open`/`close` curves (a Glide: phone→tablet opens, back
  closes), 1 → 0 reversal mid-way continues from where it is; the controls cross-fade at the middle.
- **Notebook open:** the cover and binding slide in from the edge (the first third), then the sheet turns over the
  binding and lands flat — the `book` form's shader (paper bending with a curl, the K82 light, the cover tone on its
  back) driven as a page turn about the binding's axis, the sheet alone captured, the cover and coil standing still.
  Close: the sheet turns back up over the binding, then the notebook slides out. The turn runs on the motion profile's
  curves stretched by the `book` form's pace.
- **Plain:** the panel form, as the shell's card.
- **Style change while open:** a cut (the setting is changed in Settings, not while watching the dock; the page stays).
- **Reduced motion** (`theme.motion.profile = none` or `reduced`): every style fades (120 ms) and the size change is a
  cut — no turn, no morph.

### Multi-output, budget
- Multi-output as the dock: the card is on the dock's output; the frames have no per-output state.
- **Ma:** at rest no frame is drawn: the binding, rules and holes are static geometry; the page-turn layer exists only
  while it turns (a SheetForm loaded for the transition); the tablet morph's Glide rests at its end; 0 frames in 5 s with
  a page open and still (measured). The phone's minute clock is watched only in the phone style.

### As built (W69)
- **Binding side:** the card's wording ("the right-hand sheet, at a left edge the left-hand one") and its acceptance
  ("the binding on the dock's side") disagree; built: the binding on the **dock's side** (a right edge binds on the
  right, so the sheet is a left-hand page). A question for the user.
- **Plain's join:** the card stands against the strip with the dock card's own hinge (as the shell's view card); no
  concave fillets into the strip — the strip is the shell's surface and usually shorter than the card, and the host
  does not know its span. The panel form opens it from a 32 px mouth in the middle of the span (row 694's ask).
- **Material:** the shell's cards (view, cold, empty) take the look's relief on the device's screen (DeviceFrame's
  `relief`, as PhoneFrame); the web host's theme has no texture (its Theme has no `texShell`), so the host's frames are
  the look's colours, outline and shadow without relief — as the phone was before.
- **Frames** live once in `mods/webdock/host/frames/` (DeviceFrame, NotebookGeom/Back/Sheet/Wire, FrameBox) and the
  shell reaches them through the link `mods/webdock/qml/frames`; they import nothing of either tree and take the
  caller's Theme, RoundBox and Relief as values (`theme`, `box`, `relief`).
- **Test aid:** `KURASHI_WEBDOCK_HOLD=<file>` (test only): the host holds the card at `open <p>` or `wide <p>` (a watched
  file, nothing polls), so shots are taken by progress.

### Definition of done (W69)
- [x] `page_style` setting (mod.toml, i18n en/ja, daemon `page_style` in `mod.webdock`, forced provenance; rows 702,
      703 for PROTOCOL/MODS and Home-Manager).
- [x] Each style draws the page with a pin open (host) and the shell's view/cold/empty card in the same style.
- [x] A style change and a size change keep the page (no new load report) — `mods/webdock/test/test-styles.sh`.
- [x] Phone large is a tablet (wider than tall) and back, continuously (held half-way in the shots).
- [x] The notebook's binding is on the dock's side at a left, right, top and bottom edge.
- [x] Notebook page turn, plain panel form (expand, fold, slide checked); reduced motion fades (motion profile none).
- [x] No QML error or warning; idle 0 surface commits in 5 s with a still page open, in each style.
- [x] Screenshots on nested niri, light and dark: each style opening at three held steps and at rest
      (`<style>-<scheme>-open.png`), the large size held half-way and at rest (`<style>-<scheme>-large.png`, the
      phone's is the tablet), the shell's view card and a load error (`<style>-<scheme>-states.png`) —
      `mods/webdock/shots/styles/`,
      `mods/webdock/test/shots-styles.sh`.
- [ ] The page turn on the shell's own cards (view, cold, empty): they open in the panel form the profile names, not in
      the page turn (the turn is the host's card's).

## In the bar's card (W72, session 27; I482)
**The user's answers (session 28, 2026-11-10).** (1) *Esc: the page first, then close.* Built: with the keys in the
page the first Esc is handed to the page (a key event the host makes: `isTrusted` is false, so a site that answers only
the keyboard's own events does not react) and the card stays; a second Esc within 1.5 s closes the card; with the keys
on the card's own row Esc closes at once. (2) *A click on the module opens the card*, a second click closes it; the
dock at the edge is a middle click, its key or the command line. Built; an entry in the module's menu is not (I488).
(3) *The card's size is a setting* (Phone, Tablet, Wide; one for all pins). Built in W73 ("The card's size"). (4) *Last
opened wins*: the place opened most recently shows the pin's page, the others say "shown elsewhere" with a key to bring it
here. Built in W73 ("Which place shows the page"). Suite: `mods/webdock/test/test-card.sh` steps 6 and 6b.

**User (2026-11-10, with a screenshot of a bottom bar's right corner):** "make the webdock actually appear in the corner it
opens from on hover, basically filling the blank field with web content here". The bar module's card (click, or a rest
under `bar.hover = card`) showed the pins and an empty well saying "Sites show here when the web dock is a sidebar tab".
Now the well shows the picked site's page, in that card, where it opened.

### How others show a web page in a popover (from the products; not re-checked online for this card)
- **Vivaldi / Edge / Opera side panels:** the page fills a pane of the browser's own chrome, a slim toolbar over it (back,
  forward, reload, the address, "open in a tab"); the pane is the frame, the page has none of its own. Vivaldi keeps the
  page loaded while the panel is closed.
- **Arc's Little Arc:** a small floating window, a one-line title row (the host, "open in Arc"); "open in Arc" grows it
  into a full tab — the way out to the larger place.
- **macOS menu-bar web apps** (MenubarX, Fluid's menu-bar mode, Multi): an icon in the menu bar opens a popover hanging
  from it with the site inside, a small toolbar (back, reload, pin the popover open, open in the browser); a click outside
  closes it, the page stays alive in the background, and the next click shows it as it was (no reload).
- **GNOME / KDE web widgets** (Plasma's Web Browser widget, GNOME Shell extensions with a WebKit popup): the page fills the
  plasmoid's or popup's body, the panel icon toggles it; Plasma keeps the view while the popup is hidden.
- **Taken:** the page fills the card's well edge to edge (the card is its frame, as a side panel's pane), a slim
  navigation row on top (Vivaldi, MenubarX), the page kept alive while the card is closed (macOS menu-bar apps, Vivaldi), and
  a way out to the larger place — "Show at the edge" (Little Arc's "open in Arc", MenubarX's "open in browser").

### Design
- **Anatomy (top → bottom):** the card hangs from the bar's module (the shell's Stage card, its join, outline and material);
  the pins as one row of 40 px app keys with the settings key at its end (unchanged, the panel's row); under it the **well**,
  `radius.lg`, filled by the page: a 36 px navigation row (back, forward, title, home once the page left the pin's address,
  reload, mobile/desktop view, **Show at the edge**, open in browser) and the page under it, masked to the well's radius.
- **Size:** since W73 the setting `card_size` (Phone, Tablet, Wide; since W74 "As at the edge", the default, and a key in
  the card that steps through them; see "The card's size"). (W72: the dock's phone width,
  `geometry.width`, and a well 1.6 × its width tall.) Not resizable by dragging: "Show at the edge" is the way to the
  large size.
- **Page style:** plain. `mods.webdock.page_style` (phone, notebook, plain) is the edge card's (and the sidebar's well is
  plain too): in the bar's card the card is the frame; a phone or notebook inside a card would be a frame in a frame.
- **Which pin:** the card has a pin of its own (`card.pin`, kept while the card is closed, like the sidebar's): a click on a
  pin key shows it here (`webdock.card_select`); the first opening shows the first pin. A view pin is drawn by the shell in
  the well, as in the sidebar.
- **How the page gets there (one mechanism with the sidebar, W30):** the page is the host's (one host, one page per pin,
  K38), so the shell cannot hold it. The Stage hands a mod panel that declares `property var cardPlacement` where it rests
  on the output (`{output, rest, x, y, width, height}`, logical px from the output's top-left corner; `rest: false` while
  the card opens, moves, resizes or closes — the sidebar's `Placement` with the Stage window's own origin; generic, no mod
  named). The panel adds the well's offset and reports `webdock.card {on, output, x, y, width, height}` on change only; the
  daemon publishes `mod.webdock.card {pin?, place?}` and the host maps a layer window (Overlay, exclusion ignored, anchored
  top-left with those margins) exactly over the well. The page **moves** into that window (a reparent, no reload).
- **One page, three places — who shows it:** a pin's page is in one window at a time. Since W73 (the user's answer (4)):
  **the place opened last** shows it and the others say where it is, with "Show here" — see "Which place shows the page".
  (W72 built a fixed priority — the sidebar, then the bar's card, then the edge card; a daemon that does not publish
  `elsewhere`, the mock, still gets that order.) Different pins show live in every place at once. Nothing is reloaded
  when the card closes and opens again, when its pin changes back and forth, or when the page moves between places (the
  host's load reports are counted in the test).
- **Lifetime (Ma):** a site in the open card counts as shown — kept past `max_loaded`, the idle clock waits; closed, its
  page is Frozen like any hidden page and unloads by the dock's rules. The host's card window exists only while it is mapped.

### States (in the well)
- **No pins:** `webdock.empty` with "Add a site" (Settings › Web dock › pins). The settings key stays at the row's end.
- **Mod unavailable / no document:** `webdock.dock.unavailable`.
- **Engine not installed:** `webdock.host.missing` (names `programs.kurashi.webdock`); view pins still work. **Host failed:**
  the failure's reason. No "Show at the edge" there: the edge needs the same engine.
- **Engine starting:** "Starting the web engine…" in the well (drawn by the shell) until the host's window maps.
- **Loading:** the skeleton in the host's window (no white flash) and the progress line along the navigation row's foot.
- **Load error** (offline included: the engine's code, e.g. "no connection"): the code, Retry, Open in browser. **Renderer
  crashed:** "The page stopped", Reload. **Offline:** the page's own offline state or the load error (the host has no
  `svc.network`); a `file://` page works offline.
- **A site that refuses to be framed:** framing headers (`X-Frame-Options`, CSP `frame-ancestors`) do not apply: the page is
  not in a frame, it is the top-level document of its own view. A site that refuses the embedded engine (Google sign-in)
  is the dock's existing case: the sign-in sheet says so with "Open in browser" (`webdock.signin_refused`).
- **Shown in another place opened later** (W73): `webdock.side.elsewhere`, `webdock.edge.elsewhere`, with "Show here";
  the pin keys still switch to another pin.
- **The card opening or moving:** the well is empty (the card's colour) and the page appears once the card rests.

### Hover, keyboard, a11y
- **Hover (`bar.hover = card`):** the page's window is another surface, so the Stage's card sees the pointer leave when it
  enters the page. The host reports the pointer in its window (`webdock.card_page {hover, engaged}`); the panel holds the
  card through the shell's generic overlay hook (`Peeks.hoverOverlay(key, on)`: an overlay window over a card counts as the
  card; the card's own hover is known, so pointer page → card padding never closes it). Leaving both closes the card after
  the hover grace (380 ms). A press in the page makes the card the user's (as a press in the card does: `Peeks.hoverKeep`).
- **Keyboard:** the pin keys and the settings key are Tab stops in the Stage card (Enter opens, Menu opens the pins'
  settings); Tab from the settings key hands the keyboard to the page (`webdock.card_focus`: the host's window asks for it
  once, as the edge card does on a keybind reveal). A click in the page gives it the keyboard (on demand). **Esc closes
  the card** wherever the keyboard is in the page's window (`webdock.card_close` → `ui.close`), as Esc does on the Stage's
  own keys and on a popover. As built: a window shortcut, ahead of the page — QtWebEngine 6.11 hands no unhandled Esc back
  to its parents (measured on niri, in a text field and on the page's body), so "Esc the page did not take" cannot be
  told; a site's own Esc (closing its dialog) is therefore not reached in the bar card. At the edge and in the sidebar the
  page keeps Esc.
- **a11y:** the navigation row's buttons have names (the sidebar's), "Show at the edge" names where (`webdock.side.at_edge`);
  the well's notices are text the screen reader reads; the page is the engine's own accessible tree.

### Motion, outputs, budget
- **Motion:** the page waits for the card: the Stage withdraws the placement the moment the card opens, moves, resizes or
  closes, and offers it 160 ms after it rests; the host's window then fades in (`motion.quick`, 120 ms). Following the card
  frame by frame would need a round trip through the daemon per frame and the page would trail its card (the sidebar chose
  the same, W30). Closing cuts the page at once and the card carries the close. Reduced motion (`motion.profile` none or
  reduced): a cut.
- **Every bar edge and output:** the place is output-absolute (the Stage window's origin from its own anchors and margins),
  so a top, bottom, left or right bar, a card near a screen corner and any output read the same; the host maps on the
  place's output. HiDPI: logical px on both sides (layer margins are logical).
- **Ma / budget:** card closed = no placement, the host's card window unmapped (0 frames), the page Frozen; the Placement
  watches the Stage window's swapped frames only while the card is open (none at rest); the geometry is sent on change
  only. No new process, no polling.

### As built (W72)
- **Focus on map:** sway and niri hand a freshly mapped on-demand layer the keyboard, so the page's window takes the keys
  when it appears (measured: "keyboard in" on the map). That is not counted as using the page: `engaged` is a press in the
  page or the keyboard asked for it, so a hover-opened card still closes when the pointer leaves. A click on a pin key gives
  the keys back to the card (its Tab stops).
- **Engine lifecycle:** a hidden page used to be frozen in the same turn as its hide; QtWebEngine refused that ("page is
  visible") and the page stayed Active. The freeze now follows the engine's `recommendedState` (Active while visible or
  audible), in every place the page is shown.
- **One window type:** the bar card's window is the sidebar's `SideWindow` in its card role (`cardRole`), so the two share
  the navigation row, the states and the page's mask.
- **Mock:** the mock does not know the card's actions (CONTRACT-CHANGE 722); under it the well shows its notices only.

### Definition of done (W72)
- [x] With a pin, the bar card shows the page in its well: the host window's rect equals the well's (logs), on a top and a
      bottom bar — `mods/webdock/test/test-card.sh` (sway).
- [x] Close and reopen, pin back and forth, the same pin at the edge: no new load report (the host's load reports
      counted); the edge card says "This page is shown in the bar's card" while the card holds it (not shot).
- [x] Pointer from the module into the page keeps the card (hover mode); page → card keeps it; leaving closes it; Esc
      from the page closes it; Tab past the card's keys and a click in the page give it the keyboard (typed text arrives).
- [x] No pin: the empty state with "Add a site"; engine missing: its message (the panel's notice, not shot).
- [x] Idle: the card's window draws 0 frames in 3 s after the card closed; no QML error or warning in the shell or the
      host (test-card.sh greps both logs, the engine's lifecycle warning included).
- [x] Shots on nested niri: bottom bar's right corner and top bar, light and dark; the empty and the error state —
      `mods/webdock/test/shots-card.sh` → `mods/webdock/shots/card/card-{bottom,top,error,empty}-{light,dark}.png`.
- [ ] Left and right bars, a second output, HiDPI: the geometry is output-absolute and logical by construction; not
      measured in a test.

## Background pages (W73, session 29; I488)
**User (session 29):** "Web Engine stops process like spotify after a song, so it can't be used to run that in the
background for long (maybe it needs keep alive toggle or something? Idk since the site itself seems to still be up)".

### The cause
Read in the code, then measured (see "As built (W73)"): a hidden page's engine lifecycle was `Active` only while the
engine recommended it, which it does while the page is visible or `recentlyAudible`. Between two songs a player is silent;
`recentlyAudible` falls a moment after the last sound, the hidden page is frozen (no timers, no network), and the timer
that starts the next song never runs. A frozen page cannot wake itself, and the site "seems to still be up" because its
view is kept. The daemon had a second gap of the same kind: an audible site is kept past `max_loaded`, and the moment the
gap's "not audible" report arrived, a site past the cap left `keep` and its page was destroyed.

### How browsers and other shells do it (from the products and their documentation; not re-checked online for this card)
- **Chrome** freezes or discards background tabs (Memory Saver; tab freezing on low memory) and, since Chrome 88, throttles
  timers of pages hidden for five minutes to one wake-up a minute ("intensive throttling"). Exceptions: a tab that plays
  audio or played it in the last 30 seconds, one with a live WebRTC connection, camera, microphone or screen capture, one
  with unsaved form input, and the sites the user lists under "Always keep these sites active".
- **Edge** "sleeping tabs": a tab inactive for a set time (default 2 h) sleeps; tabs playing audio and the sites under
  "Never put these sites to sleep" do not. Edge's sidebar apps kept running while their pane was closed.
- **Firefox** unloads tabs only under memory pressure, oldest first; a tab playing audio, a pinned tab and one in
  picture-in-picture come last. Background timers run on a budget, not frozen.
- **Safari** throttles background tabs and suspends their timers after a while; audio playback is exempt.
- **Opera / Vivaldi side panels:** a messenger or a music panel (Opera's "Player": Spotify, YouTube Music) keeps running
  while the panel is closed; Vivaldi users ask for hibernation of panels, so it is the other way round there.
- **Quickshell shells / HyprPanel:** none host a web page; media keeps playing in the user's browser or player.
- **Taken:** two of Chrome's and Edge's exceptions. (1) A page that played sound counts as playing for a grace time
  after its last sound (Chrome's 30 s, longer here: see below). (2) A per-pin "keep running" switch, the dock's version of
  "Always keep these sites active" and "Never put these sites to sleep", which also lifts the dock's own unload rules.

### Design
- **Grace after sound: 10 minutes.** A page that has played sound stays `Active` for 10 minutes after its last sound,
  hidden or not, and the daemon keeps it loaded (past `max_loaded`) and the host running (the idle clock waits) for the
  same time. Why 10: the gap between tracks is 0–5 s (gapless, a crossfade, a slow network's buffering, an ad break that is
  itself audible), which any grace covers; the longer case is a player the user pauses — a phone call, a coffee, the
  doorbell — and comes back to, which is minutes. Ten covers that, and a silent page does not stay awake forever: past
  it, the page freezes as before and the dock's rules apply. (Chrome's 30 s is for a tab the user can see in a tab strip;
  a dock page is out of sight, so a pause there is less likely to be noticed and resumed at once.) One constant, owned by
  the daemon: it publishes the page's `awake` mark (below), the host only follows it.
- **"Keep running in the background"** (`background`, a bool field of each pin, default off; Settings › Web dock › pins).
  Such a pin's page is never frozen while it is loaded, and the dock's own rules never unload it: not `unload_after` (the
  web engine stays running while it is loaded), not the `max_loaded` cap. It is loaded once it was opened (shown in any
  place); an engine that restarts (a crash) loads it again, but after a restart of the session it waits until it is opened
  — the dock does not start sites by itself (Calm). Turning the switch off returns the pin to the rules, at once.
- **The document:** a web pin carries `background: true` while the switch is on and `awake: true` while its page must stay
  `Active` although it is hidden and silent (in its grace, or a loaded background pin); both absent otherwise. `audible`
  stays what the engine says, so the indicator never claims sound during a pause (Shōjiki).
- **Honesty where the pin is listed:** the pin's tip and its menu on the strip say "Keeps running in the background"; the
  sidebar's and the bar card's pin keys name it in their accessible description; Settings' pin list says it on the switch,
  and the pins setting's help names the cost; `unload_after`'s help says that a background pin and sound hold the engine;
  the mod's description and its `cost = "high"` stay true (the engine is the cost).

### States
- **Playing, hidden:** `Active` (as before). **Silent, in the grace:** `Active`, `awake`. **Silent past the grace:**
  `Frozen`, unloads by the rules. **Background pin, loaded:** `Active`, `awake`, kept, the engine held. **Background pin,
  not opened yet:** nothing runs (no load, no engine). **Engine missing / failed:** the switch is inert like the pin (the
  pin's own state says why).

### Keyboard and a11y
The switch is the records editor's own bool control (Tab, Space). The strip's tip shows on a rest or keyboard focus; the
pin keys' accessible description adds "keeps running in the background".

### Budget (Ma, rule 5)
A background pin is the user's explicit exception to "idle = silent": its page's process and the web engine stay in memory
(the host's process tree measured by test-host's memory phase, session 29: 530 MiB PSS with one kept site, 575 MiB with
five, `file://` fixture pages — a real site costs more) and the page's own CPU and network run
all day. The grace costs at most 10 minutes of the same after the last sound. No poll: the host follows the document, the
daemon wakes once at the grace's end (a deadline, no ticker).

### As built (W73)
- **Measured, two causes** (`mods/webdock/test/test-background.sh`, real daemon, `pages/tone.html`: a click plays track
  1, a `setTimeout` plays track 2 after 8 s of silence; details in `docs/ux/webdock-engine.md` "The engine's lifecycle"):
  1. *The freeze* — a page hidden in a silence (the player paused, between tracks, the card closed in the gap) was frozen
     at once (QtWebEngine recommends `Frozen`, then `Discarded`) and its track 2 never started. Old `WebPage.qml`: FAIL
     ("track 2 of tone never started while hidden", lifecycle `Frozen`); new: track 2 starts hidden 7.9 s after the hide,
     the page stays `Active`. A page hidden *while it plays* was not frozen at the next gap: the engine does not revisit
     its recommendation when the sound stops — so the freeze needs a hide (or any re-evaluation) in a silence.
  2. *The cap* — past `max_loaded`, the gap's "not audible" report dropped the player from `keep` and the host destroyed
     its page. Old daemon: FAIL ("the gap's silence unloaded the player past the cap (keep ['other'])"); new: kept,
     `awake`, track 2 starts.
  Which of the two the user met is not known (it needs their pins and a real player); both are fixed.
- **Autoplay** is not a cause: a page that had one click may start new `<audio>` elements from a timer later.
- **Not proven on a real music service:** Spotify's web player needs an account (and Widevine), and the sandboxes keep
  agents off the network (K37). The stand-in plays through Chromium's fake audio output.

### Definition of done (W73, background)
- [x] A hidden page that played sound plays its next track after a silent gap longer than the engine's own audible hold:
      `mods/webdock/test/test-background.sh` (real daemon, a `file://` page whose second tone starts from a `setTimeout`),
      failing on the old `WebPage.qml` and passing on the new one.
- [x] The daemon keeps a site past the cap for the grace after its sound, then lets it go, and the idle clock starts only
      after the grace (unit tests); a `background` pin is kept past the cap and holds the engine.
- [x] `background` field (mod.toml, i18n en/ja), the tip and the menu say it, `unload_after`'s help and the pins' help are
      true; MODS.md lists `background` and `awake`.
- [ ] The tip on a background pin's key not shot; Settings' record form shows the switch with the field's label (the
      generic records editor; not shot here).

## The card's size (W73, session 29; I488 (3))
**The user's answer (session 28):** "the size a setting" — Phone, Tablet, Wide, one for all pins, for the bar's card.

### How others size a web page in a panel (from the products; not re-checked online for this card)
- **Firefox responsive design mode / Chrome device toolbar:** presets named after devices with their CSS viewports (Pixel
  7: 412 × 915, iPhone 14: 390 × 844, iPad Mini: 768 × 1024, "Laptop" 1024+); the frame is the viewport, the browser's
  chrome is not counted.
- **MenubarX:** a popover per web app with size presets (phone, tablet, desktop) and a drag handle; the user agent is a
  separate switch.
- **Vivaldi / Edge side panels:** the width per panel (Edge's minimum 376 px), the height the window's.
- **Taken:** three presets named by device class with real devices' CSS viewports less a browser's chrome; the user agent
  stays the pin's own switch (MenubarX).

### Design
- **Setting** `mods.webdock.card_size`: `phone` | `tablet` | `wide`; Settings › Web dock. (W74: a first choice `dock`,
  the edge card's size, is the default now and the document's `card_size` is absent while `dock`: see below.)
- **Sizes (the page's viewport; the well adds its 36 px navigation row):** phone 412 × 760 (a Pixel-class phone's 412 ×
  915 less a mobile browser's bars), tablet 768 × 900 (an iPad Mini's 768 × 1024 less the bars), wide 1024 × 720 (a small
  laptop's 1024 × 768 less a tab strip). The card is the well plus the Stage's padding.
- **When it does not fit:** it shrinks, never off screen. The width is the Stage's (it clamps a panel's `cardWidth` to
  360–1100 px and the output's width less its padding); the height is at most the output less two bar heights and the
  card's margins (W72's clamp). The page reflows to the smaller viewport; nothing is cut off.
- **Meets the view:** the size is the place, the pin's view (mobile / desktop user agent) is what the site is told. A
  phone card with the desktop view shows a desktop site at 412 px; a wide card with the mobile view a stretched mobile
  site. The help text says so.
- **Not the edge card:** the edge card keeps `width` and `large` (its own sizes); the sidebar's well fills the sidebar.
- **A size change** resizes the well and the host's window (the card re-rests): no reload.

### Definition of done (W73, size)
- [x] Setting (mod.toml, i18n en/ja, `card_size` in the document, forced provenance like every mod setting).
- [x] Shots of the three sizes from a bottom bar on nested niri (`mods/webdock/test/shots-card.sh` →
      `mods/webdock/shots/card/card-{phone,tablet,wide}-{light,dark}.png`), each fully on screen. On the 1920 × 1080
      output the tablet's height is clamped (the well about 850 px instead of 936): it shrinks, as designed.
- [ ] Left/right bars and a second output: not shot (the Stage's clamp is per output by construction).

### W74: the edge dock's size by default, a key to switch (session 29)
**User (session 29):** "I prefer the previous webdock card default size that it had in the edge, so make this the
default, other a setting/button to switch."
- **The size it had at the edge, read from the code:** the edge card in its phone size is `width` wide (the setting,
  360–720 px, 412) and `min(2 × width, the usable height − 2 gaps)` tall (`host/WebCard.qml` `phoneW`/`phoneH`,
  `qml/DockWindow.qml` `cardW`/`cardH`); the frame (phone, notebook, plain) is drawn inside that box. The edge's `large`
  is a toggle of the edge card (`webdock.size`), not a size of its own: the bar card follows `width` only, so it does not
  jump when the edge card is made large.
- **The new first choice `dock`** ("As at the edge"), the default: the bar card's **well** (the navigation row and the
  page under it) is the edge card's box, `width` × `2 × width` — 412 × 824 by default, so the page is 412 × 788 under its
  36 px row. The card round it adds the Stage's padding, as for every size. `phone`, `tablet`, `wide` stay (W73's
  viewports). The document publishes `card_size` absent while `dock`, and `phone`, `tablet` or `wide` otherwise.
- **When it does not fit:** W73's clamp, unchanged: the panel is at most the output's height less two bar heights and
  ten paddings (`1080 − 72 − 120 = 888` px on a 1080p output), so the well is at most 840 px there: the default
  412 × 824 well fits on a 1080p output from a bottom or a top bar; a `width` of 720 asks for 1440 and shrinks to the
  clamp, never off screen; the width is the Stage's clamp (360–1100 px and the output).
- **The size key** in the card's row of keys, between the last pin and the settings key: `[pins …] [size] [⚙]`. A
  press (click, Enter, Space) steps to the next size — As at the edge → Phone → Tablet → Wide → As at the edge — and
  writes `card_size` through the daemon (`webdock.card_size {size?}`, no argument steps), one undoable transaction of the
  user layer (`kurashi undo` and Settings' undo take it back). The card resizes and re-rests; the page moves with it, no
  reload; the key keeps the keyboard. Its icon is `resize` (the subset's), the same for every size; the size is in words.
- **States of the key:** *live* — the tip (on a rest or keyboard focus) says "Card size: As at the edge. Press for
  Phone."; *forced* (a layer above the user's sets `card_size`: `forced.card_size` in the document, I91) — the key is
  drawn at half strength, a press does nothing (the daemon refuses it too: `webdock.error.forced`), the tip and the
  accessible description say "Set by {by} in the configuration. Change it there."; *no pin / engine missing / failed*
  — the key stays (the size is the card's, not the page's); *the sidebar* — no key (the sidebar's well fills the pane).
- **Keyboard and a11y:** a Tab stop between the pins and the settings key (forced too: the reason must be reachable),
  Enter or Space presses it; Tab past the settings key still hands the keyboard to the page. Accessible name "Card size:
  <size>", role button; description the next size, or the forced reason.
- **Motion:** the card's own resize (the Stage's), the page cut in once it rests (W72); nothing new runs at rest.

### As built (W74, size)
- Measured on nested niri, 1920 × 1080, bottom bar: the default well is 412 × 824 at y 204 (the panel 872 px, under the
  888 px clamp): it fits whole; Phone 412 × 796, Tablet 768 × 848 and Wide 1024 × 756 are clamped as in W73.
- The key's icon is the subset's `resize` (a dotted box with a corner arrow); the words are in the tip and the name.
- Under the mock (no `webdock.card_size`, row 731) a press is refused silently and nothing changes.

### Definition of done (W74, size)
- [x] `card_size` gains `dock` (first, default) in mod.toml, i18n en/ja (label, help that says how it follows `width`),
      MODS.md, `nix/hm-module.nix`; unit tests: absent while `dock`, named otherwise; the step, a bad size and the
      refusal when forced (`card_size_step`).
- [x] test-card.sh step 1b (sway, 2560 × 1440): the default well is 412 × 824; one press of the size key on screen makes
      it Phone (the document, the well 412 × 796 and the host's window follow, no reload); `kurashi undo` brings the
      default back.
- [x] Shots on nested niri, bottom bar, light and dark (`shots-card.sh` → `mods/webdock/shots/card/card-dock-*`,
      `card-key-tip-*` (the tip on a rest), `card-pressed-*` (after one click on the key: Phone)), whole card on screen.
- [ ] The forced state on screen (inert key, the reason in its tip): not shot — the suites set no forced layer; the
      daemon's refusal is unit-tested and the QML follows `forced.card_size` as the strip's pin toggle does.
- [ ] Keyboard on screen (Tab to the key, Space): not driven by a suite; the key is an IconButton Tab stop before the
      settings key, and step 6's Tab walk to the page (one stop longer now) still passes.

## Which place shows the page (W73, session 29; I488 (4))
**The user's answer (session 28):** "Last opened wins": the place opened most recently shows the pin's page, the others
say "shown elsewhere" with a key to bring it here.

### How others move one live thing between places (from the products; not re-checked online for this card)
- **Spotify Connect:** the device that started playing last plays; every other device shows "Listening on <device>" with
  a tap to play here. The closest model.
- **Browsers' "Move tab to new window" / a tab dragged out:** the tab is in one window; the old window loses it, no reload.
- **Edge sidebar "Open in a tab"** and **Arc's Little Arc "Open in Arc"**: an explicit move to the larger place.
- **Taken:** Spotify Connect's rule and wording: the latest place shows it, the others say where it is and offer "Show
  here" (the browsers' move: no reload).

### Design
- **Three places:** the edge card, the sidebar's dock panel, the bar's card. Each has an *opened* stamp (a counter the
  daemon owns). A place is stamped when it opens on a pin (the edge card turning extended on a pin, or showing another;
  the sidebar's dock panel or the bar card's panel resting for the first time after it was made, `fresh: true` on its
  first `webdock.sidebar` / `webdock.card` report), and when a pin is picked in it (`webdock.open` at the edge,
  `webdock.sidebar_select`, `webdock.card_select`). A move or resize of an open place (the card or the sidebar resting
  again) is no opening and steals nothing.
- **Who shows a pin's page:** of the open places showing that pin, the one with the latest stamp. When it closes, the page
  goes to the next one (the latest of those still open), without a reload. Different pins show live in every place.
- **The document:** each place that shows a pin whose page is elsewhere says where: `elsewhere` at the top level (the edge
  card), `sidebar.elsewhere`, `card.elsewhere` — `"edge"`, `"sidebar"` or `"card"`; absent while the place shows it.
  The host draws a place's page only where the document does not say `elsewhere`; with a daemon that does not publish it
  (the mock), the old order (sidebar, bar card, edge) still decides.
- **"Show here":** the place's notice ("This page is shown in the sidebar" / "in the bar's card" / "at the screen's edge")
  has a key under it, "Show here": a click or Enter sends that place's select action (above), which stamps it. The edge
  card's key is the host's (HostButton), the sidebar's and the bar card's the panel's Notice action.

### States
- **Shown here:** the page. **Shown elsewhere:** the notice with the place's name and "Show here". **The other place
  closes:** the page comes here (it was the next latest). **A view pin:** drawn by the shell in each place at once (no
  page to share). **The engine starting / missing:** the existing notices win over "elsewhere".

### Keyboard and a11y
"Show here" is a Tab stop (the Notice's action key in the shell, a HostButton in the host); Enter or Space presses it.
The notice is text the screen reader reads; the key's name is "Show here".

### Motion and budget
The page leaves one window and appears in the other with the receiving place's own fade (the bar card's 120 ms, the
sidebar's settle, the edge card's cut); no reload, no new process. Nothing runs to decide it: the stamps change on an
action, the document carries the result.

### Definition of done (W73, places)
- [x] Daemon unit tests: latest opened wins among open places, the next one takes it on a close, a re-rest steals nothing.
- [x] test-card.sh step 4: the edge opened after the card takes the page and the card says so; "Show here" pressed in the
      card's well brings it back and the edge card says so; closing the card hands it to the edge; no reload.
- [x] test-sidebar.sh step 2b: the edge opened on the sidebar's pin takes the page, the sidebar says so; "Show here"
      pressed in the sidebar brings it back; no reload.
- [ ] The bar card and the sidebar at once (test-card.sh 4b): opening the bar card closes the sidebar in the shell today,
      so the case is reached only through the daemon (unit test), not on screen.

### W74: does a hover reveal take the page? (session 29)
W73 stamped the edge on every reveal, a hover's too, so resting the pointer on the edge while the bar card or the sidebar
showed the same pin moved the page to the edge — the user only meant to look. **The user's answer (session 29):** "A as
default, B as setting."
- **A (default, `hover_takes_page = true`, W73's behaviour):** any reveal of the edge dock counts as opening it; a hover
  reveal on the pin another place shows takes the page, the other place says "This page is shown at the screen's edge"
  with "Show here".
- **B (`hover_takes_page = false`):** only a deliberate open takes the page — a click or a key on a pin of the strip
  (`webdock.select`), the dock's key or action (`webdock.toggle`, `webdock.open`), "Show here" (`webdock.open`). A
  hover-revealed edge dock ranks below every open place: while another place shows the pin, the edge card says "This page
  is shown in the bar's card" / "in the sidebar" with "Show here"; when no other place shows it, the hover-revealed dock
  shows the page as before (it is the only open place). It never steals by an old stamp: an edge opened on purpose
  earlier, then hidden, does not keep its rank through the next hover reveal.
- **Why A is the default:** the user chose it; and it is the simpler model (Spotify Connect's "the device you touched
  last plays"). B is for a user who rests on the edge to glance at the dock while the page plays in a sidebar that stays open.
- **How others do it:** Spotify Connect moves playback only on a deliberate "play here", never on opening the app
  (B's model); macOS Universal Control / Handoff offer the app on the other device and move it on a click (B); browsers'
  tab previews on hover show a still, never the live tab (B). A is the dock's own, simpler rule.
- **Setting:** `mods.webdock.hover_takes_page` (bool, true), Settings › Web dock, next to "Reveal on hover"; the daemon
  owns it (rule 1); the document does not carry it (the result is in `elsewhere`). Forced like every mod setting.
- **States:** hover reveal, page elsewhere (B): the notice and "Show here" (the existing edge notice); hover reveal, page
  nowhere else (B): the page; deliberate open (A and B): the page; the other place closes while the hover-revealed dock
  is open: the page comes to the edge (it is the next open place); `reopen_last` off: a hover reveal shows the strip only,
  nothing to take.
- **A click on the shown pin in the strip** (B, page elsewhere) keeps its meaning: it puts the card away (W20). "Show
  here" is the way to bring the page.
- **Keyboard and a11y:** unchanged — "Show here" is the host's HostButton (Tab stop, Enter, Space; name "Show here").
- **As built (W74), where a hover meets another place:** while a Stage card is open (the bar's card included) the
  shell's click-away window (`frontend/surfaces/ClickAway.qml`, Top layer, the whole usable area) lies over the edge's
  2 px hover zone, so the pointer cannot reveal the edge dock then: the bar card meets a hover reveal only through the
  daemon (a card opened by `mod.panel.open` from a key while the pointer rests on the edge is not reachable either). The
  case on screen is a sidebar that stays open (`visibility = always` or a hover-revealed column: no catcher) showing the
  pin — that is where the rule matters to the user today. The daemon's rule is the same for all three places.

### Definition of done (W74, places)
- [x] Setting in mod.toml, i18n en/ja (label and help in the user's terms), `nix/hm-module.nix`, MODS.md.
- [x] Unit tests in `dock.rs`: A — a hover reveal takes the page; B — a hover reveal does not, the old-stamp sequence
      (card open, edge opened on purpose, edge hidden, hover reveal) does not steal, a hover reveal with no other place
      shows the page, "Show here" (`webdock.open`), the dock's key and a strip click take it, the card closing hands it
      to the hover-revealed edge.
- [x] test-card.sh step 4c on screen (sway, real daemon): with B, a rest on the right edge while an always-open left
      sidebar shows the pin reveals the dock and the sidebar keeps the page; the edge card says "This page is shown in the
      sidebar"; its "Show here" pressed on screen takes it; with A, a rest takes the page; no reload.
- [ ] The bar card against a hover reveal on screen: not reachable (the click-away window, above). Not shot on niri.

## Round three (W76, session 30; I496, I497)
**User (session 30, items 3b, 3d, 3e):** the card resizable at its edge in the default size, remembered; a pin on the
card that keeps it open while focus is elsewhere (no reserved space); a "+" that adds a site through a search/URL bar
(browse, then pin where you are); a pin's menu with reload, "update the pin to this page", "unpin but keep open"; a click
on the title opens the URL bar; a pin that was not updated goes home to its pinned page after it unloads.

### How others do it (from the products; not re-checked online for this card — the sandbox keeps agents off the net)
- **Arc:** the sidebar's width is dragged at its inner edge (no double-click reset; ⌘S hides it); Little Arc and split
  views resize at their edges with the page following live. "+" / ⌘T opens the command bar *over* the page: typing an
  address loads it, other text searches with the chosen engine (Google by default, set in Settings), and the new tab is
  *temporary* ("Today" tabs are archived after a while) until it is dragged into the pinned section. A pinned tab that
  wandered away shows a "back to pinned URL" affordance; its context menu has "Reset to pinned URL" / "Change pinned URL
  to current" and "Unpin". A click on the address in the toolbar turns it into the field, the URL selected.
- **Zen:** Essentials and pinned tabs; "Reset pinned tab" returns home, "Replace pinned URL with current"; a pinned tab
  that unloads opens at its pinned URL again. The URL bar floats over the page on ⌘T/⌘L (a single field, the
  address selected; Esc dismisses it and drops an empty new tab). The sidebar's width drags at its edge.
- **Edge's sidebar (removed in Edge 149)** and **Opera / Vivaldi panels:** the pane's width drags at its inner edge and is
  remembered per panel (Vivaldi: per panel, Opera: one); a pin icon "Keep the sidebar open" / "Pin panel" keeps the pane
  beside the page instead of overlaying, and the panel's context menu has Reload, "Remove from sidebar"; "+" opens a
  small "add a site" field that takes the current tab's address.
- **Safari:** the address field is the title: a click turns the page's name into the full address, selected; Enter loads,
  Esc puts the name back. Search goes to the engine in Settings (DuckDuckGo is one of the choices).
- **Floorp:** "+" on the panel sidebar asks for a URL and adds a panel; each panel's width is set by a drag, remembered
  per panel (0 = the global width); its context menu: reload, "unload", mute, "change URL to current page", delete.
- **Taken:** Safari's and Arc's title-is-the-field, selected on entry, Esc restores; Arc's *temporary* page from "+"
  until it is pinned where the user is now (a "Pin" key, as Arc's drag into pinned); Zen's and Arc's pinned URL as the
  pin's home (an unloaded pin opens there again) with Arc's / Floorp's "change pinned URL to current"; Edge's / Opera's
  "keep open" pin on the pane; the inner edge drag with a double-click reset and the sidebar's own Ctrl+arrow keys
  (session 30's sidebar width, `frontend/surfaces/Sidebar.qml`), remembered per output like the sidebar's width (I500).

### Design
**1. Resize (3b).** In the edge card's own size (its phone size: not `large`) and in the bar card while `card_size` is
`dock` ("As at the edge"), the card's box is the user's: a remembered `width × height` per output, else `width` × twice
that (W74). The fixed sizes (`large`, and the bar card's phone, tablet, wide) do not resize and draw no grip.
- **Where:** an 8 px grip along each free edge of the card — the edge away from the strip (the card's width at a side
  edge, its height at a top or bottom edge) and, along the strip, the two ends (the card is centred there, so an end moves
  by the pointer and the other end by as much: both ends follow). In the bar's card: the card's edge away from the bar
  (its height) and the side away from the nearer screen edge (its width), in the page's window (the host draws the well).
  The edge lights in `accent` while the pointer is on it or it is dragged; the cursor is the split cursor.
- **Live:** the page follows the drag 1:1 (the window holds the larger size while it is dragged; nothing animates); the
  size is written on release (one undo step). A press that did not move writes nothing; a double click resets (the row
  goes, the default returns). Ctrl+Left/Right (width) and Ctrl+Up/Down (height), 10 px a press, while the card's own
  chrome (its header, a grip) has the keyboard — never while the page has it (word jumps in a text field); written after a
  short pause, so a run of presses is one undo step, as the sidebar's.
- **Remembered** in a new records setting `mods.webdock.sizes` (`output`, `width`, `height`; unique by output): one row per
  output, written by the daemon (`webdock.resize {output, width?, height?}`; no size removes the row), shown and editable in
  Settings › Web dock like the pins. The document carries `sizes {<output>: {width, height}}` (absent while empty).
- **Within the output:** at least 300 × 300; at most the usable area less the strip and a gap at each end (edge), the
  Stage's card limit (bar card: `bar.card_max_*`, the Stage clamps; the well never runs off screen). A remembered size
  larger than the output it is read on (another monitor's row, a changed resolution) is clamped when drawn, not rewritten.
- **Forced** (`forced.sizes`): the grips are inert, drawn at half strength, and their accessible description says who sets
  it (I91); the daemon refuses `webdock.resize` too (`webdock.error.forced`).

**2. Keep open (3d).** A `push_pin` key in the card's toolbar (the edge card's header and the phone's bottom bar; the
shell's own cards' title row; the bar card's navigation row).
- **At the edge:** the dock's `pinned` (`webdock.pin`): lit (`color.selected`, filled glyph) while pinned; the dock stays
  open while focus is elsewhere, reserving nothing (`reserve` stays its own setting). Its name is "Keep the dock open" or
  "Let the dock hide" (the strip's own words), role button, checkable, checked while pinned.
- **In the bar's card:** "Keep open at the edge": the page moves to the edge dock (`webdock.open`), the dock is pinned
  (`webdock.pin {on: true}`) and the bar card closes — one place for "kept open", the edge, as the card asks. The key
  shows the edge it goes to (`left_panel_open` / `right_panel_open` / `dock_to_bottom`), beside "Show at the edge".
- **Forced** `pinned`: the key is inert with the reason in its description; in the bar card it still moves the page
  (the edge then follows the forced value).

**3. Add and edit sites (3e).**
- **"+"** at the end of the pins (the strip's existing add control — the old add form stays behind the empty dock's "Add
  a site"; the sidebar's and the bar card's row gain a "+" key before the size and settings keys) opens a *temporary page* in that place
  (`webdock.browse {place}`): the card shows it with the address field where the title is, focused and empty, the page
  area saying "Type an address or search". Enter: text that is an address loads it (`https`, `http`, `file`; a bare
  `example.com` or `localhost:8080` gets `https://` / `http://`), any other text searches with `mods.webdock.search` (a
  URL with `{q}`; default DuckDuckGo, `https://duckduckgo.com/?q={q}`) — the daemon decides (`webdock.go {pin, text}` →
  `{url}`), the host loads it. `javascript:`, `data:` and other schemes are searched as text, never loaded.
- **The temporary page** is a pin the daemon serves but the settings do not hold (`temporary: true` in the document; not
  drawn in the strip or the rows). It has its own page and the profile `browse` (shared by everything browsed from "+":
  a browser's default profile). A **Pin** key (`push_pin` with "Pin") in its toolbar pins the page where the user is now
  (`webdock.add {url, title, from}`): the new pin takes that page — the same page, no reload (the host renames it; the
  document says `was` on the new pin) — and the profile `browse`; it appears at the end of the strip.
- **Dropped** when Esc is pressed in its empty field, when its card closes (the edge card's ×, Esc on its chrome, the bar
  card's Esc), when the place picks another pin, or when "+" opens another one; a hover hide keeps it (the next reveal
  shows it again, as any shown pin). Where the shell cannot tell a close from a move (the bar card closed by a click
  away, the sidebar closed) it stays that place's page until another pin is picked or the dock's rules unload it.
- **The title is the field:** a click on the card's title (the edge card's header and pill, the bar card's and the
  sidebar's navigation row) turns it into the same field holding the page's address, selected; Enter goes there in the
  same page (`webdock.go`): the pin stays at its address — its *home* (W20's home key returns there; after it unloads it
  opens there again). Esc or a click elsewhere puts the title back.
- **The pin's menu** (`PinMenu.qml`, the strip's right click / menu key) gains, after what it had (move up, move down,
  remove, close): **Reload** (`webdock.reload {pin}`: the loaded page reloads; inert while not loaded), **Update pin to
  this page** (`webdock.retarget {pin}` with the page's current address, which the host reports as `at` on the pin while
  it differs from the target; inert while the page is at home or not loaded), **Unpin but keep open**
  (`webdock.unpin {pin}`: the row goes at once — one undo step, and `kurashi undo` brings the pin back with its page — and
  the page stays as a temporary page until the dock's rules unload it). A forced list keeps the three inert with the
  reason, as the menu's other edits; Reload stays live (it changes nothing that is configured).

### States
- **Resize:** default (no row), remembered (a row for this output), dragging (accent edge, live), forced (inert grips),
  a fixed size (no grips), a remembered size too large for this output (clamped).
- **Keep open:** off, on (lit), forced (inert), bar card (moves to the edge).
- **Temporary page:** empty field ("Type an address or search"), loading (the progress line), loaded (the Pin key),
  load error (the card's error state: an address that does not answer, a search while offline), the engine missing or
  failed (the place's own notice: "+" still opens the field, Enter is refused with the reason).
- **Title field:** editing (the address selected), refused (an empty text does nothing; the field stays).
- **Menu entries:** live, inert (not loaded / at home / forced).

### Keyboard and a11y
- "+" is a Tab stop in the strip and the rows (Enter, Space); the field takes the keyboard when it opens (the host's window
  holds it while the field is empty — on niri a relaxed pulse handed the keys back to the strip "+" was clicked on);
  Enter goes, Esc cancels (and drops an empty temporary page). Alt+D (a browser's own key for its address) opens the field
  in the edge card; Ctrl+L still enters the header (test-host's walk).
- The grips: role Grip, name "Resize the card", description the size and the keys (or the forced reason); the keys
  work on the card's chrome. The pin key: role button, checkable, checked while pinned. The field: role EditableText,
  name "Address or search". The Pin key: "Pin this page".

### Motion, outputs, budget
- Motion: the drag follows 1:1 (no animation, as the card asks); the field replaces the title in place (no motion); the
  menu is the existing side panel. Reduced motion changes nothing here.
- Outputs: the size row is per output (the output the card is on); a card on another output reads its own row or the
  default. HiDPI: logical px.
- Ma: nothing runs at rest — the grips are hover handlers; a drag writes once; the host reports a page's address only
  when it changes (`webdock.host.url`); a temporary page costs what a pin's page costs and unloads by the same rules.

### As built (W76)
- **Temporary pages are pins the daemon serves** (`temps`, appended to the rows' pins; a row of the same id wins, so
  `kurashi undo` of an unpin gives the page back to its pin). A "+" page is `browse-<n>`, profile `browse`, target "" until
  Enter; the host starts its engine at `about:blank` (an engine never given an address did not load the first one given
  later, measured on niri), so Back after the first page reaches a blank page (known, cosmetic).
- **Pin keeps the page:** `webdock.add {from}` writes the row with the temporary page's profile, applies it and adopts:
  the places, the loaded state and the shown order move to the new id and the pin says `was`; the host renames the page
  (`ListModel.setProperty`) and, until then, resolves the old id to the new pin (`pinById`), so the page's address and
  view never flicker through "none" (a view flicker reloaded the page: measured, fixed).
- **The keyboard for the empty field:** the host's window holds the keyboard exclusively while the field is empty (edge
  card and sidebar/bar card windows); on Enter it relaxes to on demand.
- **A typed path** (`/home/…/x.html`) is a local file (`file://`), as in a browser's address bar; the test types paths
  (the virtual keyboard's `:` did not reach the host's field).
- **The pin's menu over a site's card:** the menu opened under the host's card window (both on the Top layer, the host's
  mapped later); the card closes first now (`webdock.collapse`), the page stays loaded.
- **The bar card's resize** follows the pointer in the page's window 1:1 (the window grows on its free sides), and the
  size is written on release; the Stage then lays the card out at the new size and the page re-rests there (the page is
  cut for the Stage's 160 ms settle — the Stage withdraws the placement while the card resizes, CONTRACT-CHANGE 741). The
  Stage's limit (`bar.card_max_*`) bounds it: a box larger than the card holds is remembered and shown clamped.
- **The Stage's card limit (I504)** put the default 824 px well in a scroll view, where no page can show (the placement is
  withdrawn while a scroll view clips the panel): on this branch `test-card.sh` failed at step 1 before W76. The panel
  now asks for no more than the card holds (`stageRoom`, a stand-in: CONTRACT-CHANGE 741); test-card's step 1b reads the
  limited well (412 × 638 on 2560 × 1440 in washi).
- **B117** (the dock coming out closes an open card) changed test-card's step 4: the card closes when the edge opens; the
  card opened again takes the page back (last opened wins), and the two "Show here" keys move it.

### Definition of done (W76)
- [x] Edge card: drag the free edge → the card follows, the size is written for the output on release (test-card 6e: 60 px
      wider → `sizes[HEADLESS-1]` 472 × 824); Ctrl+Left twice on the chrome → 20 px more, one write. `large` draws no grip
      (`resizable` needs the phone size; by construction, not driven).
- [ ] A double click on the grip resets: built (`onDoubleClicked` → `webdock.resize {output}`), but the virtual pointer's
      two clicks were not seen as a double click in the suite; the reset is driven by the action there.
- [x] Bar card (`dock` size): the grip at the well's foot (a top bar) up 60 px writes the box, the card's well follows, no
      reload (test-card 6c); the box is the edge card's (one row per output). The page follows the drag 1:1 in its own
      window; the card catches up on release (the Stage withdraws the placement while it resizes, CONTRACT-CHANGE 741).
- [x] Keep-open key: lit while pinned, a press lets the dock hide (test-card 6e, the host's log); name "Keep the dock open" /
      "Let the dock hide", checkable, checked while pinned. In the bar card "Keep open at the edge" moves the page to the
      edge, pinned, and closes the card (test-card 6c).
- [ ] The forced states (inert grips, inert keep key with the reason): built from `forced.sizes` / `forced.pinned`, not shot.
- [x] "+" → field (focused) → a local test page loads → Pin → the pin `o` is in `mods.webdock.pins` (profile `browse`), the
      host renames the page, no new load (test-card 6c); "+" in the sidebar, Esc in the empty field drops it
      (test-sidebar 2c).
- [x] Title click → field with the address → Enter goes there; the pin's target is unchanged, `at` reports the page's
      address (test-card 6c).
- [x] Menu: Reload (the counter, a new load report), Update pin to this page (the target changes, `at` clears), Unpin but
      keep open (the row goes, the page stays loaded), `kurashi undo` brings the pin back (test-card 6d, keyboard).
- [x] Daemon unit tests: resolve (address / path / search / refused schemes), the search setting, temporary pages
      (browse, go, drop, the card's close, adopt), unpin keeps the page and undo gives it back, the menu's reload and the
      page's address, the sizes rows (`cargo test -p kurashi-mod-webdock`: 53 + 24).
- [x] Shots on nested niri, light and dark (`mods/webdock/test/shots-round3.sh` → `mods/webdock/shots/round3/`):
      round3-resize (a remembered box, the grip lit), round3-keep (the key lit), round3-field (empty), round3-typed,
      round3-temp (loaded, Pin), round3-menu (the three entries), round3-card (the bar card's "+" page: the field in the
      navigation row, the keep-open key), round3-cardgrip.
- [ ] Left / right bars, a second output, HiDPI: per output by construction (the row's key is the output's name), not
      measured.

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
| compact / extended | click a pin P (`webdock.select`) | extended(P), `shown` = P |
| extended(P) | click P again | compact, `shown` cleared (P stays loaded) |
| extended(P) | click Q | extended(Q), `shown` = Q |
| compact / extended | pointer leaves strip + card (24 px hysteresis) ≥ hide delay (400 ms), not pinned, not engaged | hidden (`shown` kept) |
| engaged | keyboard focus leaves (click elsewhere) | as a pointer leave: hide after 400 ms unless pinned or hovered |
| shown | keybind / bar widget | hidden |
| extended / compact | Escape on the dock's chrome (`webdock.back`) | compact / hidden (pinned: stays compact) |
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
  `large` 90 % of the output (setting 50..95 %), full available height. **Header** (36 px): back, forward, title
  (page title or pin name), **home** (only once the page left the pin's address), reload, **mobile/desktop** segmented
  toggle (sites only), phone/large, overflow menu (open in browser, **replace pin with this page** — shown with home),
  collapse. Body: the page or the view.
- Pinned + *reserve space* (setting, off): the strip claims its width as an exclusive zone; the card always overlays.
- **Reserve on a top or bottom edge (known limit, I191; CONTRACT-CHANGE 432):** the layer shell ignores an exclusive
  zone when both ends of a surface are anchored, so a pinned strip that reserves keeps a single-end anchor, and the card
  is sized to the output's height instead of the usable one (I100's span is off in that mode). On a bottom edge the card's
  top covers the top bar; on a top edge its far end runs past the output's bottom (about 20 px at 1440 px with a 36 px
  bar). Shown by the large phase's notes (`mods/webdock/shots/dock-large-{top,bottom}-reserved.png`). The fix needs the
  output's usable area from the shell or the compositor; the app dock derives its own from the bar config
  (`frontend/surfaces/Dock.qml`). Until then the dock is right without reserve, and with reserve on the side edges.

### Sites
- **Mobile view** (default for new pins: setting `default_view`): mobile user agent + phone width; **desktop view**:
  the engine's own user agent; switching reloads the page and is saved on the pin (undoable). Desktop at phone width
  shows a hint chip "Desktop pages may need the large size". Some sites ignore the user agent — the toggle says
  "view: mobile" (what was sent), not "the site is mobile".
- **Sign-in:** each pin has its own profile (cookies, storage) unless pins share a named profile ("google" for Mail +
  Calendar). Popups with an opener (sign-in windows) open as a sheet inside the card; links for a new tab or window load
  in the pin's own view (`new_tabs = dock`, default; Back returns) or go to the browser (`new_tabs = browser`). If a site refuses sign-in in an embedded engine, the card says so and offers "open in browser" — no
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
- **Forced/inert** (Nix-set pins or edge): provenance chips; the strip's pin toggle disabled with the reason. The reason is a
  tip beside the toggle on a rest or on keyboard focus (`Tip.qml`, copy `webdock.dock.forced.tip`), and the toggle's
  accessible description says the same (W38). Shots `mods/webdock/shots/dock-forced-tip*.png`. The source is set by the
  daemon's provenance feed (CONTRACT-CHANGE 430, 431); until it lands the tip shows in the mock only.
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
- [ ] niri: verified in a nested niri (layer surfaces, on-demand keyboard focus) before "UX ✅". **W38: not met.** In a nested
      niri 26.04 inside the sandbox the dock's large card geometry passes (I100's span), but no shell surface is drawn in the
      captures, and the dock's layer surface reports keyboard interactivity none, so I98's keys and the Tab order fail there
      (they pass on sway with the same tree). Blocker and the recipe: CONTRACT-CHANGE 434.
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
