//! The apps' own palette (I454, K123): with `theme.colors.real_palettes` on, terminals and the tools that run in them
//! wear a published theme as its authors made it — the 16 terminal colours verbatim, the rest from the same palette —
//! instead of colours derived from the shell's roles. The palette the shell wears is taken when it publishes a table
//! for the scheme (`Why::Own`); else the published theme whose colours lie closest to the shell's (`Why::Closest`).
//! One pick per export run, read by every target, so a terminal and the editor inside it never disagree.

use crate::color::{Rgb, linear_of_oklab, oklab_of_linear};
use crate::input::{Scheme, Source, ThemeInput};
use crate::palette::{Palette, PaletteSet, Terminal, bundled, bundled_names, user_names};

/// Why this palette: the shell's own, or the nearest published one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Why {
    Own,
    Closest,
}

impl Why {
    pub fn key(self) -> &'static str {
        match self {
            Why::Own => "own",
            Why::Closest => "closest",
        }
    }
}

/// The pick: the palette's name and label, why, its roles completed for the scheme, and its authors' terminal table.
#[derive(Clone, Debug)]
pub struct AppsPalette {
    pub name: String,
    pub label: String,
    pub why: Why,
    pub palette: Palette,
    pub terminal: Terminal,
}

/// How far two colours lie apart (Oklab, 0 = the same; black to white is 1).
fn apart(a: Rgb, b: Rgb) -> f64 {
    let (x, y) = (
        oklab_of_linear(a.to_linear()),
        oklab_of_linear(b.to_linear()),
    );
    ((x[0] - y[0]).powi(2) + (x[1] - y[1]).powi(2) + (x[2] - y[2]).powi(2)).sqrt()
}

/// The roles a match is made on and their weights: the ground decides most (a terminal is mostly its background), the
/// text and the accent next, the two side colours a little.
const WEIGHTS: [(&str, f64); 5] = [
    ("surface", 3.0),
    ("on_surface", 1.0),
    ("accent", 1.5),
    ("secondary", 0.5),
    ("tertiary", 0.5),
];

/// The distance of a candidate's raw roles from the shell's palette; `None` when it lacks one of the roles.
fn distance(shell: &Palette, set: &PaletteSet, dark: bool) -> Option<f64> {
    let raw = if dark {
        set.dark.as_ref()
    } else {
        set.light.as_ref()
    }?;
    let mut sum = 0.0;
    for (role, w) in WEIGHTS {
        sum += w * apart(*shell.roles.get(role)?, *raw.get(role)?);
    }
    Some(sum)
}

/// The set's table for the scheme, if it is one of that scheme: a "light" table on a dark ground (B81: the bundled
/// Dracula's, generated from a theme that is not its light one) is not offered as light.
fn table(set: &PaletteSet, dark: bool) -> Option<&Terminal> {
    let t = if dark {
        set.dark_terminal.as_ref()
    } else {
        set.light_terminal.as_ref()
    }?;
    ((t.background.luminance() < 0.3) == dark).then_some(t)
}

/// The terminal table the bundled palette `name` publishes for the scheme, if any (the shell's `term.*` tokens).
pub fn own_table(name: &str, dark: bool) -> Option<Terminal> {
    let set = bundled(name).ok()?;
    table(&set, dark).cloned()
}

fn label(set: &PaletteSet) -> String {
    match (&set.meta.family, &set.meta.variant) {
        (Some(f), Some(v)) if !v.is_empty() => format!("{f} {v}"),
        (Some(f), _) => f.clone(),
        _ => set.name.clone(),
    }
}

/// A pick that stays: the previous one is kept while it is within this much of the best (a track's cover or a slightly
/// different wallpaper must not flip the terminal's theme).
const STAY: f64 = 1.2;

/// The apps' palette for `shell` (the colours the apps would otherwise take) in the scheme `dark`.
/// `active`: the palette `theme.colors.palette` names, when the shell wears a named palette (not the wallpaper's).
/// `previous`: the name picked last time, kept on a near-tie. `base`: the settings the roles are completed with
/// (contrast level, ink, …; its source and scheme are replaced). `None`: no published palette has a table for this
/// scheme (never, with the bundled ones), or the pick's roles could not be resolved.
pub fn pick(
    shell: &Palette,
    dark: bool,
    active: Option<&str>,
    previous: Option<&str>,
    base: &ThemeInput,
) -> Option<AppsPalette> {
    let made = |set: PaletteSet, why: Why| -> Option<AppsPalette> {
        let terminal = table(&set, dark)?.clone();
        let mut input = base.clone();
        input.source = Source::Palette(set.name.clone());
        input.scheme = if dark { Scheme::Dark } else { Scheme::Light };
        // The apps' palette is the authors': no strong grounds, no gradient, no season of the shell's.
        input.strong_chrome = false;
        input.wash = None;
        input.season = None;
        let (palette, _) = crate::resolve_palette(&input).ok()?;
        Some(AppsPalette {
            label: label(&set),
            name: set.name,
            why,
            palette,
            terminal,
        })
    };
    if let Some(name) = active
        && let Ok(set) = bundled(name)
        && table(&set, dark).is_some()
    {
        return made(set, Why::Own);
    }
    let mut names: Vec<String> = bundled_names().into_iter().map(String::from).collect();
    names.extend(user_names());
    names.sort();
    names.dedup();
    let mut best: Option<(f64, PaletteSet)> = None;
    let mut kept: Option<(f64, PaletteSet)> = None;
    for n in names {
        let Ok(set) = bundled(&n) else { continue };
        if table(&set, dark).is_none() {
            continue;
        }
        let Some(d) = distance(shell, &set, dark) else {
            continue;
        };
        if previous == Some(n.as_str()) {
            kept = Some((d, set.clone()));
        }
        // (strictly less: the first by name wins a tie)
        if best.as_ref().is_none_or(|(b, _)| d < *b) {
            best = Some((d, set));
        }
    }
    let (bd, bset) = best?;
    match kept {
        Some((kd, kset)) if kd <= bd * STAY + 0.01 => made(kset, Why::Closest),
        _ => made(bset, Why::Closest),
    }
}

/// The values `{{term.*}}` of the terminals' templates: `background`, `foreground`, `cursor`, `cursor_text`,
/// `cursor_on`, `selection_background`, `selection_foreground` and `color0`…`color15`, each as `.hex` and
/// `.hex_stripped`. With a `table` they are its authors'; without, the roles the templates always took (so an export
/// with the switch off is what it was before the templates named `term.*`).
pub fn term_values(shell: &Palette, table: Option<&Terminal>) -> Vec<(String, Rgb)> {
    let role = |n: &str| crate::export::role(shell, n).unwrap_or(Rgb(0, 0, 0));
    let mut out: Vec<(String, Rgb)> = Vec::new();
    match table {
        Some(t) => {
            out.push(("background".into(), t.background));
            out.push(("foreground".into(), t.foreground));
            let cursor = t.cursor.unwrap_or(t.foreground);
            let cursor_text = t.cursor_text.unwrap_or(t.background);
            out.push(("cursor".into(), cursor));
            out.push(("cursor_text".into(), cursor_text));
            out.push(("cursor_on".into(), cursor_text));
            out.push((
                "selection_background".into(),
                t.selection_background.unwrap_or(t.colors[8]),
            ));
            out.push((
                "selection_foreground".into(),
                t.selection_foreground.unwrap_or(t.foreground),
            ));
            for (i, c) in t.colors.iter().enumerate() {
                out.push((format!("color{i}"), *c));
            }
        }
        None => {
            for (k, r) in [
                ("background", "surface"),
                ("foreground", "on_surface"),
                ("cursor", "primary"),
                ("cursor_text", "surface"),
                ("cursor_on", "on_primary"),
                ("selection_background", "primary_container"),
                ("selection_foreground", "on_primary_container"),
            ] {
                out.push((k.into(), role(r)));
            }
            for (i, r) in DERIVED.iter().enumerate() {
                out.push((format!("color{i}"), role(r)));
            }
        }
    }
    out
}

/// The shell's own terminal colours (W85, CONTRACT-CHANGE 785; `term.*` in the theme document, the terminal mod's
/// text): the keys of [`term_values`]. With a `table` (the palette the shell wears publishes one for the scheme) they are
/// its authors' verbatim. Without one the ground, text, cursor and selection are the roles the templates take, but the 16
/// colours are derived by hue ([`ansi_of`]) — the templates' role mapping (`DERIVED`) puts a blue under "yellow" and a
/// green under "magenta" in most palettes, which a terminal the shell draws itself must not do (git, ls and diff colour
/// by hue).
pub fn term_tokens(shell: &Palette, table: Option<&Terminal>) -> Vec<(String, Rgb)> {
    let mut out = term_values(shell, table);
    if table.is_none() {
        let ansi = ansi_of(shell);
        for (k, c) in out.iter_mut() {
            if let Some(i) = k
                .strip_prefix("color")
                .and_then(|n| n.parse::<usize>().ok())
            {
                *c = ansi[i];
            }
        }
    }
    out
}

/// OKLCh `[L, C, h°]` of a colour.
fn lch(c: Rgb) -> [f64; 3] {
    let [l, a, b] = oklab_of_linear(c.to_linear());
    [l, a.hypot(b), b.atan2(a).to_degrees().rem_euclid(360.0)]
}

/// The colour at OKLCh `[L, C, h°]`, its chroma lowered until it lies in sRGB.
fn from_lch([l, c, h]: [f64; 3]) -> Rgb {
    let mut c = c;
    loop {
        let (s, co) = h.to_radians().sin_cos();
        let lin = linear_of_oklab([l, c * co, c * s]);
        if lin.iter().all(|v| (-1e-4..=1.0 + 1e-4).contains(v)) || c <= 0.0 {
            return Rgb::from_linear(lin.map(|v| v.clamp(0.0, 1.0)));
        }
        c = (c - 0.004).max(0.0);
    }
}

/// How far apart two hues are, in degrees (0..=180).
fn hue_apart(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

/// The 16 ANSI colours of a palette without a terminal table: each hue where a terminal expects it (red, green, yellow,
/// blue, magenta, cyan), taken from the palette's own colour of that hue when it has one (kami's red pen, its blue
/// pencil), at the palette's colourfulness and a lightness that reads on its ground; black and white and the two greys
/// from its text and ground. Contrast against the ground: at least 3:1 for the six hues (normal and bright).
pub fn ansi_of(p: &Palette) -> [Rgb; 16] {
    let ground = p.roles.get("surface").copied().unwrap_or(if p.dark {
        Rgb(0x16, 0x16, 0x1a)
    } else {
        Rgb(0xf6, 0xf4, 0xef)
    });
    let ink = p.roles.get("on_surface").copied().unwrap_or(if p.dark {
        Rgb(0xe8, 0xe6, 0xe0)
    } else {
        Rgb(0x22, 0x22, 0x28)
    });
    // The palette's colours of their own, with a hue (greys say nothing about one).
    let own: Vec<[f64; 3]> = [
        "accent",
        "secondary",
        "tertiary",
        "error",
        "warning",
        "success",
        "info",
    ]
    .iter()
    .filter_map(|r| p.roles.get(*r).copied())
    .map(lch)
    .filter(|c| c[1] >= 0.04)
    .collect();
    // Its colourfulness: the middle of its own colours', held where a terminal stays legible and calm.
    let mut chromas: Vec<f64> = own.iter().map(|c| c[1]).collect();
    chromas.sort_by(f64::total_cmp);
    let chroma = chromas
        .get(chromas.len() / 2)
        .copied()
        .unwrap_or(0.11)
        .clamp(0.07, 0.15);
    // Red, green, yellow, blue, magenta, cyan (OKLCh hues of the xterm/Tango family).
    const HUES: [f64; 6] = [29.0, 142.0, 95.0, 262.0, 330.0, 195.0];
    let (l_norm, l_bright) = if p.dark { (0.74, 0.82) } else { (0.52, 0.60) };
    let hue = |want: f64| -> (f64, f64) {
        // The palette's nearest colour within 35° lends its hue and some of its chroma.
        own.iter()
            .filter(|c| hue_apart(c[2], want) <= 35.0)
            .min_by(|a, b| hue_apart(a[2], want).total_cmp(&hue_apart(b[2], want)))
            .map_or((want, chroma), |c| (c[2], (c[1] + chroma) / 2.0))
    };
    let mut out = [Rgb(0, 0, 0); 16];
    let (black, grey, silver, white) = if p.dark {
        (
            ground.mix(ink, 0.18),
            ground.mix(ink, 0.45),
            ink.mix(ground, 0.18),
            ink,
        )
    } else {
        (
            ink.mix(ground, 0.15),
            ink.mix(ground, 0.45),
            ground.mix(ink, 0.30),
            ground.mix(ink, 0.18),
        )
    };
    out[0] = black;
    // (on a light ground "white" and "silver" are its lighter greys, as light terminal themes keep them; still readable
    // enough for a prompt that prints in white: 1.6:1 and 2:1 at least)
    out[7] = crate::color::ensure_contrast(silver, ground, if p.dark { 1.0 } else { 2.0 });
    out[8] = crate::color::ensure_contrast(grey, ground, 3.0);
    out[15] = crate::color::ensure_contrast(white, ground, if p.dark { 1.0 } else { 1.6 });
    for (i, want) in HUES.iter().enumerate() {
        let (h, c) = hue(*want);
        // (yellow is the light hue: a light ground needs it darker to read)
        let lift = if i == 2 && !p.dark { -0.04 } else { 0.0 };
        out[1 + i] = crate::color::ensure_contrast(from_lch([l_norm + lift, c, h]), ground, 3.0);
        out[9 + i] = crate::color::ensure_contrast(from_lch([l_bright + lift, c, h]), ground, 3.0);
    }
    out
}

/// The roles the 16 colours are derived from while no table is in effect (the templates' mapping before I454).
pub const DERIVED: [&str; 16] = [
    "surface",
    "error",
    "tertiary",
    "secondary",
    "primary",
    "tertiary",
    "secondary",
    "on_surface",
    "surface_container_high",
    "error_container",
    "tertiary_container",
    "secondary_container",
    "primary_container",
    "on_tertiary_container",
    "on_secondary_container",
    "on_surface_variant",
];

#[cfg(test)]
mod tests {
    use super::*;

    fn shell_of(name: &str, dark: bool) -> Palette {
        let input = ThemeInput {
            source: Source::Palette(name.into()),
            scheme: if dark { Scheme::Dark } else { Scheme::Light },
            ..ThemeInput::default()
        };
        crate::resolve_palette(&input).expect("palette").0
    }

    fn tabled(dark: bool) -> Vec<String> {
        bundled_names()
            .into_iter()
            .filter(|n| bundled(n).is_ok_and(|s| table(&s, dark).is_some()))
            .map(String::from)
            .collect()
    }

    #[test]
    fn a_palette_with_a_table_is_its_own_pick_and_its_table_goes_out_verbatim() {
        for dark in [true, false] {
            let names = tabled(dark);
            assert!(names.len() >= 10, "tables for dark={dark}: {names:?}");
            for n in names {
                let shell = shell_of(&n, dark);
                let a = pick(&shell, dark, Some(&n), None, &ThemeInput::default()).expect("pick");
                assert_eq!((a.name.as_str(), a.why), (n.as_str(), Why::Own));
                let set = bundled(&n).unwrap();
                assert_eq!(
                    &a.terminal,
                    table(&set, dark).unwrap(),
                    "{n}: the table is the authors'"
                );
                let v = term_values(&a.palette, Some(&a.terminal));
                assert_eq!(
                    v.iter().find(|(k, _)| k == "color1").unwrap().1,
                    a.terminal.colors[1]
                );
                assert_eq!(
                    v.iter().find(|(k, _)| k == "background").unwrap().1,
                    a.terminal.background
                );
            }
        }
    }

    #[test]
    fn without_a_named_palette_the_closest_one_is_found_from_its_own_colours() {
        // The shell wears each palette's colours, but not by name (as a wallpaper might give them): the match finds a
        // palette of the same family (variants of one family share most colours), in the same scheme.
        for dark in [true, false] {
            for n in tabled(dark) {
                let shell = shell_of(&n, dark);
                let a = pick(&shell, dark, None, None, &ThemeInput::default()).expect("pick");
                assert_eq!(a.why, Why::Closest);
                let fam = |x: &str| {
                    bundled(x)
                        .unwrap()
                        .meta
                        .family
                        .unwrap_or_else(|| x.to_owned())
                };
                assert_eq!(
                    fam(&a.name),
                    fam(&n),
                    "{n} (dark={dark}) matched {}",
                    a.name
                );
                assert_eq!(
                    a.palette.dark, dark,
                    "{n} matched {} whose roles came out in the other scheme",
                    a.name
                );
            }
        }
    }

    #[test]
    fn a_palette_without_a_table_for_the_scheme_takes_the_closest_and_never_another_scheme() {
        // Monokai publishes no light terminal colours (K106).
        let set = bundled("monokai").unwrap();
        assert!(table(&set, false).is_none());
        let shell = shell_of("monokai", false);
        let a = pick(&shell, false, Some("monokai"), None, &ThemeInput::default()).expect("pick");
        assert_eq!(a.why, Why::Closest);
        assert_ne!(a.name, "monokai");
        assert!(
            !a.palette.dark && a.terminal.background.luminance() > 0.4,
            "{}",
            a.name
        );
    }

    #[test]
    fn the_pick_is_the_same_every_time_and_stays_on_a_small_change() {
        let shell = shell_of("gruvbox", true);
        let first = pick(&shell, true, None, None, &ThemeInput::default())
            .unwrap()
            .name;
        for _ in 0..3 {
            assert_eq!(
                pick(&shell, true, None, None, &ThemeInput::default())
                    .unwrap()
                    .name,
                first
            );
        }
        // A slightly different ground and accent (a track's cover, another crop of the wallpaper).
        let mut moved = shell.clone();
        for (role, to) in [("surface", Rgb(52, 46, 40)), ("accent", Rgb(240, 180, 60))] {
            let c = moved.roles[role];
            moved.roles.insert(role.into(), c.mix(to, 0.25));
        }
        assert_eq!(
            pick(&moved, true, None, Some(&first), &ThemeInput::default())
                .unwrap()
                .name,
            first
        );
        // A far change does move it.
        let far = shell_of("nord", true);
        assert_ne!(
            pick(&far, true, None, Some(&first), &ThemeInput::default())
                .unwrap()
                .name,
            first
        );
    }

    #[test]
    fn the_shells_terminal_colours_sit_at_their_hues_and_read_on_the_ground() {
        // (the look palettes publish no table: their colours are derived by hue)
        for name in ["kami", "sekai", "material", "wa-iro", "aqua"] {
            for dark in [false, true] {
                let Ok(set) = bundled(name) else { continue };
                if if dark {
                    set.dark.is_none()
                } else {
                    set.light.is_none()
                } {
                    continue;
                }
                let shell = shell_of(name, dark);
                let ground = shell.get("surface");
                let a = ansi_of(&shell);
                for (i, want) in [29.0, 142.0, 95.0, 262.0, 330.0, 195.0].iter().enumerate() {
                    for c in [a[1 + i], a[9 + i]] {
                        assert!(
                            crate::color::contrast(c, ground) >= 2.99,
                            "{name} dark={dark} colour {} {} on {}",
                            1 + i,
                            c.hex(),
                            ground.hex()
                        );
                        let h = lch(c);
                        assert!(
                            h[1] < 0.03 || hue_apart(h[2], *want) <= 40.0,
                            "{name} dark={dark} colour {} {} is at hue {:.0}, not near {want}",
                            1 + i,
                            c.hex(),
                            h[2]
                        );
                    }
                }
                let t: std::collections::BTreeMap<_, _> =
                    term_tokens(&shell, None).into_iter().collect();
                assert_eq!(t.len(), 7 + 16);
                assert_eq!(t["color4"], a[4]);
            }
        }
        // A palette with its own table keeps it verbatim.
        let own = own_table("dracula", true).expect("dracula's dark table");
        let t: std::collections::BTreeMap<_, _> =
            term_tokens(&shell_of("dracula", true), Some(&own))
                .into_iter()
                .collect();
        assert_eq!(t["color1"], own.colors[1]);
    }

    #[test]
    fn with_no_table_the_terminal_colours_are_the_roles_the_templates_always_took() {
        let shell = shell_of("kami", true);
        let v: std::collections::BTreeMap<_, _> = term_values(&shell, None).into_iter().collect();
        assert_eq!(
            v["background"],
            crate::export::role(&shell, "surface").unwrap()
        );
        assert_eq!(
            v["color2"],
            crate::export::role(&shell, "tertiary").unwrap()
        );
        assert_eq!(
            v["color13"],
            crate::export::role(&shell, "on_tertiary_container").unwrap()
        );
        assert_eq!(
            v["cursor_on"],
            crate::export::role(&shell, "on_primary").unwrap()
        );
        assert_eq!(v.len(), 7 + 16);
    }
}
