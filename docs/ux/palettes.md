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
| App icons | Original · Text colour · Palette tones · Palette colours | dock, window list, tray |
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
