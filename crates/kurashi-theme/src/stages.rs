//! The palette pipeline (DESIGN-SYSTEM §2): pure `Palette -> Palette` stages, each
//! returning notes for provenance. Order: source, scheme, oled, contrast, season,
//! colorblind, ink, wcag (wcag last so nothing can undo the legibility guarantee).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::UNIX_EPOCH;

use material_colors::color::Argb;
use material_colors::quantize::{Quantizer, QuantizerCelebi};
use material_colors::scheme::Scheme as MScheme;
use material_colors::score::Score;
use material_colors::theme::ThemeBuilder;

use crate::ThemeError;
use crate::color::{BLACK, Rgb, WHITE, contrast, ensure_contrast};
use crate::input::{Colorblind, ContrastLevel, Ink, Scheme, Source, Wallpaper};
use crate::palette::{CHROMA_ROLES, CONTAINERS, Palette, PaletteSet, ROLES, RawRoles};
use crate::season::{Date, season_hue, solar_term};

pub struct StageOut {
    pub palette: Palette,
    pub notes: Vec<String>,
}

fn out(palette: Palette, notes: Vec<String>) -> StageOut {
    StageOut { palette, notes }
}

// ---------- 1. source ----------

pub fn source(src: &Source) -> Result<(PaletteSet, Vec<String>), ThemeError> {
    match src {
        Source::Palette(name) => Ok((
            crate::palette::bundled(name)?,
            vec![format!("source: palette:{name}")],
        )),
        Source::PaletteToml(text) => {
            let set = PaletteSet::from_toml(text)?;
            let n = format!("source: palette:{} (user file)", set.name);
            Ok((set, vec![n]))
        }
        Source::Manual(roles) => Ok((
            PaletteSet::manual("manual", roles.clone()),
            vec!["source: manual roles".into()],
        )),
        Source::Wallpaper(w) => {
            let e = extract(w)?;
            let note = e.note(None);
            Ok((e.set, vec![note]))
        }
        Source::WallpaperFile(path) => {
            let e = wallpaper_file(path)?;
            let note = e.note(Some(path));
            Ok((e.set.clone(), vec![note]))
        }
    }
}

/// Mean HSL saturation below which a picture has no colour to build a scheme from. Material's
/// scorer then returns its fallback blue, which is not the picture's colour; the monochrome
/// fallback (`wa-iro`, see [`extract`]) is used instead. The picker flags the same pictures.
pub const MONO_SATURATION: f64 = 0.08;

/// The opaque pixels of an RGBA buffer that are neither near black nor near white.
fn chromatic_pixels(rgba: &[u8]) -> impl Iterator<Item = (f64, f64)> + '_ {
    rgba.chunks_exact(4)
        .filter(|p| p[3] >= 128)
        .filter_map(|p| {
            let r = f64::from(p[0]) / 255.0;
            let g = f64::from(p[1]) / 255.0;
            let b = f64::from(p[2]) / 255.0;
            let (mx, mn) = (r.max(g).max(b), r.min(g).min(b));
            let l = (mx + mn) / 2.0;
            if !(0.08..=0.92).contains(&l) {
                return None;
            }
            let d = mx - mn;
            let s = if d == 0.0 {
                0.0
            } else {
                d / (1.0 - (2.0 * l - 1.0).abs())
            };
            Some((s, l))
        })
}

/// True when the picture has no usable colour: its mean saturation is under [`MONO_SATURATION`].
pub fn is_monochrome(rgba: &[u8]) -> bool {
    let (sum, n) =
        chromatic_pixels(rgba).fold((0.0_f64, 0_u64), |(s, n), (sat, _)| (s + sat, n + 1));
    n == 0 || (sum / (n as f64)) < MONO_SATURATION
}

/// What a picture gives the `wallpaper` source: the roles of both schemes, the seed they were built
/// from, and whether the picture is monochrome (then `set` is the bundled `wa-iro` fallback, named
/// after the palette in effect, and `seed` is `None`).
#[derive(Clone, Debug)]
pub struct Extracted {
    pub set: PaletteSet,
    pub seed: Option<Rgb>,
    pub mono: bool,
    /// The picture's mean perceived lightness, CIE L* 0–100 (K55: scheme `wallpaper` is light from
    /// [`LIGHT_WALLPAPER`] up).
    pub lightness: f64,
}

/// The mean L* from which a wallpaper counts as light (K55). Photos of a bright sky sit near 70, night scenes
/// below 30; 55 keeps mid-grey pictures dark, where a light shell over them would glare.
pub const LIGHT_WALLPAPER: f64 = 55.0;

impl Extracted {
    /// Whether scheme `wallpaper` resolves to light for this picture (K55).
    pub fn is_light(&self) -> bool {
        self.lightness >= LIGHT_WALLPAPER
    }
}

/// The mean perceived lightness (CIE L*, 0–100) of the opaque pixels of `rgba`: the relative luminance of each
/// pixel (sRGB → linear, Rec. 709 weights) averaged, then mapped to L*.
pub fn mean_lightness(rgba: &[u8]) -> f64 {
    fn lin(c: u8) -> f64 {
        let c = f64::from(c) / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    }
    let (mut sum, mut n) = (0.0, 0u64);
    for p in rgba.chunks_exact(4).filter(|p| p[3] >= 128) {
        sum += 0.2126 * lin(p[0]) + 0.7152 * lin(p[1]) + 0.0722 * lin(p[2]);
        n += 1;
    }
    if n == 0 {
        return 0.0;
    }
    let y = sum / n as f64;
    if y > 216.0 / 24389.0 {
        116.0 * y.cbrt() - 16.0
    } else {
        y * 24389.0 / 27.0
    }
}

impl Extracted {
    /// The provenance line for the `source` stage (`source: wallpaper …`).
    fn note(&self, path: Option<&Path>) -> String {
        let from = path.map_or(String::new(), |p| format!(" {}", p.display()));
        match self.seed {
            Some(seed) => format!("source: wallpaper{from}, seed colour {seed}"),
            None => format!(
                "source: wallpaper{from} is monochrome (no colour to build a scheme from); palette {} used",
                self.set.name
            ),
        }
    }
}

fn validate(w: &Wallpaper) -> Result<(), ThemeError> {
    if w.rgba.len() != (w.width as usize) * (w.height as usize) * 4 || w.rgba.is_empty() {
        return Err(ThemeError::Image(
            "wallpaper buffer size does not match its dimensions".into(),
        ));
    }
    Ok(())
}

/// Extracts a decoded picture: material roles, or the monochrome fallback.
pub fn extract(w: &Wallpaper) -> Result<Extracted, ThemeError> {
    validate(w)?;
    let lightness = mean_lightness(&w.rgba);
    if is_monochrome(&w.rgba) {
        let mut set = crate::palette::bundled("wa-iro")?;
        set.name = "wa-iro".into();
        return Ok(Extracted {
            set,
            seed: None,
            mono: true,
            lightness,
        });
    }
    let (set, seed) = from_wallpaper(w)?;
    Ok(Extracted {
        set,
        seed: Some(seed),
        mono: false,
        lightness,
    })
}

/// Longest side the extraction decodes to: colour is all it needs.
const EXTRACT_SIDE: u32 = 128;
/// Pictures kept extracted; the cache starts over when it is full (the picker and the theme use few).
const CACHE_MAX: usize = 32;

type CacheKey = (PathBuf, u128, u64);
static CACHE: Mutex<BTreeMap<CacheKey, Arc<Extracted>>> = Mutex::new(BTreeMap::new());

fn cache() -> MutexGuard<'static, BTreeMap<CacheKey, Arc<Extracted>>> {
    // A panic in another extraction must not take the theme down with it: the map is still valid.
    CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The palette of the picture at `path`, extracted now or taken from the cache. The key is the
/// path with its mtime and size, so an edited picture is extracted again. Blocking I/O and CPU:
/// callers run it on a blocking thread.
pub fn wallpaper_file(path: &Path) -> Result<Arc<Extracted>, ThemeError> {
    let meta = std::fs::metadata(path)
        .map_err(|e| ThemeError::Image(format!("{}: {e}", path.display())))?;
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_nanos());
    let key = (path.to_path_buf(), mtime, meta.len());
    if let Some(hit) = cache().get(&key) {
        return Ok(hit.clone());
    }
    let w = Wallpaper::load(path, EXTRACT_SIDE)?;
    let got = Arc::new(extract(&w)?);
    let mut map = cache();
    if map.len() >= CACHE_MAX {
        map.clear();
    }
    map.insert(key, got.clone());
    Ok(got)
}

fn rgb_of(a: Argb) -> Rgb {
    Rgb(a.red, a.green, a.blue)
}

/// Quantise + score the pixels (material-colors), then build both schemes from the seed.
pub fn from_wallpaper(w: &Wallpaper) -> Result<(PaletteSet, Rgb), ThemeError> {
    if w.rgba.len() != (w.width as usize) * (w.height as usize) * 4 || w.rgba.is_empty() {
        return Err(ThemeError::Image(
            "wallpaper buffer size does not match its dimensions".into(),
        ));
    }
    let pixels: Vec<Argb> = w
        .rgba
        .chunks_exact(4)
        .filter(|p| p[3] >= 128) // ignore transparent pixels
        .map(|p| Argb::new(255, p[0], p[1], p[2]))
        .collect();
    if pixels.is_empty() {
        return Err(ThemeError::Image("wallpaper is fully transparent".into()));
    }
    let q = QuantizerCelebi::quantize(&pixels, 128);
    let ranked = Score::score(&q.color_to_count, None, None, None);
    let seed = ranked[0];
    let theme = ThemeBuilder::with_source(seed).build();
    let roles = |s: &MScheme, warning: &str| -> RawRoles {
        [
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
        .map(|(k, v)| (k.to_string(), rgb_of(v)))
        // Material has no warning role: use wa-iro's yamabuki, the WCAG stage fits it.
        .chain([("warning".to_string(), Rgb::parse(warning).unwrap())])
        .collect()
    };
    let set = PaletteSet {
        name: "wallpaper".into(),
        dark: Some(roles(&theme.schemes.dark, "#e0a33b")),
        light: Some(roles(&theme.schemes.light, "#b07a14")),
    };
    Ok((set, rgb_of(seed)))
}

// ---------- 2. scheme ----------

pub fn scheme(set: PaletteSet, which: Scheme) -> Result<StageOut, ThemeError> {
    let (want, other) = match which {
        Scheme::Dark => (set.dark.clone(), set.light.clone()),
        Scheme::Light => (set.light.clone(), set.dark.clone()),
    };
    let word = if which == Scheme::Dark {
        "dark"
    } else {
        "light"
    };
    let (roles, note) = match (want, other) {
        (Some(r), _) => (r, format!("scheme: {word}")),
        (None, Some(r)) => {
            // Honest fallback: the palette ships one scheme only; say so.
            let o = if which == Scheme::Dark {
                "light"
            } else {
                "dark"
            };
            (
                r,
                format!("scheme: {word} requested but palette only has {o}; using {o} roles"),
            )
        }
        (None, None) => return Err(ThemeError::Parse(format!("palette {} is empty", set.name))),
    };
    // `dark` follows what was requested for derivations only when the roles exist for it;
    // in the fallback case the roles' own lightness decides.
    let dark = match roles.get("surface") {
        Some(s) => s.luminance() < 0.18,
        None => which == Scheme::Dark,
    };
    let p = Palette {
        name: set.name,
        dark,
        roles,
    }
    .complete()?;
    Ok(out(p, vec![note]))
}

// ---------- 2b. oled ----------

pub fn oled(mut p: Palette, on: bool) -> StageOut {
    if !on {
        return out(p, vec!["oled: off".into()]);
    }
    if !p.dark {
        return out(p, vec!["oled: on but scheme is light; no effect".into()]);
    }
    p.set("surface", BLACK);
    p.derive_containers();
    out(
        p,
        vec!["oled: surface #000000, containers re-derived".into()],
    )
}

// ---------- 3. contrast ----------

pub fn contrast_level(mut p: Palette, level: ContrastLevel) -> StageOut {
    let k = match level {
        ContrastLevel::Standard => return out(p, vec!["contrast: standard".into()]),
        ContrastLevel::Medium => 0.25,
        ContrastLevel::High => 0.6,
    };
    let (fg_end, bg_end) = if p.dark {
        (WHITE, BLACK)
    } else {
        (BLACK, WHITE)
    };
    for r in [
        "on_surface",
        "on_surface_variant",
        "outline",
        "outline_variant",
    ] {
        let c = p.get(r).mix(fg_end, k);
        p.set(r, c);
    }
    for r in [
        "accent",
        "secondary",
        "tertiary",
        "success",
        "warning",
        "error",
    ] {
        let c = p.get(r).mix(fg_end, k * 0.4);
        p.set(r, c);
    }
    // Push grounds slightly away from the text so the gap widens from both sides.
    for r in std::iter::once(&"surface").chain(CONTAINERS.iter()) {
        let c = p.get(r).mix(bg_end, k * 0.3);
        p.set(r, c);
    }
    let n = format!(
        "contrast: {level:?}, text/outline/accent +{:.0}%, grounds +{:.0}%",
        k * 100.0,
        k * 30.0
    );
    out(p, vec![n])
}

// ---------- 4. season (旬) ----------

/// The fraction of the way every hue leans toward the season's own (`season_hue`): calm, and visible all year (I281:
/// the old warm/cool swing peaked at 5 % and was near 0 in spring and autumn).
pub const SEASON_STRENGTH: f64 = 0.2;
/// The saturation a grey takes in the season's hue: a whisper of colour where there is no hue to turn.
const SEASON_GREY: f64 = 0.05;
/// Then every colour is blended this far toward the season's colour at its own lightness (contrast stays; a palette
/// whose hues already sit near the season's — a warm one in autumn — still shows it).
const SEASON_BLEND: f64 = 0.1;
const SEASON_SAT: f64 = 0.55;

pub fn season(mut p: Palette, date: Option<Date>) -> StageOut {
    let Some(date) = date else {
        return out(p, vec!["season: off".into()]);
    };
    let term = solar_term(date);
    let (target, near) = season_hue(term);
    let frac = SEASON_STRENGTH;
    for r in ROLES.iter().filter(|r| !matches!(**r, "scrim" | "shadow")) {
        let c = p.get(r);
        let (h, s, l) = c.to_hsl();
        let nc = if s < 0.03 {
            // True greys have no hue to rotate: a whisper of the season's colour instead.
            Rgb::from_hsl(target, SEASON_GREY, l)
        } else {
            let mut d = (target - h).rem_euclid(360.0);
            if d > 180.0 {
                d -= 360.0;
            }
            Rgb::from_hsl(h + d * frac, s, l)
        };
        let (_, _, nl) = nc.to_hsl();
        p.set(
            r,
            nc.mix(Rgb::from_hsl(target, SEASON_SAT, nl), SEASON_BLEND),
        );
    }
    let n = format!(
        "season: {} {} ({near}), hue {:.0}% toward {:.0}°",
        term.ja,
        term.romaji,
        frac * 100.0,
        target
    );
    out(p, vec![n])
}

// ---------- 5. colorblind ----------

type M3 = [[f64; 3]; 3];

/// Machado, Oliveira & Fernandes (2009), severity 1.0, applied to linear RGB.
pub fn machado(kind: Colorblind) -> Option<M3> {
    match kind {
        Colorblind::None => None,
        Colorblind::Protanopia => Some([
            [0.152286, 1.052583, -0.204868],
            [0.114503, 0.786281, 0.099216],
            [-0.003882, -0.048116, 1.051998],
        ]),
        Colorblind::Deuteranopia => Some([
            [0.367322, 0.860646, -0.227968],
            [0.280085, 0.672501, 0.047413],
            [-0.011820, 0.042940, 0.968881],
        ]),
        Colorblind::Tritanopia => Some([
            [1.255528, -0.076749, -0.178779],
            [-0.078411, 0.930809, 0.147602],
            [0.004733, 0.691367, 0.303900],
        ]),
    }
}

fn mul(m: &M3, v: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|i| m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2])
}

/// What a person with this deficiency sees for `c`.
pub fn simulate(c: Rgb, kind: Colorblind) -> Rgb {
    match machado(kind) {
        None => c,
        Some(m) => Rgb::from_linear(mul(&m, c.to_linear())),
    }
}

/// Daltonisation: move the information the viewer loses (orig - simulated) into channels
/// they can still tell apart, so accent/secondary/status colours stay distinguishable.
/// Simulating alone would make them *less* distinguishable, which is the opposite of the goal.
pub fn daltonize(c: Rgb, kind: Colorblind) -> Rgb {
    let o = c.to_linear();
    let s = simulate(c, kind).to_linear();
    let e = [o[0] - s[0], o[1] - s[1], o[2] - s[2]];
    let shift: M3 = match kind {
        Colorblind::Tritanopia => [[0.0, 0.0, 0.7], [0.0, 0.0, 0.7], [0.0, 0.0, 0.0]],
        _ => [[0.0, 0.0, 0.0], [0.7, 0.0, 0.0], [0.7, 0.0, 0.0]],
    };
    let add = mul(&shift, e);
    Rgb::from_linear([o[0] + add[0], o[1] + add[1], o[2] + add[2]])
}

pub fn colorblind(mut p: Palette, kind: Colorblind) -> StageOut {
    if kind == Colorblind::None {
        return out(p, vec!["colorblind: none".into()]);
    }
    for r in CHROMA_ROLES {
        let c = daltonize(p.get(r), kind);
        p.set(r, c);
    }
    out(
        p,
        vec![format!(
            "colorblind: {kind:?} (Machado 2009, severity 1.0), chroma roles daltonised"
        )],
    )
}

// ---------- ink (K60) ----------

/// A named ink's shade on light paper and on dark paper: a pen on a page, a gel pen on black card.
pub fn ink_color(name: &str, dark: bool) -> Option<Rgb> {
    let (light, dark_c) = match name {
        "blue" => ("#1d3f99", "#9fc2ff"),
        "black" => ("#1f1e22", "#ecebe6"),
        "sepia" => ("#5b3a1e", "#e3c69c"),
        "red" => ("#a3222b", "#ff9d92"),
        "green" => ("#1f6b3a", "#96d8a8"),
        "violet" => ("#57308f", "#cdb0ff"),
        _ => return None,
    };
    Rgb::parse(if dark { dark_c } else { light })
}

/// The text colour (`theme.colors.ink`): `on_surface` becomes the ink and `on_surface_variant` the ink thinned toward
/// the surface. The wcag stage after it keeps both legible.
pub fn ink(mut p: Palette, ink: &Ink) -> StageOut {
    let c = match ink {
        Ink::Palette => return out(p, vec!["ink: the palette's".into()]),
        Ink::Named(name) => match ink_color(name, p.dark) {
            Some(c) => c,
            None => {
                return out(
                    p,
                    vec![format!("ink: unknown ink `{name}`, the palette's kept")],
                );
            }
        },
        Ink::Custom(c) => *c,
    };
    let before = p.get("on_surface");
    p.set("on_surface", c);
    p.set("on_surface_variant", c.mix(p.get("surface"), 0.3));
    out(p, vec![format!("ink: on_surface {before} → {c}")])
}

// ---------- 6. wcag ----------

pub const BODY: f64 = 4.5;
pub const UI: f64 = 3.0;

/// (foreground role, background role, minimum ratio). The foreground is the one moved.
/// UI-colour pairs come first so the `on_*` pairs are checked against their final backgrounds.
pub fn aa_pairs() -> Vec<(&'static str, &'static str, f64)> {
    let mut v = vec![];
    for fg in [
        "outline",
        "accent",
        "secondary",
        "tertiary",
        "success",
        "warning",
        "error",
    ] {
        v.push((fg, "surface", UI));
    }
    // Outlines also frame the containers (notification cards, lock box, stage). Measured 2.70:1
    // on surface_container at wa-iro, under the UI minimum (UX review R.2 item 5).
    v.push(("outline", "surface_container", UI));
    for (on, bg) in [
        ("on_accent", "accent"),
        ("on_accent_container", "accent_container"),
        ("on_secondary", "secondary"),
        ("on_tertiary", "tertiary"),
        ("on_success", "success"),
        ("on_warning", "warning"),
        ("on_error", "error"),
        // W53.0a: caption text on the caption's start, tooltip text on its fill.
        ("on_title", "title"),
        ("on_info", "info"),
    ] {
        v.push((on, bg, BODY));
    }
    for bg in std::iter::once("surface").chain(CONTAINERS.iter().copied()) {
        v.push(("on_surface", bg, BODY));
    }
    for bg in ["surface", "surface_container", "surface_container_high"] {
        v.push(("on_surface_variant", bg, BODY));
    }
    v
}

pub fn wcag(mut p: Palette, on: bool) -> StageOut {
    if !on {
        return out(p, vec!["wcag: off (legibility not enforced)".into()]);
    }
    let mut notes = vec![];
    for (fg, bg, min) in aa_pairs() {
        let (f, b) = (p.get(fg), p.get(bg));
        let before = contrast(f, b);
        let nf = ensure_contrast(f, b, min);
        if nf != f {
            notes.push(format!(
                "wcag: {fg} {f} → {nf} ({before:.1} → {:.1}:1 on {bg}, need {min})",
                contrast(nf, b)
            ));
            p.set(fg, nf);
        }
    }
    if notes.is_empty() {
        notes.push("wcag: AA already satisfied, no changes".into());
    }
    out(p, notes)
}
