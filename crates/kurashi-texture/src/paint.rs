//! Oil paint on primed canvas (`paint`, W31): a thin underpaint over the canvas, then a few dozen brush strokes laid in
//! passages. Each stroke is a gentle arc or S with a ductus: fine bristle tracks run along its path, each at its own depth.
//! Its body is thickest mid-stroke and thins toward the tail, where the dry brush breaks it into streaks and the canvas
//! shows between; a bead of pushed paint stands where it starts, a lip where it stops, and its sides are a little raised.
//! Later strokes lie over earlier ones. The canvas weave of `weave.rs` shows through the bare patches and the thin tails
//! and is muted under the thick passages. Tint on: the pigment's tone, a touch darker where the paint is thick. A stroke is
//! drawn at its unwrapped place, so one over the edge is drawn on both sides and the tile repeats without a seam.

use std::f32::consts::{PI, TAU};

use crate::generate::Field;
use crate::noise::{Rng, fbm_xy, hash, smoothstep};
use crate::weave;

/// The passages: each a family of strokes in a similar direction, painted one after another.
const PASSAGES: usize = 4;
/// Centreline segments per stroke: smooth at this count for an arc or an S of up to 180 px.
const SEGMENTS: usize = 12;
/// The paint's opacity over what lies under it (before its coverage): a thin layer lets the stroke below show a little.
const OPACITY: f32 = 0.93;
/// The weave under the paint as a fraction of its height: the paint smooths the canvas under a thick passage.
const CANVAS: f32 = 0.25;
/// The underpaint: its coverage where the fractal noise is high (the canvas is bare where it is low), its coverage, and
/// its height over the canvas, logical px.
const GROUND: (f32, f32) = (0.2, 0.42);
const GROUND_COVER: f32 = 0.9;
const GROUND_HEIGHT: f32 = 0.3;
/// The bare canvas as a fraction of its weave's height: calmer than the weave of a cloth (it reads behind text).
const BARE: f32 = 0.6;

/// One brush stroke. Its centreline is in unwrapped logical px.
struct Stroke {
    pts: Vec<[f32; 2]>,
    /// Arc length to each vertex.
    cum: Vec<f32>,
    len: f32,
    /// Half the brush width.
    half: f32,
    /// Paint thickness mid-stroke, logical px.
    body: f32,
    /// Spacing of the bristle tracks, logical px (no finer than 2.5: the normals are taken over 2 px).
    track: f32,
    /// Where the tracks start across the stroke (0..1 of a track).
    phase: f32,
    /// Where along the stroke (0..1) the dry brush starts.
    dry: f32,
    /// Pigment tone, 0..1.
    tone: f32,
    /// The stroke's number and seed: its own bristles and streaks.
    idx: i64,
    seed: u64,
}

/// Oil paint: the canvas of `weave.rs`, the underpaint, then the strokes of the tile, each over the ones before. Tint on:
/// the paint's pigment (A), a slight tone that follows the strokes.
pub fn oil(f: &mut Field, seed: u64, tint: bool) {
    weave::fabric(f, seed, false);
    let canvas = f.h.clone();
    let (n, l) = (f.n, f.logical);
    let mut cover = vec![0f32; n * n];
    let mut tone = vec![0f32; n * n];
    for iy in 0..n {
        for ix in 0..n {
            let k = iy * n + ix;
            let g = smoothstep(
                GROUND.0,
                GROUND.1,
                fbm_xy(f.uv(ix), f.uv(iy), 4, 4, 3, seed ^ 0x6E),
            );
            // The underpaint is relief only: the pigment follows the strokes.
            let c = GROUND_COVER * g;
            f.h[k] = (1.0 - c) * BARE * canvas[k] + c * (CANVAS * canvas[k] + GROUND_HEIGHT);
        }
    }
    for s in layout(seed, l) {
        lay(f, &s, &canvas, &mut cover, &mut tone);
    }
    if tint {
        for k in 0..n * n {
            // Where the paint is, a touch darker where it is thick and a little by its passage's tone.
            let thick = ((f.h[k] - CANVAS * canvas[k]) / 2.0).clamp(0.0, 1.0);
            f.ink[k] = (cover[k] * (0.5 + 0.2 * tone[k] + 0.3 * thick)).clamp(0.0, 1.0);
        }
    }
}

/// The strokes of the tile in the order they are laid: passage by passage, each passage closed by a stroke across it.
fn layout(seed: u64, l: f32) -> Vec<Stroke> {
    let mut rng = Rng::new(seed ^ 0x9A17_7E00);
    let mut out: Vec<Stroke> = Vec::new();
    for _ in 0..PASSAGES {
        // A passage: a direction (a line; a stroke may go either way), a region and a brush.
        let heading = rng.range(0.0, PI);
        let spread = rng.range(0.1, 0.2);
        let centre = [rng.range(0.0, l), rng.range(0.0, l)];
        let reach = rng.range(130.0, 200.0);
        let width = rng.range(17.0, 25.0);
        let passage_tone = rng.unit();
        let count = 13 + (rng.unit() * 3.0) as usize;
        for k in 0..=count {
            let (psi, at, len, w) = if k == count {
                // The stroke across the passage: it ties the strokes together and makes the crossings.
                (
                    heading + PI / 2.0 + rng.range(-0.2, 0.2),
                    centre,
                    rng.range(80.0, 120.0),
                    width * 0.9,
                )
            } else {
                let r = reach * rng.unit().sqrt();
                let phi = TAU * rng.unit();
                let flip = if rng.unit() < 0.2 { PI } else { 0.0 };
                (
                    heading + flip + spread * (2.0 * rng.unit() - 1.0),
                    [centre[0] + r * phi.cos(), centre[1] + r * phi.sin()],
                    rng.range(90.0, 180.0),
                    width * rng.range(0.85, 1.15),
                )
            };
            let s_curve = rng.unit() < 0.35;
            let bend = if s_curve {
                rng.range(0.2, 0.4)
            } else {
                rng.range(-0.45, 0.45)
            };
            let pts = path(at, psi, len, bend, s_curve);
            let mut cum = vec![0.0f32];
            for p in pts.windows(2) {
                let last = cum[cum.len() - 1];
                cum.push(last + (p[1][0] - p[0][0]).hypot(p[1][1] - p[0][1]));
            }
            let len = cum[cum.len() - 1];
            out.push(Stroke {
                pts,
                cum,
                len,
                half: w * 0.5,
                body: rng.range(1.5, 2.2),
                track: rng.range(2.8, 3.6),
                phase: rng.unit(),
                dry: rng.range(0.4, 0.7),
                tone: (passage_tone + 0.3 * (rng.unit() - 0.5)).clamp(0.0, 1.0),
                idx: out.len() as i64,
                seed: rng.next_u64(),
            });
        }
    }
    out
}

/// The centreline of a stroke: `len` px from `heading`, bent by a turn of `bend` radians (an arc) or swung to an S of
/// amplitude `bend` (`s_curve`), and centred on `at`.
fn path(at: [f32; 2], heading: f32, len: f32, bend: f32, s_curve: bool) -> Vec<[f32; 2]> {
    let step = len / SEGMENTS as f32;
    let mut pts = vec![[0.0f32; 2]];
    for k in 0..SEGMENTS {
        let s = (k as f32 + 0.5) / SEGMENTS as f32;
        let psi = heading
            + if s_curve {
                bend * (TAU * s).sin()
            } else {
                bend * (s - 0.5)
            };
        let [x, y] = pts[pts.len() - 1];
        pts.push([x + psi.cos() * step, y + psi.sin() * step]);
    }
    let n = pts.len() as f32;
    let (mx, my) = pts
        .iter()
        .fold((0.0, 0.0), |(sx, sy), p| (sx + p[0] / n, sy + p[1] / n));
    pts.iter()
        .map(|p| [at[0] + p[0] - mx, at[1] + p[1] - my])
        .collect()
}

/// The nearest centreline point of a stroke for every texel of its box: the distance `d`, the signed offset across the
/// path `e` and the arc position `u`. `u` is unclamped beyond the two ends, so the head and the tail come out round.
struct Near {
    x0: isize,
    y0: isize,
    w: usize,
    h: usize,
    d: Vec<f32>,
    e: Vec<f32>,
    u: Vec<f32>,
}

fn near(s: &Stroke, scale: f32, reach: f32) -> Near {
    let (mut x0, mut y0, mut x1, mut y1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for p in &s.pts {
        x0 = x0.min(p[0]);
        y0 = y0.min(p[1]);
        x1 = x1.max(p[0]);
        y1 = y1.max(p[1]);
    }
    let ix0 = ((x0 - reach) * scale).floor() as isize;
    let iy0 = ((y0 - reach) * scale).floor() as isize;
    let ix1 = ((x1 + reach) * scale).ceil() as isize;
    let iy1 = ((y1 + reach) * scale).ceil() as isize;
    let (w, h) = ((ix1 - ix0 + 1) as usize, (iy1 - iy0 + 1) as usize);
    let mut near = Near {
        x0: ix0,
        y0: iy0,
        w,
        h,
        d: vec![f32::MAX; w * h],
        e: vec![0.0; w * h],
        u: vec![0.0; w * h],
    };
    // Each segment fills only its own box (grown by the reach), so the work follows the stroke's length, not its box.
    let last = s.pts.len() - 2;
    for j in 0..=last {
        let (a, b) = (s.pts[j], s.pts[j + 1]);
        let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
        let ll = dx.hypot(dy).max(1e-6);
        let (ux, uy) = (dx / ll, dy / ll);
        let jx0 = ((a[0].min(b[0]) - reach) * scale).floor() as isize;
        let jx1 = ((a[0].max(b[0]) + reach) * scale).ceil() as isize;
        let jy0 = ((a[1].min(b[1]) - reach) * scale).floor() as isize;
        let jy1 = ((a[1].max(b[1]) + reach) * scale).ceil() as isize;
        for iy in jy0..=jy1 {
            let py = (iy as f32 + 0.5) / scale - a[1];
            for ix in jx0..=jx1 {
                let px = (ix as f32 + 0.5) / scale - a[0];
                let t = (px * ux + py * uy) / ll;
                let tau = t.clamp(0.0, 1.0);
                let (qx, qy) = (px - ux * ll * tau, py - uy * ll * tau);
                let d = qx.hypot(qy);
                let i = (iy - iy0) as usize * w + (ix - ix0) as usize;
                if d < near.d[i] {
                    // Beyond the first or the last segment the arc position runs on, so the caps are round.
                    let t_end = if (j == 0 && t < 0.0) || (j == last && t > 1.0) {
                        t
                    } else {
                        tau
                    };
                    near.d[i] = d;
                    near.e[i] = ux * py - uy * px;
                    near.u[i] = s.cum[j] + t_end * ll;
                }
            }
        }
    }
    near
}

/// Smooth noise along a stroke (0..1): a hash per cell of `t` (a few px), blended, so a track's streaks run a short way.
fn along(i: i64, t: f32, seed: u64) -> f32 {
    let k = t.floor();
    let f = t - k;
    let s = f * f * (3.0 - 2.0 * f);
    let (a, b) = (hash(i, k as i64, seed), hash(i, k as i64 + 1, seed));
    a + (b - a) * s
}

/// Lays one stroke over the surface: its relief over `f.h` (the paint covers what it reaches, the canvas shows between and
/// through the dry brush), and its coverage and tone for the pigment.
fn lay(f: &mut Field, s: &Stroke, canvas: &[f32], cover: &mut [f32], tone: &mut [f32]) {
    // The widest the brush wanders (1.2 half-widths) and the coverage's edge, so every texel that is covered is in the box.
    let reach = s.half * 1.2 + 1.2;
    let near = near(s, f.scale, reach);
    let n = f.n as isize;
    for by in 0..near.h {
        for bx in 0..near.w {
            let bi = by * near.w + bx;
            // Beyond the reach no texel is covered (the brush is at most 1.19 half-widths wide): skip it before the noise.
            if near.d[bi] >= reach {
                continue;
            }
            let (e, u) = (near.e[bi], near.u[bi]);
            // The brush's half-width wanders along the stroke, so its edges are never ruled lines.
            let half = s.half
                * (0.85
                    + 0.3 * along(0, u / 22.0, s.seed ^ 0x77)
                    + 0.08 * (along(0, u / 5.0, s.seed ^ 0x79) - 0.5));
            // `outside` is the distance to the stroke (0 within) and `sd` its signed distance (negative within), for the
            // coverage and the ridge along its sides. Past either end the stroke is a flat-ended rectangle, round only at its
            // corners; along the body it is the round-edged path itself, so a joint between two segments does not square off.
            let d = near.d[bi];
            let (outside, sd) = if u < 0.0 || u > s.len {
                let lat = e.abs() - half;
                let beyond = (-u).max(u - s.len);
                (lat.max(0.0).hypot(beyond.max(0.0)), lat.max(beyond))
            } else {
                (d - half, d - half)
            };
            if outside >= 1.2 {
                continue;
            }
            let (ix, iy) = (near.x0 + bx as isize, near.y0 + by as isize);
            let k = (iy.rem_euclid(n) * n + ix.rem_euclid(n)) as usize;
            let t = (u / s.len).clamp(0.0, 1.0);
            // Coverage: full inside the brush, a soft edge, thinner toward the tail, and a little thicker and thinner along.
            let edge = smoothstep(0.8, -0.9, outside);
            let thick = (1.0 - 0.7 * smoothstep(0.45, 1.0, t))
                * (0.85 + 0.3 * along(0, u / 30.0, s.seed ^ 0x78));
            // Dry brush: from `dry` along the stroke the tracks lose their paint in streaks, the canvas between.
            let dryness = smoothstep(s.dry, 1.0, t);
            let across = e / s.track + s.phase + (along(0, u / 14.0, s.seed ^ 0x51) - 0.5);
            let track = across.floor();
            let frac = across - track;
            let ti = track as i64;
            let streak = along(ti, u / 6.0, s.seed ^ 0xD2);
            let cut = 0.75 * dryness;
            let alive = 1.0 - dryness * (1.0 - smoothstep(cut - 0.1, cut + 0.1, streak));
            // Ductus: each bristle track has its own depth, which deepens and breaks up along the stroke.
            let depth = ((0.35 + 0.65 * hash(ti, s.idx, s.seed ^ 0xA7))
                * (0.6 + 0.8 * along(ti, u / 9.0, s.seed ^ 0xB3)))
            .clamp(0.0, 1.2);
            let groove = 0.8 * depth * (1.0 - (PI * frac).sin()).powf(1.5);
            // Impasto: the paint lumps along each track, so the body is never an even plateau.
            let lump = 0.8 + 0.4 * along(ti, u / 12.0, s.seed ^ 0x91);
            let body = (s.body * thick * lump - groove).max(0.0);
            // Pushed paint: a bead where the stroke starts, a lip where it stops, and raised sides.
            let across_w = (1.0 - (e / half).powi(2)).max(0.0).sqrt();
            let bead = 0.55 * s.body * (-(u / 2.2).powi(2)).exp() * across_w;
            let lip = 0.5
                * s.body
                * (-((u - s.len) / 2.5).powi(2)).exp()
                * across_w
                * (1.0 - 0.4 * dryness);
            let side = 0.3 * thick * (-((sd + 0.7) / 0.7).powi(2)).exp();
            let top = body + bead + lip + side;
            let c = (edge * thick * alive * OPACITY).clamp(0.0, 1.0);
            f.h[k] = f.h[k] * (1.0 - c) + c * (CANVAS * canvas[k] + top);
            cover[k] += (1.0 - cover[k]) * c;
            tone[k] += (s.tone - tone[k]) * c;
        }
    }
}
