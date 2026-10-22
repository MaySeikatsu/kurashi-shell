//! Brush strokes (`brush`, K61): long, gently curving strokes of a hairy brush laid over the whole sheet, the way a wall or a
//! canvas is painted in passes: every stroke a bundle of bristle tracks that run its whole length, ridges of paint pushed to
//! its edges, a thick blob where the brush lands and dry-brush breakup where it runs out; the strokes overlap and run on,
//! so there is no bare canvas anywhere. Tint on: the pigment varies a little in tone per stroke and along the tracks.
//!
//! **Lanes.** A pass is a family of parallel lanes along a whole-number direction: with `s = (p x + q y) / l` the lines of
//! constant `s` run along `(q, −p)` and, because `p` and `q` are whole and coprime, each line closes on itself on the tile
//! after `l √(p² + q²)` px — several tile widths. A slow periodic field bends `s` (so the lanes sweep and swell), a lane
//! is a band of `s`, and the strokes of a lane are laid end to end round its loop, each overlapping the next. Every texel
//! finds its lane and its place along the lane's loop from its own position (canonically, so the same point of the loop
//! gets the same coordinates from every image of the tile), which makes the sheet seamless and every row independent.
//!
//! **Passes.** Three passes at slightly different angles (18°, 22° and 14° above the horizontal, rising to the right): the
//! first covers the sheet edge to edge (its strokes are wider than its lanes), the two after it leave gaps between their
//! strokes and skip some, so the earlier strokes show between them and their edges stand on the paint below.

use crate::generate::{Field, rows2};
use crate::noise::{Rng, fbm_xy, hash, smoothstep, value_xy};

/// The bristle tracks' pitch, logical px: the finest groove the normals still resolve at scale 1 (I170), and a finer
/// octave of single hairs between them.
const TRACK: f32 = 2.6;
const HAIR: f32 = 1.25;
/// The bristles' relief, logical px for the full swing of the grain.
const GRAIN: f32 = 2.0;
/// A clump of bristles that share their paint, logical px across.
const CLUMP: f32 = 9.0;
/// How much of the paint below a stroke's surface follows (it is laid over the ridges below, not levelled).
const CONFORM: f32 = 0.3;
/// The underpaint's height, logical px: about where layers of strokes settle (`body / (1 − CONFORM)`).
const UNDER: f32 = 2.8;
/// The paint's opacity where the brush is loaded.
const OPACITY: f32 = 0.97;

/// One pass: its direction `(p, q)`, its lanes per unit of `s`, the strokes' width as a share of a lane, the strokes per
/// loop, the share of strokes that are laid, and how far the field bends its lanes (px).
struct Pass {
    p: i64,
    q: i64,
    lanes: i64,
    width: f32,
    strokes: (usize, usize),
    laid: f32,
    bend: f32,
}

const PASSES: [Pass; 3] = [
    Pass {
        p: 1,
        q: 3,
        lanes: 3,
        width: 1.4,
        strokes: (1, 2),
        laid: 1.0,
        bend: 40.0,
    },
    Pass {
        p: 2,
        q: 5,
        lanes: 1,
        width: 0.82,
        strokes: (2, 3),
        laid: 0.8,
        bend: 45.0,
    },
    Pass {
        p: 1,
        q: 4,
        lanes: 2,
        width: 0.8,
        strokes: (1, 2),
        laid: 0.6,
        bend: 35.0,
    },
];

/// One stroke round a lane's loop.
struct Stroke {
    /// Where it starts along the loop (units of `s`), and its length (px).
    start: f32,
    len: f32,
    /// Half its width (px), its paint thickness (px), where its brush starts to run dry (0..1 of its length), its tone.
    half: f32,
    body: f32,
    dry: f32,
    tone: f32,
    seed: u64,
}

/// A pass ready to be evaluated: its geometry and the strokes of each lane.
struct Frame {
    p: f32,
    q: f32,
    /// The loop's length in units (`p² + q²`), and the shift along the loop from one unit of `s` to the next.
    m: f32,
    tau: f32,
    /// Px per unit of `s` (and of the along coordinate), per lane.
    unit: f32,
    lane: f32,
    lanes: i64,
    bend: f32,
    seed: u64,
    strokes: Vec<Vec<Stroke>>,
}

/// One stroke's paint at a texel: its coverage, the height of its surface over the paint below, its pigment, and where it
/// lies in the order of the strokes (later on top).
#[derive(Clone, Copy)]
struct Dab {
    order: (u32, f32, i64, f32),
    cover: f32,
    top: f32,
    ink: f32,
}

/// `a` with `a x + b y = 1` for coprime `p`, `q` (the extended Euclid), so one unit of `s` shifts the loop by `a q − b p`.
fn bezout(p: i64, q: i64) -> (i64, i64) {
    let (mut r0, mut r1, mut s0, mut s1, mut t0, mut t1) = (p, q, 1i64, 0i64, 0i64, 1i64);
    while r1 != 0 {
        let k = r0 / r1;
        (r0, r1) = (r1, r0 - k * r1);
        (s0, s1) = (s1, s0 - k * s1);
        (t0, t1) = (t1, t0 - k * t1);
    }
    (s0, t0)
}

fn frame(pass: &Pass, index: usize, l: f32, rng: &mut Rng) -> Frame {
    let (a, b) = bezout(pass.p, pass.q);
    let m = (pass.p * pass.p + pass.q * pass.q) as f32;
    let unit = l / m.sqrt();
    let lane = unit / pass.lanes as f32;
    let loop_px = m * unit;
    let strokes = (0..pass.lanes)
        .map(|_| {
            let count = pass.strokes.0
                + (rng.unit() * (pass.strokes.1 - pass.strokes.0 + 1) as f32) as usize;
            let count = count.min(pass.strokes.1);
            let first = rng.range(0.0, m);
            let starts: Vec<f32> = (0..count)
                .map(|i| first + (i as f32 + rng.range(-0.22, 0.22)) * m / count as f32)
                .collect();
            (0..count)
                .filter_map(|i| {
                    let next = if i + 1 < count {
                        starts[i + 1]
                    } else {
                        starts[0] + m
                    };
                    let overlap = rng.range(50.0, 110.0);
                    let s = Stroke {
                        start: starts[i].rem_euclid(m),
                        len: ((next - starts[i]) * unit + overlap).min(loop_px + overlap),
                        half: 0.5 * lane * pass.width * rng.range(0.88, 1.1),
                        body: rng.range(1.8, 3.0),
                        dry: rng.range(0.5, 0.75),
                        tone: rng.unit(),
                        seed: rng.next_u64(),
                    };
                    (rng.unit() < pass.laid).then_some(s)
                })
                .collect()
        })
        .collect();
    Frame {
        p: pass.p as f32,
        q: pass.q as f32,
        m,
        tau: (a * pass.q - b * pass.p).rem_euclid(m as i64) as f32,
        unit,
        lane,
        lanes: pass.lanes,
        bend: pass.bend,
        seed: rng.next_u64() ^ index as u64,
        strokes,
    }
}

/// Smooth noise along a track: a hash per cell of `t`, blended (0..1).
fn along(i: i64, t: f32, seed: u64) -> f32 {
    let k = t.floor();
    let f = t - k;
    let s = f * f * (3.0 - 2.0 * f);
    let (a, b) = (hash(i, k as i64, seed), hash(i, k as i64 + 1, seed));
    a + (b - a) * s
}

/// A quantity of each band of pitch 1 at `x` (in pitches; a track's paint, its end, a clump's dryness): its own band's
/// value, blended with the neighbour's over `aa` pitches either side of their border, so a border is never a step (a hard
/// step along a nearly level track stairs into a dotted line at scale 1).
fn banded(x: f32, aa: f32, val: impl Fn(i64) -> f32) -> f32 {
    let k = x.floor();
    let f = x - k;
    let i = k as i64;
    let (j, to_border) = if f < 0.5 {
        (i - 1, f)
    } else {
        (i + 1, 1.0 - f)
    };
    let w = 0.5 * (1.0 - smoothstep(0.0, aa.max(1e-3), to_border));
    (1.0 - w) * val(i) + w * val(j)
}

/// Tracks of pitch 1 at `x` (in pitches): each track a ridge whose height is its own value, varying slowly along the
/// stroke (`u` in px over `run`); `aa` is a texel in pitches. Returns the height (0..1).
fn tracks(x: f32, u: f32, run: f32, aa: f32, seed: u64) -> f32 {
    let f = x - x.floor();
    let v = banded(x, aa, |j| {
        0.6 * hash(j, 0, seed) + 0.4 * along(j, u / run, seed ^ 0x7A)
    });
    // Each track is a rounded ridge: highest at its middle, a groove where two meet.
    let ridge = 1.0 - (2.0 * f - 1.0).abs().powf(1.6);
    v * (0.35 + 0.65 * ridge)
}

impl Frame {
    /// The paint of this pass's strokes at logical `(x, y)` (tile coordinates `u`, `v`), into `dabs`.
    fn dabs(&self, x: f32, y: f32, u: f32, v: f32, texel: f32, pass: u32, dabs: &mut Vec<Dab>) {
        let l = self.unit * self.m.sqrt();
        // The bent across coordinate: whole units per tile in x and y, plus a periodic field.
        let bend = self.bend
            * (2.0 * (fbm_xy(u, v, 2, 2, 3, self.seed) - 0.5)
                + 0.5 * (value_xy(u, v, 5, 5, self.seed ^ 0x5) - 0.5));
        let s = (self.p * x + self.q * y) / l + bend / self.unit;
        let t = (self.q * x - self.p * y) / l;
        let g = (s * self.lanes as f32).floor() as i64;
        for d in -1..=1 {
            let lane = g + d;
            let k = lane.div_euclid(self.lanes);
            let j = (lane - k * self.lanes) as usize;
            // Across the lane from its middle (px), and along its loop (units, canonical).
            let e = (s * self.lanes as f32 - (lane as f32 + 0.5)) * self.lane;
            let along_loop = (t - k as f32 * self.tau).rem_euclid(self.m);
            for st in &self.strokes[j] {
                if e.abs() > st.half * 1.25 + 2.0 {
                    continue;
                }
                let loop_px = self.m * self.unit;
                let mut a = (along_loop - st.start).rem_euclid(self.m) * self.unit;
                // Just before the start: the rounded head of the brush.
                if a > loop_px - st.half {
                    a -= loop_px;
                }
                // A stroke longer than its loop meets its own start: the part past the loop lies under the head.
                for u_px in [a, a + loop_px] {
                    if u_px > st.len + 2.0 || u_px < -st.half {
                        continue;
                    }
                    if let Some(dab) = stroke(st, e, u_px, texel) {
                        dabs.push(Dab {
                            order: (pass, hash(j as i64, 0, self.seed), lane, -u_px),
                            ..dab
                        });
                    }
                }
            }
        }
    }
}

/// One stroke at `e` px across its lane and `u` px along it from its start.
fn stroke(st: &Stroke, e: f32, u: f32, texel: f32) -> Option<Dab> {
    let t = (u / st.len).clamp(0.0, 1.0);
    // The width wanders a little and narrows as the brush runs out.
    let hw = st.half
        * (1.0 + 0.12 * (along(0, u / 55.0, st.seed ^ 0x11) - 0.5))
        * (1.0 - 0.12 * smoothstep(0.55, 1.0, t));
    let ea = e.abs();
    if ea > hw + 1.5 {
        return None;
    }
    let en = (ea / hw).min(1.0);
    let round = (1.0 - en * en).sqrt();
    // The bristles: they drift together and apart slowly, so the tracks converge and part along the stroke.
    let eb = e
        + 3.0 * (along(1, u / 170.0, st.seed ^ 0x13) - 0.5)
        + 0.08 * e * (along(2, u / 130.0, st.seed ^ 0x15) - 0.5);
    let xt = eb / TRACK + 0.37;
    let aa = texel / TRACK;
    let track = tracks(xt, u, 110.0, aa, st.seed ^ 0x21);
    let own = |salt: u64| banded(xt, aa, |j| hash(j, 0, st.seed ^ salt));
    // The head: the brush lands as a rounded blob, each track touching down a little earlier or later.
    let head = smoothstep(-0.8, 0.8, u + 0.6 * hw * round + 5.0 * (own(7) - 0.5));
    if head <= 0.0 {
        return None;
    }
    // Single hairs between the tracks (sub-texel at scale 1: three taps across the texel keep them from aliasing).
    let hair = (0..3)
        .map(|k| {
            tracks(
                (eb + (k as f32 - 1.0) * 0.33 * texel) / HAIR,
                u,
                70.0,
                texel / HAIR,
                st.seed ^ 0x23,
            )
        })
        .sum::<f32>()
        / 3.0;
    let ck = eb / CLUMP;
    let clump = {
        let ci = ck.floor() as i64;
        let cf = smoothstep(0.0, 1.0, ck - ck.floor());
        let a = along(ci, u / 150.0, st.seed ^ 0x25);
        let b = along(ci + 1, u / 150.0, st.seed ^ 0x25);
        a + (b - a) * cf
    };
    let grain = 0.75 * (track - 0.33) + 0.45 * (hair - 0.33) + 0.2 * (clump - 0.5);
    // The load: the brush unloads along the stroke, so the paint thins; the thick blob where it landed.
    let load = 1.0 - 0.5 * smoothstep(0.05, 1.0, t);
    let blob = (-(u.max(0.0) / (1.3 * hw)).powi(2)).exp() * round;
    let thick = st.body * load * (0.7 + 0.3 * round) + 0.45 * st.body * blob;
    // Ridges of paint the brush pushed to its edges.
    let ridge = 0.55 * st.body * load * (-((ea - (hw - 2.2)) / 1.7).powi(2)).exp();
    let top = thick + GRAIN * (0.55 + 0.45 * load) * (1.0 - 0.25 * blob) * grain + ridge;
    // Dry brush: toward the end, and at the very edges, the tracks lose their paint in streaks; a clump goes dry together.
    let dry = (smoothstep(st.dry, 1.05, t) + 0.6 * smoothstep(0.78, 1.0, en)).min(1.0);
    let alive = if dry > 0.01 {
        let streak = 0.55 * banded(xt, aa, |j| along(j, u / 16.0, st.seed ^ 0x31))
            + 0.3 * banded(ck, texel / CLUMP, |j| along(j, u / 40.0, st.seed ^ 0x33))
            + 0.15 * hair;
        let cut = 0.92 * dry;
        smoothstep(cut - 0.05, cut + 0.05, streak)
    } else {
        1.0
    };
    // The tail: each track ends at its own length, so the stroke feathers out; the edge is ragged by track.
    let end = st.len * (1.0 - 0.12 * own(5).powf(1.5));
    let tail = smoothstep(end + 1.0, end - 1.0, u);
    let edge_at = hw * (1.0 - 0.07 * own(6));
    let edge = smoothstep(edge_at + 0.8, edge_at - 0.8, ea);
    let cover = (head * tail * edge * alive * OPACITY).clamp(0.0, 1.0);
    if cover <= 0.0 {
        return None;
    }
    let ink = 0.55 + 0.25 * (st.tone - 0.5) + 0.15 * grain + 0.08 * (thick / st.body - 1.0);
    Some(Dab {
        order: (0, 0.0, 0, 0.0),
        cover,
        top,
        ink: ink.clamp(0.0, 1.0),
    })
}

/// The brush: three passes of strokes over a thin underpaint. Tint on: the pigment (A).
pub fn brush(f: &mut Field, seed: u64, tint: bool) {
    let (n, l, g) = (f.n, f.logical, f.grid());
    let texel = 1.0 / g.scale;
    let mut rng = Rng::new(seed ^ 0xB2B5_0000);
    let frames: Vec<Frame> = PASSES
        .iter()
        .enumerate()
        .map(|(i, p)| frame(p, i, l, &mut rng))
        .collect();
    let under = seed ^ 0x0DE2;
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, hrow, irow| {
        let mut dabs = Vec::with_capacity(16);
        let (y, v) = (g.at(iy), g.uv(iy));
        for ix in 0..n {
            let (x, u) = (g.at(ix), g.uv(ix));
            // The underpaint: earlier coats, about as high as the strokes' paint, so a dry streak never opens onto bare
            // canvas.
            let mut h = UNDER + 0.5 * (value_xy(u, v, 24, 160, under) - 0.5);
            let mut ink = 0.5;
            dabs.clear();
            for (i, fr) in frames.iter().enumerate() {
                fr.dabs(x, y, u, v, texel, i as u32, &mut dabs);
            }
            dabs.sort_by(|a, b| {
                a.order
                    .0
                    .cmp(&b.order.0)
                    .then(a.order.1.total_cmp(&b.order.1))
                    .then(a.order.2.cmp(&b.order.2))
                    .then(a.order.3.total_cmp(&b.order.3))
            });
            for d in &dabs {
                h = h * (1.0 - d.cover) + d.cover * (CONFORM * h + d.top);
                ink = ink * (1.0 - d.cover) + d.cover * d.ink;
            }
            hrow[ix] = h;
            if tint {
                irow[ix] = ink;
            }
        }
    });
}
