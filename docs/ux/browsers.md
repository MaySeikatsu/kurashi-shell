# Zen and Firefox — UX brief
Status: implemented (functional) (I422, K100, session 24). Not yet tried on the user's own profile: to ask.

## Job
The browser reads as part of the desktop: the palette, the corners, the material on its sidebar and toolbar, translucency when asked. Today `kurashi/apps/zen.css` was written and nothing imported it, so only dark and light changed.

## References
- **Pywalfox** (`Frewacom/pywalfox`): native messaging plus `browser.theme.update`. Live, no restart, but only what the theme API reaches.
- **Zen** (`zen-browser/desktop`, branch dev, read 2026-11-07): `src/zen/common/styles/zen-browser-ui.css` paints sidebar and toolbar on `.zen-browser-generic-background`'s `::after` and `::before`, and `ZenGradientGenerator` sets `--zen-main-browser-background` per window on those elements themselves. So a variable on `:root`, even `!important`, never reaches them (this is why the old file only changed the rest). `--zen-border-radius`, `--zen-appcontent-border` work on `:root`. `prefs/zen/gtk.yaml`: `zen.widget.linux.transparency`.
- **Stylix, Catppuccin's Firefox**: colours through userChrome or a theme extension; a restart or an extension, the same choice.
- **GNOME, KDE**: no reach into browsers but `prefers-color-scheme`.

## What was checked: live updates with an extension
A small unsigned extension with `browser.theme.update`, in Zen Twilight on nested niri, in a fresh profile. Zen allows it: with `xpinstall.signatures.required = false` and a sideload it is active, unsigned. **But the colours do not reach Zen's sidebar or toolbar**: Zen paints those itself, over a lightweight theme. So Pywalfox's way gives Zen nothing visible, and it is not built. A browser's chrome is read at start: Settings says a restart shows a change. Firefox was not tried with the extension.

## Design
- **Profiles**: `profiles.ini` per machine, never a name in the code; `[Install…] Default` first, then `Default=1`; Settings lists them under the app, the one it opens first, each with **Link** or **Unlink**. A folder with none says so.
- **Link** is the one time the shell writes into a profile, and only on that click: the import first in `chrome/userChrome.css`, the prefs in a marked block of `user.js`. **Unlink** takes back exactly those lines. While linked, the block follows the toggles. A profile not linked is never written.
- **Palette**: `mozilla.css` as before, for both; Zen's background on its layers.
- **Corners and frame**: `--zen-border-radius` from `radius.window`, `--zen-appcontent-border` in the outline.
- **Material** (`theme.browser_material`, on): a tile, 80 % of the shell's relief, on Zen's layers and Firefox's toolbox and sidebar. Zen's own grain is off under it.
- **Translucent browser** (`theme.browser_translucent`): the layers at the surface's alpha, capped so text stays; no tile, as a picture is opaque; Zen's `zen.widget.linux.transparency` written to a linked profile. **Translucent pages** (`theme.browser_translucent_pages`): opt-in of its own, inert without it; `browser.tabs.allow_transparent_browser`.

## States
No browser or no ini: an empty list, said. Profile locked or running: the files are written all the same; shows after a restart. Light and dark: the scheme's palette. Material off or kind none: colours, corners, no tile. A user's own `userChrome.css`: kept; the import is first. High contrast: the material's own forcing applies.

## Keyboard, a11y, multi-output, budget
Link is a Settings button. Its name carries the profile. The browser's window is one per scheme: no per-output state. Tiles are baked on change only; nothing runs at rest.

## Fit
`theme.export`'s page; `docs/ux/terminal-texture.md` shares the baking. Ask the user about their own profile before Link is clicked there.

## Definition of done
- [x] `frontend/test-browsers.sh`: profiles from the ini, link and unlink byte for byte, the other profile alone, toggles move prefs. Real HOME not used.
- [x] Seen in Zen Twilight on nested niri in a fresh profile: palette, tile, corners, translucent UI.
- [ ] Translucent pages seen. Firefox's toolbox tile seen. The user's own profile.

## Another stylesheet in the profile (session 24)
A linked profile can still look untouched: the user's profile imported Noctalia's old theme right after ours, and its `!important` rules on the same elements won. Seen in Zen: the sidebar was Noctalia's grey, and only with that line gone did ours show. Settings names any other `@import` in a linked profile's `userChrome.css` and offers to turn it off: `theme.export.others {target, profile, on}` comments the line out with a mark, and that or Unlink brings it back, byte for byte. Nothing happens without the click. Ours also goes after the other imports now, so it wins a tie. Zen's element fill (grey at 80 %) under our colour goes transparent, or it dims a translucent colour.

## The tile's strength (session 24, I445)
At 0.8 of the shell's strength the tile measured a standard deviation of 0.013 and the user saw it "barely". **Material strength in browsers** (default 1.6, 0.4–3) sets it; chrome has little text, so it takes more than a terminal (0.45). Both switches say they are off while Translucent browser is on: the tile is opaque and would close what translucency opens.

## Fonts (K105)
With Fonts in apps on, the interface takes the shell's font, and a linked profile's pages fall back to it (`font.name.*` for Western and Unicode text) and to its monospaced font. Pages that name their own fonts keep them unless **Websites too** is on (`browser.display.use_document_fonts = 0`), which can turn a site's icon font into words or boxes, so it stays a separate opt-in. A restart of the browser shows either.
