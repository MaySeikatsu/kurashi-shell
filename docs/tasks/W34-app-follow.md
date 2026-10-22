# Card W34-app-follow — apps follow the shell: light/dark, fonts, icons, and the compositor's shape (I183, I184, I175)

**User (session 13):** wants every Qt/GTK app to follow the shell by default ("Nautilus and Dolphin … every qt/gtk app by
default to follow it"); "it would also be nice if icons and fonts could be inherited too"; earlier "export animations,
themes, corner radius, darkmode, transparency, blur to niri/compositor to let it match the shell's settings".

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K49 (the exporter: kurashid writes its own files, never
edits an app's own config; reports the include line); `crates/kurashi-theme/src/export.rs`,
`crates/kurashid/src/theme_export.rs`, `templates/**` (+ README), `settings/components/ThemeExportStatus.qml`,
`i18n/*/theme-export.toml`, `nix/hm-module.nix` (themeExport), the schema keys `theme.export`, `theme.icon_theme` (new,
choices from `icon_themes`), `theme.typography.*`, `theme.shape.*`, `theme.motion.*`, `theme.material.*`.

**Task:**
1. **Template placeholders beyond colours:** `{{fonts.family}}`, `{{fonts.size}}`, `{{fonts.mono}}`, `{{icons.theme}}`,
   `{{scheme}}` (`dark`/`light`), `{{shape.radius}}` (px), `{{shape.border}}`, `{{motion.ms}}`, `{{motion.curve}}`,
   `{{material.opacity}}` — rendered from the theme document (tokens) and config; unknown → reported as today.
2. **Targets:**
   - `gsettings` (new, opt-in like every target): sets `org.gnome.desktop.interface` `color-scheme` (prefer-dark /
     default from the effective scheme), `font-name`, `monospace-font-name`, `icon-theme` (when `theme.icon_theme` is set)
     — only when a value changed; `svc.theme_export` reports what it set. This is the only target that writes settings
     instead of a file: say so in its Settings help (Shōjiki) and DECISIONS amendment text in your report.
   - GTK 3/4 colour files: unchanged (+ `gtk4-colors.css` keeps the libadwaita variables).
   - Qt (qt6ct/qt5ct): the colour file as today; report the `icon_theme=` / font lines `qt6ct.conf` needs (include lines;
     kurashid does not edit it).
   - `kde`: `Kurashi.colors` as today plus the icon theme / fonts lines for `kdeglobals` as include-lines.
   - `niri` (I175): extend `niri-colors.kdl` into the layout the shell can own: focus ring and border colours/width,
     `geometry-corner-radius` window rule from `shape.radius`, an `animations {}` block from the motion profile
     (calm/lively/none → spring params), shadow colour — as an include niri reads (`include "kurashi.kdl"`); report the
     include line.
3. **Settings:** the "Apps that follow" status lists each target's state and lines (existing component; add gsettings
   and the new include lines); `theme.icon_theme` row works (the offers exist).
4. **HM module:** `themeExport.apps` enum gains `gsettings`; for Qt add the qt6ct `icon_theme`/font lines when
   `qt.enable` and the HM module owns `qt6ct.conf` is NOT assumed — just document.
5. **Tests:** unit tests for every new placeholder and target (temp dirs; gsettings through a fake/keyfile backend —
   `GSETTINGS_BACKEND=keyfile` with a temp `XDG_CONFIG_HOME`); `cargo test -p kurashi-theme -p kurashid`; niri include
   validated with `niri validate` on a temp config that includes the rendered file.

**Owned paths:** `crates/kurashi-theme/src/export.rs`, `crates/kurashid/src/theme_export.rs`, `templates/**`,
`settings/components/ThemeExportStatus.qml`, `i18n/{en,ja}/theme-export.toml`, `nix/hm-module.nix` (themeExport only).
Not the schema (frozen — a needed key → CONTRACT-CHANGE row), not other kurashid files beyond a one-line register call.

**Acceptance:** tests green incl. `niri validate` of the rendered include; `cargo clippy -p kurashi-theme -p kurashid
--all-targets -- -D warnings`; a short how-to in `templates/README.md` (what each app needs, one line each).

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w34-app CARGO_BUILD_JOBS=4`; never touch the user's real
gsettings or config files (temp dirs only). Model: haiku (max effort).
