//! Display (`display`, W62, after the YoRHa wallpaper): a screen's pixel grid. Square cells on a regular lattice of
//! [`PITCH`] logical px, each gap [`GAP`] px wide (the black matrix of an LCD). The lattice lives in logical px, so the
//! same pattern shows at every scale and only its resolution changes. A gap's coverage is the box filter over its texel
//! ([`band`]): at 1× every texel is exactly cell or gap, and at fractional scales the edges soften honestly.
//!
//! The gaps are the ink (tint on): black, at the material's ink alpha, so they darken whatever surface lies under them
//! in every scheme and never add a colour. The cells stand a hair above the gaps (a dent, the relief of tint off), and a
//! slow cloud of brightness (a panel's unevenness) lies over the whole sheet: its gentle slope is the only relief the
//! light's angle moves, so the grid itself never embosses or shimmers.

use crate::generate::{Field, rows2};
use crate::noise::fbm_xy;
use crate::raster::band;

/// The lattice's pitch, logical px (every tile is a multiple of it: 48 × k is a multiple of 4).
pub const PITCH: f32 = 4.0;
/// The gap between cells, logical px: a quarter of the pitch, as the reference's black matrix.
pub const GAP: f32 = 1.0;
/// How far the cells stand over the gaps, logical px: a dent too shallow to emboss every texel.
const DENT: f32 = 0.1;
/// The panel's unevenness: the cloud's peak-to-peak height, logical px.
const CLOUD: f32 = 0.6;
/// Where the first gap starts, logical px: every gap covers `[OFFSET + PITCH·k, … + GAP)`. The tile's edge is a multiple of
/// the pitch, so this puts the wrap between two cells rather than across a grid line (a dense lattice would otherwise
/// make a mean-based seam check read a grid line at the edge as a seam).
const OFFSET: f32 = 1.0;

/// Logical distance from `x` to the nearest gap centre (`OFFSET + GAP/2`, once per pitch).
fn gap_distance(x: f32) -> f32 {
    let t = (x - (OFFSET + GAP * 0.5)).rem_euclid(PITCH);
    t.min(PITCH - t)
}

/// The gap's coverage of a texel at logical `x` (side `texel` logical px): 1 in a gap, 0 in a cell, the box filter between.
fn gap_coverage(x: f32, texel: f32) -> f32 {
    band(gap_distance(x), GAP * 0.5, texel)
}

/// The pixel grid on the sheet: gaps in ink (tint on), the cells' dent and the panel cloud in the heights.
pub fn display(f: &mut Field, seed: u64, tint: bool) {
    let (n, l, texel) = (f.n, f.logical, 1.0 / f.scale);
    let g = f.grid();
    rows2(n, f.threads, &mut f.h, &mut f.ink, |iy, h, ink| {
        let y = g.at(iy);
        let cover_y = gap_coverage(y, texel);
        for ix in 0..n {
            let x = g.at(ix);
            let cover = gap_coverage(x, texel).max(cover_y);
            let cloud = fbm_xy(x / l, y / l, 2, 2, 3, seed ^ 0xD15) - 0.5;
            h[ix] = DENT * (1.0 - cover) + CLOUD * cloud;
            if tint {
                ink[ix] = cover;
            }
        }
    });
}
