#!/usr/bin/env python3
"""Generate `palettes/<id>.toml` for the common palettes (I451) from their official kitty themes.

The kitty files (kovidgoyal/kitty-themes, each naming its upstream and licence) carry the authors' own terminal colours,
which go into `[<scheme>.terminal]` verbatim (I454: apps that follow get the real palette). The shell's roles are taken
from those colours by the table below: background/foreground as ground and ink, the palette's signature hue as accent.

Usage: tools/palettes/from_kitty.py <dir with the .conf files> <palettes dir>
Re-run after a palette's upstream changes; the output is committed.
"""

import sys
from pathlib import Path

# id: (family, variant, dark conf, light conf or None, accent, secondary, tertiary, description)
# accent/secondary/tertiary: an ANSI index (0..15) into that scheme's colours, or a "#rrggbb" pair (dark, light)
# when the palette's signature hue is not among its terminal colours (Catppuccin's mauve).
SPEC = {
    "catppuccin-macchiato": ("Catppuccin", "Macchiato", "Catppuccin-Macchiato", "Catppuccin-Latte",
                             ("#c6a0f6", "#8839ef"), 4, 5, "Catppuccin Macchiato / Latte"),
    "catppuccin-frappe": ("Catppuccin", "Frappé", "Catppuccin-Frappe", "Catppuccin-Latte",
                          ("#ca9ee6", "#8839ef"), 4, 5, "Catppuccin Frappé / Latte"),
    "rose-pine-moon": ("Rosé Pine", "Moon", "rose-pine-moon", "rose-pine-dawn", 5, 4, 6, "Rosé Pine Moon / Dawn"),
    "tokyo-night-storm": ("Tokyo Night", "Storm", "tokyo_night_storm", "tokyo_night_day", 4, 5, 6,
                          "Tokyo Night Storm / Day"),
    "tokyo-night-moon": ("Tokyo Night", "Moon", "tokyo_night_moon", "tokyo_night_day", 4, 5, 6,
                         "Tokyo Night Moon / Day"),
    "gruvbox": ("Gruvbox", "Medium", "gruvbox-dark", "gruvbox-light", 11, 12, 14, "Gruvbox, retro groove"),
    "gruvbox-hard": ("Gruvbox", "Hard", "gruvbox-dark-hard", "gruvbox-light", 11, 12, 14, "Gruvbox hard contrast"),
    "gruvbox-soft": ("Gruvbox", "Soft", "gruvbox-dark-soft", "gruvbox-light", 11, 12, 14, "Gruvbox soft contrast"),
    "gruvbox-material": ("Gruvbox Material", "Medium", "GruvboxMaterialDarkMedium", "GruvboxMaterialLightMedium",
                         3, 4, 6, "Gruvbox Material, softer"),
    "nord": ("Nord", "", "Nord", None, 6, 4, 5, "Nord, arctic frost"),
    "dracula": ("Dracula", "", "Dracula", "Alucard", 4, 5, 6, "Dracula / Alucard"),
    "everforest": ("Everforest", "Medium", "everforest_dark_medium", "everforest_light_medium", 2, 4, 5,
                   "Everforest, green and warm"),
    "kanagawa": ("Kanagawa", "Wave", "kanagawa", "kanagawa_light", 4, 5, 3, "Kanagawa Wave / Lotus"),
    "kanagawa-dragon": ("Kanagawa", "Dragon", "kanagawa_dragon", "kanagawa_light", 4, 5, 3,
                        "Kanagawa Dragon / Lotus"),
    "solarized": ("Solarized", "", "Solarized_Dark", "Solarized_Light", 4, 6, 5, "Solarized dark / light"),
    "one": ("One", "", "OneDark", "AtomOneLight", 4, 5, 6, "One Dark / One Light (Atom)"),
    "monokai": ("Monokai", "Classic", "Monokai_Classic", None, 1, 6, 2, "Monokai, the classic"),
    "ayu": ("Ayu", "Dark", "ayu", "ayu_light", 3, 4, 6, "Ayu Dark / Light"),
    "ayu-mirage": ("Ayu", "Mirage", "ayu_mirage", "ayu_light", 3, 4, 6, "Ayu Mirage / Light"),
    "nightfox": ("Nightfox", "Nightfox", "Nightfox", "Dayfox", 4, 5, 6, "Nightfox / Dayfox"),
    "carbonfox": ("Nightfox", "Carbonfox", "Carbonfox", "Dayfox", 4, 5, 6, "Carbonfox / Dayfox"),
    "duskfox": ("Nightfox", "Duskfox", "Duskfox", "Dawnfox", 4, 5, 6, "Duskfox / Dawnfox"),
    "nordfox": ("Nightfox", "Nordfox", "Nordfox", "Dayfox", 4, 5, 6, "Nordfox / Dayfox"),
    "terafox": ("Nightfox", "Terafox", "Terafox", "Dayfox", 4, 5, 6, "Terafox / Dayfox"),
}

# Palettes the shell already ships with hand-picked roles: only metadata and the terminal tables are added.
EXISTING = {
    "catppuccin": ("Catppuccin", "Mocha", "Catppuccin-Mocha", "Catppuccin-Latte"),
    "rose-pine": ("Rosé Pine", "Main", "rose-pine", "rose-pine-dawn"),
    "tokyo-night": ("Tokyo Night", "Night", "tokyo_night_night", "tokyo_night_day"),
}

# Palettes whose authors published no light scheme: a light one written from their own colours (K53: every palette
# has both, authored). No terminal table for these: there is none to be faithful to.
AUTHORED_LIGHT = {
    # Nord's style guide: Snow Storm as the ground of bright designs, Polar Night as text, Frost and Aurora as accents.
    "nord": {"surface": "#eceff4", "on_surface": "#2e3440", "outline": "#4c566a", "accent": "#5e81ac",
             "secondary": "#81a1c1", "tertiary": "#b48ead", "success": "#a3be8c", "warning": "#d08770",
             "error": "#bf616a"},
    # Monokai's own accents on a warm paper; the wcag stage deepens them as far as text needs.
    "monokai": {"surface": "#fafaf8", "on_surface": "#272822", "outline": "#75715e", "accent": "#f92672",
                "secondary": "#66d9ef", "tertiary": "#a6e22e", "success": "#a6e22e", "warning": "#e6db74",
                "error": "#f92672"},
}

TERM_KEYS = ["background", "foreground", "cursor", "cursor_text_color", "selection_background",
             "selection_foreground"]


def read_conf(path: Path) -> tuple[dict, dict]:
    vals, meta = {}, {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith("## ") and ":" in line:
            k, v = line[3:].split(":", 1)
            meta[k.strip()] = v.strip()
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1].startswith("#") and len(parts[1]) == 7:
            vals[parts[0]] = parts[1].lower()
    missing = [f"color{i}" for i in range(16) if f"color{i}" not in vals]
    if missing or "background" not in vals or "foreground" not in vals:
        raise SystemExit(f"{path}: missing {missing or 'background/foreground'}")
    return vals, meta


def pick(sel, vals: dict, light: bool) -> str:
    if isinstance(sel, tuple):
        return sel[1] if light else sel[0]
    return vals[f"color{sel}"]


def roles(vals: dict, accent, secondary, tertiary, light: bool) -> list[str]:
    # A light scheme's bright ANSI colours are often too pale for UI; the normal ones (0..7) read better there.
    def idx(sel):
        if isinstance(sel, int) and light and sel >= 8:
            return sel - 8
        return sel
    lines = [
        f'surface = "{vals["background"]}"',
        f'on_surface = "{vals["foreground"]}"',
        f'outline = "{vals["color8"]}"',
        f'accent = "{pick(idx(accent), vals, light)}"',
        f'secondary = "{pick(idx(secondary), vals, light)}"',
        f'tertiary = "{pick(idx(tertiary), vals, light)}"',
        f'success = "{vals["color2"]}"',
        f'warning = "{vals["color3"]}"',
        f'error = "{vals["color1"]}"',
    ]
    return lines


def terminal(vals: dict) -> list[str]:
    out = [f'{k} = "{vals[k]}"' for k in TERM_KEYS if k in vals]
    cols = ", ".join(f'"{vals[f"color{i}"]}"' for i in range(16))
    out.append(f"colors = [{cols}]")
    return out


def source_line(meta: dict) -> str:
    up = meta.get("upstream", "kovidgoyal/kitty-themes")
    lic = meta.get("license", "see upstream")
    return f"{up} ({lic})"


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    for pid, (family, variant, dark, light, acc, sec, ter, desc) in SPEC.items():
        dv, dm = read_conf(src / f"{dark}.conf")
        lv, lm = read_conf(src / f"{light}.conf") if light else (None, None)
        head = [
            f"# {family}{' ' + variant if variant else ''} — generated by tools/palettes/from_kitty.py (I451) from the",
            "# authors' kitty themes; the terminal tables are theirs verbatim. Edit the generator, not this file.",
            f"# dark: {source_line(dm)}",
        ]
        if lm:
            head.append(f"# light: {source_line(lm)}")
        body = [
            f'name = "{pid}"',
            f'kind = "{"pair" if light or pid in AUTHORED_LIGHT else "dark"}"',
            f'description = "{desc}"',
            'category = "common"',
            f'family = "{family}"',
        ]
        if variant:
            body.append(f'variant = "{variant}"')
        body += ["", "[dark]", *roles(dv, acc, sec, ter, False), "", "[dark.terminal]", *terminal(dv)]
        if lv:
            body += ["", "[light]", *roles(lv, acc, sec, ter, True), "", "[light.terminal]", *terminal(lv)]
        elif pid in AUTHORED_LIGHT:
            body += ["", "[light]", *(f'{k} = "{v}"' for k, v in AUTHORED_LIGHT[pid].items())]
        (dst / f"{pid}.toml").write_text("\n".join(head + body) + "\n")
        print(dst / f"{pid}.toml")
    for pid, (family, variant, dark, light) in EXISTING.items():
        path = dst / f"{pid}.toml"
        text = path.read_text()
        if "[dark.terminal]" in text:
            continue
        dv, _ = read_conf(src / f"{dark}.conf")
        lv, _ = read_conf(src / f"{light}.conf")
        meta = f'category = "common"\nfamily = "{family}"\nvariant = "{variant}"\n'
        text = text.replace("\n[dark]\n", f"\n{meta}\n[dark]\n", 1)
        text = text.replace("\n[light]\n", "\n[dark.terminal]\n" + "\n".join(terminal(dv)) + "\n\n[light]\n", 1)
        text = text.rstrip("\n") + "\n\n[light.terminal]\n" + "\n".join(terminal(lv)) + "\n"
        path.write_text(text)
        print(path, "(terminal tables added)")


if __name__ == "__main__":
    main()
