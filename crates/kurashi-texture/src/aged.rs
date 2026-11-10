//! Aged stock (`old_paper`, `canvas`; I470, session 27 — the user's pictures: a sheet browned and unevenly discoloured, as
//! a treasure map but milder, and a painter's canvas). The age is the ink: broad browned areas whose outline wanders (a
//! warped fBm), a darker tide line where a stain dried at its edge, a finer uneven tone over all of it, and foxing, sparse
//! small spots. The ink's colour is the material's (`InkRole::Stain`, a sepia), so the stains are brown in every palette;
//! the daemon caps their alpha so text stays legible on the darkest stain. Tint off: the relief alone.
//!
//! Old paper is the plain paper stock under the stains. Canvas is a coarse plain weave, 6 px a thread: each thread a dome
//! across its width that rises where it passes over the crossing thread and dips where it passes under, threads of
//! slightly different thickness, and a slow unevenness of the stretched cloth.

use crate::generate::{Field, rows};
use crate::noise::{cells, fbm_xy, hash, smoothstep, value_xy};
use crate::paper;

/// A canvas thread's pitch, logical px (every tile is a multiple of it, and holds an even count of threads).
const PITCH: f32 = 6.0;

/// The stains, into the ink (the maximum with what is there: a sheet's own pigment stays under them).
fn stains(f: &mut Field, seed: u64, strength: f32) {
    let (n, g) = (f.n, f.grid());
    rows(n, f.threads, &mut f.ink, |iy, ink| {
        let v = g.uv(iy);
        for (ix, out) in ink.iter_mut().enumerate() {
            let u = g.uv(ix);
            // The browned areas: a slow field whose coordinates bend, so their outline wanders as a dried liquid's does.
            let wx = fbm_xy(u, v, 2, 2, 3, seed ^ 0xA1) - 0.5;
            let wy = fbm_xy(u, v, 2, 2, 3, seed ^ 0xA2) - 0.5;
            let broad = fbm_xy(u + 0.16 * wx, v + 0.16 * wy, 2, 2, 4, seed ^ 0xA3);
            let blot = smoothstep(0.40, 0.70, broad);
            // The tide line: darker just inside the stain's edge.
            let rim = (1.0 - smoothstep(0.0, 0.03, (broad - 0.56).abs())) * blot.max(0.25);
            // An uneven tone a few dozen px across, everywhere.
            let mottle = (fbm_xy(u, v, 7, 7, 3, seed ^ 0xA4) - 0.32).max(0.0);
            // Foxing: sparse small spots with soft edges.
            let c = cells(u, v, 36, seed ^ 0xA5);
            let fox = if c.id < 0.1 {
                (1.0 - smoothstep(0.05, 0.28, c.f1)) * (0.5 + 0.5 * c.id / 0.1)
            } else {
                0.0
            };
            let s = 0.62 * blot + 0.26 * rim + 0.36 * mottle + 0.45 * fox;
            *out = out.max((strength * s).clamp(0.0, 1.0));
        }
    });
}

/// Old paper: the plain stock, browned.
pub fn old_paper(f: &mut Field, seed: u64, tint: bool) {
    // (the fibres stay unprinted: in the stain's ink at its alpha they read as brown scribbles over the whole sheet)
    paper::plain(f, seed, false);
    if tint {
        stains(f, seed ^ 0x0A6E, 1.0);
    }
}

/// Canvas: a coarse plain weave, a little dirty.
pub fn canvas(f: &mut Field, seed: u64, tint: bool) {
    use std::f32::consts::PI;
    let (n, g) = (f.n, f.grid());
    let threads = (f.logical / PITCH).round() as i64;
    rows(n, f.threads, &mut f.h, |iy, h| {
        let b = g.at(iy) / PITCH;
        let j = b.floor() as i64;
        let fy = b - j as f32 - 0.5;
        let weft_w = 0.82 + 0.36 * hash(0, j.rem_euclid(threads), seed ^ 0xC2);
        for (ix, out) in h.iter_mut().enumerate() {
            let a = g.at(ix) / PITCH;
            let i = a.floor() as i64;
            let fx = a - i as f32 - 0.5;
            let warp_w = 0.82 + 0.36 * hash(i.rem_euclid(threads), 0, seed ^ 0xC1);
            // +1 where the warp passes over here, −1 where the weft does.
            let over = if (i + j).rem_euclid(2) == 0 {
                1.0
            } else {
                -1.0
            };
            let dome_x = (PI * fx).cos().max(0.0).powf(0.7);
            let dome_y = (PI * fy).cos().max(0.0).powf(0.7);
            let warp = warp_w * dome_x * (0.55 + 0.45 * over * (PI * fy).cos());
            let weft = weft_w * dome_y * (0.55 - 0.45 * over * (PI * fx).cos());
            let lay = 0.3 * (value_xy(g.uv(ix), g.uv(iy), 5, 5, seed ^ 0xC3) - 0.5);
            *out = 1.3 * warp.max(weft) + lay;
        }
    });
    if tint {
        stains(f, seed ^ 0x0C4A, 0.75);
    }
}
