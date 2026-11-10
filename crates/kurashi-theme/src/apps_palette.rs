//! The apps' own palette (I454, K123): with `theme.colors.real_palettes` on, terminals and the tools that run in them
//! wear a published theme as its authors made it — the 16 terminal colours verbatim, the rest from the same palette —
//! instead of colours derived from the shell's roles. The palette the shell wears is taken when it publishes a table
//! for the scheme (`Why::Own`); else the published theme whose colours lie closest to the shell's (`Why::Closest`).
//! One pick per export run, read by every target, so a terminal and the editor inside it never disagree.

use crate::color::{Rgb, oklab_of_linear};
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
