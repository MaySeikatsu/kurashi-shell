//! Wallpaper extraction modes (I455, session 26). `TonalMatched` is today's Material tonal spot from the
//! picture's one seed; `Vibrant` is Material's vibrant variant from the same seed; `Prominent` takes the colours
//! that are in the picture — the surface its most populous dark (or light) colour, the ink its light (or dark)
//! one, the accents its most prominent hues as they are — nudged only as far as contrast needs; `Mixed` keeps
//! the vibrant scheme's tones (readability) and takes hue and chroma from the picture's prominent colours.
//! Every mode ends in the same pipeline (scheme → … → wcag), so legibility is guaranteed the same way.

use material_colors::color::Argb;
use material_colors::dynamic_color::Variant;
use material_colors::quantize::{Quantizer, QuantizerCelebi};
use material_colors::scheme::Scheme as MScheme;
use material_colors::score::Score;
use material_colors::theme::ThemeBuilder;

use crate::ThemeError;
use crate::color::{
    BLACK, Rgb, WHITE, contrast, ensure_contrast, linear_of_oklab, oklab_of_linear,
};
use crate::input::Wallpaper;
use crate::palette::{PaletteSet, RawRoles};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    TonalMatched,
    Vibrant,
    Prominent,
    Mixed,
}

impl Mode {
    pub const ALL: [Mode; 4] = [
        Mode::TonalMatched,
        Mode::Vibrant,
        Mode::Prominent,
        Mode::Mixed,
    ];
    pub fn name(self) -> &'static str {
        match self {
            Mode::TonalMatched => "tone-matched",
            Mode::Vibrant => "vibrant",
            Mode::Prominent => "prominent",
            Mode::Mixed => "mixed",
        }
    }
}

/// OKLCh: lightness 0..1, chroma (0..~0.37), hue in degrees.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lch {
    pub l: f64,
    pub c: f64,
    pub h: f64,
}

impl Lch {
    pub fn of(c: Rgb) -> Lch {
        let [l, a, b] = oklab_of_linear(c.to_linear());
        Lch {
            l,
            c: a.hypot(b),
            h: b.atan2(a).to_degrees().rem_euclid(360.0),
        }
    }
    /// Back to sRGB, chroma reduced until the colour is in gamut (hue and lightness kept).
    pub fn rgb(self) -> Rgb {
        let mut c = self.c;
        for _ in 0..40 {
            let (a, b) = (c * self.h.to_radians().cos(), c * self.h.to_radians().sin());
            let lin = linear_of_oklab([self.l, a, b]);
            if lin.iter().all(|v| (-0.0005..=1.0005).contains(v)) {
                return Rgb::from_linear(lin.map(|v| v.clamp(0.0, 1.0)));
            }
            c *= 0.9;
        }
        Rgb::from_linear(linear_of_oklab([self.l, 0.0, 0.0]).map(|v| v.clamp(0.0, 1.0)))
    }
    fn with(self, l: f64, c: f64) -> Lch {
        Lch {
            l: l.clamp(0.0, 1.0),
            c: c.max(0.0),
            h: self.h,
        }
    }
}

fn hue_gap(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

fn delta_e(a: Lch, b: Lch) -> f64 {
    let (aa, ab) = (a.c * a.h.to_radians().cos(), a.c * a.h.to_radians().sin());
    let (ba, bb) = (b.c * b.h.to_radians().cos(), b.c * b.h.to_radians().sin());
    ((a.l - b.l).powi(2) + (aa - ba).powi(2) + (ab - bb).powi(2)).sqrt()
}

/// A colour of the picture and the share of pixels near it.
#[derive(Clone, Copy, Debug)]
pub struct Swatch {
    pub lch: Lch,
    pub rgb: Rgb,
    pub share: f64,
}

/// Below this chroma a colour reads as grey (white, black, greys): ground and ink, not an accent.
const CHROMATIC: f64 = 0.045;

/// The picture's colours by share: Celebi quantisation, then clusters closer than a just-visible difference merged
/// (so one red in three shades counts as one red).
pub fn swatches(w: &Wallpaper) -> Vec<Swatch> {
    let pixels: Vec<Argb> = w
        .rgba
        .chunks_exact(4)
        .filter(|p| p[3] >= 128)
        .map(|p| Argb::new(255, p[0], p[1], p[2]))
        .collect();
    if pixels.is_empty() {
        return vec![];
    }
    let total = pixels.len() as f64;
    let q = QuantizerCelebi::quantize(&pixels, 128);
    let mut raw: Vec<(Lch, f64)> = q
        .color_to_count
        .iter()
        .map(|(a, n)| (Lch::of(Rgb(a.red, a.green, a.blue)), *n as f64 / total))
        .collect();
    raw.sort_by(|a, b| b.1.total_cmp(&a.1));
    // Merge in OKLab (weighted means), most populous first.
    let mut out: Vec<([f64; 3], f64)> = vec![];
    for (lch, share) in raw {
        let lab = [
            lch.l,
            lch.c * lch.h.to_radians().cos(),
            lch.c * lch.h.to_radians().sin(),
        ];
        let near = out.iter_mut().find(|(m, _)| {
            ((m[0] - lab[0]).powi(2) + (m[1] - lab[1]).powi(2) + (m[2] - lab[2]).powi(2)).sqrt()
                < 0.07
        });
        match near {
            // The cluster keeps its most populous member's colour (a mean would grey a vivid red toward its
            // shadows); only the share adds up.
            Some((_, s)) => *s += share,
            None => out.push((lab, share)),
        }
    }
    let mut sw: Vec<Swatch> = out
        .into_iter()
        .map(|([l, a, b], share)| {
            let lch = Lch {
                l,
                c: a.hypot(b),
                h: b.atan2(a).to_degrees().rem_euclid(360.0),
            };
            Swatch {
                lch,
                rgb: lch.rgb(),
                share,
            }
        })
        .collect();
    sw.sort_by(|a, b| b.share.total_cmp(&a.share));
    sw
}

/// Up to three accents: the most prominent chromatic colours whose hues stand apart (no red, light red, whitish
/// red). Prominence is share, lifted a little by chroma so a small vivid patch beats a large muddy one of the
/// same hue family. Fewer than three distinct hues: the rest are filled by the next colours that differ enough at
/// all (a white/red/black picture gives red, then its neutrals).
pub fn accents(sw: &[Swatch], skip: &[Lch]) -> Vec<Lch> {
    let mut chromatic: Vec<&Swatch> = sw
        .iter()
        .filter(|s| s.lch.c >= CHROMATIC && s.share >= 0.002)
        .collect();
    chromatic.sort_by(|a, b| {
        let score = |s: &Swatch| s.share * (0.6 + s.lch.c * 6.0);
        score(b).total_cmp(&score(a))
    });
    let mut picked: Vec<Lch> = vec![];
    for s in &chromatic {
        if picked.len() == 3 {
            break;
        }
        if picked.iter().all(|p| hue_gap(p.h, s.lch.h) >= 35.0) {
            picked.push(s.lch);
        }
    }
    // An accent is never grey while the picture has any colour at all: the most colourful patch, however small.
    if picked.is_empty() {
        if let Some(s) = sw
            .iter()
            .filter(|s| s.lch.c >= 0.025)
            .max_by(|a, b| a.lch.c.total_cmp(&b.lch.c))
        {
            picked.push(s.lch);
        }
    }
    for s in sw {
        if picked.len() == 3 {
            break;
        }
        let distinct = picked
            .iter()
            .chain(skip)
            .all(|p| delta_e(*p, s.lch) >= 0.12);
        if distinct && s.share >= 0.01 {
            picked.push(s.lch);
        }
    }
    picked
}

fn on(bg: Rgb) -> Rgb {
    if contrast(WHITE, bg) >= contrast(BLACK, bg) {
        WHITE
    } else {
        BLACK
    }
}

/// The picture's own ground for a scheme: its most populous colour on the right side of the lightness line,
/// kept as it is when it is dark (light) enough, else moved there with its hue. Chroma is capped so text on it
/// stays calm.
fn ground(sw: &[Swatch], dark: bool) -> Lch {
    let ok = |s: &&Swatch| {
        if dark {
            s.lch.l <= 0.32
        } else {
            s.lch.l >= 0.86
        }
    };
    let pick = sw
        .iter()
        .filter(ok)
        .filter(|s| s.share >= 0.02)
        .max_by(|a, b| a.share.total_cmp(&b.share));
    match pick {
        Some(s) => s.lch.with(s.lch.l, s.lch.c.min(0.07)),
        None => {
            let base = sw.first().map_or(
                Lch {
                    l: 0.2,
                    c: 0.0,
                    h: 0.0,
                },
                |s| s.lch,
            );
            if dark {
                base.with(0.2, base.c.min(0.05))
            } else {
                base.with(0.95, base.c.min(0.03))
            }
        }
    }
}

/// Text on the ground: the picture's own light (dark) neutral when it has one, else the ground's hue near white
/// (black). The wcag stage still lifts it if it falls short.
fn ink(sw: &[Swatch], g: Lch, dark: bool) -> Lch {
    let ok = |s: &&Swatch| {
        if dark {
            s.lch.l >= 0.82
        } else {
            s.lch.l <= 0.3
        }
    };
    match sw
        .iter()
        .filter(ok)
        .filter(|s| s.share >= 0.01)
        .max_by(|a, b| a.share.total_cmp(&b.share))
    {
        Some(s) => s.lch.with(s.lch.l, s.lch.c.min(0.05)),
        None => g.with(if dark { 0.93 } else { 0.2 }, g.c.min(0.02)),
    }
}

fn containers(roles: &mut RawRoles, g: Lch, dark: bool) {
    let steps: [(&str, f64); 5] = [
        ("surface_container_lowest", -0.03),
        ("surface_container_low", 0.025),
        ("surface_container", 0.05),
        ("surface_container_high", 0.085),
        ("surface_container_highest", 0.12),
    ];
    for (k, d) in steps {
        let l = if dark { g.l + d } else { g.l - d };
        roles.insert(k.into(), g.with(l, g.c).rgb());
    }
}

/// The least change of lightness (hue and chroma kept, as far as the gamut allows) that gives `min` against
/// `bg`: a red stays red instead of washing toward pink as a mix with white would.
pub fn lift(c: Rgb, bg: Rgb, min: f64) -> Rgb {
    if contrast(c, bg) >= min {
        return c;
    }
    let lch = Lch::of(c);
    let up = Lch::of(bg).l < 0.5;
    for i in 1..=100 {
        let d = f64::from(i) * 0.01;
        let l = if up { lch.l + d } else { lch.l - d };
        if !(0.0..=1.0).contains(&l) {
            break;
        }
        let t = lch.with(l, lch.c).rgb();
        if contrast(t, bg) >= min {
            return t;
        }
    }
    ensure_contrast(c, bg, min)
}

fn accent_roles(roles: &mut RawRoles, name: &str, c: Rgb, surface: Rgb, dark: bool) {
    // Non-text UI parts need 3:1 against the ground (WCAG 1.4.11); text on accents is the `on_*` role's job.
    let c = lift(c, surface, 3.0);
    roles.insert(name.into(), c);
    roles.insert(format!("on_{name}"), on(c));
    if name == "accent" {
        let cont = c.mix(surface, if dark { 0.62 } else { 0.7 });
        roles.insert("accent_container".into(), cont);
        roles.insert(
            "on_accent_container".into(),
            ensure_contrast(c.mix(on(cont), 0.35), cont, 4.5),
        );
    }
}

fn prominent_scheme(sw: &[Swatch], dark: bool) -> RawRoles {
    let g = ground(sw, dark);
    let t = ink(sw, g, dark);
    let surface = g.rgb();
    let mut r = RawRoles::new();
    r.insert("surface".into(), surface);
    containers(&mut r, g, dark);
    let text = ensure_contrast(t.rgb(), surface, 7.0);
    r.insert("on_surface".into(), text);
    r.insert("on_surface_variant".into(), text.mix(surface, 0.3));
    r.insert("outline".into(), text.mix(surface, 0.55));
    r.insert("outline_variant".into(), text.mix(surface, 0.78));
    let acc = accents(sw, &[g, t]);
    let fallback = g.with(if dark { 0.75 } else { 0.45 }, 0.12);
    for (i, name) in ["accent", "secondary", "tertiary"].iter().enumerate() {
        let c = acc.get(i).copied().unwrap_or(fallback).rgb();
        accent_roles(&mut r, name, c, surface, dark);
    }
    standard_rest(&mut r, dark);
    r
}

fn standard_rest(r: &mut RawRoles, dark: bool) {
    let (err, warn) = if dark {
        ("#ffb4ab", "#e0a33b")
    } else {
        ("#ba1a1a", "#b07a14")
    };
    r.insert("error".into(), Rgb::parse(err).unwrap());
    r.insert("warning".into(), Rgb::parse(warn).unwrap());
    r.insert("scrim".into(), BLACK);
    r.insert("shadow".into(), BLACK);
}

fn material_roles(s: &MScheme, dark: bool) -> RawRoles {
    let rgb = |a: Argb| Rgb(a.red, a.green, a.blue);
    let mut r: RawRoles = [
        ("surface", s.surface),
        ("surface_container_lowest", s.surface_container_lowest),
        ("surface_container_low", s.surface_container_low),
        ("surface_container", s.surface_container),
        ("surface_container_high", s.surface_container_high),
        ("surface_container_highest", s.surface_container_highest),
        ("on_surface", s.on_surface),
        ("on_surface_variant", s.on_surface_variant),
        ("outline", s.outline),
        ("outline_variant", s.outline_variant),
        ("accent", s.primary),
        ("on_accent", s.on_primary),
        ("accent_container", s.primary_container),
        ("on_accent_container", s.on_primary_container),
        ("secondary", s.secondary),
        ("on_secondary", s.on_secondary),
        ("tertiary", s.tertiary),
        ("on_tertiary", s.on_tertiary),
        ("error", s.error),
        ("on_error", s.on_error),
        ("scrim", s.scrim),
        ("shadow", s.shadow),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), rgb(v)))
    .collect();
    let warn = if dark { "#e0a33b" } else { "#b07a14" };
    r.insert("warning".into(), Rgb::parse(warn).unwrap());
    r
}

/// The picture's distinct chromatic colours by prominence, up to `n`, each hue at least 30° from the others.
fn hues(sw: &[Swatch], n: usize) -> Vec<Lch> {
    let mut chromatic: Vec<&Swatch> = sw
        .iter()
        .filter(|s| s.lch.c >= CHROMATIC && s.share >= 0.002)
        .collect();
    chromatic.sort_by(|a, b| {
        let score = |s: &Swatch| s.share * (0.6 + s.lch.c * 6.0);
        score(b).total_cmp(&score(a))
    });
    let mut out: Vec<Lch> = vec![];
    for s in chromatic {
        if out.len() == n {
            break;
        }
        if out.iter().all(|p| hue_gap(p.h, s.lch.h) >= 30.0) {
            out.push(s.lch);
        }
    }
    out
}

/// Mixed (session 26, the user's words: "it actually takes all the prominent colors into the color palette, so they
/// appear in the shell"): the picture's colours spread over the parts the shell shows most. The ground is the
/// picture's own dark (light) in its hue; cards and panels lean toward a second colour of the picture; lines and
/// outlines take a third; the accent is the most vivid colour that stands apart from the ground; secondary and
/// tertiary the rest; text the picture's own light (dark). Every pair is lifted to its contrast as in Prominent.
fn mixed_scheme(sw: &[Swatch], dark: bool) -> RawRoles {
    let g = ground(sw, dark);
    let g = g.with(g.l, g.c.clamp(0.03, 0.09));
    let t = ink(sw, g, dark);
    let surface = g.rgb();
    let picks = hues(sw, 5);
    // The accent: the most vivid pick (one that stands apart from a coloured ground); the rest by prominence go to
    // secondary, tertiary and the lines, so each of the picture's colours shows somewhere.
    let apart = |p: &Lch| g.c < 0.04 || hue_gap(p.h, g.h) >= 20.0;
    let accent = picks
        .iter()
        .copied()
        .filter(apart)
        .max_by(|a, b| a.c.total_cmp(&b.c))
        .or_else(|| picks.first().copied());
    let rest: Vec<Lch> = picks
        .iter()
        .copied()
        .filter(|p| Some(*p) != accent)
        .collect();
    let card = rest.first().copied().or(accent).unwrap_or(g);
    let line = rest
        .get(2)
        .or(rest.get(1))
        .or(rest.first())
        .copied()
        .or(accent)
        .unwrap_or(t);
    let mut r = RawRoles::new();
    r.insert("surface".into(), surface);
    let steps: [(&str, f64, f64); 5] = [
        ("surface_container_lowest", -0.03, 0.0),
        ("surface_container_low", 0.03, 0.18),
        ("surface_container", 0.05, 0.26),
        ("surface_container_high", 0.08, 0.34),
        ("surface_container_highest", 0.11, 0.42),
    ];
    for (k, dl, toward) in steps {
        let l = if dark { g.l + dl } else { g.l - dl };
        let base = g.with(l, g.c).rgb();
        // Toward the card colour at the container's own lightness: its hue, not its brightness.
        let tint = card.with(l, card.c.min(0.14)).rgb();
        r.insert(k.into(), base.mix(tint, toward));
    }
    let text = ensure_contrast(t.rgb(), surface, 7.0);
    r.insert("on_surface".into(), text);
    r.insert("on_surface_variant".into(), text.mix(surface, 0.3));
    let outline = lift(line.with(line.l, line.c).rgb(), surface, 3.0);
    r.insert("outline".into(), outline);
    r.insert("outline_variant".into(), outline.mix(surface, 0.5));
    let fallback = g.with(if dark { 0.75 } else { 0.45 }, 0.12);
    let order = [
        accent.unwrap_or(fallback),
        rest.first().copied().unwrap_or(fallback),
        rest.get(1)
            .copied()
            .or(rest.first().copied())
            .unwrap_or(fallback),
    ];
    for (name, c) in ["accent", "secondary", "tertiary"].iter().zip(order) {
        accent_roles(&mut r, name, c.rgb(), surface, dark);
    }
    standard_rest(&mut r, dark);
    r
}

/// The palette pair of `w` in `mode`. `None` for a picture with no pixels.
pub fn palette(w: &Wallpaper, mode: Mode) -> Result<PaletteSet, ThemeError> {
    let sw = swatches(w);
    if sw.is_empty() {
        return Err(ThemeError::Image("wallpaper is fully transparent".into()));
    }
    let pixels: Vec<Argb> = w
        .rgba
        .chunks_exact(4)
        .filter(|p| p[3] >= 128)
        .map(|p| Argb::new(255, p[0], p[1], p[2]))
        .collect();
    let q = QuantizerCelebi::quantize(&pixels, 128);
    let seed = Score::score(&q.color_to_count, None, None, None)[0];
    let material = |v: Variant| ThemeBuilder::with_source(seed).variant(v).build();
    let (dark, light) = match mode {
        Mode::TonalMatched => {
            let t = material(Variant::TonalSpot);
            (
                material_roles(&t.schemes.dark, true),
                material_roles(&t.schemes.light, false),
            )
        }
        Mode::Vibrant => {
            let t = material(Variant::Vibrant);
            (
                material_roles(&t.schemes.dark, true),
                material_roles(&t.schemes.light, false),
            )
        }
        Mode::Prominent => (prominent_scheme(&sw, true), prominent_scheme(&sw, false)),
        Mode::Mixed => (mixed_scheme(&sw, true), mixed_scheme(&sw, false)),
    };
    Ok(PaletteSet {
        name: format!("wallpaper-{}", mode.name()),
        dark: Some(dark),
        light: Some(light),
        ..Default::default()
    })
}
