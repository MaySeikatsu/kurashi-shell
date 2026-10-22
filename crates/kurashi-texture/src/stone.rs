//! Stone (`stone`): rock forms (a domain-warped ridged fBm, so the rises and seams wander), a granular surface (domes of
//! grains about 5 px across with creased gaps between them, as in granite), a few round pits, a few hairline cracks, and
//! mineral specks (the ink, tint on). Every noise is periodic and the warp is periodic too, so the tile wraps.

use crate::generate::{Field, rows2};
use crate::noise::{cells, fbm_xy, smoothstep, value_xy};

/// The cells of the grains (96 across: 5 px), the pits (24: 20 px), the cracks (12: 40 px) and the specks (160: 3 px).
const GRAIN_CELLS: u32 = 96;
const PIT_CELLS: u32 = 24;
const CRACK_CELLS: u32 = 12;
const SPECK_CELLS: u32 = 160;

pub fn stone(f: &mut Field, seed: u64, tint: bool) {
    let (n, g) = (f.n, f.grid());
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, h, ink| {
        for ix in 0..n {
            let (u, v) = (g.uv(ix), g.uv(iy));
            // Rock forms: the coordinates bend under a slow field, then a ridged fBm gives sharp rises and rounded hollows.
            let qx = fbm_xy(u, v, 3, 3, 3, seed ^ 0x11) - 0.5;
            let qy = fbm_xy(u, v, 3, 3, 3, seed ^ 0x22) - 0.5;
            let (wu, wv) = (u + 0.4 * qx, v + 0.4 * qy);
            let (mut ridge, mut amp, mut norm, mut per) = (0.0f32, 1.0f32, 0.0f32, 3u32);
            for o in 0..4 {
                let r = 1.0
                    - (2.0 * value_xy(wu, wv, per, per, seed.wrapping_add(o * 131)) - 1.0).abs();
                ridge += amp * r * r;
                norm += amp;
                amp *= 0.5;
                per *= 2;
            }
            let rock = ridge / norm - 0.5;
            // Grains: a dome per cell of a fine pattern, its height set per cell, the gaps between domes creased.
            let g = cells(u, v, GRAIN_CELLS, seed ^ 0x33);
            let dome = (1.0 - (g.f1 / 0.7).powi(2)).max(0.0).sqrt() * (0.55 + 0.45 * g.id);
            let crease = smoothstep(0.0, 0.3, g.f2 - g.f1);
            // Pits: a few round dishes.
            let p = cells(u, v, PIT_CELLS, seed ^ 0x44);
            let pit = if p.id < 0.3 {
                (1.0 - (p.f1 / 0.45).powi(2)).max(0.0)
            } else {
                0.0
            };
            // Cracks: a few hairlines along the edges of a coarse pattern.
            let e = cells(u, v, CRACK_CELLS, seed ^ 0x55);
            let crack = if e.id < 0.18 {
                1.0 - smoothstep(0.0, 0.035, e.f2 - e.f1)
            } else {
                0.0
            };
            // Specks: grains of another mineral, a little proud of the rock.
            let s = cells(u, v, SPECK_CELLS, seed ^ 0x66);
            let speck = if s.id < 0.3 {
                1.0 - smoothstep(0.2, 0.35, s.f1)
            } else {
                0.0
            };
            h[ix] = 0.8 * rock + 1.1 * dome * (0.4 + 0.6 * crease) - 0.9 * pit - 0.5 * crack
                + 0.25 * speck;
            if tint {
                ink[ix] = speck;
            }
        }
    });
}
