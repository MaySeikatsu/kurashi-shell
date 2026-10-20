# App theme templates (K49)

kurashid renders these with the final palette into the files listed in `crates/kurashi-theme/src/export.rs`
(`TARGETS`), for the targets named in `theme.export`. The syntax is matugen's colour subset
(`{{colors.<role>.<default|dark|light>.<hex|hex_stripped|rgb|rgba|red|green|blue>}}`), so matugen templates work as
they are. A file of the same name in `~/.config/kurashi/templates/` replaces the bundled one.

Sources: `gtk-colors.css`, `qtct-colors.conf`, `niri-colors.kdl` from DankMaterialShell (MIT, Copyright (c) 2025
Avenge Media LLC, https://github.com/AvengeMedia/DankMaterialShell); the terminal templates (`foot.ini`, `kitty.conf`,
`alacritty.toml`, `ghostty.conf`) from shellseikatsu.
