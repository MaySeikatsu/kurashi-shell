//! Wallpaper Color Grade (K88, `docs/ux/wallpaper-color-grade.md`): the wallpaper recoloured to the theme's colours by a 3D
//! lookup table, never an overlay. The picture's own main colours are read first (a median cut in Oklab) and paired with the
//! theme's, so its colour structure survives (Chang et al. 2015's approach, here automatic); a near-colourless picture has
//! too little colour for that and takes a gradient map. The table is built once per picture and theme; the original file is
//! never written. Pure: the daemon's bake (`kurashid::texture`) decides when, and caches the result.

use serde_json::{Map, Value};

use crate::color::{Rgb, linear_of_oklab, linear_to_srgb, oklab_of_linear, srgb_to_linear};

/// The theme's colours a picture is graded towards.
pub const TARGET_ROLES: [&str; 6] = [
    "color.surface",
    "color.surface_container_high",
    "color.selected",
    "color.tertiary",
    "color.secondary",
    "color.accent",
];
/// Colours read from a picture.
const ANCHORS: usize = 6;
/// Side of the picture's thumbnail its colours are read from.
pub const THUMB_SIDE: u32 = 96;
/// Grid points per axis of the table: 35 937 entries, trilinear in between.
const GRID: usize = 33;
/// Below this mean chroma a picture counts as near-colourless (user's check pattern: 0.031).
const NEUTRAL_CHROMA: f64 = 0.035;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// `Match`, or `Gradient` for a near-colourless picture.
    Auto,
    /// The picture's colours mapped onto the theme's.
    Match,
    /// The picture's colour balance shifted to the theme's.
    Balance,
    /// Shadows to highlights through the theme's colours.
    Gradient,
    /// The picture pulled towards the theme's colours, whatever its own were.
    Palette,
}

impl Mode {
    pub fn parse(s: &str) -> Self {
        match s {
            "match" => Self::Match,
            "balance" => Self::Balance,
            "gradient" => Self::Gradient,
            "palette" => Self::Palette,
            _ => Self::Auto,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Grade {
    pub mode: Mode,
    /// 0: the original, 1: fully graded.
    pub strength: f64,
    /// How far the picture's lightness may follow the theme: 0 keeps it.
    pub lightness: f64,
    pub targets: [Rgb; 6],
}

impl Grade {
    /// A stable text of everything that changes the result, for the bake's cache key.
    pub fn key(&self) -> String {
        format!("{self:?}")
    }
}

/// The theme's colours from its tokens; `None` when one is missing.
pub fn targets_of(tokens: &Map<String, Value>) -> Option<[Rgb; 6]> {
    let mut out = [Rgb(0, 0, 0); 6];
    for (slot, role) in out.iter_mut().zip(TARGET_ROLES) {
        *slot = tokens
            .get(role)
            .and_then(Value::as_str)
            .and_then(Rgb::parse)?;
    }
    Some(out)
}

type Lab = [f64; 3];

fn lab_of(c: Rgb) -> Lab {
    oklab_of_linear(c.to_linear())
}

fn chroma(p: &Lab) -> f64 {
    p[1].hypot(p[2])
}

/// The picture's main colours with their share: a median cut in Oklab, always `ANCHORS` long.
fn palette_of(rgba: &[u8]) -> Vec<(Lab, f64)> {
    let mut boxes: Vec<Vec<Lab>> = vec![
        rgba.chunks_exact(4)
            .filter(|p| p[3] > 127)
            .map(|p| lab_of(Rgb(p[0], p[1], p[2])))
            .collect(),
    ];
    while boxes.len() < ANCHORS {
        // Split the box with the most colour variation left, weighted by how much of the picture it holds.
        let spread = |b: &Vec<Lab>, axis: usize| {
            let (lo, hi) = b.iter().fold((f64::MAX, f64::MIN), |(l, h), p| {
                (l.min(p[axis]), h.max(p[axis]))
            });
            hi - lo
        };
        let Some((i, axis)) = boxes
            .iter()
            .enumerate()
            .filter(|(_, b)| b.len() > 1)
            .flat_map(|(i, b)| (0..3).map(move |a| (i, a, b)))
            .max_by(|x, y| {
                let score =
                    |(_, a, b): &(usize, usize, &Vec<Lab>)| spread(b, *a) * (b.len() as f64).sqrt();
                score(x).total_cmp(&score(y))
            })
            .map(|(i, a, _)| (i, a))
        else {
            break;
        };
        let mut b = boxes.swap_remove(i);
        b.sort_by(|p, q| p[axis].total_cmp(&q[axis]));
        let rest = b.split_off(b.len() / 2);
        boxes.push(b);
        boxes.push(rest);
    }
    let total: usize = boxes.iter().map(Vec::len).sum::<usize>().max(1);
    let mut out: Vec<(Lab, f64)> = boxes
        .iter()
        .filter(|b| !b.is_empty())
        .map(|b| {
            let n = b.len() as f64;
            let m = b
                .iter()
                .fold([0.0; 3], |a, p| [a[0] + p[0], a[1] + p[1], a[2] + p[2]]);
            ([m[0] / n, m[1] / n, m[2] / n], n / total as f64)
        })
        .collect();
    let first = out.first().copied().unwrap_or(([0.5, 0.0, 0.0], 1.0));
    while out.len() < ANCHORS {
        out.push((first.0, 0.0));
    }
    out
}

/// Mean and spread of a weighted palette, per Oklab axis.
fn stats(list: &[(Lab, f64)]) -> (Lab, Lab) {
    let total: f64 = list.iter().map(|(_, w)| w).sum::<f64>().max(1e-9);
    let mut mean = [0.0; 3];
    for (p, w) in list {
        for a in 0..3 {
            mean[a] += p[a] * w / total;
        }
    }
    let mut sigma = [0.0; 3];
    for (p, w) in list {
        for a in 0..3 {
            sigma[a] += (p[a] - mean[a]).powi(2) * w / total;
        }
    }
    (mean, sigma.map(f64::sqrt))
}

/// The grade worked out for one picture: what each colour becomes, before the strength.
struct Mapping {
    mode: Mode,
    lightness: f64,
    /// Pairs for `Match`: neutral with neutral, vivid with vivid.
    pairs: Vec<(Lab, Lab)>,
    /// The targets, sorted by lightness for `Gradient`.
    ramp: Vec<Lab>,
    targets: Vec<Lab>,
    source_mean: Lab,
    source_sigma: Lab,
    target_mean: Lab,
    target_sigma: Lab,
    low: f64,
    high: f64,
}

impl Mapping {
    fn new(grade: &Grade, rgba: &[u8]) -> Self {
        let source = palette_of(rgba);
        let (source_mean, source_sigma) = stats(&source);
        let mean_chroma = source.iter().map(|(p, w)| chroma(p) * w).sum::<f64>();
        let mode = match grade.mode {
            Mode::Auto if mean_chroma < NEUTRAL_CHROMA => Mode::Gradient,
            Mode::Auto => Mode::Match,
            m => m,
        };
        let targets: Vec<Lab> = grade.targets.iter().map(|c| lab_of(*c)).collect();
        let weighted: Vec<(Lab, f64)> = targets.iter().map(|p| (*p, 1.0)).collect();
        let (target_mean, target_sigma) = stats(&weighted);
        let mut by_chroma: Vec<Lab> = source.iter().map(|(p, _)| *p).collect();
        by_chroma.sort_by(|a, b| chroma(a).total_cmp(&chroma(b)));
        let mut vivid = targets.clone();
        vivid.sort_by(|a, b| chroma(a).total_cmp(&chroma(b)));
        let mut ramp = targets.clone();
        ramp.sort_by(|a, b| a[0].total_cmp(&b[0]));
        let low = source.iter().map(|(p, _)| p[0]).fold(1.0, f64::min);
        let high = source.iter().map(|(p, _)| p[0]).fold(0.0, f64::max);
        Self {
            mode,
            lightness: grade.lightness,
            pairs: by_chroma.into_iter().zip(vivid).collect(),
            ramp,
            targets,
            source_mean,
            source_sigma,
            target_mean,
            target_sigma,
            low,
            high,
        }
    }

    /// Shepard interpolation: each anchor pulls by the inverse of its distance, so what lies between anchors moves smoothly.
    /// Lightness counts for less: hue decides which anchor a colour belongs to.
    fn matched(&self, p: Lab) -> Lab {
        let (mut sum, mut total) = ([0.0; 3], 0.0);
        for (s, d) in &self.pairs {
            let v = [(p[0] - s[0]) * 0.5, p[1] - s[1], p[2] - s[2]];
            let w = 1.0 / (v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + 0.002).powf(1.5);
            for a in 0..3 {
                sum[a] += w * (d[a] - s[a]);
            }
            total += w;
        }
        [
            p[0] + sum[0] / total * self.lightness,
            p[1] + sum[1] / total,
            p[2] + sum[2] / total,
        ]
    }

    /// Reinhard's transfer, on the colour axes: the picture's balance and spread become the theme's.
    fn balanced(&self, p: Lab) -> Lab {
        let axis = |a: usize| {
            let ratio = (self.target_sigma[a] / self.source_sigma[a].max(0.005)).clamp(0.0, 3.0);
            (p[a] - self.source_mean[a]) * ratio + self.target_mean[a]
        };
        [
            p[0] + (self.target_mean[0] - self.source_mean[0]) * self.lightness,
            axis(1),
            axis(2),
        ]
    }

    fn gradient(&self, p: Lab) -> Lab {
        let t = ((p[0] - self.low) / (self.high - self.low).max(0.02)).clamp(0.0, 1.0)
            * (self.ramp.len() - 1) as f64;
        let i = (t.floor() as usize).min(self.ramp.len() - 2);
        let f = t - i as f64;
        let c = |a: usize| self.ramp[i][a] + (self.ramp[i + 1][a] - self.ramp[i][a]) * f;
        [p[0] + (c(0) - p[0]) * self.lightness, c(1), c(2)]
    }

    /// A Gaussian pull towards the nearest targets (the approach of lutgen): the picture's own colours do not count.
    fn pulled(&self, p: Lab) -> Lab {
        let (mut sum, mut total) = ([0.0; 3], 0.0);
        for d in &self.targets {
            let v = [(p[0] - d[0]) * 0.5, p[1] - d[1], p[2] - d[2]];
            let w = (-(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) * 60.0).exp();
            for a in 0..3 {
                sum[a] += w * d[a];
            }
            total += w;
        }
        let total = total.max(1e-4);
        let c = |a: usize| sum[a] / total;
        [p[0] + (c(0) - p[0]) * self.lightness, c(1), c(2)]
    }

    fn apply(&self, p: Lab) -> Lab {
        match self.mode {
            Mode::Balance => self.balanced(p),
            Mode::Gradient => self.gradient(p),
            Mode::Palette => self.pulled(p),
            Mode::Match | Mode::Auto => self.matched(p),
        }
    }
}

/// A 3D lookup table over sRGB.
pub struct Lut {
    data: Vec<[f32; 3]>,
    /// The grade the picture took: `Auto` resolved.
    pub mode: Mode,
}

impl Lut {
    /// The table for a grade and a picture's `thumbnail` (RGBA, about [`THUMB_SIDE`] a side).
    pub fn build(grade: &Grade, thumbnail: &[u8]) -> Self {
        let map = Mapping::new(grade, thumbnail);
        let step = 1.0 / (GRID - 1) as f64;
        let mut data = Vec::with_capacity(GRID * GRID * GRID);
        for b in 0..GRID {
            for g in 0..GRID {
                for r in 0..GRID {
                    let c = [r as f64 * step, g as f64 * step, b as f64 * step];
                    let lab = oklab_of_linear(c.map(srgb_to_linear));
                    let o =
                        linear_of_oklab(map.apply(lab)).map(|v| linear_to_srgb(v.clamp(0.0, 1.0)));
                    let mixed: [f32; 3] =
                        std::array::from_fn(|i| (c[i] + (o[i] - c[i]) * grade.strength) as f32);
                    data.push(mixed);
                }
            }
        }
        Self {
            data,
            mode: map.mode,
        }
    }

    fn at(&self, r: usize, g: usize, b: usize) -> [f32; 3] {
        self.data[r + g * GRID + b * GRID * GRID]
    }

    fn sample(&self, c: [f32; 3]) -> [f32; 3] {
        let scale = (GRID - 1) as f32;
        let pos = c.map(|v| v * scale);
        let i = pos.map(|v| (v as usize).min(GRID - 2));
        let f: [f32; 3] = std::array::from_fn(|a| pos[a] - i[a] as f32);
        let mut out = [0.0; 3];
        for (bits, weight) in [
            (0, (1.0 - f[0]) * (1.0 - f[1]) * (1.0 - f[2])),
            (1, f[0] * (1.0 - f[1]) * (1.0 - f[2])),
            (2, (1.0 - f[0]) * f[1] * (1.0 - f[2])),
            (3, f[0] * f[1] * (1.0 - f[2])),
            (4, (1.0 - f[0]) * (1.0 - f[1]) * f[2]),
            (5, f[0] * (1.0 - f[1]) * f[2]),
            (6, (1.0 - f[0]) * f[1] * f[2]),
            (7, f[0] * f[1] * f[2]),
        ] {
            let v = self.at(
                i[0] + (bits & 1),
                i[1] + ((bits >> 1) & 1),
                i[2] + ((bits >> 2) & 1),
            );
            for a in 0..3 {
                out[a] += v[a] * weight;
            }
        }
        out
    }

    /// Grades RGBA pixels in place; alpha stays.
    pub fn apply(&self, rgba: &mut [u8]) {
        for p in rgba.chunks_exact_mut(4) {
            let c = [p[0], p[1], p[2]].map(|v| f32::from(v) / 255.0);
            let o = self.sample(c);
            for a in 0..3 {
                p[a] = (o[a].clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEAL: [&str; 6] = [
        "#00504e", "#0e6a67", "#2f7f7c", "#4d9e9a", "#66b8b4", "#80d5d2",
    ];

    fn targets() -> [Rgb; 6] {
        TEAL.map(|h| Rgb::parse(h).unwrap())
    }

    fn grade(mode: Mode) -> Grade {
        Grade {
            mode,
            strength: 1.0,
            lightness: 0.0,
            targets: targets(),
        }
    }

    /// A colourful picture: two hues over a lightness ramp.
    fn colourful() -> Vec<u8> {
        (0..96 * 96)
            .flat_map(|i| {
                let (x, y) = ((i % 96) as f32 / 95.0, (i / 96) as f32 / 95.0);
                let v = (40.0 + 200.0 * y) as u8;
                if x < 0.5 {
                    [v, (v as f32 * 0.4) as u8, 30, 255]
                } else {
                    [30, (v as f32 * 0.5) as u8, v, 255]
                }
            })
            .collect()
    }

    /// The user's kind of wallpaper: a beige check.
    fn beige() -> Vec<u8> {
        (0..96 * 96)
            .flat_map(|i| {
                let line = (i % 96) % 6 == 0;
                if line {
                    [174u8, 159, 144, 255]
                } else {
                    [205, 188, 170, 255]
                }
            })
            .collect()
    }

    fn graded(mode: Mode, picture: &[u8]) -> Vec<u8> {
        let lut = Lut::build(&grade(mode), picture);
        let mut out = picture.to_vec();
        lut.apply(&mut out);
        out
    }

    fn mean_lab(rgba: &[u8]) -> Lab {
        let (mut m, mut n) = ([0.0; 3], 0.0);
        for p in rgba.chunks_exact(4) {
            let l = lab_of(Rgb(p[0], p[1], p[2]));
            for a in 0..3 {
                m[a] += l[a];
            }
            n += 1.0;
        }
        m.map(|v| v / n)
    }

    fn hue_gap(a: f64, b: f64) -> f64 {
        let d = (a - b).abs() % std::f64::consts::TAU;
        d.min(std::f64::consts::TAU - d)
    }

    #[test]
    fn a_near_colourless_picture_takes_a_gradient_and_a_colourful_one_a_match() {
        assert_eq!(
            Lut::build(&grade(Mode::Auto), &beige()).mode,
            Mode::Gradient
        );
        assert_eq!(
            Lut::build(&grade(Mode::Auto), &colourful()).mode,
            Mode::Match
        );
        // A choice stays a choice.
        assert_eq!(
            Lut::build(&grade(Mode::Palette), &beige()).mode,
            Mode::Palette
        );
    }

    /// The prototype's bug: a grey result. The beige must take the theme's hue, with real colour.
    #[test]
    fn the_beige_check_turns_teal_and_not_grey() {
        let out = graded(Mode::Auto, &beige());
        let m = mean_lab(&out);
        let target = lab_of(targets()[3]);
        assert!(chroma(&m) > 0.025, "chroma {:.3}: grey", chroma(&m));
        assert!(
            hue_gap(m[2].atan2(m[1]), target[2].atan2(target[1])) < 0.5,
            "the hue left the theme's"
        );
    }

    #[test]
    fn every_mode_moves_a_picture_and_keeps_its_lightness_by_default() {
        for mode in [Mode::Match, Mode::Balance, Mode::Gradient, Mode::Palette] {
            let src = colourful();
            let out = graded(mode, &src);
            assert_ne!(out, src, "{mode:?} did nothing");
            let worst = src
                .chunks_exact(4)
                .zip(out.chunks_exact(4))
                .map(|(a, b)| {
                    let (la, lb) = (lab_of(Rgb(a[0], a[1], a[2])), lab_of(Rgb(b[0], b[1], b[2])));
                    (la[0] - lb[0]).abs()
                })
                .fold(0.0, f64::max);
            // Out-of-gamut colours clip, so a little moves; the picture's structure must not.
            assert!(worst < 0.2, "{mode:?} moved lightness by {worst:.3}");
        }
    }

    #[test]
    fn strength_zero_is_the_original_and_alpha_stays() {
        let src: Vec<u8> = colourful()
            .chunks_exact(4)
            .flat_map(|p| [p[0], p[1], p[2], 128])
            .collect();
        let g = Grade {
            strength: 0.0,
            ..grade(Mode::Match)
        };
        let mut out = src.clone();
        Lut::build(&g, &src).apply(&mut out);
        assert!(
            src.iter().zip(&out).all(|(a, b)| a.abs_diff(*b) <= 1),
            "strength 0 changed the picture"
        );
        assert!(out.chunks_exact(4).all(|p| p[3] == 128));
    }

    #[test]
    fn lightness_lets_the_picture_follow_the_theme() {
        let src = colourful();
        let dark = Grade {
            lightness: 1.0,
            ..grade(Mode::Palette)
        };
        let mut out = src.clone();
        Lut::build(&dark, &src).apply(&mut out);
        assert!((mean_lab(&out)[0] - mean_lab(&src)[0]).abs() > 0.02);
    }

    /// How far the table strays from the exact grade, over a picture.
    fn table_error(g: &Grade, src: &[u8]) -> (f64, f64) {
        let map = Mapping::new(g, src);
        let mut out = src.to_vec();
        Lut::build(g, src).apply(&mut out);
        let (mut worst, mut sum, mut n) = (0.0_f64, 0.0, 0.0);
        for (a, b) in src.chunks_exact(4).zip(out.chunks_exact(4)) {
            let exact = linear_of_oklab(map.apply(lab_of(Rgb(a[0], a[1], a[2]))))
                .map(|v| linear_to_srgb(v.clamp(0.0, 1.0)) * 255.0);
            for i in 0..3 {
                let gap = (exact[i] - f64::from(b[i])).abs();
                worst = worst.max(gap);
                sum += gap;
                n += 1.0;
            }
        }
        (worst, sum / n)
    }

    #[test]
    fn the_table_stays_close_to_the_exact_grade() {
        for mode in [Mode::Match, Mode::Balance, Mode::Gradient, Mode::Palette] {
            let (worst, mean) = table_error(&grade(mode), &colourful());
            eprintln!("{mode:?}: worst {worst:.1}, mean {mean:.2}");
            assert!(
                mean < 1.0 && worst < 12.0,
                "{mode:?}: off by {mean:.2} on average, {worst:.1} at worst"
            );
        }
    }

    #[test]
    fn the_keys_differ_when_the_result_would() {
        let a = grade(Mode::Auto);
        assert_ne!(a.key(), Grade { strength: 0.5, ..a }.key());
        assert_ne!(
            a.key(),
            Grade {
                mode: Mode::Match,
                ..a
            }
            .key()
        );
        let mut t = a;
        t.targets[0] = Rgb(1, 2, 3);
        assert_ne!(a.key(), t.key());
    }

    #[test]
    fn targets_come_from_the_tokens_and_need_all_six() {
        let mut m = Map::new();
        for (role, c) in TARGET_ROLES.iter().zip(TEAL) {
            m.insert((*role).into(), Value::String(c.into()));
        }
        assert_eq!(targets_of(&m), Some(targets()));
        m.remove("color.accent");
        assert_eq!(targets_of(&m), None);
    }

    /// The bake's budget (brief): `cargo test --release -p kurashi-theme a_grade_is_quick -- --ignored --nocapture`.
    #[test]
    #[ignore = "a release measure"]
    fn a_grade_is_quick() {
        let thumb = colourful();
        let t0 = std::time::Instant::now();
        let lut = Lut::build(&grade(Mode::Match), &thumb);
        let built = t0.elapsed();
        let mut pixels = vec![120u8; 2560 * 1440 * 4];
        let t1 = std::time::Instant::now();
        lut.apply(&mut pixels);
        eprintln!("table {built:?}, 2560x1440 {:?}", t1.elapsed());
        assert!(built + t1.elapsed() < std::time::Duration::from_millis(500));
    }

    #[test]
    fn a_blank_or_tiny_picture_does_not_panic() {
        for picture in [vec![], vec![10, 20, 30, 255], vec![0, 0, 0, 0]] {
            let _ = Lut::build(&grade(Mode::Auto), &picture);
        }
    }
}
