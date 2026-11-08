# App theme templates (K49, W34)

kurashid renders these from the theme in effect into the files of the targets named in `theme.export`
(`crates/kurashi-theme/src/export.rs`, `TARGETS`). kurashid never edits an app's own config: Settings ("Apps that
follow") shows each line the app needs, with a Copy key. A file of the same name in `~/.config/kurashi/templates/`
(`lines/` for the line templates) replaces the bundled one.

Placeholders: `{{colors.<role>.<default|dark|light>.<hex|hex_stripped|rgb|rgba|red|green|blue>}}` (matugen's syntax,
so matugen templates work unchanged), and:

| Placeholder | Value |
|---|---|
| `{{fonts.family}}` | the first installed family of `theme.typography.family` |
| `{{fonts.size}}` | the body size in points (px × 0.75, to the half point: 13 px → 10) |
| `{{fonts.mono}}` | the shell's monospaced font, `theme.typography.mono` resolved (`font.family_mono`, K104) |
| `{{icons.theme}}` | `theme.icon_theme`; empty = leave as is |
| `{{scheme}}` | `dark` or `light`, the scheme in effect |
| `{{shape.radius}}` | `radius.lg` in px: the shell's panel corner (0 under `shape none`) |
| `{{shape.border}}` | the shell's outline width in px; 2 for flat chrome, which draws none |
| `{{motion.ms}}` | the standard motion duration in ms |
| `{{motion.curve}}` | the continuous easing as `cubic-bezier(…)` |
| `{{motion.niri}}` | niri's `animations {}` block for the motion profile and speed (calm, lively: springs; none: `off`); empty with `theme.window_animations` off |
| `{{motion.hyprland}}`, `{{motion.mango}}` | the same for Hyprland (`animations {}`: a `kurashi` bezier from the continuous curve, speed from the standard duration) and MangoWM (`animation_*` keys); empty with `theme.window_animations` off |
| `{{frame.niri.ring}}`, `{{frame.niri.border}}`, `{{frame.hyprland}}`, `{{frame.mango}}`, `{{frame.sway}}` | `theme.window_frame` on: the frame at `{{shape.border}}` (niri: `off` for the focus ring, `on` for the border); off: empty, the compositor keeps its own |
| `{{frame.active.hex}}`, `{{frame.active.hex_stripped}}` | the colour round the focused window (`theme.window_frame_color`): the accent, the shell's outline ink or a palette role |
| `{{opacity.niri}}`, `{{opacity.hyprland}}`, `{{opacity.mango}}` | `theme.inactive_transparent` on: unfocused windows at `theme.inactive_opacity` (niri: a `window-rule` on `is-focused=false`); off: empty |
| `{{titlebar.sway}}`, `{{titlebar.hyprland}}` | `theme.window_titlebars` on: sway's `default_border normal` and font; Hyprland's `plugin { hyprbars { … } }` block (the plugin must be loaded); off: empty |
| `{{ghostty.shader}}` | the ghostty target only: `custom-shader = <abs path>` and `custom-shader-animation = false` while the material is on for the shell (scope shell / shell_wallpaper, a known kind), else empty; the shader is `ghostty/shaders/kurashi.glsl` (I174, row 403) |
| `{{terminal.image}}` | a terminal's line for its faint material picture (K99): Kitty's `background_image` lines (empty when off), WezTerm's `background` table (`nil` when off) |
| `{{material.opacity}}` | the surface opacity in effect (1.00 when solid) |
| `{{paths.config}}` | `$XDG_CONFIG_HOME`, absolute |
| `{{gsettings.color_scheme}}` | `prefer-dark` or `default` (GNOME's colour scheme) |

An include line may name these values too (Firefox's `@import` names `{{paths.config}}`), and an include file that starts
with `~/` sits under `$HOME` (Zen's profile), not `$XDG_CONFIG_HOME`.

A placeholder with no value is reported as unknown and left in the file. A line whose value is empty
(`icon_theme=` with no icon theme chosen, `icon-theme=''`) is not written: the app keeps its own choice.

## Targets

- **gtk3, gtk4**: `gtk-colors.css` (GTK 4 also gets libadwaita's CSS variables). Add the `@import` line to `gtk.css`.
- **qt, qt5**: `qtct-colors.conf` is the colour file. `lines/qt6ct.conf` (`lines/qt5ct.conf`) holds the lines qt6ct.conf
  needs: `color_scheme_path`, `custom_palette=true`, `icon_theme`, and `general` (the font).
- **kde**: `kde-colors.colors` as the Kurashi colour scheme (`$XDG_DATA_HOME/color-schemes/`). `lines/kdeglobals.conf`
  holds `ColorScheme=Kurashi`, `[Icons] Theme` and `[General] font`.
- **foot, kitty, alacritty, ghostty**: the colour file, read by one include line each.
- **niri**: `niri-colors.kdl` is written as `niri/kurashi.kdl`: focus ring and border (width and colours), shadow,
  the window corner rule (`geometry-corner-radius`, with `clip-to-geometry true`) and the animations. Include it
  after your own `layout`, `window-rule` and `animations` blocks: `include "kurashi.kdl"`. The shell owns six
  animations there (workspace-switch, horizontal-view-movement, window-open, window-close, window-movement,
  window-resize); the others keep niri's. `clip-to-geometry true` clips windows to the corner radius, so it also
  clips their client-side shadows. Earlier versions wrote
  `kurashi-colors.kdl`; that file is now a comment-only stub, so an old include still loads, and Settings marks its
  line as stale. Replace it with the new line.
- **zellij**: `zellij/themes/kurashi.kdl` (`theme "kurashi"` in `config.kdl`).
- **fzf**: `kurashi/apps/fzf`, an options file of `--color` lines for fzf 0.47+, read through `FZF_DEFAULT_OPTS_FILE`
  (fish: `set -gx FZF_DEFAULT_OPTS_FILE …` in `config.fish`; bash/zsh: `export`). noren's picker is fzf, so noren follows
  through it (and zellij's theme around it).
- **nvim**: `nvim/colors/kurashi.lua`, a colour scheme (`vim.cmd.colorscheme("kurashi")` in `init.lua`; it is read when
  the scheme is loaded, so `:colorscheme kurashi` again after a theme change).
- **helix**: `helix/themes/kurashi.toml` (`theme = "kurashi"`, then `:config-reload`).
- **zed**: `zed/themes/kurashi.json`, a theme family with one theme in the scheme in effect (`"theme": "Kurashi",` in
  `settings.json`; Zed watches the folder).
- **firefox, zen**: `mozilla.css` written as `kurashi/apps/firefox.css` (`zen.css`), the browser chrome's variables
  (Zen's own included). `@import url("file://…");` at the very top of the profile's `chrome/userChrome.css`, and
  `toolkit.legacyUserProfileCustomizations.stylesheets` = true in `about:config` (Zen has it on). Restart to reload.
- **vesktop**: `vesktop/themes/kurashi.css`, Discord's CSS variables (old and refreshed names). Enable it in Vesktop:
  Settings → Vencord → Themes. No config line.
- **spicetify**: `spicetify/Themes/Kurashi/color.ini`; `lines/spicetify.ini` holds `current_theme` and `color_scheme`
  for `config-xpui.ini`. Spotify takes the colours on `spicetify apply`: run it after a theme change (the shell runs
  nothing).
- **obsidian**: `kurashi/apps/obsidian.css`, Obsidian's CSS variables. Link it into each vault and enable it under
  Settings → Appearance → CSS snippets: `ln -s ~/.config/kurashi/apps/obsidian.css <vault>/.obsidian/snippets/kurashi.css`.
- **hyprland**: `hypr/kurashi.conf` (`source = ~/.config/hypr/kurashi.conf` at the end of `hyprland.conf`): border
  colours, groups, corner radius, shadow, background; frame, see-through, animations and titlebars as switched.
- **mango**: `mango/kurashi.conf` (`source=~/.config/mango/kurashi.conf` at the end of `config.conf`): border, focus and
  urgent colours, the root colour, corner radius; frame, see-through and animations as switched (no titlebars).
- **sway**: `sway/kurashi.conf` (`include ~/.config/sway/kurashi.conf`): `client.*` colours; frame and titlebars as
  switched (sway has no animations and no unfocused opacity).
- **gsettings**: `gsettings.ini` is applied, not written to a file. It sets `color-scheme`, `font-name` and
  `icon-theme` of `org.gnome.desktop.interface` (GNOME, GTK 4 and libadwaita apps read them), and only the values that
  differ from the current ones. The opt-in is the only consent: nothing else is changed. It needs `gsettings` on the
  daemon's PATH and a dconf session.

The shipped templates set the fonts only while `theme.export_fonts` is on (K104, K105): `{{fonts.ui_gtk}}`, `{{fonts.ui_qt}}`, `{{vesktop.fonts}}`, `{{obsidian.fonts}}`, `{{browser.fonts}}` for the shell's font, and `{{ghostty.font}}`, `{{kitty.font}}`, `{{wezterm.font}}`, `{{foot.font}}`, `{{alacritty.font}}`, `{{fonts.mono_gtk}}`, `{{fonts.mono_qt}}` are each app's lines, empty (`nil` for WezTerm) while it is off, so each app keeps its own.
