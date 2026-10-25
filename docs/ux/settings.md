# Settings app, mods and pickers — UX brief
Status: agreed (lead, session 5) — functional base merged (W9-config-profiles, W10-settings); UX pass: card W13-settings-ux

## Job
Change anything the shell does, understand *why* a value is what it is, and undo freely. Kurashi's edge over every
other shell is provenance (K21): each row knows its source, what overrides it, and why a control is inert. The UI
must make that visible without becoming noisy, and treat mods as first-class citizens (K25).

## References (research 2026-10-09, cited)
- **VS Code settings**: modified-bar on changed rows, `@modified` filter, per-setting gear (Reset, Copy setting link),
  `@haspolicy` and a policy diagnostics view (current vs enforced), profiles with preview and review-on-import,
  theme picker previews on Up/Down and commits on Enter.
- **KDE System Settings**: opt-in "Highlight changed settings"; kiosk-locked controls hidden or pinned (pitfall:
  inconsistent); Get New Stuff; defaults without preview (bug 145741).
- **GNOME**: panel-level search only (per-setting search requested, gitlab #2150); dconf-locked extension dimmed but
  still toggleable via CLI (issue 6045 — "dimmed is not enforced"); HIG: drop-downs for long lists, never < 3 items.
- **Firefox policies**: locked prefs; "managed by your organization" banner (also for NixOS-declared prefs) — generic
  banners hide the source (pitfall); add-on updates that add permissions are held for approval.
- **COSMIC design**: one scrollable search list across panels, "Related settings" cross-links.
- **DMS / Noctalia**: plugin scan + toggle + restart; plugins run with full session permissions.
- **WAI-ARIA APG**: switch pattern, select-only combobox, grid; WCAG 2.5.7 (no drag-only), 1.4.1 (no colour only).

## Beyond the basic job — what Settings can become
1. **Provenance you can read**: each row's chip names the layer ("Kanso profile", "you", "Nix: programs.kurashi.
   settings.theme.palette", "accessibility"); hovering shows the full `cfg.why` stack; inert rows say why in one
   line with a link to the controlling key ("Controlled by High contrast → open").
2. **"Changed" view**: a sidebar filter "Changed from default" listing every user/profile-set key across pages,
   with per-key and per-page reset that *previews the diff* first (dry-run apply exists).
3. **Live preview for visual keys**: palette, scheme, fonts, radius, bar edge preview on focus (Up/Down) and
   commit on Enter as one undo step; Esc reverts (VS Code pattern, plus Esc).
4. **Search that lands on the row**: results show breadcrumb "Appearance › Colours › Palette", Enter scrolls and
   flashes the row; deep links `kurashi settings <key>` (CLI) open it; "Copy setting link".
5. **Mods as citizens**: a mod page shows on/off first, then "Running now: …", capabilities and cost, its settings,
   its contributions (slots, faces, widgets — "Adds: weather in the clock view, a bar widget") with jump links to
   where they appear; "Changed on disk: Reload" when a manifest changes; enable refused → the error in the page.
6. **Profiles as stories**: header "Kanso · 3 settings differ — Show / Save / Revert"; profile cards with origin
   (bundled, yours, imported); load = preview diff → apply; export drops machine-local keys; import reviews first;
   Nix-forced keys listed as "not applied: set by Nix".
7. **Related settings**: footer links between pages that interact (Island ↔ Notifications ↔ Quick settings).

## Design
- Window: sidebar (search on top, core + mod pages alphabetical with state marks, then "Changed", Mods, Profiles) +
  page. Rows: label/help left, control right, provenance chip + reset under the control.
- Controls: 2 options → switch; 3–5 visible → segmented; long or dynamic → dropdown (select-only combobox: type-ahead,
  greyed options with reason as a second line, Esc cancels); ordered subsets → **vertical** pick list (rows with
  move up/down buttons, Alt+Up/Down, remove, "Add…" dropdown; one provenance for the list; never horizontal).
- Mod page header: name, on/off switch (inert + "Set by Nix" when forced), status line, description, "Adds:" list.
- Focus ring visible on every control state (the ON-switch issue fixed in the shell's ToggleSwitch applies here).

## States
default · profile · user · nix-forced (read-only, no reset, names the option) · inert (requires / mods.disabled /
restart pending / choice unavailable) · invalid input (inline, keeps the typed text) · preview (uncommitted) ·
undo/redo after external change (CLI) · empty search (names its scope) · mod: available / loaded-off / on / running
/ enable failed / invalid / removed while on · ja copy lengths.

## Fit and constraints
Settings is a thin view over `schema.settings`, `config`, `mods` (rule 1); all diffs and previews come from the
daemon (dry-run apply, `cfg.why`). New contract needs: `cfg.why` in Settings already exists; "changed" listing can be
derived from the `config` doc's provenance (no new contract); deep link = an argument to the settings app.

## Definition of done
- [ ] provenance chip names the layer incl. Nix option path; hover shows the stack
- [ ] "Changed" view with per-key / per-page reset and diff preview
- [ ] live preview for palette/scheme/font/radius (focus → preview, Enter → commit, Esc → revert)
- [ ] search lands on the row; `kurashi settings <key>` opens it
- [ ] mod page: switch, running, capabilities, "Adds:" with links, enable errors
- [ ] vertical pick list with keyboard reorder; dropdown with greyed reasons
- [ ] profiles: differ count, preview, export/import review
- [ ] screenshots of all states; keyboard-only run through every page

## Later
Related-settings links · per-slot ordering UI (K28) · settings sync across machines · a11y audit with Orca.

## Appearance blocks (W29, K53; brief: docs/ux/looks.md "Settings")
- A row whose offers are appearance packs (`choices_from` = `styles`, `looks`, `palettes`: the keys of `theme.previews`)
  leaves its section on its page and opens the page as a block of its own (`SettingRow { stacked }`): the card's title
  is the setting's name, its first line says what the kind is (`settings.appearance.<source>.what`), the cards take the
  full width, the provenance chip and Reset sit under them. A block can take companion rows with it (display map
  `packCompanions` in `SettingsPages`: the scheme switch sits with the palette). In a search they are plain rows.
- Cards by category (`PackCards`): chips with counts for the offers' `group`s, one open (the current pack's until a chip
  is opened; a new pack in effect opens its own), offers without a group (None) as plain cards in front. Styles and
  looks are applied by their actions (`Store.pickPack`; "None" only sets the style); their arrows move the focus only.
- "Differs from the style" (`StyleDiffers`) under the Style block, from `theme.appearance.overrides`; Reset applies
  the style again. Provenance words: `style:<n>` → "From the style Washi", `look:<n>` → "From the look …", a value a
  style only recommends (the scheme) → "Recommended by the style …".
- Search: Return lands on the first row whose name has the query, else the first hit ("palette" lands on Palette,
  not on the Style whose help names a palette).
- A watched document is dropped a moment after its last viewer goes, unless a view watches it again in the same turn
  (a page rebuilt from a search keeps its previews, and the keyboard focus its card).
- Shots: `settings/shots/appearance/` (washi, sekai, win95 pages; each category of styles and looks; the "differs" line;
  a look over the style; the palette block in dark).

## Section cards (K48 (5), I104; W24-desk-settings)
References: **DMS** `Modules/Settings/Widgets/SettingsCard.qml` + `SettingsGroup.qml` (a section label in the primary
colour above a group of rows on tonal slots), **Noctalia** `SettingsPanel/Tabs` (headed sections between dividers),
**Caelestia** dashboard cards (rounded container blocks), **GNOME** libadwaita preference groups (boxed lists under a title).
- Each section of a page is a card (`SectionCard`): the container fill, the chrome's ink outline (keycap, line) or a
  hairline, keycap's hard shadow; the section's Material Symbols icon (accent, a mark not text) and title on top; rows
  inside, hairlines between them, none after the last. Icons come from a map in `SettingsPages` by section id (or
  `page.section`), a mod's section gets the puzzle piece, anything else the sliders — display only, no key named.
- Search results keep their breadcrumbs, one card per section found, with no card title (the crumb names it). The
  Changed view is unchanged (its own list).
- **A row's document** (the one place Settings shows one): a per-key map `extras` in `SettingsPages` (key → component),
  drawn under the row's control column; `SettingRow` knows nothing of it. First use: under `theme.export`, each chosen
  app from `svc.theme_export` — where its file went ("Written to" / "Up to date"), "Read by <file>" when the include is
  there, else the line to add with the config file it goes in and Copy (wl-copy through `launcher.launch {id: "calc:…"}`;
  "Copied" on the key until the line changes, a refusal line if it could not), an error by its i18n key, unknown colour
  names. The document is watched only while the status shows (Ma). DMS writes the include itself
  (`IncludeSetupBanner`); kurashid never edits an app's own config (K49), so we show the one step and copy it.
- Shots: `settings/shots/{28-cards-power,29-cards-desktop,30-theme-export,31-theme-export-copied,ja-cards-power}.png`.

## Settings as a sheet (K63, wave 32)
User (session 13): the menu "is currently not affected by the light source at all … toggle the menu between states of a
'normal compositor window' (as it currently is) and a quickshell hosted settings window (that overlays in the center of
the screen, kinda like other extended surfaces of the shell do)"; chosen: a modal sheet.

**How others do it.** GNOME Settings, KDE System Settings, COSMIC Settings, macOS System Settings and Windows 11 Settings
are ordinary app windows. macOS *sheets* (a dialog attached to its window, dimming it) and GNOME's modal dialogs are the
model for "modal over what is behind". Quickshell shells draw their settings inside the shell: Noctalia's settings panel
and DankMaterialShell's settings modal are centred shell surfaces over the desktop — themed exactly like the bar,
movable they are not. Launchers (Spotlight, KRunner, our own launcher) set the interaction: centred, dim behind, Esc and
a click outside close.

**Design.** `settings.window = sheet`: the same on-demand process (K2) maps a layer-shell surface (layer Overlay,
namespace `kurashi-settings`, exclusive keyboard) on the focused output: a backdrop dimmed with the scrim token (fades
in with `motion.standard`), the sheet centred, about 1040 × 740 logical px or 90 % of the output when smaller, with the
shell's chrome, corner radius, shadow, material and the texture/light/carried sheet like every shell surface (the window
mode keeps a plain ground; its own sheet, unregistered). Esc closes (an open preview is put back first, as now), a click
on the backdrop closes, Ctrl+F searches. Switching the key while Settings is open re-hosts it at once on the same page and
scroll position. The window mode is unchanged.

**States.** Opening (backdrop and sheet fade/scale in, 220 ms; reduce motion: instant), open, closing, a preview in
progress when Esc comes (put back, then close), a second `kurashi settings <key>` while open (jumps, as now), no daemon
(the existing veil), multi-output (the focused output; the sheet does not follow focus once open).

**Keyboard, a11y.** Exclusive keyboard while the sheet is up: Tab order as the window; Esc closes; the backdrop is not
focusable; screen readers see one dialog named "Settings".

**Definition of done.** Both modes from the key, live switch; sheet textured and lit (shots kami light/dark, paint with
spotlight); Esc/backdrop/close button; `settings/test.sh` green in both modes; idle 0 frames while open and still.

## Free lists and page links (W36-core; I54, I40, K65)
References: **GNOME** Settings › Search › Search Locations (a list of folders, add and remove); **KDE** System Settings ›
File Search (folders to index or skip, one per row, Add…); **macOS** Spotlight › Privacy (a folder list with + and −). Each shows one entry per row.
- **Free string lists** (a mod's `type = "list"` without choices, and core lists such as the launcher's terminal command or
  the dock's pins) use the pick list's vertical rows: number, entry, move up / move down / remove, Alt+Up/Down and
  Delete on a focused row, the focus following a moved row. Under the rows a text field adds an entry: Return adds the
  trimmed text as the last entry; an entry already listed is not added twice; blank adds nothing. The list is one value
  with one provenance (the row's chip). The font chain keeps its chips (its edits are previews).
- **Path lists** (`unit = "path"`, e.g. the wallpaper's `folders`): the field's placeholder says "Add a path: /… or ~/…",
  the empty line says what a path looks like, the field is monospace and the entries elide in the middle (start and last folder
  stay visible). kurashid refuses an entry that is neither absolute nor under `~` (`error.config.not_a_path`); whether
  the folder exists is the mod's to say (the wallpaper picker names a missing folder). A refused entry stays in the field
  with its edge marked and the reason under the row, so it can be corrected. No file picker yet: the shell has no portal
  client, and a picker that is a Process in the frontend would break rule 1 (later: an `xdg-desktop-portal` FileChooser
  through the daemon).
- **Old values**: a free list saved as one `:`-joined string (the wallpaper's folders before lists) reads as its parts; the
  first edit writes the list.
- **States**: empty ("Nothing listed yet." / "No paths yet …"), entries, refused entry (invalid path), Nix-forced (rows and
  field disabled, the chip names the layer), inert (requires) like any row.
- **Page links**: `settings.open {page}` opens Settings on a page — a schema page id (`keys`) or `mod:<id>` for a loaded mod's
  page — at start (`KURASHI_SETTINGS_PAGE`) or on a running window (`ipc call settings page <page>`); the page opens at its
  top and out of a search. A key link wins when both are given. kurashid refuses a page Settings does not have
  (`error.settings.unknown_page`), so a link never opens an empty window. First link: the wallpaper picker's overflow menu,
  "Wallpaper settings" (`mod:wallpaper`).
- Shots: `settings/shots/{freelist-empty,freelist-three,freelist-added,freelist-invalid-path,page-link-keys,ja-page-link-records}.png`.
- Definition of done: free list add / remove / reorder by keyboard and pointer ✓; path hint and refusal ✓; old colon
  string read ✓; page link at start and while running ✓; en + ja copy ✓; a native file picker ✗ (later, needs a portal client).
