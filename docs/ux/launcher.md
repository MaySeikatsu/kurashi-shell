# Launcher — UX brief (M5, K44, I105/I126, card W26-launcher)
Status: implemented (functional, W26) — clipboard with images and pins, emoji grid with recents, keybind cheat sheet.
UX review by the lead against the shots in `frontend/shots/launcher/w26/`.

## Job
One keyboard surface for "get me to a thing": apps, arithmetic and units, shell commands (`>`), the web, and three
small tools the user reaches for many times a day — the clipboard history (`;`), emoji (`:`) and "what was that key
again?" (`?`). It opens on the focused output, centred, with exclusive keyboard focus (Mod+Space → `launcher.toggle`;
`launcher.keys` opens it on the cheat sheet). The daemon owns every list (rule 1); the card renders rows.

## References (what others do, cited)
- **Raycast** (macOS): Clipboard History is its own command — a list on the left, a large preview on the right
  (images shown whole, text with metadata: app, time, characters); pin, delete and "delete all" (behind a
  confirmation) from the action panel, each with a shortcut; pinned items on top; typing filters. The emoji picker is
  a grid with recently used ones first. Raycast's own hotkeys live in its Settings.
- **Alfred**: Clipboard Viewer (⌥⌘C) — a list of text/image/file clips, images as thumbnails, "Clear" in the
  Viewer asks first; snippets alongside. No emoji grid (third-party workflows).
- **KRunner / Plasma**: Klipper history in the runner and a tray popup (pin = "keep", a QR code per entry, edit in
  place); `Meta+.` opens the Emoji Selector — a grid by category with "Recent". Plasma's *Shortcuts* KCM lists every
  shortcut searchable, but only in System Settings.
- **GNOME**: no clipboard history (extensions: Clipboard Indicator — pins as "favourites", images as thumbnails,
  "Clear history" with a confirmation). Characters app: grid, "Recently used" first. Keyboard shortcuts: Settings →
  Keyboard → View and customise, searchable; apps show a `Ctrl+?` Shortcuts window (`GtkShortcutsWindow`): groups,
  key caps, searchable — the model for our `?`.
- **niri**: `Mod+Shift+/` shows its hotkey overlay — the binds with `hotkey-overlay-title`, `=null` hides one. We
  read the same file and honour the same titles.
- **DankMaterialShell**: `Modals/Clipboard/**` (list + preview, pins kept through "clear", per-entry delete, keyboard
  hints in a footer — `ClipboardKeyboardHints.qml`) over its own backend; `KeybindsModal` + `core/internal/keybinds/
  providers/niri_parser.go` (walk `config.kdl` through `include`, `binds` and `recent-windows`, group by action) —
  our cheat sheet's parser and grouping follow it.
- **Noctalia**: `Modules/Launcher/ClipboardHistory.qml` + `Services/CliphistService.qml`: cliphist through
  `list -preview-width`, images detected by `[[ binary data … ]]` and decoded to base64 data URLs, `decode | wl-copy`,
  `cliphist wipe`. Emoji in the launcher with an `:` prefix.
- **end-4/ii**: `services/Cliphist.qml` (image regex `[[ … binary data … WxH ]]`, `cliphist delete` reads the line
  on stdin, superpaste), `services/Emojis.qml` (a list, fuzzy search).

**Taken:** DMS's/Raycast's pins-first and "pins survive clear"; Noctalia's cliphist calls and ii's line parsing and
delete; GNOME's/Characters' and Raycast's recents-first emoji grid; GtkShortcutsWindow's grouped, searchable key caps
and niri's own title rules; DMS's niri parser model and footer key hints. **Not taken:** a separate preview pane
(the card stays one column at 600 px; the thumbnail is the preview), OCR, skin tones, editing shortcuts (read-only:
the user's config file is the source), Klipper's QR codes.

## Beyond the basic job
- Clipboard: Enter puts any entry back with its type (an image stays an image), Ctrl+P pins (kept in the state dir,
  so a pin outlives cliphist's pruning and a wipe), Shift+Delete removes. Later: paste into the focused app after
  copying (ii's superpaste needs a virtual keyboard), a larger preview on hover, "copied from <app>" when the history
  can tell (cliphist cannot).
- Emoji: recents are frecency (the launcher's own model): what you use stays in front without a separate list.
- Cheat sheet: the shell's own keys (kurashi act binds) are a group of their own, labelled with the action's name;
  the pointer bindings (`<component>.input.<slot>`) follow. Later: Hyprland/Sway adapters read their configs the same
  way; a bind could be run from the sheet (Enter) once the compositor adapter can dispatch arbitrary actions.

## Design
- **`;` clipboard**: rows of 58 px (text: two wrapped lines, plain text never markup) or 72 px (image: an 84×56
  thumbnail letterboxed, "W × H FORMAT" and the size); pinned rows first with an accent pin; last a "Clear history (n)
  — p pinned stay" row: Enter turns it red "Press ↵ again to delete n entries. Esc keeps them.", Enter again wipes,
  Esc or moving away cancels. Footer: `↵ Copy · Ctrl+P Pin · Shift+Del Remove`. Refusals show their own line
  (`launcher.clip.error.*`).
- **`:` emoji**: an 8-column grid, cells 60 px, five rows visible; arrows move in two dimensions (Left/Right too —
  the text cursor does not need them in a one-character prefix mode), PageUp/PageDown by a screen; the selected
  emoji's name (and "Recent") under the grid with the hint `Arrows move · ↵ Copy · recently used first`.
- **`?` keys**: group headers in the accent (Shell, Apps, Windows, Workspaces, Monitors, Media and brightness,
  Screenshots, System, Other, Shell: pointer), rows of 38 px: the label left, key caps right (Blocks: the decor's chrome,
  `Mod` shown as the configured mod key, xkb names as symbols — `,` `←` `PrtSc` `Vol +`); the selected row also shows
  the raw action (`spawn kurashi act launcher.toggle`) so a label never hides what the key does. Typing filters by
  label, keys and action. Footer: "Read-only: niri's keys from its config, and the shell's own".
- Motion: none new — the list is replaced, the highlight moves (spring per the decor); no animation in the grid.
- **App icons (W37, row 380)**: each `app` row carries `icon_path`, the file kurashid resolved from the row's icon name
  (`theme.icon_theme`, else the desktop's Qt/GTK theme; inherited themes, hicolor, pixmaps; scalable first, then from
  60 px up), cached in the daemon. The row loads it with an asynchronous `Image` (off the GUI thread), so the first open
  of a session no longer holds its morph on icon lookups (W36's `warmQueue` is gone). `icon_path: null` (no theme has
  the name): the row asks Qt for the name as before, and the initial-letter tile stands in while nothing loads.
- **`>` Settings links (W37, row 387, I40)**: "Shortcut settings" (Settings on the Keys page — named apart from the
  cheat sheet's "Keyboard shortcuts") follows "Open Settings" in every `>` list; "Settings: <page>" rows (each schema
  page and each enabled mod's page) appear only for a query that names them (`>settings bar`, `>weather`), so an empty
  `>` stays short. Enter closes the launcher first (Settings is its own window), then sends `settings.open {page}`; a
  page Settings lacks is refused with `error.settings.unknown_page`.

## States
- **cliphist missing**: a note row "Clipboard history needs cliphist (…)"; pins still listed above it.
- **empty history**: "The clipboard history is empty" (no clear row); with pins, only the pins.
- **image entries**: decoded only when their row exists (the list creates rows for what is on screen, `cacheBuffer:
  0`), once, scaled to ≤ 256 px, to `$XDG_CACHE_HOME/kurashi/clip/<id>.png`; "Loading preview…" until then; "No
  preview" when refused (> 32 MiB, > 64 Mpx, not decodable). Cached files of entries that left the history are
  removed on the next listing and on clear.
- **huge entries**: text arrives already cut by cliphist (`-preview-width 240`), shown in two lines with an ellipsis;
  copying puts the whole entry back. Binary non-image entries read "Binary data · <size>", copied as they are.
- **no niri config**: "No niri config at <path>: niri's built-in keys are in effect", then the shell's pointer
  bindings; a config without binds says so; an include that points at no file is named (not when filtering).
- **many items**: the clipboard lists 60 history entries (cliphist keeps more; type to search all of them), the emoji
  grid 240 (160 for a search), the cheat sheet everything.
- **ja**: every string has a ja key; key caps are symbols or English key names in both.
- **icon missing** (W37): `icon_path` null → Qt's lookup, then the initial-letter tile; a file that fails to load shows
  the tile too (the Image is only visible once `Ready`).

## Fit and constraints
- Ma: nothing runs while the launcher is closed (no list, no watcher, no decode); the cheat sheet re-reads niri's files
  only when their mtime changed; thumbnails are decoded on demand, once.
- Shōjiki: notes instead of blank lists; the raw action under a label; "No preview" instead of an empty box.
- Contracts (rows 190–193): `runtime.ui.launcher_query`; actions `launcher.keys`, `launcher.clip.{thumb,delete,pin,clear}`;
  the row shapes (`image`, `thumb`, `pinned`, `binary`, `clipclear`, `key`/`keygroup`, note `arg`, emoji `recent`).

## Definition of done
- [x] `;` shows thumbnails for visible images only; Enter copies with the image type; Shift+Delete removes; Ctrl+P
  pins (first, kept through clear); clear asks first (`frontend/test-launcher.sh`, sekai and none).
- [x] `:` grid with 2-D arrows; a copied emoji comes first next time.
- [x] `?` and `launcher.keys`: grouped, searchable, the shell's binds labelled, includes followed, `=null` and `/-`
  respected; `launcher.keys` again closes.
- [ ] Lead review of the shots; a niri bind for `launcher.keys` in `docs/niri-binds.kdl` (row 193).
- [x] W37: app rows carry `icon_path` (svg from scalable, png from 64 px, null for an unknown name), drawn in the list
  (`shots/launcher/w26/icons-sekai.png`); the cold first open holds no frame longer than 100 ms (measured 26–39 ms,
  W36 measured ~200 ms before); `>` lists the Settings links and refuses an unknown page (`test-launcher.sh` icons).

## Later
Paste-after-copy; a preview pane for large images; Hyprland/Sway bind readers; running a bind from the sheet; skin
tones; the mock's parity for the new actions.
