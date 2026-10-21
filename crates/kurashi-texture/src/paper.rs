//! Paper (`paper`, `paper_dots`, `paper_lines`, `paper_grid`): a felted sheet with washi's character. Long thin fibres, nearly
//! straight with a little bend, stand a little proud and catch the light as fine lines; a soft felt mottles the surface a
//! few px across; felt pores dent it; a slow formation cloud thickens the fibres in places. Nothing repeats at a visible
//! pitch and nothing is uniform noise: the grain comes from the fibres. The rulings sit at a 24 px pitch: printed as ink
//! (tint on: the A channel only, no relief) or blind-embossed (tint off: soft dents, no colour). The halftone stock
//! reuses the sheet.

use crate::generate::Field;
use crate::noise::{Rng, fbm_xy, value_xy};
use crate::raster::{arc, band, bowl, bowl_at, tube};

/// The rulings' pitch, logical px (every tile is a multiple of it: 48 × k).
pub const PITCH: f32 = 24.0;

/// Which rulings a ruled paper carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ruling {
    Lines,
    Dots,
    Grid,
}

/// The sheet's relief: the felt, the fibres and the pores. `pigment` also prints the fibres faintly (ink).
pub fn sheet(f: &mut Field, seed: u64, pigment: bool) {
    let (n, l) = (f.n, f.logical);
    let formation = |x: f32, y: f32| fbm_xy(x / l, y / l, 3, 3, 3, seed ^ 0xF0F0);
    // The felt: soft bumps a few px across, over the whole sheet, thicker where the formation is.
    for iy in 0..n {
        for ix in 0..n {
            let (u, v) = (f.uv(ix), f.uv(iy));
            let felt = 0.22 * (value_xy(u, v, 96, 96, seed ^ 0xFE11) - 0.5)
                + 0.1 * (value_xy(u, v, 224, 224, seed ^ 0xFE12) - 0.5);
            f.h[iy * n + ix] = felt * (0.6 + 0.8 * formation(f.at(ix), f.at(iy)));
        }
    }
    let mut rng = Rng::new(seed ^ 0xF1B2);
    for _ in 0..(l * l / 105.0) as usize {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let dens = formation(x, y);
        if rng.unit() > 0.2 + 0.8 * dens {
            continue;
        }
        let len = rng.range(8.0, 24.0);
        let a = rng.range(0.0, std::f32::consts::TAU);
        let (ca, sa) = (a.cos(), a.sin());
        let bend = rng.range(-0.4, 0.4) * len;
        let control = [
            x + ca * len * 0.5 - sa * bend,
            y + sa * len * 0.5 + ca * bend,
        ];
        let pts = arc([x, y], control, [x + ca * len, y + sa * len], 8);
        let w = rng.range(0.35, 0.6);
        let h = rng.range(0.4, 0.7) * (0.5 + 0.7 * dens);
        tube(f, &pts, w, h, if pigment { 0.7 } else { 0.0 });
    }
    for _ in 0..(l * l / 520.0) as usize {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let r = rng.range(0.5, 1.0);
        bowl_at(f, x, y, r, rng.range(0.12, 0.3));
    }
}

/// Distance from `v` to the nearest ruling, which sit at `PITCH / 2 + PITCH × k` (the middle of each pitch cell).
fn ruling_dist(v: f32) -> f32 {
    let r = (v - PITCH * 0.5).rem_euclid(PITCH);
    r.min(PITCH - r)
}

/// The rulings: a 1 px line, or a 2.2 px dot, at every pitch cell's middle. Tint on: their coverage is the ink; tint off:
/// blind-embossed, a soft dent that the light reads without any colour.
pub fn rulings(f: &mut Field, which: Ruling, tint: bool) {
    const HALF_LINE: f32 = 0.5;
    const R_DOT: f32 = 1.1;
    // A blind-embossed ruling must show at the default strength: a 4 px dent with steep flanks (up to about 40°).
    const EMBOSS_LINE: f32 = 2.0;
    const EMBOSS_DOT: f32 = 2.6;
    const DEPTH: f32 = 1.2;
    let (n, texel) = (f.n, 1.0 / f.scale);
    for iy in 0..n {
        let dy = ruling_dist(f.at(iy));
        for ix in 0..n {
            let dx = ruling_dist(f.at(ix));
            let (cov, dent) = match which {
                Ruling::Lines => (band(dy, HALF_LINE, texel), bowl(dy / EMBOSS_LINE)),
                Ruling::Grid => (
                    band(dx, HALF_LINE, texel).max(band(dy, HALF_LINE, texel)),
                    bowl(dx / EMBOSS_LINE) + bowl(dy / EMBOSS_LINE),
                ),
                Ruling::Dots => {
                    let d = dx.hypot(dy);
                    (band(d, R_DOT, texel), bowl(d / EMBOSS_DOT))
                }
            };
            let k = iy * n + ix;
            if tint {
                f.ink[k] = cov;
            } else {
                f.h[k] -= DEPTH * dent;
            }
        }
    }
}
