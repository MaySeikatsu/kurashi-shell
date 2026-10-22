//! Print (`halftone`): Ben-Day dots on a 45° lattice, printed on rough stock (a comic page). The lattice is spanned by
//! (p, p) and (p, −p), so its period is 2p and the tile holds whole periods. Each dot's radius follows a slow tone field.
//! Tint on: the dots are ink (A) and the relief is only the stock's; tint off: the dots are raised a little.

use crate::generate::{Field, rows2};
use crate::noise::{fbm_xy, smoothstep};
use crate::paper;
use crate::raster::band;

/// The lattice step, logical px: dot centres at `STEP × (i + j)`, `STEP × (i − j)`. Dots never touch below `STEP × √2 / 2`.
const STEP: f32 = 8.0;

/// The dot radius (0..1 tone) at logical `(x, y)`: a slow field, so the print shades from light to dark across the sheet.
fn tone(x: f32, y: f32, l: f32, seed: u64) -> f32 {
    smoothstep(0.2, 0.8, fbm_xy(x / l, y / l, 2, 2, 3, seed ^ 0x7011))
}

/// Halftone print on rough stock: the paper sheet (lighter fibres), the dots on their lattice.
pub fn halftone(f: &mut Field, seed: u64, tint: bool) {
    let (n, l, texel) = (f.n, f.logical, 1.0 / f.scale);
    paper::sheet(f, seed ^ 0x57, false);
    for h in f.h.iter_mut() {
        *h *= 0.6;
    }
    let r_max = 0.5 * STEP * std::f32::consts::SQRT_2 * 0.84;
    let g = f.grid();
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, h, ink| {
        for ix in 0..n {
            let (x, y) = (g.at(ix), g.at(iy));
            // The lattice in its own coordinates is the integer grid: round to the nearest dot.
            let (ui, vi) = (
                ((x + y) / (2.0 * STEP)).round(),
                ((x - y) / (2.0 * STEP)).round(),
            );
            let (cx, cy) = (STEP * (ui + vi), STEP * (ui - vi));
            let d = (x - cx).hypot(y - cy);
            let r = r_max * tone(cx, cy, l, seed).sqrt();
            if r < 0.05 {
                continue;
            }
            if tint {
                ink[ix] = band(d, r, texel);
            } else if d < r {
                h[ix] += 1.0 * (1.0 - (d / r) * (d / r)).sqrt();
            }
        }
    });
}
