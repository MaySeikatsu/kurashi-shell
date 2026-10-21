//! Wood (`wood`): three planks, each a set of growth rings about 12 px apart. The grain wanders under a warp (a slow noise and
//! an integer harmonic along x, so the rings wrap across the tile); the late wood is the thin dark end of each ring; fine
//! streaks run along the grain and long pores sit in the early wood; a seam dents the sheet where one plank meets the next.
//! Tint on: the late wood is printed as ink (A).

use crate::generate::Field;
use crate::noise::{fbm_xy, smoothstep, value_xy};
use crate::raster::bowl;

const PLANKS: usize = 3;

pub fn planks(f: &mut Field, seed: u64, tint: bool) {
    let (n, l) = (f.n, f.logical);
    let band = l / PLANKS as f32;
    let tau = std::f32::consts::TAU;
    for iy in 0..n {
        let y = f.at(iy);
        let b = ((y / band).floor() as usize).min(PLANKS - 1);
        let t = (y - b as f32 * band) / band;
        let rings = 14.0 + 2.0 * b as f32;
        let seam = ((y / band).round() * band - y).abs();
        let dent = 0.9 * bowl(seam / 1.4);
        for ix in 0..n {
            let (u, v) = (f.uv(ix), f.uv(iy));
            // The grain wanders: a slow noise and an integer harmonic along x, both periodic in the tile (the same at every
            // plank, so the rings run on across the seams). The ring phase is offset by half a ring: each plank starts and
            // ends in early wood, so the late-wood edge never falls on a seam.
            let warp =
                0.6 * (fbm_xy(u, v, 3, 3, 4, seed ^ 0x3A) - 0.5) + 0.15 * (tau * u + 1.3).sin();
            let ring = (t * rings + 0.5 + 1.8 * warp).rem_euclid(1.0);
            let late = smoothstep(0.66, 0.84, ring) * (1.0 - smoothstep(0.95, 1.0, ring));
            // Streaks along the grain: a pixel thin across, long along x.
            let streak = value_xy(u, v, 4, 480, seed ^ 0xF1B) - 0.5;
            // Pores: long and thin along the grain, in the early wood only.
            let pore = smoothstep(0.72, 0.86, value_xy(u, v, 5, 240, seed ^ 0x9A)) * (1.0 - late);
            let k = iy * n + ix;
            f.h[k] = 1.0 * late + 0.12 * streak - 0.3 * pore - dent;
            if tint {
                f.ink[k] = 0.85 * late;
            }
        }
    }
}
