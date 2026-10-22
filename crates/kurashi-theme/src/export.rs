//! App theme export (VISION "app theme export", M2 "exporter", K49): the final palette rendered through templates
//! into files other programs read — GTK, Qt, terminals, niri. The template language is matugen's colour subset
//! (`{{colors.<role>.<mode>.<format>}}`), so the templates DMS and shellseikatsu ship for matugen, and a user's own
//! matugen templates, work unchanged. Matugen's Material role names map onto ours (`primary` = `accent`, `background`
//! = `surface`, …); a name we cannot map is left in place and reported, never guessed silently (Shōjiki).
//!
//! Formats: `hex` (`#rrggbb`), `hex_stripped` (`rrggbb`), `rgb` (`rgb(r, g, b)`), `rgba` (`rgba(r, g, b, 1.0)`),
//! `red`/`green`/`blue` (0–255). Modes `default`, `dark` and `light` all give the current scheme: kurashi resolves one
//! scheme at a time.

use std::collections::BTreeSet;

use crate::color::{BLACK, Rgb, WHITE};
use crate::palette::Palette;

/// A matugen role name as one of ours, or a colour derived from ours.
pub fn role(p: &Palette, name: &str) -> Option<Rgb> {
    let g = |r: &str| p.roles.get(r).copied();
    let tone = |base: Rgb, amount: f64| {
        // Material "container" roles: the base pulled towards the surface.
        base.mix(
            g("surface").unwrap_or(if p.dark { BLACK } else { WHITE }),
            amount,
        )
    };
    Some(match name {
        "primary" | "source_color" | "surface_tint" => g("accent")?,
        "on_primary" => g("on_accent")?,
        "primary_container" | "primary_fixed" | "primary_fixed_dim" | "inverse_primary" => {
            g("accent_container")?
        }
        "on_primary_container" | "on_primary_fixed" | "on_primary_fixed_variant" => {
            g("on_accent_container")?
        }
        "secondary_container" | "secondary_fixed" | "secondary_fixed_dim" => {
            tone(g("secondary")?, 0.65)
        }
        "on_secondary_container" | "on_secondary_fixed" | "on_secondary_fixed_variant" => {
            g("on_surface")?
        }
        "tertiary_container" | "tertiary_fixed" | "tertiary_fixed_dim" => {
            tone(g("tertiary")?, 0.65)
        }
        "on_tertiary_container" | "on_tertiary_fixed" | "on_tertiary_fixed_variant" => {
            g("on_surface")?
        }
        "error_container" => tone(g("error")?, 0.65),
        "on_error_container" => g("on_surface")?,
        "background" | "surface_dim" => g("surface")?,
        "on_background" => g("on_surface")?,
        "surface_bright" => g("surface_container_highest")?,
        "surface_variant" => g("surface_container_highest")?,
        "inverse_surface" => g("on_surface")?,
        "inverse_on_surface" => g("surface")?,
        other => g(other)?,
    })
}

fn format(c: Rgb, fmt: &str) -> Option<String> {
    let Rgb(r, g, b) = c;
    Some(match fmt {
        "hex" => c.hex(),
        "hex_stripped" => c.hex().trim_start_matches('#').to_owned(),
        "rgb" => format!("rgb({r}, {g}, {b})"),
        "rgba" => format!("rgba({r}, {g}, {b}, 1.0)"),
        "red" => r.to_string(),
        "green" => g.to_string(),
        "blue" => b.to_string(),
        _ => return None,
    })
}

/// `template` with every `{{colors.<role>.<mode>.<format>}}` filled in, and the placeholders that could not be (left
/// as they were). Other `{{…}}` (matugen's image or custom keys) are left and reported too.
pub fn render(template: &str, p: &Palette) -> (String, BTreeSet<String>) {
    let mut out = String::with_capacity(template.len());
    let mut unknown = BTreeSet::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        out.push_str(&rest[..start]);
        let Some(len) = rest[start..].find("}}") else {
            out.push_str(&rest[start..]);
            rest = "";
            break;
        };
        let whole = &rest[start..start + len + 2];
        let inner = whole[2..whole.len() - 2].trim();
        let filled = inner.strip_prefix("colors.").and_then(|path| {
            let mut parts = path.split('.');
            let (name, mode, fmt) = (parts.next()?, parts.next()?, parts.next()?);
            if parts.next().is_some() || !matches!(mode, "default" | "dark" | "light") {
                return None;
            }
            format(role(p, name)?, fmt)
        });
        match filled {
            Some(v) => out.push_str(&v),
            None => {
                unknown.insert(inner.to_owned());
                out.push_str(whole);
            }
        }
        rest = &rest[start + len + 2..];
    }
    out.push_str(rest);
    (out, unknown)
}

/// A bundled export target: its name (`theme.export` lists these), the template file under `templates/`, where the
/// file goes (relative to `$XDG_CONFIG_HOME`; `@data/…` to `$XDG_DATA_HOME`), and the line the program's own config needs to read it, when it does
/// not read the file by itself.
pub struct Target {
    pub name: &'static str,
    pub template: &'static str,
    pub path: &'static str,
    pub include: Option<(&'static str, &'static str)>,
}

/// The targets, in the order Settings lists them. `include` = (the config file, the line it must hold).
pub const TARGETS: &[Target] = &[
    Target {
        name: "gtk3",
        template: "gtk-colors.css",
        path: "gtk-3.0/kurashi-colors.css",
        include: Some(("gtk-3.0/gtk.css", "@import 'kurashi-colors.css';")),
    },
    Target {
        name: "gtk4",
        // libadwaita 1.6+ reads CSS variables: GTK 4 gets them besides the named colours (GTK 3 would warn on them).
        template: "gtk4-colors.css",
        path: "gtk-4.0/kurashi-colors.css",
        include: Some(("gtk-4.0/gtk.css", "@import 'kurashi-colors.css';")),
    },
    Target {
        name: "qt",
        template: "qtct-colors.conf",
        path: "qt6ct/colors/kurashi.conf",
        include: None,
    },
    Target {
        name: "qt5",
        template: "qtct-colors.conf",
        path: "qt5ct/colors/kurashi.conf",
        include: None,
    },
    // KDE apps take their colours from a KDE colour scheme over the Qt palette: one for them to pick, in
    // `$XDG_DATA_HOME` (the `@data/` prefix), where their Window Color Scheme menu lists it.
    Target {
        name: "kde",
        template: "kde-colors.colors",
        path: "@data/color-schemes/Kurashi.colors",
        include: None,
    },
    Target {
        name: "foot",
        template: "foot.ini",
        path: "foot/kurashi-colors.ini",
        include: Some(("foot/foot.ini", "include=~/.config/foot/kurashi-colors.ini")),
    },
    Target {
        name: "kitty",
        template: "kitty.conf",
        path: "kitty/kurashi-colors.conf",
        include: Some(("kitty/kitty.conf", "include kurashi-colors.conf")),
    },
    Target {
        name: "alacritty",
        template: "alacritty.toml",
        path: "alacritty/kurashi-colors.toml",
        include: Some((
            "alacritty/alacritty.toml",
            "general.import = [\"~/.config/alacritty/kurashi-colors.toml\"]",
        )),
    },
    Target {
        name: "ghostty",
        template: "ghostty.conf",
        path: "ghostty/themes/kurashi",
        include: Some(("ghostty/config", "theme = kurashi")),
    },
    Target {
        name: "niri",
        template: "niri-colors.kdl",
        path: "niri/kurashi-colors.kdl",
        include: Some(("niri/config.kdl", "include \"kurashi-colors.kdl\"")),
    },
];

pub fn target(name: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|t| t.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn palette() -> Palette {
        let mut roles = BTreeMap::new();
        for (r, c) in [
            ("surface", Rgb(0x1b, 0x1a, 0x1e)),
            ("on_surface", Rgb(0xe9, 0xe4, 0xd8)),
            ("accent", Rgb(0xc9, 0x40, 0x4b)),
            ("on_accent", Rgb(0xff, 0xf6, 0xf1)),
            ("secondary", Rgb(0x5b, 0x7f, 0xa6)),
            ("error", Rgb(0xe4, 0x69, 0x62)),
        ] {
            roles.insert(r.to_owned(), c);
        }
        Palette {
            name: "t".into(),
            dark: true,
            roles,
        }
    }

    #[test]
    fn matugen_placeholders_fill_from_our_roles() {
        let (s, unknown) = render(
            "bg={{colors.background.default.hex}} fg={{ colors.on_surface.dark.hex_stripped }} \
             a={{colors.primary.default.red}},{{colors.primary.default.green}} {{image}} {{colors.nope.default.hex}}",
            &palette(),
        );
        assert_eq!(
            s,
            "bg=#1b1a1e fg=e9e4d8 a=201,64 {{image}} {{colors.nope.default.hex}}"
        );
        assert_eq!(
            unknown.into_iter().collect::<Vec<_>>(),
            vec!["colors.nope.default.hex", "image"]
        );
    }

    #[test]
    fn containers_are_derived_and_every_target_template_exists() {
        assert!(role(&palette(), "secondary_container").is_some());
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        for t in TARGETS {
            assert!(
                root.join(t.template).is_file(),
                "{} lacks templates/{}",
                t.name,
                t.template
            );
        }
    }
}
