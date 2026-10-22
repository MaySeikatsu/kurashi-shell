//! Wood (`wood`): three flat-sawn boards of unequal width, each with growth rings that run as arches (the cathedral pattern
//! of a board sawn off the pith: a ring rises to a peak and falls away on either side, nested rings sharing the peak), a
//! narrow dark late wood at the outer edge of each ring and a wide pale early wood inside it, long fine pores in the early
//! wood, a few ray flecks, and a rare knot round which the rings bend. The boards meet at fine seams. Tint on: the late
//! wood, the knots and the seams are printed (A). Every term is periodic in x and in y, so the tile wraps.

use std::f32::consts::{PI, TAU};

use crate::generate::{Field, rows2};
use crate::noise::{fbm_xy, hash, smoothstep, value_xy};
use crate::raster::bowl;

/// The boards: where each starts (a fraction of the side: its joint), its width (a fraction of the side; the three sum to
/// 1), its rings across it, the apex of its arches (a fraction of the side) and the arches' height in rings. The last
/// board runs across the tile's edge, so the grain is continuous there and the tile repeats with no joint.
const BOARDS: [(f32, f32, f32, f32, f32); 3] = [
    (0.21, 0.34, 12.0, 0.22, 3.0),
    (0.55, 0.25, 13.5, 0.61, 2.3),
    (0.80, 0.41, 11.0, 0.09, 3.4),
];
/// The knots: centre (fractions of the side) and radius, logical px.
const KNOTS: [(f32, f32, f32); 2] = [(0.37, 0.22, 14.0), (0.79, 0.74, 11.0)];
/// The arch's smallest value, at its apex: rounded like a hyperbola's tip, so the arches are pointed, not round.
const TIP: f32 = 0.25;

/// `d` wrapped to −`l`/2 … `l`/2 (the nearest image on the tile).
fn wrap(d: f32, l: f32) -> f32 {
    d - l * (d / l).round()
}

pub fn boards(f: &mut Field, seed: u64, tint: bool) {
    let (n, l, g) = (f.n, f.logical, f.grid());
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, h, ink| {
        let y = g.at(iy);
        // The board of this row: the first whose span from its joint covers the row (the spans wrap across the tile).
        let p = BOARDS
            .iter()
            .position(|b| (y - b.0 * l).rem_euclid(l) < b.1 * l)
            .unwrap_or(2);
        let (start, width, rings, apex, lift) = BOARDS[p];
        // Across the board, 0 at its joint: continuous over the tile's edge, where the last board goes on.
        let t = (y - start * l).rem_euclid(l) / (width * l);
        // The seam: the nearest joint, its groove dented and inked.
        let seam = BOARDS
            .iter()
            .map(|b| wrap(y - b.0 * l, l).abs())
            .fold(f32::MAX, f32::min);
        let dent = 0.9 * bowl(seam / 1.4);
        let seam_ink = bowl(seam / 1.0);
        for ix in 0..n {
            let x = g.at(ix);
            let (u, v) = (g.uv(ix), g.uv(iy));
            // The arches: the ring coordinate falls by `lift` rings at the apex, where the sine vanishes, and the board's
            // rings are nested around it. A slow wobble keeps them from being perfect curves.
            let s = (PI * (x - apex * l) / l).sin();
            let arch = (TIP * TIP + s * s).sqrt();
            let wobble = 0.5 * (fbm_xy(u, v, 3, 3, 3, seed ^ 0x3A) - 0.5);
            // The rings converge and part slowly along the board, so their spacing is never quite even.
            let spacing = 1.0 + 0.08 * (TAU * x / l + 1.3 + 2.1 * p as f32).cos();
            let mut rho = t * rings * spacing - lift * arch + wobble;
            // The knots: the rings bend round each one, and its core is dark, hard and a little proud.
            let (mut core, mut knot_bend) = (0.0f32, 0.0f32);
            for (kx, ky, r) in KNOTS {
                let (dx, dy) = (wrap(x - kx * l, l), wrap(y - ky * l, l));
                let d = (dx * dx + dy * dy).sqrt();
                knot_bend += 1.2 * (-(d / (2.6 * r)).powi(2)).exp();
                core = core.max(smoothstep(r, 0.6 * r, d));
            }
            rho += knot_bend;
            // Late wood: the outer part of each ring, ramped in and cut off sharply where the next ring's early wood
            // starts. Each ring has its own width and darkness, as no two summers do.
            let ring = rho.floor() as i64;
            let own = hash(ring, p as i64, seed ^ 0x2B);
            let phase = rho.rem_euclid(1.0);
            let start = 0.64 + 0.14 * own;
            let late = (0.65 + 0.35 * own)
                * smoothstep(start, 0.80, phase)
                * (1.0 - smoothstep(0.985, 1.0, phase));
            // Streaks along the grain: a pixel thin, long along x.
            let streak = value_xy(u, v, 6, 480, seed ^ 0xF1B) - 0.5;
            // Pores: long thin dashes along the grain, in the early wood only.
            let pore = smoothstep(0.70, 0.86, value_xy(u, v, 36, 320, seed ^ 0x9A)) * (1.0 - late);
            // Ray flecks: a few short pale-and-dark dashes across the grain.
            let ray = smoothstep(0.88, 0.93, value_xy(u, v, 20, 200, seed ^ 0x7A));
            h[ix] = 1.0 * late + 0.12 * streak - 0.4 * pore - dent + 0.6 * core;
            if tint {
                ink[ix] = (0.9 * late + 0.7 * core + 0.4 * ray + 0.5 * seam_ink + 0.35 * pore)
                    .clamp(0.0, 1.0);
            }
        }
    });
}
