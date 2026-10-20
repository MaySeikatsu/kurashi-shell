# Wallpaper (mod) — UX brief
Status: agreed (lead, session 5) — implementation card W12-wallpaper (revised from this brief)

## Job
Make the desktop feel like *yours* in seconds: browse your images, set one per output (or all), rotate if you
like, and — the part that makes it more than a picker — let the whole shell's colours follow the image when you
want. Wallpaper is the **Look & feel** family's entry point (COMPOSITION §2), joined with theming (DESIGN-SYSTEM §2)
and the lock screen.

## References (research 2026-10-09, cited)
- **awww 0.12.1** (codeberg.org/LGFae/awww): `--resize crop|fit|stretch|no`, `--crop-gravity`, 14 transitions,
  `--transition-pos` (aliases/%/px, no cursor), restores last image per output unless `--no-cache`; reads
  `AWWW_TRANSITION*` env when flags are absent (always pass flags).
- **waypaper / hyprpaper / wpaperd**: GUIs and daemons with random, fill modes, per-output sections; wpaperd's
  `queue-size` history makes "previous" work only within it.
- **Noctalia**: grid, ALL vs per-monitor target, ★ snapshots *theme mode + palette* with the image, per-monitor
  folders rotating independently, random transitions.
- **DankMaterialShell 1.6**: matugen + random cycling + "wallpaper colour source" mode; HyprPanel users report
  theme lag at fast rotation (debounce palette work).
- **GNOME**: separate desktop/lock backgrounds, light/dark variants that follow the style, time-of-day slideshows.
- **macOS**: dynamic wallpapers by time of day with light/dark variants. **Windows**: per-display slideshow,
  separate lock screen (Spotlight).
- **KDE**: slideshow settings lost across sessions (bugs 329147, 339403) — persist state ourselves.
- **Thumbnails**: freedesktop sizes 128–1024 px; Qt `Image.sourceSize` caps decode; `asynchronous` defaults false.
- **Colour**: matugen (`scheme-tonal-spot` default), wallust; Android "basic colors" fallback for monochrome images.

## Beyond the basic job — what wallpaper can become
1. **Wallpaper + theme as one gesture**: each tile shows 3–4 palette chips derived from the image (material-colors on
   the thumbnail, computed in the daemon once and cached); selecting previews the shell recoloured (dry-run apply →
   `preview` diff, existing contract); "Apply" or "Apply wallpaper only". Monochrome images warn and offer a fallback.
2. **Favourites as looks**: ★ stores {image, theme mode, palette variant} — a one-click "look" (Noctalia), listed in
   quick settings' Display page and usable from the launcher ("look: autumn").
3. **Time of day**: per-image light/dark variants (pairs detected by name `x-light`/`x-dark`), or a day/night
   schedule that swaps wallpaper *and* scheme at sunset (sun times from the weather mod's place when on, else a
   fixed time) — modules meeting.
4. **Per output, honestly**: target chips [All] [DP-1] [DP-2] with each output's current thumb; "Span" disabled with
   the reason (awww has no span) until pre-cropped derivatives exist.
5. **Lock screen**: the lock reads the current path once on lock and draws a blurred copy (no live subscription).
6. **Touchpoints**: quick-settings tile "Wallpaper · Rotating 30 min" (Next, Random, Pause), `wallpaper.next/prev/
   random` actions for keybinds, launcher provider, a bar widget only if the user places it.
7. **Later**: Wallhaven browsing (D3), video wallpapers with a daemon-owned pause policy, per-workspace wallpapers.

## Design
- **Picker** (Stage panel `mod:wallpaper:wallpaper`, ~720 × 480 px — the largest Stage card; scrolls inside):
  header target chips → toolbar (folder breadcrumb, `/` search, sort Name/Newest/Random, ★ filter, Random) → virtual
  grid of 16:9 tiles (256 px thumbnails from a disk cache keyed by path+mtime+size, decoded with `sourceSize`, only
  visible cells hold textures) with palette chips and badges (current on output, ★, light/dark pair) → preview strip
  (selected image large, palette, "Apply / Wallpaper only / ★") → footer "awww 0.12.1 · 2 outputs · 412 images".
- Keys: arrows move (WAI-ARIA grid), Enter apply to target, Shift+Enter all outputs, F favourite, R random,
  Backspace folder up, `/` search, Esc close. Transition `grow` from the clicked tile position (output-local px).
- Drop an image/folder on the card: preview it / add the folder to the library.
- **Settings page**: backend dropdown (awww / swww, missing one greyed with reason); fit (Crop | Fit | Stretch | Keep)
  + crop anchor; transition (None | Fade | Wipe | Wave | Grow | Random, duration, angle); rotation (Off/5/15/30/60/
  custom, shuffle or alphabetical, per output or same); theme (source wallpaper/palette, variant, mode auto/light/
  dark); advanced (restore on login, clear thumbnail cache, restart backend).

## States
backend missing · daemon down/crashed/starting · outputs not yet known · no folder (onboarding: pick a folder) ·
folder missing/unmounted (greyed, last known) · empty folder · unsupported/corrupt file (broken tile + reason) ·
huge library (paged, virtualised) · hot-plug/renamed output · set during transition (last wins) · rotation list
shrinks · monochrome image (theme fallback) · palette updating (debounced) · ja copy.

## Fit and constraints
Ma: the rotation timer exists only while rotation is on (one timer, per-output due times); thumbnails are generated
only while the picker is open and cancelled on close; no file watching. State: our own state file is the truth;
start the backend with `--no-cache` and re-apply on start (one restore owner). Budget: the picker is on the Stage;
textures only for visible cells (500 decoded 256 px thumbs ≈ 70 MiB — never all at once). Palette extraction in the
daemon (Rust material-colors), never in QML.

## Contract notes
`mod.wallpaper`: `{available, backend:{id, version?, available, reason?}, outputs:{<name>:{path, fit}}, library:{count,
folders:[{path, available, reason?}]}, rotation:{on, interval_min, next_at?}, favourites:[…]}`; actions
`wallpaper.set {path, output?}`, `wallpaper.next|prev|random {output?}`, `wallpaper.favourite {path}`,
`wallpaper.thumbs {folder, offset, limit}` (action data: rows with thumb path + palette chips, built on demand);
choice source `wallpaper.backends`; panel `wallpaper`; slot `quick.tiles`.

## Definition of done
- [ ] picker grid with thumbnails, palette chips, target chips, keyboard grid nav, search/sort
- [ ] preview with theme diff; apply / wallpaper only; ★ looks
- [ ] backend dropdown with greyed missing backend; every backend state drawn
- [ ] rotation with one timer; state restored after daemon restart (test with fake backend)
- [ ] quick-settings tile via slot; actions bindable
- [ ] no work while the picker is closed and rotation off (test)
- [ ] screenshots of empty/onboarding/error states; memory of the open picker measured

## Later
Day/night schedule · Wallhaven (D3) · video wallpapers · span · per-workspace.

## Wallhaven (K48 (3), card W24-media; D3)
**Others.** shellseikatsu `Services/WallhavenService.qml` (search via the public API, SFW keyless, `toplist` default,
categories `111`, download to `<wallpaper dir>/wallhaven/wallhaven-<id>.<ext>`, then apply); Caelestia and DMS have
no browser; Wallhaven's own site: Top / Latest / Random, General / Anime / People, SFW / Sketchy / NSFW (NSFW needs an
account key), 24 per page.

**Ours.** A second tab in the picker (*Library* · *Wallhaven*), sharing the targets, the theme switch and Apply.
- The tab is made only while shown; opening it runs one search (Top, all categories, **SFW only**); nothing is
  fetched before (Ma, sandbox check). Search on Return; Top / Latest / Random (a second press refreshes; Random keeps
  the daemon's seed while paging); General / Anime / People toggles (one stays on); SFW is fixed on, Sketchy opt-in,
  NSFW not offered in the picker (the action takes it only with an API key).
- The daemon (`wallpaper.wallhaven.search`) fetches the page's small thumbnails into
  `$XDG_CACHE_HOME/kurashi/wallpaper/wallhaven/` (6 at a time, trimmed at 600), so the picker shows local files; a
  missing thumbnail shows the picture's main colour and a mark.
- *Download and set* (or *… with theme* when the theme switch is on; Return in the grid) asks
  `wallpaper.wallhaven.download {id}` (the picture into `$XDG_DATA_HOME/kurashi/wallpaper/wallhaven/`, named after
  its real format; once), then the picker's own `wallpaper.set`. A saved picture carries ✓ and *saved*.
- Settings: `wallhaven` (on/off) and `wallhaven_api_key` (optional; sent as `X-API-Key`, never in a URL; stored as a
  plain setting until the manifest has a secret type, row 152).
- States: searching · results · nothing found · offline (*Try again*; the library still works) · refused: bad key,
  rate limited (45/min), Wallhaven off, a reply we cannot read · thumbnail missing · downloading · saved · backend
  down (Set disabled). A failed search clears the page (its results are not this search's).
- Keys: Tab to the field; Return searches; Down to the grid; arrows move; Return sets; PageUp / PageDown page; `/`
  back to the field.
- Shots: `frontend/shots/media/{picker-library,wallhaven,wallhaven-set,wallhaven-offline}-{sekai,none}.png`
  (`frontend/test-media.sh`, a fixture API on loopback via `KURASHI_WALLHAVEN_API`).
