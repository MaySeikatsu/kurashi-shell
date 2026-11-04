# Wallpaper Color Grade — UX brief (K88)
Status: agreed (user, session 22: prototype on their live shell, "that's sooo cool").

## Job
With one switch, the wallpaper belongs to the theme: whenever the theme's colours change, by a palette, a style or Dynamic
Media Color, the picture is recoloured to them, keeping its detail. Off, the picture is exactly itself.

## References
- **lutgen-rs** (Gaussian LUT from a palette), **gowall**, **dipc** (nearest colour by DeltaE), **ImageGoNord**: pictures forced
  to a palette, one result per palette whatever the picture. Taken as the optional `palette` mode.
- **Chang et al. 2015, "Palette-based Photo Recoloring"**: the picture's own palette paired with a target one, smoothly in
  between. The default here, automatic. **Reinhard et al. 2001**: colour transfer by mean and spread: `balance`.
- **Our Dynamic Media Color** (K87): the colours the grade follows while a track plays. **Our wallpaper bake** (K59): the
  way a picture reaches the backend, with its fade.

## Why a baked table, not a live shader
A prototype drew it live with a shader in its own process: about 181 MiB PSS with the picture against 88 MiB without, on one
nested output. That is most of the frontend's 150 MiB budget (rule 9), for a picture that changes every few minutes. A bake
costs nothing between changes (rule 5), and the backend's fade is already there. Traded away: the colour wheel blend does not
reach the wallpaper, which always fades. A live shader stays an idea for that and for wallpaper animations (I401).

## Design
- **Switch:** `theme.colors.wallpaper_grade.enabled`, off by default; it needs the Wallpaper mod, and says so.
- **How it recolours** (`mode`): `auto` (default) is `match` for a colourful picture and `gradient` for a nearly colourless one
  (mean chroma under 0.035); `match`, `balance`, `gradient`, `palette`.
- **Strength** (`strength`, 1) from the original to fully recoloured. **Follow the theme's brightness** (`lightness`, 0) keeps
  the picture's own light and dark by default, so it keeps its structure and the shell stays readable over it.
- **Targets:** surface, high container, selection, tertiary, secondary, accent, as in effect, so a track's colours count.

## States
Off · on, baking (the old picture stays until the new one fades in) · on, shown · a theme seen before: its file is reused ·
a bake that fails: the picture as is, and a log line · no Wallpaper mod: nothing happens, as the help says · a theme without all
six colours: the picture as is · texture baked into the wallpaper too (K59): grade first, relief over it.

## Keyboard, a11y
Ordinary Settings rows, from the schema. The picture's lightness stays by default, so no contrast depends on the grade.

## Multi-output
One bake per output's size, as K59 bakes; colours are read from the whole picture, so two crops of it grade alike.

## Fit
The filter behind `mod.wallpaper`: the mod's state keeps the picture's own path, so its picker, favourites, and palette
`wallpaper` (K34) still read the original and colours cannot feed back into themselves.

## Budget
Nothing between changes: no surface, no frame. One change: table about 10s of ms, the rest as the texture bake's re-bake.
Cache: the newest 24 bakes in `$XDG_CACHE_HOME/kurashi/texture/wallpaper`.

## Definition of done
`frontend/test-wallpaper-grade.sh`: off shows the picture; on shows a bake at the output's size with the original untouched and
the mod's path unchanged; palette, mode and strength bake anew, a theme seen before reuses its file; a track's colours grade it;
off shows the picture. `wallpaper_grade.rs`'s tests: the user's beige check turns the theme's hue, not grey.
