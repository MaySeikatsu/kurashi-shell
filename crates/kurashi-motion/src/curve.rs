//! Curves: how time maps to progress (K83, `docs/ux/motion-engine.md` §4).
//!
//! One text form for every curve a user, a motion pack or Settings writes — the value of `theme.motion.timing.*`:
//! a preset id (`expressive`, `snap`, `fluid` …), `cubic-bezier(x1, y1, x2, y2)`, `segments(…)` (several cubics in QML's
//! `bezierCurve` order: c1x c1y c2x c2y ex ey per segment, the last end 1, 1), `spring(<ms>, <bounce>)`, `steps(<n>)`
//! or `linear`. On input it also takes what users bring from elsewhere — Hyprland's bare `x0, y0, x1, y1`, CSS's
//! `ease-in-out`, easings.net's `easeOutBack` — and writes them back in the canonical form ([`Spec::canonical`]).
//! Any other identifier is a [`Spec::Named`] curve a motion pack may define (`[curves]`); whether it exists is the
//! resolver's question, not the parser's.

use std::fmt::Write as _;

/// A curve as the frontend runs it.
#[derive(Clone, Debug, PartialEq)]
pub enum Curve {
    /// Cubic Bézier segments in QML `bezierCurve` order (c1x c1y c2x c2y ex ey per segment; the last end is 1, 1).
    Cubic(Vec<f64>),
    /// A spring by its response (the role's duration, ms) and bounce (0 = critically damped, < 0 overdamped):
    /// SwiftUI's model, mass 1 — `stiffness = (2π / response)²`; niri's `damping-ratio = 1 − bounce`.
    Spring {
        response_ms: f64,
        bounce: f64,
    },
    /// K42's spring in QML SpringAnimation units, integrated the way that does (16 ms steps): today's calm and lively,
    /// kept bit-exact. Only the presets `calm` and `lively` make one; there is no text form for it.
    SpringQ {
        spring: f64,
        damping: f64,
    },
    /// `n` equal jumps, each held (`motion.style = stepped`, W53.0a).
    Steps(u32),
    Linear,
}

/// A parsed curve value.
#[derive(Clone, Debug, PartialEq)]
pub enum Spec {
    /// A built-in preset.
    Preset(&'static Preset),
    /// A curve written out.
    Curve(Curve),
    /// An identifier that is no built-in preset: a curve a motion pack names in its `[curves]`.
    Named(String),
}

/// Why a curve value is refused; [`CurveError::key`] is its i18n key (`error.config.curve.*`).
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
pub enum CurveError {
    #[error("not a curve: {0:?}")]
    Syntax(String),
    #[error("a cubic takes 4 numbers, segments 6 per segment")]
    Count,
    #[error("the x of every point must be within 0…1")]
    XRange,
    #[error("the y of every point must be within -1…2")]
    YRange,
    #[error("a segment's points must not go back in time")]
    Order,
    #[error("the last segment must end at 1, 1")]
    End,
    #[error("a spring's duration must be within 50…3000 ms and its bounce within -0.5…0.9")]
    SpringRange,
    #[error("steps must be within 1…60")]
    StepsRange,
    #[error("{0} has no cubic form; use a spring")]
    NotCubic(String),
}

impl CurveError {
    /// The i18n key Settings and the config diagnostics show.
    pub fn key(&self) -> &'static str {
        match self {
            CurveError::Syntax(_) => "error.config.curve.syntax",
            CurveError::Count => "error.config.curve.count",
            CurveError::XRange => "error.config.curve.x_range",
            CurveError::YRange => "error.config.curve.y_range",
            CurveError::Order => "error.config.curve.order",
            CurveError::End => "error.config.curve.end",
            CurveError::SpringRange => "error.config.curve.spring_range",
            CurveError::StepsRange => "error.config.curve.steps_range",
            CurveError::NotCubic(_) => "error.config.curve.not_cubic",
        }
    }
}

/// The limits of a written curve.
pub const X_RANGE: (f64, f64) = (0.0, 1.0);
pub const Y_RANGE: (f64, f64) = (-1.0, 2.0);
pub const SPRING_MS: (f64, f64) = (50.0, 3000.0);
pub const BOUNCE: (f64, f64) = (-0.5, 0.9);
pub const STEPS: (u32, u32) = (1, 60);

enum Shape {
    Cubic(&'static [f64]),
    Spring(f64, f64),
    SpringQ(f64, f64),
    Linear,
}

/// A built-in curve: its id (the i18n label is `config.choice.curve.<id>`), its usual duration, and whether the curve
/// editor may open it as a starting point (`spring_q` presets are not editable: they have no text form).
pub struct Preset {
    pub id: &'static str,
    pub ms: u32,
    shape: Shape,
}

impl std::fmt::Debug for Preset {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Preset({})", self.id)
    }
}

impl PartialEq for Preset {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}

impl Preset {
    pub fn curve(&self) -> Curve {
        match self.shape {
            Shape::Cubic(p) => Curve::Cubic(p.to_vec()),
            Shape::Spring(response_ms, bounce) => Curve::Spring {
                response_ms,
                bounce,
            },
            Shape::SpringQ(spring, damping) => Curve::SpringQ { spring, damping },
            Shape::Linear => Curve::Linear,
        }
    }
    pub fn editable(&self) -> bool {
        !matches!(self.shape, Shape::SpringQ(..))
    }
}

/// K74's emphasized close (M3, two segments), as tokens.rs has published it since session 15.
const EMPHASIZED: [f64; 12] = [
    0.05,
    0.0,
    2.0 / 15.0,
    0.06,
    1.0 / 6.0,
    0.4,
    5.0 / 24.0,
    0.82,
    0.25,
    1.0,
    1.0,
    1.0,
];

/// Every built-in curve (brief §4). Values that existed before K83 are copied, not re-derived: K74's open/close/fast/
/// effects, the looks' curves (fluent, aqua, material, ps2, kawaii's rubber), K42's calm and lively springs.
pub const PRESETS: &[Preset] = &[
    // K74 (Caelestia's M3 expressive tokens, read 2026-10-28).
    p(
        "expressive",
        500,
        Shape::Cubic(&[0.38, 1.21, 0.22, 1.0, 1.0, 1.0]),
    ),
    p("emphasized", 400, Shape::Cubic(&EMPHASIZED)),
    p(
        "expressive-fast",
        350,
        Shape::Cubic(&[0.42, 1.67, 0.21, 0.9, 1.0, 1.0]),
    ),
    p(
        "effects",
        200,
        Shape::Cubic(&[0.34, 0.8, 0.34, 1.0, 1.0, 1.0]),
    ),
    // Material 3 and platform curves (the looks of W53).
    p(
        "standard",
        300,
        Shape::Cubic(&[0.2, 0.0, 0.0, 1.0, 1.0, 1.0]),
    ),
    p(
        "emphasized-decelerate",
        400,
        Shape::Cubic(&[0.05, 0.7, 0.1, 1.0, 1.0, 1.0]),
    ),
    p(
        "emphasized-accelerate",
        200,
        Shape::Cubic(&[0.3, 0.0, 0.8, 0.15, 1.0, 1.0]),
    ),
    p(
        "decelerate",
        250,
        Shape::Cubic(&[0.0, 0.0, 0.0, 1.0, 1.0, 1.0]),
    ),
    p(
        "accelerate",
        200,
        Shape::Cubic(&[0.3, 0.0, 1.0, 1.0, 1.0, 1.0]),
    ),
    p(
        "fluent-exit",
        167,
        Shape::Cubic(&[1.0, 0.0, 1.0, 1.0, 1.0, 1.0]),
    ),
    p("ease", 250, Shape::Cubic(&[0.25, 0.1, 0.25, 1.0, 1.0, 1.0])),
    p(
        "ease-in",
        200,
        Shape::Cubic(&[0.42, 0.0, 1.0, 1.0, 1.0, 1.0]),
    ),
    p(
        "ease-out",
        250,
        Shape::Cubic(&[0.0, 0.0, 0.58, 1.0, 1.0, 1.0]),
    ),
    p(
        "ease-in-out",
        400,
        Shape::Cubic(&[0.42, 0.0, 0.58, 1.0, 1.0, 1.0]),
    ),
    p(
        "rubber",
        500,
        Shape::Cubic(&[0.34, 1.56, 0.64, 1.0, 1.0, 1.0]),
    ),
    // K83's characters.
    // The user's "harsh acceleration and deceleration, smoothing out before stopping": a hard in-out to 0.88 by 40 % of
    // the time, leaving at a third of the average speed, then a long soft glide home (no stop at the joint).
    p(
        "snap",
        450,
        Shape::Cubic(&[
            0.25, 0.0, 0.28, 0.838, 0.4, 0.88, 0.55, 0.9325, 0.75, 1.0, 1.0, 1.0,
        ]),
    ),
    // easeInOutBack: pulls back ~6 %, then overshoots ~6 %.
    p(
        "anticipate",
        500,
        Shape::Cubic(&[0.68, -0.55, 0.27, 1.55, 1.0, 1.0]),
    ),
    // A drop: falls under gravity, lands, rebounds 6 % and 1.5 %.
    p(
        "drop",
        600,
        Shape::Cubic(&[
            0.25, 0.0, 0.45, 0.7, 0.55, 1.0, //
            0.6, 0.96, 0.66, 0.94, 0.7, 0.94, //
            0.74, 0.94, 0.8, 0.98, 0.85, 1.0, //
            0.87, 0.99, 0.9, 0.985, 0.92, 0.985, //
            0.95, 0.985, 0.98, 1.0, 1.0, 1.0,
        ]),
    ),
    // Paper: a soft landing without overshoot (origami, scrolls).
    p("paper", 520, Shape::Cubic(&[0.3, 0.7, 0.1, 1.0, 1.0, 1.0])),
    // Springs. K42's, bit-exact (SpringAnimation units).
    p("calm", 0, Shape::SpringQ(4.0, 0.45)),
    p("lively", 0, Shape::SpringQ(3.2, 0.26)),
    p("gentle", 450, Shape::Spring(450.0, 0.0)),
    p("fluid", 500, Shape::Spring(500.0, 0.25)),
    p("bouncy", 550, Shape::Spring(550.0, 0.45)),
    p("pudding", 650, Shape::Spring(650.0, 0.65)),
    p("linear", 250, Shape::Linear),
];

const fn p(id: &'static str, ms: u32, shape: Shape) -> Preset {
    Preset { id, ms, shape }
}

/// The built-in preset with this id.
pub fn preset(id: &str) -> Option<&'static Preset> {
    PRESETS.iter().find(|p| p.id == id)
}

/// easings.net's names that are cubics (its elastic and bounce are not: they are refused with a hint).
const EASINGS_NET: &[(&str, [f64; 4])] = &[
    ("easeInSine", [0.12, 0.0, 0.39, 0.0]),
    ("easeOutSine", [0.61, 1.0, 0.88, 1.0]),
    ("easeInOutSine", [0.37, 0.0, 0.63, 1.0]),
    ("easeInQuad", [0.11, 0.0, 0.5, 0.0]),
    ("easeOutQuad", [0.5, 1.0, 0.89, 1.0]),
    ("easeInOutQuad", [0.45, 0.0, 0.55, 1.0]),
    ("easeInCubic", [0.32, 0.0, 0.67, 0.0]),
    ("easeOutCubic", [0.33, 1.0, 0.68, 1.0]),
    ("easeInOutCubic", [0.65, 0.0, 0.35, 1.0]),
    ("easeInQuart", [0.5, 0.0, 0.75, 0.0]),
    ("easeOutQuart", [0.25, 1.0, 0.5, 1.0]),
    ("easeInOutQuart", [0.76, 0.0, 0.24, 1.0]),
    ("easeInQuint", [0.64, 0.0, 0.78, 0.0]),
    ("easeOutQuint", [0.22, 1.0, 0.36, 1.0]),
    ("easeInOutQuint", [0.83, 0.0, 0.17, 1.0]),
    ("easeInExpo", [0.7, 0.0, 0.84, 0.0]),
    ("easeOutExpo", [0.16, 1.0, 0.3, 1.0]),
    ("easeInOutExpo", [0.87, 0.0, 0.13, 1.0]),
    ("easeInCirc", [0.55, 0.0, 1.0, 0.45]),
    ("easeOutCirc", [0.0, 0.55, 0.45, 1.0]),
    ("easeInOutCirc", [0.85, 0.0, 0.15, 1.0]),
    ("easeInBack", [0.36, 0.0, 0.66, -0.56]),
    ("easeOutBack", [0.34, 1.56, 0.64, 1.0]),
    ("easeInOutBack", [0.68, -0.6, 0.32, 1.6]),
];

/// Parse a curve value. `""` is not a curve (the config's "the profile's" is handled by the caller).
pub fn parse(input: &str) -> Result<Spec, CurveError> {
    let s = input.trim();
    let syntax = || CurveError::Syntax(input.to_owned());
    if s.is_empty() {
        return Err(syntax());
    }
    if let Some(p) = preset(s) {
        return Ok(Spec::Preset(p));
    }
    if let Some((_, c)) = EASINGS_NET.iter().find(|(n, _)| *n == s) {
        return cubic(c).map(Spec::Curve);
    }
    if s.starts_with("easeInElastic")
        || s.starts_with("easeOutElastic")
        || s.starts_with("easeInOutElastic")
        || s.starts_with("easeInBounce")
        || s.starts_with("easeOutBounce")
        || s.starts_with("easeInOutBounce")
    {
        return Err(CurveError::NotCubic(s.to_owned()));
    }
    if let Some((name, args)) = call(s) {
        return match name {
            "cubic-bezier" => {
                let n = numbers(args).ok_or_else(syntax)?;
                if n.len() != 4 {
                    return Err(CurveError::Count);
                }
                cubic(&n).map(Spec::Curve)
            }
            "segments" => {
                let n = numbers(args).ok_or_else(syntax)?;
                segments(n).map(Spec::Curve)
            }
            "spring" => {
                let parts: Vec<&str> = args.split(',').map(str::trim).collect();
                let [ms, bounce] = parts[..] else {
                    return Err(syntax());
                };
                let response_ms = duration(ms).ok_or_else(syntax)?;
                let bounce: f64 = bounce.parse().map_err(|_| syntax())?;
                if !(SPRING_MS.0..=SPRING_MS.1).contains(&response_ms)
                    || !(BOUNCE.0..=BOUNCE.1).contains(&bounce)
                {
                    return Err(CurveError::SpringRange);
                }
                Ok(Spec::Curve(Curve::Spring {
                    response_ms,
                    bounce,
                }))
            }
            "steps" => {
                let n: u32 = args.trim().parse().map_err(|_| syntax())?;
                if !(STEPS.0..=STEPS.1).contains(&n) {
                    return Err(CurveError::StepsRange);
                }
                Ok(Spec::Curve(Curve::Steps(n)))
            }
            _ => Err(syntax()),
        };
    }
    // Hyprland's `bezier = name, x0, y0, x1, y1` body, or four bare numbers from anywhere else.
    if s.starts_with(|c: char| c.is_ascii_digit() || c == '.' || c == '-')
        && let Some(n) = numbers(s)
    {
        if n.len() != 4 {
            return Err(CurveError::Count);
        }
        return cubic(&n).map(Spec::Curve);
    }
    if is_ident(s) {
        return Ok(Spec::Named(s.to_owned()));
    }
    Err(syntax())
}

/// `name(args)` → (name, args).
fn call(s: &str) -> Option<(&str, &str)> {
    let open = s.find('(')?;
    let args = s[open + 1..].strip_suffix(')')?;
    Some((s[..open].trim(), args))
}

/// Numbers separated by commas and/or whitespace.
fn numbers(s: &str) -> Option<Vec<f64>> {
    s.split(|c: char| c == ',' || c.is_whitespace())
        .filter(|t| !t.is_empty())
        .map(|t| t.parse::<f64>().ok().filter(|v| v.is_finite()))
        .collect()
}

/// `550`, `550ms` or `0.55s` → ms.
fn duration(s: &str) -> Option<f64> {
    let s = s.trim();
    let v = if let Some(ms) = s.strip_suffix("ms") {
        ms.trim().parse::<f64>().ok()?
    } else if let Some(sec) = s.strip_suffix('s') {
        sec.trim().parse::<f64>().ok()? * 1000.0
    } else {
        s.parse::<f64>().ok()?
    };
    v.is_finite().then_some(v)
}

/// A motion pack's curve name: lowercase ASCII, digits and dashes, starting with a letter.
pub fn is_ident(s: &str) -> bool {
    let mut chars = s.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        && s.len() <= 48
}

fn cubic(n: &[f64]) -> Result<Curve, CurveError> {
    segments(vec![n[0], n[1], n[2], n[3], 1.0, 1.0])
}

fn segments(n: Vec<f64>) -> Result<Curve, CurveError> {
    validate_cubic(&n)?;
    Ok(Curve::Cubic(n))
}

/// The checks every cubic passes, presets included: whole segments, every point in range, time never runs back
/// (each segment's controls between its ends, ends in order — so x(t) has one t per x for QML and for niri), end 1, 1.
pub fn validate_cubic(n: &[f64]) -> Result<(), CurveError> {
    if n.is_empty() || n.len() % 6 != 0 {
        return Err(CurveError::Count);
    }
    let in_x = |v: f64| (X_RANGE.0..=X_RANGE.1).contains(&v);
    let in_y = |v: f64| (Y_RANGE.0..=Y_RANGE.1).contains(&v);
    let mut x0 = 0.0;
    for seg in n.chunks(6) {
        let [c1x, c1y, c2x, c2y, ex, ey] = seg else {
            unreachable!("chunks of 6")
        };
        if ![c1x, c2x, ex].iter().all(|v| in_x(**v)) {
            return Err(CurveError::XRange);
        }
        if ![c1y, c2y, ey].iter().all(|v| in_y(**v)) {
            return Err(CurveError::YRange);
        }
        if *ex < x0 || ![c1x, c2x].iter().all(|v| (x0..=*ex).contains(*v)) {
            return Err(CurveError::Order);
        }
        x0 = *ex;
    }
    let end = &n[n.len() - 2..];
    if (end[0] - 1.0).abs() > 1e-9 || (end[1] - 1.0).abs() > 1e-9 {
        return Err(CurveError::End);
    }
    Ok(())
}

impl Spec {
    /// The curve this value stands for; a [`Spec::Named`] curve needs its pack (`None`).
    pub fn curve(&self) -> Option<Curve> {
        match self {
            Spec::Preset(p) => Some(p.curve()),
            Spec::Curve(c) => Some(c.clone()),
            Spec::Named(_) => None,
        }
    }

    /// The value as it is written back: a preset or a pack's name as itself, a curve in its canonical form.
    pub fn canonical(&self) -> String {
        match self {
            Spec::Preset(p) => p.id.to_owned(),
            Spec::Named(n) => n.clone(),
            Spec::Curve(c) => c.canonical(),
        }
    }
}

impl Curve {
    /// The canonical text form ([`parse`] reads it back to the same curve). A `SpringQ` has none (it is only ever a
    /// preset); it is written in K42's own units for logs.
    pub fn canonical(&self) -> String {
        match self {
            Curve::Cubic(n) if n.len() == 6 => {
                format!(
                    "cubic-bezier({}, {}, {}, {})",
                    num(n[0]),
                    num(n[1]),
                    num(n[2]),
                    num(n[3])
                )
            }
            Curve::Cubic(n) => {
                let mut s = String::from("segments(");
                for (i, seg) in n.chunks(6).enumerate() {
                    if i > 0 {
                        s.push_str(", ");
                    }
                    let parts: Vec<String> = seg.iter().map(|v| num(*v)).collect();
                    s.push_str(&parts.join(" "));
                }
                s.push(')');
                s
            }
            Curve::Spring {
                response_ms,
                bounce,
            } => format!("spring({}ms, {})", num(*response_ms), num(*bounce)),
            Curve::SpringQ { spring, damping } => {
                format!("spring-q({}, {})", num(*spring), num(*damping))
            }
            Curve::Steps(n) => format!("steps({n})"),
            Curve::Linear => "linear".into(),
        }
    }

    /// Progress at time `x` ∈ [0, 1] for the curves that are a function of time alone (cubic, steps, linear); springs
    /// answer in `spring.rs` (W59.1). For tests, plots and the niri export.
    pub fn sample(&self, x: f64) -> Option<f64> {
        let x = x.clamp(0.0, 1.0);
        match self {
            Curve::Linear => Some(x),
            Curve::Steps(n) => {
                let n = f64::from(*n);
                Some(if x >= 1.0 { 1.0 } else { (x * n).floor() / n })
            }
            Curve::Cubic(c) => Some(sample_cubic(c, x)),
            Curve::Spring { .. } | Curve::SpringQ { .. } => None,
        }
    }
}

fn sample_cubic(c: &[f64], x: f64) -> f64 {
    let (mut x0, mut y0) = (0.0, 0.0);
    for seg in c.chunks(6) {
        let [c1x, c1y, c2x, c2y, ex, ey] = [seg[0], seg[1], seg[2], seg[3], seg[4], seg[5]];
        if x <= ex || ex >= 1.0 {
            if ex - x0 < 1e-12 {
                return ey;
            }
            let bez = |t: f64, a: f64, b: f64, c: f64, d: f64| {
                let u = 1.0 - t;
                u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d
            };
            // x(t) is monotonic (validate_cubic): bisection is exact enough and never diverges.
            let (mut lo, mut hi) = (0.0, 1.0);
            for _ in 0..48 {
                let mid = 0.5 * (lo + hi);
                if bez(mid, x0, c1x, c2x, ex) < x {
                    lo = mid;
                } else {
                    hi = mid;
                }
            }
            return bez(0.5 * (lo + hi), y0, c1y, c2y, ey);
        }
        (x0, y0) = (ex, ey);
    }
    1.0
}

/// A number without trailing zeros, at most 4 decimals.
fn num(v: f64) -> String {
    let mut s = String::new();
    let r = (v * 1e4).round() / 1e4;
    let _ = write!(s, "{r}");
    if s == "-0" { "0".into() } else { s }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cubic_of(s: &str) -> Vec<f64> {
        match parse(s).unwrap().curve().unwrap() {
            Curve::Cubic(c) => c,
            other => panic!("{s}: not a cubic: {other:?}"),
        }
    }

    #[test]
    fn every_preset_is_valid_and_reads_back() {
        for p in PRESETS {
            if let Curve::Cubic(c) = p.curve() {
                validate_cubic(&c).unwrap_or_else(|e| panic!("{}: {e}", p.id));
            }
            assert_eq!(parse(p.id).unwrap(), Spec::Preset(p), "{}", p.id);
            assert_eq!(parse(p.id).unwrap().canonical(), p.id);
            assert!(is_ident(p.id), "{}", p.id);
        }
        let mut ids: Vec<_> = PRESETS.iter().map(|p| p.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), PRESETS.len(), "preset ids are unique");
    }

    #[test]
    fn todays_curves_are_copied_exactly() {
        // K74's tokens before K83 (tokens.rs, session 15) and K42's springs.
        assert_eq!(cubic_of("expressive"), [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]);
        assert_eq!(cubic_of("emphasized"), EMPHASIZED);
        assert_eq!(
            cubic_of("expressive-fast"),
            [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
        );
        assert_eq!(cubic_of("effects"), [0.34, 0.8, 0.34, 1.0, 1.0, 1.0]);
        assert_eq!(cubic_of("rubber"), [0.34, 1.56, 0.64, 1.0, 1.0, 1.0]);
        assert_eq!(
            preset("calm").unwrap().curve(),
            Curve::SpringQ {
                spring: 4.0,
                damping: 0.45
            }
        );
        assert_eq!(
            preset("lively").unwrap().curve(),
            Curve::SpringQ {
                spring: 3.2,
                damping: 0.26
            }
        );
        assert!(!preset("calm").unwrap().editable());
    }

    #[test]
    fn written_curves_round_trip() {
        for s in [
            "cubic-bezier(0.2, 0, 0, 1)",
            "cubic-bezier(0.68, -0.55, 0.27, 1.55)",
            "segments(0.1 0 0.2 0.5 0.5 0.6, 0.6 0.7 0.9 1 1 1)",
            "spring(550ms, 0.45)",
            "spring(400ms, -0.2)",
            "steps(6)",
            "linear",
        ] {
            let spec = parse(s).unwrap();
            assert_eq!(spec.canonical(), s);
            assert_eq!(parse(&spec.canonical()).unwrap(), spec);
        }
    }

    #[test]
    fn foreign_notations_become_canonical() {
        // Hyprland, CSS keyword, easings.net, seconds, loose separators.
        assert_eq!(
            parse("0.05, 0.9, 0.1, 1.05").unwrap().canonical(),
            "cubic-bezier(0.05, 0.9, 0.1, 1.05)"
        );
        assert_eq!(parse("ease-in-out").unwrap().canonical(), "ease-in-out");
        assert_eq!(
            parse("easeOutBack").unwrap().canonical(),
            "cubic-bezier(0.34, 1.56, 0.64, 1)"
        );
        assert_eq!(
            parse("spring(0.5s, 0.3)").unwrap().canonical(),
            "spring(500ms, 0.3)"
        );
        assert_eq!(
            parse("  cubic-bezier(0.2 0 0 1) ").unwrap().canonical(),
            "cubic-bezier(0.2, 0, 0, 1)"
        );
        assert_eq!(
            parse("easeOutBounce"),
            Err(CurveError::NotCubic("easeOutBounce".into()))
        );
    }

    #[test]
    fn names_are_left_to_the_packs() {
        assert_eq!(parse("my-snap").unwrap(), Spec::Named("my-snap".into()));
        assert_eq!(parse("my-snap").unwrap().curve(), None);
        assert!(matches!(parse("My Snap"), Err(CurveError::Syntax(_))));
    }

    #[test]
    fn bad_curves_say_why() {
        assert_eq!(parse("cubic-bezier(1.2, 0, 0, 1)"), Err(CurveError::XRange));
        assert_eq!(
            parse("cubic-bezier(0.2, 2.5, 0.3, 1)"),
            Err(CurveError::YRange)
        );
        assert_eq!(parse("cubic-bezier(0.2, 0, 1)"), Err(CurveError::Count));
        assert_eq!(
            parse("segments(0.1 0 0.2 0.5 0.5 0.6)"),
            Err(CurveError::End)
        );
        assert_eq!(
            parse("segments(0.6 0 0.2 0.5 0.5 0.6, 0.6 0.7 0.9 1 1 1)"),
            Err(CurveError::Order)
        );
        assert_eq!(parse("spring(20ms, 0.2)"), Err(CurveError::SpringRange));
        assert_eq!(parse("spring(500ms, 1)"), Err(CurveError::SpringRange));
        assert_eq!(parse("steps(0)"), Err(CurveError::StepsRange));
        assert!(matches!(parse("spring(500)"), Err(CurveError::Syntax(_))));
        assert!(matches!(parse(""), Err(CurveError::Syntax(_))));
        assert!(matches!(
            parse("cubic-bezier(a, 0, 0, 1)"),
            Err(CurveError::Syntax(_))
        ));
    }

    #[test]
    fn snap_is_harsh_then_glides_without_stopping() {
        let c = preset("snap").unwrap().curve();
        let at = |x| c.sample(x).unwrap();
        assert!(at(0.1) < 0.1, "a slow start: {}", at(0.1));
        assert!((at(0.4) - 0.88).abs() < 1e-6);
        // Still moving after the joint (no stop), then easing out to 1.
        let v_after = (at(0.45) - at(0.4)) / 0.05;
        assert!(v_after > 0.2, "glides on: {v_after}");
        assert!(at(0.9) > 0.99 && at(0.9) < 1.0);
    }

    #[test]
    fn drop_lands_and_rebounds_twice() {
        let c = preset("drop").unwrap().curve();
        let at = |x| c.sample(x).unwrap();
        assert!((at(0.55) - 1.0).abs() < 1e-6, "lands");
        assert!((at(0.7) - 0.94).abs() < 1e-3, "rebounds 6 %");
        assert!((at(0.92) - 0.985).abs() < 1e-3, "rebounds 1.5 %");
        assert!((at(1.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn samples_meet_the_ends_and_overshoot_where_stated() {
        for p in PRESETS {
            let c = p.curve();
            if let Some(y0) = c.sample(0.0) {
                assert!(y0.abs() < 1e-6, "{} starts at 0", p.id);
                assert!(
                    (c.sample(1.0).unwrap() - 1.0).abs() < 1e-6,
                    "{} ends at 1",
                    p.id
                );
            }
        }
        let max = |id| {
            (0..=200)
                .map(|i| {
                    preset(id)
                        .unwrap()
                        .curve()
                        .sample(f64::from(i) / 200.0)
                        .unwrap()
                })
                .fold(0.0, f64::max)
        };
        assert!(max("expressive") > 1.0 && max("expressive") < 1.1);
        assert!(max("paper") <= 1.0 + 1e-9);
        assert!(max("anticipate") > 1.05);
    }

    #[test]
    fn steps_hold_then_jump() {
        let c = Curve::Steps(4);
        assert_eq!(c.sample(0.1), Some(0.0));
        assert_eq!(c.sample(0.3), Some(0.25));
        assert_eq!(c.sample(1.0), Some(1.0));
    }
}
