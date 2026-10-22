//! Cloth: a plain-weave fabric (warp and weft yarns that pass over and under in a chequer; each yarn a round tube with its
//! own width, spacing and twist, the odd slub, and a fine fibre fuzz lying along it) and a stockinette knit (a V per
//! stitch, its two legs plump loops of yarn, a soft halo of fibre). Both are seamless at the tile's pitch: the weave has
//! 480 / 4 = 120 yarns a way, the knit 480 / 16 = 30 columns and 480 / 12 = 40 rows.

use std::f32::consts::{PI, TAU};

use crate::generate::{Field, box_blur, rows, rows2};
use crate::noise::{Rng, hash, hash2, smoothstep, value_xy};
use crate::raster::{dist_seg, tube_add};

/// The yarn pitch of the weave, logical px: fine enough that the cloth reads as cloth (linen, canvas) at 1:1 rather than
/// as a grid of squares.
const PITCH: f32 = 4.0;
/// The length of one tone cell along a yarn, logical px (a divisor of every tile side).
const RUN: f32 = 4.0;
/// The period of the twist striations along a yarn, logical px (a divisor of every tile side).
const TWIST: f32 = 2.0;
/// The half-width of a yarn, in pitches: wider than its pitch, so neighbours overlap and no valley runs straight.
const HALF: f32 = 0.62;

/// One yarn of a row or column: its width and height factors, its tone (0..1), its spacing offset (pitches) and the
/// phase of its twist (cycles).
struct Yarn {
    width: f32,
    height: f32,
    tone: f32,
    offset: f32,
    phase: f32,
}

/// Yarn `i` (periodic in `nt` yarns): its own width, height, tone, spacing and twist, from the seed.
fn yarn(i: i64, nt: i64, seed: u64) -> Yarn {
    let w = i.rem_euclid(nt);
    let (a, b) = hash2(w, 0, seed);
    Yarn {
        width: 0.9 + 0.2 * a,
        height: 0.92 + 0.16 * b,
        tone: hash(w, 1, seed ^ 0x7017),
        // No two yarns sit on the same grid: each is up to a tenth of a pitch off its place.
        offset: 0.2 * (hash(w, 2, seed ^ 0x5BA) - 0.5),
        phase: hash(w, 3, seed ^ 0x7A1),
    }
}

/// The centre of yarn `k` across the cloth, logical px.
fn centre(k: i64, y: &Yarn) -> f32 {
    (k as f32 + 0.5 + y.offset) * PITCH
}

/// Value noise along a yarn: `t` in cells of `RUN` px, the lattice `period` cells long, per yarn `i`.
fn along(i: i64, t: f32, period: i64, seed: u64) -> f32 {
    let t0 = t.floor();
    let k = t - t0;
    let s = k * k * (3.0 - 2.0 * k);
    let j = t0 as i64;
    let a = hash(i, j.rem_euclid(period), seed);
    let b = hash(i, (j + 1).rem_euclid(period), seed);
    a + (b - a) * s
}

/// The profile of a yarn across its width: a round tube (a half-circle), 1 at its centre and 0 at its half-width, scaled
/// by its height.
fn across(x: f32, centre: f32, half: f32, height: f32) -> f32 {
    let u = ((x - centre) / half).abs();
    if u >= 1.0 {
        return 0.0;
    }
    (1.0 - u * u).sqrt() * height
}

/// The sign of the over/under pattern for yarn `k`: `(−1)^k`.
fn sign(k: i64) -> f32 {
    if k.rem_euclid(2) == 0 { 1.0 } else { -1.0 }
}

/// The over/under lift of a yarn at `p` (logical px along it): +1 where it lies over the crossing, −1 under it. The gain
/// is modest, so a yarn turns from over to under across the crossing rather than in a square step: the rounded pillows
/// of cloth, with the yarns still running on as long lines.
fn lift(k: i64, p: f32) -> f32 {
    (sign(k) * (PI * (p / PITCH - 0.5)).cos() * 1.4).clamp(-1.0, 1.0)
}

/// The warp yarn in column `k` at `(x, y)`: its height and its tone. Its wander, swell and tone change slowly along it, and
/// its twist striates the surface at a slant, as a spun yarn does.
fn warp_at(k: i64, nt: i64, seed: u64, per: i64, x: f32, y: f32) -> (f32, f32) {
    let w = yarn(k, nt, seed ^ 0xF0);
    let xc = centre(k, &w);
    let r = k.rem_euclid(nt);
    let wander = 1.4 * (along(r, y / 16.0, per / 4, seed ^ 0x3A) - 0.5);
    let swell = 0.85 + 0.3 * along(r, y / 16.0, per / 4, seed ^ 0x3B);
    let stripe = 0.1 * (along(r, y / RUN, per, seed ^ 0x2A) - 0.5);
    let twist = 1.0 + 0.1 * (TAU * (y / TWIST + 0.8 * (x - xc) / PITCH + w.phase)).sin();
    let h = across(x - wander, xc, HALF * PITCH * w.width, w.height)
        * swell
        * (0.58 + 0.42 * lift(k, y))
        * twist
        + stripe;
    (h, w.tone)
}

/// The weft yarn in row `k` at `(x, y)`: the mirror of [`warp_at`], over where the warp is under.
fn weft_at(k: i64, nt: i64, seed: u64, per: i64, x: f32, y: f32) -> (f32, f32) {
    let w = yarn(k, nt, seed ^ 0xF1);
    let yc = centre(k, &w);
    let r = nt + k.rem_euclid(nt);
    let wander = 1.4 * (along(r, x / 16.0, per / 4, seed ^ 0x3C) - 0.5);
    let swell = 0.85 + 0.3 * along(r, x / 16.0, per / 4, seed ^ 0x3D);
    let stripe = 0.1 * (along(r, x / RUN, per, seed ^ 0x2B) - 0.5);
    let twist = 1.0 + 0.1 * (TAU * (x / TWIST + 0.8 * (y - yc) / PITCH + w.phase)).sin();
    let h = across(y - wander, yc, HALF * PITCH * w.width, w.height)
        * swell
        * (0.58 - 0.42 * lift(k, x))
        * twist
        + stripe;
    (h, w.tone)
}

/// A lump on one yarn (`warp`: a column at `c`, else a row at `c`): Gaussian along it, round across it.
fn slub(f: &mut Field, warp: bool, c: f32, t0: f32, len: f32, amp: f32) {
    let (n, scale) = (f.n, f.scale);
    let half = HALF * PITCH;
    let ext = 2.5 * len;
    let (xr, yr) = if warp {
        ((c - half, c + half), (t0 - ext, t0 + ext))
    } else {
        ((t0 - ext, t0 + ext), (c - half, c + half))
    };
    crate::raster::texels(n, scale, xr.0, yr.0, xr.1, yr.1, |idx, x, y| {
        let (across_d, along_d) = if warp {
            (x - c, y - t0)
        } else {
            (y - c, x - t0)
        };
        let t = across_d / half;
        if t.abs() < 1.0 {
            let g = (-(along_d / len).powi(2)).exp();
            f.h[idx] += amp * g * (1.0 - t * t).sqrt();
        }
    });
}

/// Plain-weave cloth. Tint on: each yarn's tone is printed faintly in the ink (A), so the weave shows in colour.
pub fn fabric(f: &mut Field, seed: u64, tint: bool) {
    let (n, l) = (f.n, f.logical);
    let nt = (l / PITCH).round() as i64;
    let per = (l / RUN).round() as i64;
    let g = f.grid();
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, hrow, ink| {
        let y = g.at(iy);
        let j = (y / PITCH).floor() as i64;
        for ix in 0..n {
            let x = g.at(ix);
            let i = (x / PITCH).floor() as i64;
            // The top of the yarns near this point, warp or weft (a yarn overlaps its neighbours).
            let (mut top, mut tone) = (f32::MIN, 0.0f32);
            for k in i - 1..=i + 1 {
                let (h, t) = warp_at(k, nt, seed, per, x, y);
                if h > top {
                    (top, tone) = (h, t);
                }
            }
            for k in j - 1..=j + 1 {
                let (h, t) = weft_at(k, nt, seed, per, x, y);
                if h > top {
                    (top, tone) = (h, t);
                }
            }
            hrow[ix] = top.max(0.0);
            if tint {
                // Each yarn's tone varies little: the weave shows, the yarns do not look like blocks.
                ink[ix] = ((0.52 + 0.06 * tone) * smoothstep(0.0, 0.12, top)).clamp(0.0, 1.0);
            }
        }
    });
    let mut rng = Rng::new(seed ^ 0x51ab);
    // Slubs: a thicker stretch of a yarn, a few pitches long.
    for _ in 0..(l * l / 2600.0) as usize {
        let warp = rng.unit() < 0.5;
        let k = (rng.unit() * nt as f32) as i64;
        let yarn_seed = if warp { seed ^ 0xF0 } else { seed ^ 0xF1 };
        let c = centre(k, &yarn(k, nt, yarn_seed));
        let (t0, len, amp) = (rng.range(0.0, l), rng.range(6.0, 18.0), rng.range(0.2, 0.4));
        slub(f, warp, c, t0, len, amp);
    }
    // Fibre fuzz: short strands lying along a yarn and standing off it, about one every 20 px of yarn.
    for _ in 0..(l * l / 40.0) as usize {
        let warp = rng.unit() < 0.5;
        let k = (rng.unit() * nt as f32) as i64;
        let yarn_seed = if warp { seed ^ 0xF0 } else { seed ^ 0xF1 };
        let c = centre(k, &yarn(k, nt, yarn_seed));
        let across_d = rng.range(-0.5, 0.5) * HALF * PITCH * 2.0;
        let along_d = rng.range(0.0, l);
        let len = rng.range(1.5, 4.0);
        let tilt = rng.range(-0.3, 0.3);
        let (dx, dy) = (tilt.cos() * len, tilt.sin() * len);
        let pts = if warp {
            let p = [c + across_d, along_d];
            [p, [p[0] + dy, p[1] + dx]]
        } else {
            let p = [along_d, c + across_d];
            [p, [p[0] + dx, p[1] + dy]]
        };
        tube_add(f, &pts, 0.25, rng.range(0.15, 0.3));
    }
}

/// Stockinette knit: a V per stitch (two legs from the stitch's top corners to its bottom middle, each leg a plump round
/// loop of yarn, the loop at the foot a little higher), and a soft halo of fibre round the yarn. No ink: the wool is its
/// own colour under the palette.
pub fn knit(f: &mut Field, seed: u64) {
    let (n, l) = (f.n, f.logical);
    // A stitch is 16 px wide and 12 px tall: its top corners are 8 px apart, so the V's inner valley and the valleys
    // between the columns show between the plump legs (16 and 12 divide every tile side).
    const W: f32 = 16.0;
    const H: f32 = 12.0;
    let (cols, nrows) = ((l / W).round() as i64, (l / H).round() as i64);
    // A stitch: its top-left and top-right corners, its bottom middle, the legs' radius and height. Periodic in the stitch
    // index, so the stitches at the edge have their neighbours across the seam; each stitch is a little its own.
    let stitch = |c: i64, r: i64| {
        let (wc, wr) = (c.rem_euclid(cols), r.rem_euclid(nrows));
        let (jx, jy) = hash2(wc, wr, seed);
        // Plump loops: a leg is about 5.5 px across and stands 1.8 px proud of the valleys: slopes steep enough to show.
        let rad = 2.5 + 0.3 * hash(wc, wr, seed ^ 0xA1);
        let height = 1.8 * (0.92 + 0.16 * hash(wc, wr, seed ^ 0xA2));
        let (x0, y0) = (c as f32 * W, r as f32 * H);
        let bottom = [x0 + W * 0.5 + (jx - 0.5) * 1.5, y0 + H + (jy - 0.5) * 1.0];
        ([x0 + 4.0, y0], [x0 + W - 4.0, y0], bottom, rad, height)
    };
    let g = f.grid();
    rows(n, f.threads, &mut f.h, |iy, hrow| {
        let y = g.at(iy);
        let r0 = (y / H).floor() as i64;
        for (ix, out) in hrow.iter_mut().enumerate() {
            let x = g.at(ix);
            let c0 = (x / W).floor() as i64;
            let mut best = 0.0f32;
            for r in r0 - 1..=r0 + 1 {
                for c in c0 - 1..=c0 + 1 {
                    let (tl, tr, bottom, rad, height) = stitch(c, r);
                    for top in [tl, tr] {
                        let t = dist_seg(top, bottom, x, y) / rad;
                        if t < 1.0 {
                            best = best.max(height * (1.0 - t * t).sqrt());
                        }
                    }
                    // The loop at the foot of the V: a round head of yarn, a little higher than the legs.
                    let t = (x - bottom[0]).hypot(y - bottom[1]) / (rad * 1.05);
                    if t < 1.0 {
                        best = best.max(1.1 * height * (1.0 - t * t).sqrt());
                    }
                }
            }
            *out = best;
        }
    });
    // The fibre halo: the yarn's blurred shoulder, and a fine fuzz over it.
    let halo = box_blur(&f.h, n, 3, f.threads);
    let fuzz = seed ^ 0xF022;
    rows(n, f.threads, &mut f.h, |iy, hrow| {
        for (ix, out) in hrow.iter_mut().enumerate() {
            let (u, v) = (g.uv(ix), g.uv(iy));
            *out +=
                0.25 * halo[iy * n + ix] + 0.08 * (value_xy(u, v, n as u32, n as u32, fuzz) - 0.5);
        }
    });
    // The nap: fine strands at every angle, low and sparse, so the yarn has a soft fuzz rather than specks.
    let mut rng = Rng::new(seed ^ 0xF1B3);
    for _ in 0..(l * l / 120.0) as usize {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let a = rng.range(0.0, TAU);
        let len = rng.range(2.0, 4.0);
        let pts = [[x, y], [x + a.cos() * len, y + a.sin() * len]];
        tube_add(f, &pts, 0.35, rng.range(0.08, 0.15));
    }
}
