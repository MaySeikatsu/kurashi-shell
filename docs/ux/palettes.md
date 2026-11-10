# Palettes, wallpaper colours, chrome fill and gradient — UX brief
Status: implemented (functional), session 26 (K106–K111). Reviewed live on the user's niri session, two outputs, the kami look.

## Job
Colours that look like the wallpaper or the palette the user picked — the picture's own colours, the real Gruvbox, a pink
bar with white text and light-blue buttons when the picture is pink, white and blue — and never at the cost of text that
cannot be read.

## How others do it
- **matugen / Material You (Android, end-4, Caelestia, DankMaterialShell, Noctalia):** one seed, a tonal scheme around it.
  Calm and legible; a picture of three strong colours comes out as one muted hue. Kept as Tone-matched (and Vibrant).
- **pywal / wallust:** the picture's dominant colours as the 16 terminal colours, little care for contrast. Taken: the
  picture's actual colours (Prominent, Mixed); not taken: no contrast guarantee.
- **Base16 / the ricing palettes (Gruvbox, Catppuccin, Rosé Pine, Tokyo Night, Nord, Dracula…):** each publishes its own
  terminal colours and variants. Taken: the authors' tables verbatim (K106), the variants as one family.
- **KDE colour schemes, GNOME accent:** a scheme or one accent, the controls all in that accent. Taken as "One accent";
  "Spread" goes further.
- **macOS / Windows wallpaper tinting (Windows 11's accent from wallpaper, macOS's desktop tinting of windows):** a faint
  tint of the picture on chrome. The wash's "wallpaper under it" pattern is the strong version of that.
- **Hyprland / niri gradients on borders:** a gradient on a line; here the gradient fills every ground as one sheet.

## Settings (Appearance › Colours)
| Setting | Choices | Notes |
|---|---|---|
| Palette | by category: Kurashi · Common · Inspired (+ Wallpaper, mod palettes in front) | Common = the coding/ricing palettes with their variants |
| Wallpaper colours | Tone-matched (default) · Vibrant · Prominent · Mixed | only with palette Wallpaper |
| Colours on the controls | Automatic · One accent · Spread | Automatic spreads under Mixed |
| App icons | Original · Text colour · Palette tones · Palette colours | dock, window list, tray, launcher rows and grid, notifications (an app's icon, never the notification's own picture); every choice keeps the icon's drawing |
| Chrome fill | Neutral · Strong colour | apps that follow take it too |
| Gradient | on/off; colours, pattern (linear, radial, watercolour, the wallpaper under it), angle from the wallpaper, angle, range of tones, softness, pool size, across all screens | over either fill |
| Launcher › Logo colour | As the look draws it · Original · Text colour · Palette colours · Palette tones | OS logo or own image |
Seasonal tint's help says it shifts these hues too (the user's violet-for-blue surprise).

## States
- **No wallpaper picture yet:** palette Wallpaper waits (as K34); the gradient's auto angle falls back to the angle; the
  wallpaper pattern falls back to linear until the picture has loaded.
- **Evenly lit picture:** no light side, so the auto angle uses the angle (said in its help).
- **Grey picture:** Prominent's accent is the most colourful patch, never a grey; Mixed keeps the scheme's colours where
  the picture has none; strong chrome on a grey accent keeps the neutral ground and says why (theme notes).
- **Error:** an unreadable picture is the wallpaper source's error, as before.
- **Forced / inert:** every gradient row is inert (with its reason) while Gradient is off; angle while auto angle is on.

## Legibility (the guarantee)
- Text ≥ 4.5:1 everywhere (the wcag stage is still last); on a strong ground 6:1, on its containers and on every gradient
  stop 5.5:1, so the material's relief keeps room to shade (K108).
- Controls ≥ 3:1 against their track or ground (WCAG 1.4.11), reached by moving lightness only, the shorter way.
- The wallpaper pattern darkens or lightens each colour in linear light only as far as the text needs.

## Keyboard and a11y
Every setting is a schema row: the Settings controls' keyboard paths, provenance chips and inert reasons apply unchanged.
Colours never carry meaning alone (states keep their marks and labels).

## Motion
A change of palette, mode or fill goes through the existing colour blend (ColorBlend, K87). The gradient is still: no
animation (moving colour is I461, with its own gate).

## Multi-output
The gradient spans every output as one canvas from their places in the layout (default) or each output alone; the
wallpaper pattern always reads each output's own picture.

## Fit
Island, Stage, quick settings, sidebars, dock, launcher and Settings all draw the wash on their grounds and their controls
from the component tokens. Apps that follow the theme get the strong fill and the spread colours; the gradient is the
shell's only (apps take its middle through the palette).

## Budget
No new layer per surface: the wash is a ShaderEffect per ground, drawn only when that ground draws; idle = 0 frames. The
wallpaper pattern loads one small picture per output (24–160 px). Icon tint: a layer per icon only while a tint is on.

## Definition of done
- [x] All settings in the schema, Settings and HM `settings`; i18n en/ja.
- [x] Legibility as above, unit-tested (`kurashi-theme` tests: strong chrome, stops, containers, sage, teal, pink).
- [x] Seen live on niri with the user's wallpapers (pink, teal, green, red).
- [ ] Floating bar pill and translucent floating dock washed.
- [ ] Controls coloured by the wallpaper under them (user's "C"), Custom palettes and the editor (I453), apps' real
  palettes (I454).

## Custom palettes (I453, card W68)
Status: built (functional; UX per the definition of done below), session 27. Brief written before the build.

### Job
The user's own palette, made in Settings without writing TOML: pick the colours of the roles the shell paints with, see the
shell wear them while picking, save them as a palette that sits beside the bundled ones — and never be told a colour is in
effect when the legibility stages moved it (Shōjiki).

### How others do it
- **KDE Plasma's colour scheme editor:** a scheme is a file (`~/.local/share/color-schemes/*.colors`); the editor lists every
  role (View / Window / Button / Selection / Tooltip × background, alternate, text, link, negative, neutral, positive) with a
  swatch each, a preview of a fake window, "Save As…" with a name, and the scheme list with Edit and Remove. Taken: a file
  per palette, role rows with swatches, the preview, Edit and Remove on the list. Not taken: 40-odd roles — too many for a
  shell; most of ours derive.
- **GNOME + Gradience (archived 2024):** presets, then a short role list (accent, destructive, success, warning, error,
  window, view, headerbar, card, popover), each a colour button opening GTK's picker, a live preview of the widgets and
  "Save preset". Taken: the short list grouped Grounds / Text / Colours / States, the live preview. GNOME 47's own accent is
  ten fixed dots and no picker — too little here.
- **macOS:** Accent and Highlight, eight dots plus "Other…" (the system colour panel: wheel, sliders, hex, saved swatches).
  Taken: quick swatches in the picker (the palette's and the wallpaper's colours).
- **Windows 11:** Accent from the wallpaper or a 48-swatch grid; "Custom colour" opens a saturation/value square, a hue
  slider and a hex field, and warns *"This colour may be hard to read"*. Taken: square + hue + hex, and the honest warning —
  ours says what the shell shows instead and why.
- **Material You (Android, matugen; end-4, Caelestia, DankMaterialShell, Noctalia):** one seed (or the wallpaper) generates
  the scheme; DankMaterialShell and Noctalia list named schemes and read custom ones a user drops in a folder; end-4 picks a
  seed hex. Taken: "start from the wallpaper's colours" and user files in a folder; not taken: seed-only (the user asked for
  roles).
- **Caelestia / Noctalia scheme pickers:** a grid of scheme cards, user schemes from a folder, no in-app editor. Taken: user
  files listed with the bundled ones, in their own category.
- **Catppuccin-style userstyles, base16 / base24 (tinted-theming):** a palette is a small named table (base00–base0F, base24
  eight more) that feeds every app's template. Taken: one file per palette in the shell's own format, which already carries
  the authors' 16 terminal colours (K106). Stretch: import a base16/base24 YAML.

### Where and what
Appearance › Colours, the Palette block. After Kurashi · Common · Inspired, a fourth category, **Your own**
(`appearance.category.custom`, the word the styles and looks use for the user's files), always shown for palettes.
- **Tiles:** each custom palette is a card drawn in the look and scheme in effect (as every palette card), with **Edit**,
  **Duplicate** and **Delete**; a **New palette** tile last. Picking a tile picks the palette (one change, undoable).
- **New palette** opens the editor on a copy of the palette in effect (the wallpaper's current result when that is the
  palette), named "<palette> copy". **Duplicate** does the same from its tile; **Edit** opens the palette itself.
- **Delete** asks once, on the tile ("Delete <name>?" Delete · Keep). The palette in effect falls back to the default.
- **The editor** (in the block, in place of the tiles): a name field; **Dark | Light** (which side is being edited, and
  whether the palette has it: a side it lacks says "Light mode uses the dark colours", which is what the pipeline does, and
  offers "Add light colours"); one row per role, grouped:
  - Grounds: Ground (`surface`), Cards (`surface_container`), Lines (`outline`)
  - Text: Text (`on_surface`), Quiet text (`on_surface_variant`), Text on accent (`on_accent`)
  - Colours: Accent, Secondary, Tertiary
  - States: Error, Warning, Success
  Each row: the role's name, a swatch (a button named by its role and hex), the hex, and its provenance — **yours** or
  **derived** (worked out from the others, drawn in the derived colour). Ground, Text, Accent, Secondary, Tertiary and
  Warning are the format's required roles: always yours. A derived role becomes yours when picked; one of yours that may
  derive has "Derive".
- **The colour picker** (opens under its row, one at a time): a saturation × lightness square, a hue strip, a hex field, the
  quick swatches (the palette in effect's colours, and the wallpaper's when there is a picture), OK and Cancel.
- **"Shown as":** where a stage moves a picked colour, the row says *"You picked #xxxxxx, shown as #yyyyyy: raised for
  contrast against Ground"* (wcag), or *"…: seasonal tint"*, *"…: colour-blind aid"*, *"…: strong chrome"*, *"…: higher
  contrast"*, *"…: OLED black"* — the stage in words (i18n); a dot beside the swatch shows the colour on screen.
- **Live preview:** while the editor is open, the shell (and Settings) wears the draft, in the scheme in effect. The daemon
  holds the draft in memory and writes nothing; the theme document says so in its notes (`theme.note.palette_draft`); apps
  that follow the theme keep the saved colours. Leaving the editor without Save (Cancel, Escape, another category or page,
  Settings closing or crashing) ends the draft. A **sample card** in the editor (text on ground, a button, a slider, a
  switch, the three states) draws the side being edited, which may not be the one in effect, and stays visible when
  Settings covers the shell.
- **Save** writes `$XDG_CONFIG_HOME/kurashi/palettes/<slug>.toml` (the bundled format, `category = "custom"`, the name as
  `label`) and picks it: one change, so Undo goes back to the palette before.

### States
- **Empty:** no custom palette yet: the New palette tile and one line ("Palettes you make, or files you put in <dir>, show
  here").
- **Loading:** the editor waits for the palette's roles (one action reply); nothing half-drawn, no spinner.
- **Broken file:** a greyed tile with its file name, the reason it does not load, and Delete; not selectable. A config naming
  it reads unavailable (the offer's reason).
- **Name clash:** "A palette named <slug> exists" (bundled: "<slug> is a bundled palette's name"); Save is off. Saving over
  the palette being edited is fine.
- **Invalid name:** the field shows the file name it will write (letters, digits, `-`); an empty one turns Save off.
- **Deleted while active** (in Settings or by hand): the theme falls back to the default palette and says so
  (`theme.note.palette_gone`); Delete in Settings also resets the row.
- **Read-only config** (Home-Manager links the directory, or it cannot be written): the editor says where the files would go
  and that it cannot write there; Save and Delete are off; the live preview still works.
- **Disconnected:** as every Settings page (stale, inert).

### Keyboard and a11y
- Tiles: Tab reaches each tile, then its Edit / Duplicate / Delete; Return or Space picks or presses.
- Editor: Tab walks name → Dark | Light → each swatch (accessible name "<role>, <hex>, yours | derived") → Save / Cancel.
  Return or Space on a swatch opens the picker with focus in the square.
- Picker: in the square Left/Right change saturation, Up/Down lightness; in the hue strip Left/Right move the hue (Shift:
  ten steps); Tab to the hex field (Return takes a typed hex), the quick swatches (arrows), OK, Cancel. Return confirms,
  Escape cancels and restores the colour before the picker opened.
- Escape in the editor (picker closed) leaves it without saving.
- Colour never carries meaning alone: yours / derived and "shown as" are words; every swatch has its hex as text.

### Motion
None of its own: the editor and the picker appear in place; colour changes go through the theme's colour blend (K87),
which reduce motion already cuts.

### Multi-output
The draft is one theme for every output, like a palette. The editor lives in the Settings window.

### Fit
Island, Stage, quick settings, sidebars, dock and launcher wear the draft as any palette (component tokens, rule 4). A saved
custom palette is a palette everywhere: profiles and styles may name it, the theme export writes it for apps, and its
terminal colours are its `[dark.terminal]` table when a hand-written file has one, else derived as today.

### Budget
The editor closed costs nothing: no timer, no watcher of its own (the config directory's inotify watch already exists and
wakes only on file changes there). A draft change is one theme resolve per edit (≈ a palette pick); the picker sends at
most one while dragging per 50 ms. Custom palettes' preview cards are resolved per publish, uncached (a handful).

### Definition of done
- [x] Custom files load beside the bundled ones (a bundled name wins; a broken one is listed with its reason), are offered
  under `palettes` with group `custom`, watched, and the active one re-themes on change.
- [x] Actions list / get / duplicate / save / delete / draft; names validated (slug, no path parts, no bundled or reserved
  name).
- [x] The editor: every role row above with its provenance, Dark | Light, the picker (square, hue, hex, quick swatches,
  keyboard), the sample card, "shown as" with its reason, a live draft that ends with the editor (a crash too).
- [x] States: empty, broken, name clash (the note under the name: the file it saves as instead), read-only — drawn and
  screenshotted (`settings/shots/palettes/`); deleted while active — in Settings (test C8: the default is back) and by
  hand (kurashid test: the default with `theme.note.palette_gone`), no shot of its own.
- [x] i18n en + ja (`i18n/{en,ja}/palettes.toml`).
- [x] `settings/test.sh` part `palettes`; cargo tests; seen on nested niri (`settings/shots/palettes/niri-*.png`).
- [x] A Home-Manager option that writes palette files (`programs.kurashi.palettes`; read-only in Settings).
- [ ] Stretch: base16/base24 import.
