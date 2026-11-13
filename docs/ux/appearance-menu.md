# Appearance menu — UX brief (session 33, card W84)
Status: brief written with the implementation (W84); the user chose prototype C (an icon rail on the left, a pane on the
right) from three (scratchpad `protoshots/shots/proto-{a,b,c}-*.png`).

## Job
"A clean and simple menu, not the whole settings page." The few choices that change how the desktop *looks* — the
picture, the colours, the style and its material, the motion, the effects, the fonts — one keystroke away from the
launcher, each shown live before it counts, each one step to undo. Settings › Appearance stays the place for everything;
this menu holds the essentials and says "More in Settings…" for the rest.

It opens two ways (a setting, `launcher.appearance_opens`): **in the launcher** (typing "wallpaper", "theme", "colours"…
offers it; Enter turns the launcher's card into the menu, Esc goes back to the search) or **as its own card** (a Stage
panel `appearance:<pane>`, on the output it was asked on; the same component).

## References (what others do, cited)
- **macOS** (System Settings › Wallpaper, › Appearance): Wallpaper is a page of large thumbnails grouped by source
  (Dynamic, Landscapes, Photos, "Add Folder…" with a folder list and a remove button), a big preview of the current
  picture on top, "Auto-Rotate" with an interval and "Shuffle" beside it. Appearance is three pictured choices (Light,
  Dark, Auto) and an accent row of dots; every choice applies at once, no Apply button.
- **GNOME** (Settings › Appearance since 42): one page — Style (Default / Dark as two pictured previews of the desktop
  in that style), the accent colours (47+: a row of nine dots), then Background (a grid, "Add Picture…"). The preview
  *is* the choice: the tile is a miniature desktop. No undo; a choice applies at once.
- **KDE Plasma** (Quick Settings → Global Theme; Desktop › Configure Desktop and Wallpaper): the wallpaper dialog has a
  live preview of the desktop that follows the selection, then *Apply* / *OK* / *Cancel* — nothing changes until Apply;
  "Get New Wallpapers…" for online sources; a slideshow page with folders (add/remove) and an interval. Plasma Style and
  Colours are separate KCMs with pictured tiles and Apply.
- **Windows 11** (Settings › Personalization): a live preview of the desktop at the top of the page ("preview of your
  desktop with the current theme"), then Background (Picture / Solid colour / Slideshow / Spotlight; "Recent images" as
  five thumbnails, "Browse photos"), Colours (Light/Dark/Custom, an accent grid, "Automatic" from the wallpaper),
  Themes. Choices apply at once.
- **Caelestia** (`modules/launcher`): the launcher's `>wallpaper` mode — a horizontal strip of thumbnails in the
  launcher's own card, arrows move, Enter sets, the scheme follows the picture (`>scheme` lists schemes the same way,
  `>variant` the Material variants). A menu *inside* the launcher — the model for our launcher host.
- **end-4/ii** (`modules/ii/wallpaperSelector`, `overview`): a wallpaper grid as an overlay over the screen with folder
  navigation (a breadcrumb, Backspace up), search; the colours follow through matugen; dark/light in its quick toggles.
- **DankMaterialShell** (`Modules/Settings/WallpaperTab`, `ThemeColorsTab`): the wallpaper as a big preview with ‹ ›
  arrows and a folder browser, per-monitor; "Theme colour: Dynamic (from wallpaper) / static palettes" as swatch tiles;
  light/dark one switch; Matugen variants as chips.
- **Noctalia** (`Modules/Panels/Wallpaper`, `Settings/Tabs/ColorScheme`): a panel with a search field, Local and
  Wallhaven as sources (Wallhaven: categories, purity, sorting, its API key in settings), the folder shown with a
  button to change it; colour schemes as tiles of dots; "Use wallpaper colours" switch; dark mode as one switch.

**Taken:** Caelestia's menu in the launcher; Noctalia's Local | Wallhaven sources with the folder shown and changeable
right there; Windows' and KDE's live desktop preview (as a section the user can switch off — the user: "I don't know how
I feel about it before trying it"); GNOME's and Windows' pictured light/dark and dots for palettes; macOS' "Add Folder"
list with a remove button and Auto-Rotate + Shuffle side by side; KDE's "nothing counts until you keep it", made
keyboard-quick (Enter keeps, Esc puts back) instead of three buttons. **Not taken:** a separate Apply/OK/Cancel triple
(KDE); one long page (GNOME, B prototype — the user chose the rail); online sources beyond those the wallpaper mod
configures; per-output pictures here (the mod's own picker keeps targets).

## Design
### Layout (prototype C)
- **Rail** (left, 76 px): seven entries, icon over a caption — Wallpaper (`wallpaper`), Colours (`palette`), Style
  (`style`), Material (`texture`), Motion (`animation`), Effects (`auto_awesome`), Fonts (`text_fields`). The chosen one
  sits on the `selected` tone; the highlight springs between entries (motion profile).
- **Pane** (right): a heading with the pane's name and, at its end, "More in Settings…" (opens Settings on that page, the
  launcher or card closes first). Under it the **live preview** section (when on), then the pane's controls in a column
  that scrolls (ScrollEdge, KineticWheel).
- **Keep bar** (pane foot, only while something is previewed): "Previewing n changes — ↵ Keep · Esc Put back" with the
  two as buttons (Keep is the one accent fill). Mouse users keep with the button.
- Width 760 in the launcher (its card widens while the menu is shown; the clipboard's two columns are untouched), the
  Stage card asks for 760 too (`cardWidth`). Height 560 (the launcher card's rows are replaced, not added to).

### The live preview (switchable)
A miniature of the desktop, 16:5 at the pane's width: the wallpaper (the selected picture in the Wallpaper pane, before
Enter; the current one elsewhere) with a bar strip and a small card in the colours in effect — `theme` tokens (accent,
surface, on_surface, secondary), so a previewed palette, scheme or style shows there and on the real shell at once. In
the Wallpaper pane, when the colours follow the wallpaper (`theme.colors.palette = wallpaper`), the bar and card take the
selected picture's dry-run roles (`wallpaper.preview`, the picker's machinery) — so a picture's colours show before it
is set. Caption: "Preview — ↵ keeps, Esc puts back" ("↵ sets the picture" on Wallpaper). An eye button at its corner
(a Tab stop) switches it off
(`launcher.appearance_preview = false`, a config key; one apply, not part of the preview session); while off, the pane
heading carries a small "Show preview" button instead. Ma: the preview loads the picture at 480 px once per change.

### Panes (what each holds — the schema decides, rule 3)
Every config row a pane shows carries `appearance = "<pane>"` in the schema (`#[kurashi(appearance = "colours")]`,
repeatable, published on the `schema.settings` row like `modules`); a pane draws its marked rows in schema order by
control kind: a choice → a row of chips (a radio group: Left/Right move *and preview*); a choice whose options the theme
previews (`choices_from` = a list of `theme.previews`: palettes, styles, looks) → a strip of pictured tiles, each in its
own tokens (a palette as five dots, a style or look as a small card), scrolling sideways so the pane's other rows stay in
view, the chosen one kept in view; a toggle → a switch row with its help; a range → a slider with its value; a list
(`pick_list`) → toggle chips; a font → its families in their own face (Space opens Settings on that key: the installed
fonts are a long list). Rows the schema marks `advanced` are not shown.
- **Wallpaper** — the wallpaper mod's compact picker (`mods/wallpaper/qml/Picker.qml`, loaded beside its `Panel.qml`
  from the `mods` document, so it exists only while the mod is on): the **sources** — Local, Wallhaven (while
  `mods.wallpaper.wallhaven` is on) — with the count, then for Local the **folders** (each a chip with its path, middle
  elided, and ×; Delete on a focused chip removes it; a click or Space browses that folder alone; "+ Add folder" opens a
  path field: `~/…` or absolute, Enter adds, the daemon refuses a non-path), search, the grid (4 columns, three rows,
  its own scroll; a dot marks a picture on a screen now), and one row: Shuffle now · Rotate every [Off/15/30/60 min, and
  the configured one] · the order (In order / Shuffled, while rotating). Wallhaven: the mod's `Wallhaven.qml`, unchanged.
  Below the picker, the recolouring rows the schema marks `wallpaper` (`theme.colors.extraction`,
  `theme.colors.wallpaper_grade.enabled`). The folders and rotation are the mod's library settings, applied at once
  (not part of the preview session, which is for the look).
- **Colours** — the palettes (tiles; "From wallpaper" among them as a plain tile), the mode (`theme.colors.scheme`:
  Auto / From wallpaper / Dark / Light), the recolouring, contrast, OLED black, and "Apps follow the colours"
  (`theme.export`: one toggle chip per target the daemon offers).
- **Style** — the styles and looks as tiles (`theme.previews`), corners, density.
- **Material** — colour flow, texture, the material (solid / translucent), its opacity, blur, scroll edges. (Prototype C
  had pictured Paper/Glass/Solid tiles; they would be a hand mapping of three keys, so the rows stand on their own.)
- **Motion** — the profile (`theme.motion.profile`, the packs the daemon offers), speed, how content comes in.
- **Effects** — the gradient, dynamic media colour, light, the text effect and how text comes in, the pointer's decoration.
- **Fonts** — the font mix, the interface font, the monospace font, the text scale (the Japanese font is `advanced`).

### Preview session (one undo step, Esc puts back)
A style or a look is an action, not a value (`theme.style.apply` / `theme.look.apply` reset the kind's keys, K53 — as
Settings' pickPack applies them): a pick is a step of its own, the next pick undoes it while it is still the last change,
Esc undoes it, Enter keeps it; a key session open is kept first.

Settings' machinery (`settings/core/Changes.qml`) ported to the shell's Store (`components/appearance/PreviewSession.qml`):
the session holds every key changed in this visit; each change undoes the session's last transaction (only when no one
committed since: the `config` document's `history.rev`) and applies the whole set as **one** `apply` — the visit is one
undo step. **Enter** keeps it, **Esc** puts it back (undo, or — when another change came in between — a `set`/`reset`
of the starting values), and so does every other way out (the launcher closing, the card closing, a click away): a value
that was not kept is not left in effect (Shōjiki). A wallpaper is an action, not config: Enter in the grid sets it at once
(the mod's `wallpaper.set`, with the theme image), as the mod's picker does.

### Keyboard
- Rail: Up/Down move and show the pane; Ctrl+1…7 jump (from anywhere in the menu); Tab or Right enters the pane.
- Pane: Tab / Shift+Tab — and Up/Down where the control does not use them — move between controls (back from the first
  reaches the rail); in a choice row Left/Right move
  *and preview*; Space or a click chooses; Enter keeps the session (in the wallpaper grid: sets the picture); Esc puts
  back when something is previewed, else (launcher) goes back to the search with the query kept, (card) closes.
- Every control has an accessible name (the schema label) and description (its help); choice rows are radio groups
  (`Accessible.RadioButton`, checked); the rail is a `PageTabList`, its entries `PageTab`s.

### Motion (DESIGN-SYSTEM §9)
Pane change: the old pane fades out over `quickMs`, the new one fades in and rises 8 px over `stdMs` on the enter curve;
the rail's highlight springs to its entry. The launcher's card grows to the menu's size as its rows did (the morph and
the slide are the launcher's own). Reduce motion / profile `none`: cuts.

### Inert rows (rule 2)
A row the daemon holds inert stays visible, greyed, with its reason under it (forced by accessibility, needs a key —
"Needs: Blur on", a capability the compositor lacks), as the module menu shows them (`inertWhy`). The Wallpaper pane
without the mod says "Pictures need the wallpaper mod" with a button that enables it (`mod.enable {id: "wallpaper"}`).

## States
- **No wallpaper mod** (off or not loaded): the Wallpaper pane shows the note and "Turn on the wallpaper mod"; the live
  preview shows the theme's surface with the bar and card (no picture); Colours keeps "From wallpaper" (a choice the
  daemon offers; it judges it).
- **Wallpaper backend missing** (awww/swww not installed): the mod's own empty state ("Wallpapers need awww or swww")
  inside the pane; folders and rotation still editable.
- **No Wallhaven key / Wallhaven off**: the Wallhaven source is listed only while `mods.wallpaper.wallhaven` is on; without
  a key Wallhaven works SFW without one (its API allows it) — the mod's tab says so.
- **Offline**: the Wallhaven tab's own offline state ("Wallhaven cannot be reached", Retry).
- **Empty folder**: "No images yet — No pictures in <path>" beside "+ Add folder". **Missing folder**: the chip is struck,
  with a warning mark and "not found" (its × removes it); the grid says the folder is missing and how to fix it.
- **No folders at all**: "Add a folder of pictures — choose + Add folder and type its path".
- **Loading** (documents not yet there): "Reading the settings…" in the pane; the picker says "Looking at the backend…".
- **Daemon refuses a change**: the row says why (the apply's error code, translated) and the session drops that step.
- **Card host unavailable** (a daemon without `appearance.open`): the menu opens in the launcher instead, with one line
  "Opened here: a card of its own needs a newer kurashid".
- **Previewing**: the keep bar, and the rail entry of each pane with a pending change carries a dot.

## Fit
- **Launcher**: a mode beside the prefix modes, not a prefix — words find it (the daemon's rows, `appearance:<pane>`;
  CONTRACT-CHANGE row 790). The field stays on top showing the query; the clipboard's two columns are untouched.
  Start-menu looks (`decor.start`): the menu is shown at the menu's width inside the start menu's chrome (the card widens
  to 760 px); the system-menu form and the start grid step aside while it is shown.
- **Stage**: `appearance:<pane>` is one more panel kind (row 791: `appearance.open {pane?, output?}`, `runtime.ui.panel`),
  one at a time with the others, click-away and polkit as they are; a quick tile and a bar module open it (row 792).
- **Settings**: "More in Settings…" opens the page; the keys are the same keys (one schema), so both show the same
  values and provenance.
- **Wallpaper mod**: its own picker (`mod:wallpaper:wallpaper`) is unchanged; the menu reuses its Wallhaven tab and the
  same actions. The mod's settings the pane shows (folders, rotation, Wallhaven) are named in its own QML, as its picker
  names them (a manifest marker is asked for in row 793).

## Budget
Closed: nothing — no Watch, no Loader, no timer (the launcher's mode and the Stage's view are made only while shown).
Open: `schema.settings`, `config`, `theme` (always watched by the shell), `theme.previews` only in Colours and Style
(it starts the daemon's swatch work — Settings' cost), `mod.wallpaper` while the menu is open (the preview's picture;
the mod's service runs while the mod is on, watching starts nothing); thumbnails only for visible cells (the mod's
paging). First open of the menu ≤ 100 ms to a frame (the launcher's cold-open budget) — not measured yet.

## Definition of done
- [ ] UX brief (this file) before the code.
- [ ] Schema: `appearance = "<pane>"` (repeatable) on the rows each pane shows; published on `schema.settings` rows;
  goldens; `launcher.appearance_opens` and `launcher.appearance_preview` with en + ja labels.
- [ ] One component (`frontend/components/appearance/AppearanceMenu.qml`) used by both hosts.
- [ ] Launcher: "wallpaper" / "theme" / "colours" (and ja) offer the menu; Enter shows it on that pane; Esc back to the
  search; the clipboard mode unchanged.
- [ ] Card: a Stage panel `appearance:<pane>` on the output asked (needs rows 790–792 in the daemon and shell.qml).
- [ ] Wallpaper pane: Local's folder shows and can be added/removed; a picture applies (`mod.wallpaper` shows it);
  Wallhaven listed when on; rotation and shuffle.
- [ ] Colours: light/dark switches live (the `theme` document) and Esc puts it back; Enter keeps as one undo step.
- [ ] The preview section toggles (config key) and its absence leaves the panes whole.
- [ ] Keyboard path end to end; a11y names; inert rows say why; motion from the profile.
- [ ] States drawn and shot: no wallpaper mod, empty folder, missing folder, previewing, preview off.
- [ ] `frontend/test-appearance-menu.sh` on nested niri; shots light and dark in two looks.
