//! Leather (`leather`): a pebbled grain (domes about 12 px across, each its own size, the gaps between them creased), small
//! pores, and a slow wrinkle where the hide folds. No ink: the material is its medium gloss (K59).

use crate::generate::{Field, rows};
use crate::noise::{cells, fbm_xy, smoothstep};

pub fn leather(f: &mut Field, seed: u64) {
    let (n, g) = (f.n, f.grid());
    rows(n, f.threads, &mut f.h, |iy, h| {
        for (ix, out) in h.iter_mut().enumerate() {
            let (u, v) = (g.uv(ix), g.uv(iy));
            // Pebbles: one dome per cell of 40 across the tile, its radius set per cell, the gaps creased.
            let c = cells(u, v, 40, seed);
            let size = 0.7 + 0.3 * c.id;
            let dome = (1.0 - (c.f1 / (0.62 * size)).powi(2)).max(0.0).sqrt();
            let crease = smoothstep(0.0, 0.3, c.f2 - c.f1);
            // Pores: small pits in some cells of a finer pattern.
            let p = cells(u, v, 160, seed ^ 0x9E);
            let pore = if p.id < 0.35 {
                1.0 - smoothstep(0.12, 0.2, p.f1)
            } else {
                0.0
            };
            // A slow wrinkle: a soft ridge where the hide folds.
            let fold = fbm_xy(u, v, 3, 3, 3, seed ^ 0x51);
            let ridge = 1.0 - (2.0 * fold - 1.0).abs();
            *out = 0.8 * dome * (0.35 + 0.65 * crease) - 0.3 * pore + 0.3 * ridge * ridge;
        }
    });
}
