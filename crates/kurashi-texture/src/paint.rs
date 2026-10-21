//! Oil paint on primed canvas (`paint`, W31): a surface the strokes cover edge to edge. The strokes are streamlines of one
//! slowly turning flow over the tile, grouped in passages (each with its own lean, brush width and pigment tone) and laid in
//! order, so later strokes lie over earlier ones and their edge ridges and beads stand on the paint below. Each stroke has
//! bristle tracks along its length, each at its own depth; its body lumps and thins toward a dry-brush tail, where the canvas
//! shows through in streaks; a bead of pushed paint stands where it starts, a lip where it stops, and its sides are raised.
//! The canvas weave of `weave.rs` shows only in the dry tails and the rare thin spot, and is muted under the paint. Tint on:
//! the pigment follows the strokes, a touch darker where the paint is thick. The flow, the strokes and the noise are periodic
//! in the tile, and a stroke over the edge is drawn on both sides, so the tile repeats without a seam.

use std::f32::consts::{PI, TAU};

use crate::generate::Field;
use crate::noise::{Rng, hash, smoothstep};
use crate::weave;

/// The passages: each a region with its own lean of the strokes, brush width and pigment tone.
const PASSAGES: usize = 3;
/// The strokes: one per cell of a jittered grid of this many cells a side.
const GRID: usize = 7;
/// Centreline segments per stroke, and how many of them lie before the seed (the seed sits near the middle).
const SEGMENTS: usize = 8;
const BACK: usize = 3;
/// The paint's opacity over what lies under it (before its coverage): a thin layer lets the stroke below show a little.
const OPACITY: f32 = 0.93;
/// The weave under the paint as a fraction of its height: the paint smooths the canvas under a thick passage.
const CANVAS: f32 = 0.25;
/// The bare canvas as a fraction of its weave's height (the start, before any stroke): calmer than a cloth's weave.
const BARE: f32 = 0.6;
/// The relief of a stroke's bead, lip and raised sides, as fractions of its body thickness.
const BEAD: f32 = 0.7;
const LIP: f32 = 0.5;
const SIDE: f32 = 0.45;

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

/// A passage: a Gaussian region of the tile (`radius`) where the strokes lean by `lean` radians, with its brush and tone.
#[derive(Clone, Copy)]
struct Passage {
    centre: [f32; 2],
    radius: f32,
    lean: f32,
    width: f32,
    tone: f32,
}

/// The direction of the strokes at a point (radians). A few slow waves over the tile (whole periods, so the field is
/// periodic) and each passage's lean where it lies, blended by the passages' Gaussians of the wrapped distance.
struct Flow {
    phase: [f32; 4],
    passages: [Passage; PASSAGES],
    size: f32,
}

/// `d` wrapped to −`l`/2 … `l`/2 (the nearest image on the tile).
fn wrap(d: f32, l: f32) -> f32 {
    d - l * (d / l).round()
}

impl Flow {
    fn weights(&self, p: [f32; 2]) -> [f32; PASSAGES] {
        std::array::from_fn(|j| {
            let q = &self.passages[j];
            let (dx, dy) = (
                wrap(p[0] - q.centre[0], self.size),
                wrap(p[1] - q.centre[1], self.size),
            );
            (-(dx * dx + dy * dy) / (2.0 * q.radius * q.radius)).exp()
        })
    }

    fn angle(&self, p: [f32; 2]) -> f32 {
        let (x, y, t) = (p[0], p[1], TAU / self.size);
        let wave = 0.16 * (t * x + self.phase[0]).sin()
            + 0.10 * (t * y + self.phase[1]).sin()
            + 0.06 * (t * (x + y) + self.phase[2]).sin()
            + 0.05 * (t * (x - y) + self.phase[3]).sin();
        let w = self.weights(p);
        let (mut sum, mut lean) = (1.0f32, 0.0f32);
        for (j, wj) in w.iter().enumerate() {
            sum += wj;
            lean += wj * self.passages[j].lean;
        }
        wave + lean / sum
    }

    /// The passage a point belongs to most: the one with the largest weight.
    fn owner(&self, p: [f32; 2]) -> usize {
        let w = self.weights(p);
        (0..PASSAGES)
            .max_by(|a, b| w[*a].total_cmp(&w[*b]))
            .unwrap_or(0)
    }
}

/// Oil paint: the canvas of `weave.rs`, muted to bare, then the strokes of the tile, each over the ones before. Tint on: the
/// paint's pigment (A), a slight tone that follows the strokes.
pub fn oil(f: &mut Field, seed: u64, tint: bool) {
    weave::fabric(f, seed, false);
    let canvas = f.h.clone();
    let (n, l) = (f.n, f.logical);
    for (h, c) in f.h.iter_mut().zip(&canvas) {
        *h = BARE * c;
    }
    let mut cover = vec![0f32; n * n];
    let mut tone = vec![0f32; n * n];
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

/// The strokes of the tile in the order they are laid: passage by passage, and within a passage in grid order.
fn layout(seed: u64, l: f32) -> Vec<Stroke> {
    let mut rng = Rng::new(seed ^ 0x9A17_7E00);
    let passages = std::array::from_fn(|_| Passage {
        centre: [rng.range(0.0, l), rng.range(0.0, l)],
        radius: rng.range(140.0, 220.0),
        lean: rng.range(-0.45, 0.45),
        width: rng.range(40.0, 60.0),
        tone: rng.unit(),
    });
    let phase = std::array::from_fn(|_| rng.range(0.0, TAU));
    let flow = Flow {
        phase,
        passages,
        size: l,
    };
    let cell = l / GRID as f32;
    let mut laid: Vec<(usize, Stroke)> = Vec::with_capacity(GRID * GRID);
    for j in 0..GRID {
        for i in 0..GRID {
            let seed_at = [
                (i as f32 + 0.5 + rng.range(-0.4, 0.4)) * cell,
                (j as f32 + 0.5 + rng.range(-0.4, 0.4)) * cell,
            ];
            let owner = flow.owner(seed_at);
            let pass = flow.passages[owner];
            // A streamline through the seed: a few segments back, the rest forward along the flow.
            let total = rng.range(130.0, 200.0);
            let step = total / SEGMENTS as f32;
            let a0 = flow.angle(seed_at);
            let mut q = [
                seed_at[0] - a0.cos() * step * BACK as f32,
                seed_at[1] - a0.sin() * step * BACK as f32,
            ];
            let mut pts = vec![q];
            for _ in 0..SEGMENTS {
                let a = flow.angle(q);
                q = [q[0] + a.cos() * step, q[1] + a.sin() * step];
                pts.push(q);
            }
            let mut cum = vec![0.0f32];
            for p in pts.windows(2) {
                let last = cum[cum.len() - 1];
                cum.push(last + (p[1][0] - p[0][0]).hypot(p[1][1] - p[0][1]));
            }
            let len = cum[cum.len() - 1];
            let stroke = Stroke {
                pts,
                cum,
                len,
                half: 0.5 * pass.width * rng.range(0.8, 1.2),
                body: rng.range(1.0, 2.6),
                track: rng.range(3.0, 4.0),
                phase: rng.unit(),
                dry: rng.range(0.4, 0.7),
                tone: (pass.tone + 0.3 * (rng.unit() - 0.5)).clamp(0.0, 1.0),
                idx: 0,
                seed: rng.next_u64(),
            };
            laid.push((owner, stroke));
        }
    }
    // Passage by passage (a stable sort keeps the grid order within one): later passages lie over earlier ones.
    laid.sort_by_key(|(owner, _)| *owner);
    laid.into_iter()
        .enumerate()
        .map(|(i, (_, mut s))| {
            s.idx = i as i64;
            s
        })
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

/// How far the brush has come at arc position `u`: 0 beyond the ends, rounding up over the head (0.55 of the half-width) and
/// the tail (0.9, dragged out), and 1 across the body. A rounded tip, so no stroke ends in a straight line.
fn end_taper(u: f32, len: f32, half: f32) -> f32 {
    if u <= 0.0 || u >= len {
        return 0.0;
    }
    let (head, tail) = (0.55 * half, 0.9 * half);
    let round = |x: f32| (1.0 - x * x).max(0.0).sqrt();
    let mut k = 1.0;
    if u < head {
        k = round((head - u) / head);
    }
    if u > len - tail {
        k = k.min(round((u - (len - tail)) / tail));
    }
    k
}

/// Smooth noise along a stroke (0..1): a hash per cell of `t` (a few px), blended, so a track's streaks run a short way.
fn along(i: i64, t: f32, seed: u64) -> f32 {
    let k = t.floor();
    let f = t - k;
    let s = f * f * (3.0 - 2.0 * f);
    let (a, b) = (hash(i, k as i64, seed), hash(i, k as i64 + 1, seed));
    a + (b - a) * s
}

/// Lays one stroke over the surface: its relief over `f.h` (it covers what it reaches; the paint below shows only where it
/// is thin), and its coverage and tone for the pigment.
fn lay(f: &mut Field, s: &Stroke, canvas: &[f32], cover: &mut [f32], tone: &mut [f32]) {
    // The widest the brush wanders (1.2 half-widths) and the coverage's edge, so every texel that is covered is in the box.
    let reach = s.half * 1.2 + 1.2;
    let near = near(s, f.scale, reach);
    let n = f.n as isize;
    for by in 0..near.h {
        for bx in 0..near.w {
            let bi = by * near.w + bx;
            // Beyond the reach no texel is covered (the brush is at most 1.19 half-widths wide): skip it before the noise.
            let d = near.d[bi];
            if d >= reach {
                continue;
            }
            let (e, u) = (near.e[bi], near.u[bi]);
            // The brush's half-width: wandering along the stroke, so its edges are never ruled lines, and tapering to a rounded
            // end at either end. `outside` is the distance to the stroke (0 within), `sd` its signed distance for the ridge
            // along its sides. The distance is to the centreline itself, so a joint between two segments stays round.
            let wobble = 0.85 + 0.3 * along(0, u / 22.0, s.seed ^ 0x77);
            let hw = s.half * wobble * end_taper(u, s.len, s.half);
            let outside = d - hw;
            let sd = outside;
            if outside >= 1.2 {
                continue;
            }
            let half = hw.max(1e-3);
            let (ix, iy) = (near.x0 + bx as isize, near.y0 + by as isize);
            let k = (iy.rem_euclid(n) * n + ix.rem_euclid(n)) as usize;
            let t = (u / s.len).clamp(0.0, 1.0);
            // Coverage: full inside the brush, a soft edge, and thinner toward the tail.
            let edge = smoothstep(0.8, -0.9, outside);
            let thick = 1.0 - 0.7 * smoothstep(0.45, 1.0, t);
            // Dry brush: from `dry` along the stroke the tracks lose their paint in streaks, the canvas between.
            let dryness = smoothstep(s.dry, 1.0, t);
            let across = e / s.track + s.phase + (along(0, u / 14.0, s.seed ^ 0x51) - 0.5);
            let track = across.floor();
            let frac = across - track;
            let ti = track as i64;
            let alive = if dryness > 0.0 {
                let cut = 0.75 * dryness;
                let streak = along(ti, u / 6.0, s.seed ^ 0xD2);
                1.0 - dryness * (1.0 - smoothstep(cut - 0.1, cut + 0.1, streak))
            } else {
                1.0
            };
            // Ductus: each bristle track has its own depth, which deepens and breaks up along the stroke.
            // Most tracks are shallow and a few are deep, so the grooves read as strokes of the brush rather than corrugation.
            let pick = hash(ti, s.idx, s.seed ^ 0xA7);
            let depth = ((0.15 + 0.85 * pick * pick)
                * (0.5 + 0.9 * along(ti, u / 9.0, s.seed ^ 0xB3)))
            .clamp(0.0, 1.4);
            let groove = 0.9 * depth * (1.0 - (PI * frac).sin()).powf(2.5);
            // Impasto: the paint lumps along each track, so the body is never an even plateau.
            let lump = 0.8 + 0.4 * along(ti, u / 12.0, s.seed ^ 0x91);
            let body = (s.body * thick * lump - groove).max(0.0);
            // Pushed paint: a bead where the stroke starts, a lip where it stops, and raised sides.
            let across_w = (1.0 - (e / half).powi(2)).max(0.0).sqrt();
            let bead = BEAD * s.body * (-(u / 2.2).powi(2)).exp() * across_w;
            let lip = LIP
                * s.body
                * (-((u - s.len) / 2.5).powi(2)).exp()
                * across_w
                * (1.0 - 0.4 * dryness);
            let side = SIDE * thick * (-((sd + 0.7) / 0.7).powi(2)).exp();
            let top = body + bead + lip + side;
            let c = (edge * thick * alive * OPACITY).clamp(0.0, 1.0);
            f.h[k] = f.h[k] * (1.0 - c) + c * (CANVAS * canvas[k] + top);
            cover[k] += (1.0 - cover[k]) * c;
            tone[k] += (s.tone - tone[k]) * c;
        }
    }
}
