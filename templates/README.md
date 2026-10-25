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
| `{{fonts.mono}}` | `monospace`, the generic family (the shell has no monospace choice yet) |
| `{{icons.theme}}` | `theme.icon_theme`; empty = leave as is |
| `{{scheme}}` | `dark` or `light`, the scheme in effect |
| `{{shape.radius}}` | `radius.lg` in px: the shell's panel corner (0 under `shape none`) |
| `{{shape.border}}` | the shell's outline width in px; 2 for flat chrome, which draws none |
| `{{motion.ms}}` | the standard motion duration in ms |
| `{{motion.curve}}` | the continuous easing as `cubic-bezier(…)` |
| `{{motion.niri}}` | niri's `animations {}` block for the motion profile and speed (calm, lively: springs; none: `off`) |
| `{{material.opacity}}` | the surface opacity in effect (1.00 when solid) |
| `{{paths.config}}` | `$XDG_CONFIG_HOME`, absolute |
| `{{gsettings.color_scheme}}` | `prefer-dark` or `default` (GNOME's colour scheme) |

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
- **gsettings**: `gsettings.ini` is applied, not written to a file. It sets `color-scheme`, `font-name` and
  `icon-theme` of `org.gnome.desktop.interface` (GNOME, GTK 4 and libadwaita apps read them), and only the values that
  differ from the current ones. The opt-in is the only consent: nothing else is changed. It needs `gsettings` on the
  daemon's PATH and a dconf session.

The shipped templates do not set a monospace font: the shell does not choose one yet (`{{fonts.mono}}` is there for
your own templates).
