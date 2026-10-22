//! App theme export (VISION "app theme export", M2 "exporter", K49, W34): the final palette and the theme's tokens
//! rendered through templates into files other programs read — GTK, Qt, KDE, terminals, niri — and the desktop's
//! settings (gsettings), the one target that writes settings instead of a file. The template language is matugen's
//! colour subset (`{{colors.<role>.<mode>.<format>}}`), so the templates DMS and shellseikatsu ship for matugen, and a
//! user's own matugen templates, work unchanged. Matugen's Material role names map onto ours (`primary` = `accent`,
//! …); a name we cannot map is left in place and reported, never guessed silently (Shōjiki).
//!
//! Beyond colours (W34) a template names values of the theme in effect: see [`values`] and templates/README.md.
//!
//! Formats: `hex` (`#rrggbb`), `hex_stripped` (`rrggbb`), `rgb` (`rgb(r, g, b)`), `rgba` (`rgba(r, g, b, 1.0)`),
//! `red`/`green`/`blue` (0–255). Modes `default`, `dark` and `light` all give the current scheme: kurashi resolves one
//! scheme at a time.

use std::collections::{BTreeMap, BTreeSet};

use serde_json::Value;

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

/// `{{colors.<role>.<mode>.<format>}}` filled from the palette.
fn colour(p: &Palette, path: &str) -> Option<String> {
    let mut parts = path.split('.');
    let (name, mode, fmt) = (parts.next()?, parts.next()?, parts.next()?);
    if parts.next().is_some() || !matches!(mode, "default" | "dark" | "light") {
        return None;
    }
    format(role(p, name)?, fmt)
}

/// Every value a template names besides the palette's colours, by its dotted name (W34). Built once per export run
/// by [`values`]; a name missing from the map is reported as unknown, like a misspelt colour.
pub type Values = BTreeMap<String, String>;

/// Where the values come from: the theme document's tokens and scheme in effect, the config values the apps follow,
/// and the config home the lines point into.
pub struct Inputs<'a> {
    pub tokens: &'a serde_json::Map<String, Value>,
    /// `dark` or `light`: the scheme in effect (the theme document's `appearance.scheme_effective`).
    pub scheme: &'a str,
    /// `theme.icon_theme`; "" = leave each app's own choice (I183).
    pub icon_theme: &'a str,
    /// `theme.motion.speed`.
    pub motion_speed: f64,
    /// `$XDG_CONFIG_HOME`, absolute.
    pub config_dir: &'a str,
}

/// The shell's values as templates name them. Typography, shape, motion and material are the tokens in effect (a
/// value the theme does not carry is absent and reported, never invented); the icon theme and the config home come
/// from the config and the paths. Shipped templates: templates/README.md.
pub fn values(i: &Inputs) -> Values {
    let num = |k: &str| i.tokens.get(k).and_then(Value::as_f64);
    let mut v = Values::new();
    if let Some(f) = i.tokens.get("font.family").and_then(Value::as_str) {
        v.insert("fonts.family".into(), f.into());
    }
    if let Some(px) = num("font.size.body") {
        v.insert("fonts.size".into(), pt(px));
    }
    // The shell has no monospace choice of its own (a CONTRACT-CHANGE row asks for one): the generic family, which
    // fontconfig maps to the installed one. The shipped templates do not set it, so a user's font stays.
    v.insert("fonts.mono".into(), "monospace".into());
    v.insert("icons.theme".into(), i.icon_theme.into());
    v.insert("scheme".into(), i.scheme.into());
    v.insert(
        "gsettings.color_scheme".into(),
        if i.scheme == "light" {
            "default"
        } else {
            "prefer-dark"
        }
        .into(),
    );
    if let Some(r) = num("radius.lg") {
        v.insert("shape.radius".into(), whole(r));
    }
    // The shell's outline width; flat chrome draws none, and a 0 px focus ring would hide the focused window, so 2.
    if let Some(o) = num("chrome.outline") {
        v.insert("shape.border".into(), whole(if o > 0.0 { o } else { 2.0 }));
    }
    if let Some(ms) = num("motion.standard_ms") {
        v.insert("motion.ms".into(), whole(ms));
    }
    if let Some(c) = i
        .tokens
        .get("motion.easing.continuous")
        .and_then(Value::as_array)
    {
        let c: Vec<f64> = c.iter().filter_map(Value::as_f64).collect();
        if let [a, b, cc, d] = c[..] {
            v.insert(
                "motion.curve".into(),
                format!(
                    "cubic-bezier({}, {}, {}, {})",
                    num_text(a),
                    num_text(b),
                    num_text(cc),
                    num_text(d)
                ),
            );
        }
    }
    if let Some(a) = num("color.surface_alpha") {
        v.insert("material.opacity".into(), format!("{a:.2}"));
    }
    if let Some(profile) = i.tokens.get("motion.profile").and_then(Value::as_str) {
        v.insert(
            "motion.niri".into(),
            niri_animations(profile, i.motion_speed),
        );
    }
    v.insert("paths.config".into(), i.config_dir.into());
    v
}

/// A pixel size as points for the apps' font strings (96 dpi), to the half point: 13 px → 10 pt.
pub fn pt(px: f64) -> String {
    num_text((px * 0.75 * 2.0).round() / 2.0)
}

/// Whole numbers without a fraction, the rest as they are.
fn whole(x: f64) -> String {
    format!("{}", x.round() as i64)
}

fn num_text(x: f64) -> String {
    if x.fract() == 0.0 {
        format!("{}", x as i64)
    } else {
        format!("{x}")
    }
}

/// The animations the shell owns in niri (W34). The others keep niri's own.
const NIRI_ANIMATIONS: [&str; 6] = [
    "workspace-switch",
    "horizontal-view-movement",
    "window-open",
    "window-close",
    "window-movement",
    "window-resize",
];

/// niri's `animations` block for a motion profile (W34): calm settles without a bounce, lively overshoots a little,
/// none turns every animation off with niri's `off` (not a stiff spring that only looks instant). The stiffness
/// scales with the speed setting squared: a spring's time scale grows with the square root of its stiffness.
pub fn niri_animations(profile: &str, speed: f64) -> String {
    if profile == "none" {
        return "animations {\n    off\n}".into();
    }
    let (damping, stiffness) = if profile == "lively" {
        (0.75, 1000.0)
    } else {
        (1.0, 800.0)
    };
    let k = (stiffness * speed.clamp(0.25, 4.0).powi(2)).round() as i64;
    let mut out = String::from("animations {\n");
    for name in NIRI_ANIMATIONS {
        // niri reads the damping ratio as a float: `1` is an integer and refused.
        out.push_str(&format!(
            "    {name} {{\n        spring damping-ratio={damping:.2} stiffness={k} epsilon=0.0001\n    }}\n"
        ));
    }
    out.push('}');
    out
}

/// `template` with every `{{…}}` filled in: `colors.<role>.<mode>.<format>` from the palette, any other name from
/// `values`. The placeholders that could not be filled stay as they were and are returned (reported, Shōjiki).
pub fn render(template: &str, p: &Palette, values: &Values) -> (String, BTreeSet<String>) {
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
        let filled = match inner.strip_prefix("colors.") {
            Some(path) => colour(p, path),
            None => values.get(inner).cloned(),
        };
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

/// One `key=value` a rendered template asks an app's config (or the desktop's settings) to hold, under its `[section]`
/// (`""` before any). `value` is the text after the `=`, quotes included: gsettings reads GVariant text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub section: String,
    pub key: String,
    pub value: String,
}

impl Entry {
    /// The line as the file holds it.
    pub fn line(&self) -> String {
        format!("{}={}", self.key, self.value)
    }
}

/// The entries of a rendered template. Comments (`#`, `;`) and blank lines are skipped; so is a line whose value is
/// empty once its quotes are removed: a value the shell does not have (no icon theme chosen) is left to the app, not
/// written over (Shōjiki, K49 amendment). So is a value a placeholder did not fill (`{{…}}` left in it): the braces would
/// go into the app's or the desktop's setting, and the placeholder is reported as unknown instead.
pub fn entries(text: &str) -> Vec<Entry> {
    let mut out = Vec::new();
    let mut section = String::new();
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some(s) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = s.trim().to_owned();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let (key, value) = (key.trim(), value.trim());
        if value.trim_matches(['\'', '"']).trim().is_empty() || value.contains("{{") {
            continue;
        }
        out.push(Entry {
            section: section.clone(),
            key: key.to_owned(),
            value: value.to_owned(),
        });
    }
    out
}

/// Where a target's output goes.
pub enum Output {
    /// A file: `template` under `templates/`, written to `path` under `$XDG_CONFIG_HOME` (`@data/…`: under
    /// `$XDG_DATA_HOME`).
    File {
        template: &'static str,
        path: &'static str,
    },
    /// The desktop's settings (K49 amendment, W34): `template` holds `[schema]` sections of `key='value'` lines,
    /// applied with gsettings. The only target that writes settings instead of a file; opt-in like every target.
    Settings { template: &'static str },
}

/// A bundled export target: its name (`theme.export` lists these), its output, and what the program's own config must
/// hold to use it.
pub struct Target {
    pub name: &'static str,
    pub output: Output,
    /// The line the program's config must hold to read the file: (the config file under `$XDG_CONFIG_HOME`, the line).
    pub include: Option<(&'static str, &'static str)>,
    /// Lines the program's config must hold, rather than an include: (the config file, the template under
    /// `templates/lines/`).
    pub lines: Option<(&'static str, &'static str)>,
    /// A file an earlier version wrote (the include line that named it): kurashid keeps it as a stub, so the old
    /// include still loads, and reports the old line as stale.
    pub legacy: Option<(&'static str, &'static str)>,
}

/// Written in place of a superseded file (see [`Target::legacy`]). Comments only: an empty include is valid for niri.
pub const LEGACY_STUB: &str = "// Superseded (K49, W34): the shell's niri settings are in kurashi.kdl now. Replace the\n// include line that names this file with `include \"kurashi.kdl\"`.\n";

/// The targets, in the order Settings lists them.
pub const TARGETS: &[Target] = &[
    Target {
        name: "gtk3",
        output: Output::File {
            template: "gtk-colors.css",
            path: "gtk-3.0/kurashi-colors.css",
        },
        include: Some(("gtk-3.0/gtk.css", "@import 'kurashi-colors.css';")),
        lines: None,
        legacy: None,
    },
    Target {
        name: "gtk4",
        // libadwaita 1.6+ reads CSS variables: GTK 4 gets them besides the named colours (GTK 3 would warn on them).
        output: Output::File {
            template: "gtk4-colors.css",
            path: "gtk-4.0/kurashi-colors.css",
        },
        include: Some(("gtk-4.0/gtk.css", "@import 'kurashi-colors.css';")),
        lines: None,
        legacy: None,
    },
    Target {
        name: "qt",
        output: Output::File {
            template: "qtct-colors.conf",
            path: "qt6ct/colors/kurashi.conf",
        },
        include: None,
        lines: Some(("qt6ct/qt6ct.conf", "lines/qt6ct.conf")),
        legacy: None,
    },
    Target {
        name: "qt5",
        output: Output::File {
            template: "qtct-colors.conf",
            path: "qt5ct/colors/kurashi.conf",
        },
        include: None,
        lines: Some(("qt5ct/qt5ct.conf", "lines/qt5ct.conf")),
        legacy: None,
    },
    // KDE apps take their colours from a KDE colour scheme over the Qt palette: one for them to pick, in
    // `$XDG_DATA_HOME` (the `@data/` prefix), where their Window Color Scheme menu lists it. kdeglobals names it.
    Target {
        name: "kde",
        output: Output::File {
            template: "kde-colors.colors",
            path: "@data/color-schemes/Kurashi.colors",
        },
        include: None,
        lines: Some(("kdeglobals", "lines/kdeglobals.conf")),
        legacy: None,
    },
    Target {
        name: "foot",
        output: Output::File {
            template: "foot.ini",
            path: "foot/kurashi-colors.ini",
        },
        include: Some(("foot/foot.ini", "include=~/.config/foot/kurashi-colors.ini")),
        lines: None,
        legacy: None,
    },
    Target {
        name: "kitty",
        output: Output::File {
            template: "kitty.conf",
            path: "kitty/kurashi-colors.conf",
        },
        include: Some(("kitty/kitty.conf", "include kurashi-colors.conf")),
        lines: None,
        legacy: None,
    },
    Target {
        name: "alacritty",
        output: Output::File {
            template: "alacritty.toml",
            path: "alacritty/kurashi-colors.toml",
        },
        include: Some((
            "alacritty/alacritty.toml",
            "general.import = [\"~/.config/alacritty/kurashi-colors.toml\"]",
        )),
        lines: None,
        legacy: None,
    },
    Target {
        name: "ghostty",
        output: Output::File {
            template: "ghostty.conf",
            path: "ghostty/themes/kurashi",
        },
        include: Some(("ghostty/config", "theme = kurashi")),
        lines: None,
        legacy: None,
    },
    Target {
        name: "niri",
        output: Output::File {
            template: "niri-colors.kdl",
            path: "niri/kurashi.kdl",
        },
        include: Some(("niri/config.kdl", "include \"kurashi.kdl\"")),
        lines: None,
        legacy: Some(("niri/kurashi-colors.kdl", "include \"kurashi-colors.kdl\"")),
    },
    Target {
        name: "gsettings",
        output: Output::Settings {
            template: "gsettings.ini",
        },
        include: None,
        lines: None,
        legacy: None,
    },
];

pub fn target(name: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|t| t.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;

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

    /// The theme document's tokens as the tests' palette and shape want them (W34).
    fn tokens() -> serde_json::Map<String, Value> {
        serde_json::json!({
            "font.family": "Inter",
            "font.size.body": 13,
            "radius.lg": 18,
            "chrome.outline": 2,
            "motion.standard_ms": 220,
            "motion.easing.continuous": [0.4, 0.0, 0.2, 1.0],
            "color.surface_alpha": 0.85,
            "motion.profile": "calm",
        })
        .as_object()
        .cloned()
        .unwrap()
    }

    fn inputs(tokens: &serde_json::Map<String, Value>) -> Values {
        values(&Inputs {
            tokens,
            scheme: "dark",
            icon_theme: "Papirus-Dark",
            motion_speed: 1.0,
            config_dir: "/home/u/.config",
        })
    }

    #[test]
    fn matugen_placeholders_fill_from_our_roles() {
        let (s, unknown) = render(
            "bg={{colors.background.default.hex}} fg={{ colors.on_surface.dark.hex_stripped }} \
             a={{colors.primary.default.red}},{{colors.primary.default.green}} {{image}} {{colors.nope.default.hex}}",
            &palette(),
            &Values::new(),
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
    fn values_fill_every_non_colour_placeholder() {
        let t = tokens();
        let v = inputs(&t);
        let (s, unknown) = render(
            "{{fonts.family}}|{{fonts.size}}|{{fonts.mono}}|{{icons.theme}}|{{scheme}}|{{shape.radius}}|\
             {{shape.border}}|{{motion.ms}}|{{motion.curve}}|{{material.opacity}}|{{paths.config}}|\
             {{gsettings.color_scheme}}",
            &palette(),
            &v,
        );
        assert_eq!(
            s,
            "Inter|10|monospace|Papirus-Dark|dark|18|2|220|cubic-bezier(0.4, 0, 0.2, 1)|0.85|/home/u/.config|prefer-dark"
        );
        assert!(unknown.is_empty(), "{unknown:?}");
    }

    #[test]
    fn a_missing_token_or_unknown_name_is_reported_not_invented() {
        let empty = serde_json::Map::new();
        let (s, unknown) = render(
            "{{fonts.family}} {{shape.radius}} {{fonts.nope}}",
            &palette(),
            &inputs(&empty),
        );
        assert_eq!(s, "{{fonts.family}} {{shape.radius}} {{fonts.nope}}");
        assert_eq!(
            unknown.into_iter().collect::<Vec<_>>(),
            vec!["fonts.family", "fonts.nope", "shape.radius"]
        );
    }

    #[test]
    fn scheme_light_and_the_settings_values_follow_it() {
        let t = tokens();
        let v = values(&Inputs {
            tokens: &t,
            scheme: "light",
            icon_theme: "",
            motion_speed: 1.0,
            config_dir: "/c",
        });
        assert_eq!(v["gsettings.color_scheme"], "default");
        assert_eq!(v["scheme"], "light");
        assert_eq!(
            v["icons.theme"], "",
            "`leave as is` is an empty value, not a missing one"
        );
    }

    #[test]
    fn shape_border_floor_for_flat_chrome_and_pixels_as_points() {
        let mut t = tokens();
        t.insert("chrome.outline".into(), serde_json::json!(0));
        assert_eq!(
            inputs(&t)["shape.border"],
            "2",
            "flat chrome draws no outline; the focus ring keeps 2 px"
        );
        t.insert("chrome.outline".into(), serde_json::json!(1));
        assert_eq!(inputs(&t)["shape.border"], "1");
        assert_eq!(pt(13.0), "10", "13 px = 9.75 pt, to the half point");
        assert_eq!(pt(11.0), "8.5", "11 px = 8.25 pt, to the half point");
        assert_eq!(pt(16.0), "12");
        assert_eq!(pt(9.0), "7");
    }

    #[test]
    fn niri_animations_by_profile_and_speed() {
        assert_eq!(niri_animations("none", 1.0), "animations {\n    off\n}");
        let calm = niri_animations("calm", 1.0);
        assert!(calm.starts_with("animations {\n"), "{calm}");
        assert!(
            calm.contains("spring damping-ratio=1.00 stiffness=800 epsilon=0.0001"),
            "{calm}"
        );
        assert!(niri_animations("lively", 1.0).contains("damping-ratio=0.75 stiffness=1000"));
        // Twice as fast: a spring's stiffness four times as big.
        assert!(niri_animations("calm", 2.0).contains("stiffness=3200"));
        for name in NIRI_ANIMATIONS {
            assert!(calm.contains(&format!("    {name} {{")), "{name} missing");
        }
    }

    #[test]
    fn entries_keep_sections_and_drop_values_the_shell_does_not_have() {
        let text = "# comment\n[Appearance]\nicon_theme=\ncustom_palette=true\n\n[Fonts]\ngeneral=\"Inter,10\"\n\
                    [org.gnome.desktop.interface]\nicon-theme=''\ncolor-scheme='prefer-dark'\nfont-name='{{fonts.family}} 10'\n";
        let e = entries(text);
        let lines: Vec<String> = e
            .iter()
            .map(|x| format!("{}|{}", x.section, x.line()))
            .collect();
        assert_eq!(
            lines,
            vec![
                "Appearance|custom_palette=true",
                "Fonts|general=\"Inter,10\"",
                "org.gnome.desktop.interface|color-scheme='prefer-dark'",
            ]
        );
    }

    #[test]
    fn every_target_template_exists() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../templates");
        for t in TARGETS {
            let template = match t.output {
                Output::File { template, .. } | Output::Settings { template } => template,
            };
            assert!(
                root.join(template).is_file(),
                "{} lacks templates/{template}",
                t.name
            );
            if let Some((_, lines)) = t.lines {
                assert!(
                    root.join(lines).is_file(),
                    "{} lacks templates/{lines}",
                    t.name
                );
            }
        }
    }
}
