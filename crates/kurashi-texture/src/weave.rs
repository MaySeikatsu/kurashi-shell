//! Cloth: a plain-weave fabric (warp and weft tubes that pass over and under in a chequer, each with its own width and
//! height, twist striations along the thread, the odd slub) and a stockinette knit (a V per stitch, its two arms round
//! yarn, a soft halo of fibre). Both are seamless at the pitch of the tile (480 / 8 = 60 threads, 60 courses).

use crate::generate::{Field, box_blur};
use crate::noise::{Rng, hash, hash2, smoothstep, value_xy};
use crate::raster::{dist_seg, texels, tube_add};

/// The thread pitch of the weave, logical px: coarse enough that the over and under read at 1:1.
const PITCH: f32 = 8.0;
/// Length of one twist striation along a thread, logical px.
const TWIST: f32 = 4.0;
/// The half-width of a thread, in pitches: wider than its pitch, so neighbours overlap and no valley runs a grid.
const HALF: f32 = 0.62;

/// Value noise along a thread: `t` in cells of `TWIST` px, the lattice `period` cells long, per thread `i`.
fn along(i: i64, t: f32, period: i64, seed: u64) -> f32 {
    let t0 = t.floor();
    let k = t - t0;
    let s = k * k * (3.0 - 2.0 * k);
    let j = t0 as i64;
    let a = hash(i, j.rem_euclid(period), seed);
    let b = hash(i, (j + 1).rem_euclid(period), seed);
    a + (b - a) * s
}

/// A thread's width factor, height factor and tone (0..1), from its index (periodic in `nt` threads).
fn thread(i: i64, nt: i64, seed: u64) -> [f32; 3] {
    let w = i.rem_euclid(nt);
    let (a, b) = hash2(w, 0, seed);
    [0.9 + 0.2 * a, 0.92 + 0.16 * b, hash(w, 1, seed ^ 0x7017)]
}

/// The profile of a thread across its width: a round tube (a super-ellipse with exponent 2, a half-circle), 1 at its centre
/// and 0 at its half-width, scaled by its height.
fn across(x: f32, centre: f32, half: f32, height: f32) -> f32 {
    let u = ((x - centre) / half).abs();
    if u >= 1.0 {
        return 0.0;
    }
    (1.0 - u * u).sqrt() * height
}

/// The sign of the over/under pattern for thread `k`: `(−1)^k`.
fn sign(k: i64) -> f32 {
    if k.rem_euclid(2) == 0 { 1.0 } else { -1.0 }
}

/// The warp thread in column `k` at `(x, y)`: its height (over at a crossing when `k + j` is even: full height; under: it
/// sinks) and its tone. Its lift swings along its length, so it passes smoothly from over to under between crossings.
fn warp_at(k: i64, nt: i64, seed: u64, per: i64, x: f32, y: f32) -> (f32, f32) {
    let w = thread(k, nt, seed ^ 0xF0);
    let xc = (k as f32 + 0.5) * PITCH;
    // The lift saturates: long over and under runs with a short crossing between them, as in cloth.
    let lift = (sign(k) * (std::f32::consts::PI * (y / PITCH - 0.5)).cos() * 2.5).clamp(-1.0, 1.0);
    let wander = 1.4 * (along(k.rem_euclid(nt), y / 16.0, per / 4, seed ^ 0x3A) - 0.5);
    let swell = 0.85 + 0.3 * along(k.rem_euclid(nt), y / 16.0, per / 4, seed ^ 0x3B);
    let stripe = 0.1 * (along(k.rem_euclid(nt), y / TWIST, per, seed ^ 0x2A) - 0.5);
    let h =
        across(x - wander, xc, HALF * PITCH * w[0], w[1]) * swell * (0.58 + 0.42 * lift) + stripe;
    (h, w[2])
}

/// The weft thread in row `k` at `(x, y)`: the mirror of [`warp_at`], over where the warp is under.
fn weft_at(k: i64, nt: i64, seed: u64, per: i64, x: f32, y: f32) -> (f32, f32) {
    let w = thread(k, nt, seed ^ 0xF1);
    let yc = (k as f32 + 0.5) * PITCH;
    let lift = (sign(k) * (std::f32::consts::PI * (x / PITCH - 0.5)).cos() * 2.5).clamp(-1.0, 1.0);
    let wander = 1.4 * (along(nt + k.rem_euclid(nt), x / 16.0, per / 4, seed ^ 0x3C) - 0.5);
    let swell = 0.85 + 0.3 * along(nt + k.rem_euclid(nt), x / 16.0, per / 4, seed ^ 0x3D);
    let stripe = 0.1 * (along(nt + k.rem_euclid(nt), x / TWIST, per, seed ^ 0x2B) - 0.5);
    let h =
        across(y - wander, yc, HALF * PITCH * w[0], w[1]) * swell * (0.58 - 0.42 * lift) + stripe;
    (h, w[2])
}

/// A lump on one thread (`warp`: a column at `c`, else a row at `c`): Gaussian along it, round across it.
fn slub(f: &mut Field, warp: bool, c: f32, t0: f32, len: f32, amp: f32) {
    let (n, scale) = (f.n, f.scale);
    let half = HALF * PITCH;
    let ext = 2.5 * len;
    let (xr, yr) = if warp {
        ((c - half, c + half), (t0 - ext, t0 + ext))
    } else {
        ((t0 - ext, t0 + ext), (c - half, c + half))
    };
    texels(n, scale, xr.0, yr.0, xr.1, yr.1, |idx, x, y| {
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

/// Plain-weave cloth. Tint on: each thread's tone is printed faintly in the ink (A), so the weave shows in colour.
pub fn fabric(f: &mut Field, seed: u64, tint: bool) {
    let (n, l) = (f.n, f.logical);
    let nt = (l / PITCH).round() as i64;
    let per = (l / TWIST).round() as i64;
    for iy in 0..n {
        let y = f.at(iy);
        let j = (y / PITCH).floor() as i64;
        for ix in 0..n {
            let x = f.at(ix);
            let i = (x / PITCH).floor() as i64;
            // The top of the threads near this point, warp or weft (a thread overlaps its neighbours).
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
            let k = iy * n + ix;
            f.h[k] = top.max(0.0);
            if tint {
                // Each thread's tone varies little: the weave shows, the threads do not look like blocks.
                f.ink[k] = ((0.52 + 0.06 * tone) * smoothstep(0.0, 0.12, top)).clamp(0.0, 1.0);
            }
        }
    }
    let mut rng = Rng::new(seed ^ 0x51ab);
    for _ in 0..(l as usize / 16) {
        let warp = rng.unit() < 0.5;
        let i = (rng.unit() * nt as f32) as i64;
        let c = (i as f32 + 0.5) * PITCH;
        let (t0, len, amp) = (
            rng.range(0.0, l),
            rng.range(8.0, 26.0),
            rng.range(0.25, 0.45),
        );
        slub(f, warp, c, t0, len, amp);
    }
    // Fibre hairs: short strands standing off the threads, a few per thread crossing.
    for _ in 0..(l * l / 60.0) as usize {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let a = rng.range(0.0, std::f32::consts::TAU);
        let len = rng.range(2.0, 4.5);
        let pts = [[x, y], [x + a.cos() * len, y + a.sin() * len]];
        tube_add(f, &pts, 0.3, rng.range(0.2, 0.45));
    }
}

/// Stockinette knit: a V per stitch (two arms from the stitch's top corners to its bottom middle, each arm a round
/// yarn), and a soft halo of fibre round the yarn. No ink: the wool is its own colour under the palette.
pub fn knit(f: &mut Field, seed: u64) {
    let (n, l) = (f.n, f.logical);
    const W: f32 = 8.0;
    const H: f32 = 8.0;
    let (cols, rows) = ((l / W).round() as i64, (l / H).round() as i64);
    // A stitch: its top-left corner, its top-right corner, its bottom middle, arm radius and arm height. Periodic in
    // the stitch index, so the arms of a stitch at the edge are the ones across the seam.
    let stitch = |c: i64, r: i64| {
        let (wc, wr) = (c.rem_euclid(cols), r.rem_euclid(rows));
        let (jx, jy) = hash2(wc, wr, seed);
        let rad = 1.7 + 0.4 * hash(wc, wr, seed ^ 0xA1);
        let height = 1.0 + 0.3 * hash(wc, wr, seed ^ 0xA2);
        let (x0, y0) = (c as f32 * W, r as f32 * H);
        let bottom = [x0 + W * 0.5 + (jx - 0.5) * 1.2, y0 + H + (jy - 0.5) * 1.0];
        ([x0, y0], [x0 + W, y0], bottom, rad, height)
    };
    for iy in 0..n {
        let y = f.at(iy);
        let r0 = (y / H).floor() as i64;
        for ix in 0..n {
            let x = f.at(ix);
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
                    // The loop at the foot of the V: a round head of yarn, a little higher than the arms.
                    let t = (x - bottom[0]).hypot(y - bottom[1]) / (rad + 0.4);
                    if t < 1.0 {
                        best = best.max(1.1 * height * (1.0 - t * t).sqrt());
                    }
                }
            }
            f.h[iy * n + ix] = best;
        }
    }
    // The fibre halo: the yarn's blurred shoulder, and a fine fuzz over it.
    let halo = box_blur(&f.h, n, 3);
    let fuzz = seed ^ 0xF022;
    for iy in 0..n {
        for ix in 0..n {
            let k = iy * n + ix;
            let (u, v) = (f.uv(ix), f.uv(iy));
            f.h[k] += 0.35 * halo[k] + 0.08 * (value_xy(u, v, n as u32, n as u32, fuzz) - 0.5);
        }
    }
}
