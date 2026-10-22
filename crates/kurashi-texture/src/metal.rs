//! Brushed steel (`metal`): the brushing is the dominant feature, a dense fine streak along x. Every pixel row takes its own
//! level, and that level changes in segments some 40 px long, so the streaks are many, short and varied rather than one
//! flat stripe. Over it a few short light scratches run in nearly one direction, and a couple of tiny dings. Calm at a
//! glance, rich up close. No ink: the material is its gloss (K59).

use crate::generate::{Field, rows};
use crate::noise::{Rng, value_xy};
use crate::raster::{bowl_at, groove};

/// Scratches per tile: a few, not a field. Most run with the brushing, the rest at a slant.
const SCRATCHES: usize = 9;
/// Dings per tile: tiny, pressed or raised.
const DINGS: usize = 3;

pub fn brushed(f: &mut Field, seed: u64) {
    let (n, l) = (f.n, f.logical);
    let lines = n as u32;
    rows(n, f.threads, &mut f.h, |iy, h| {
        // Evaluated at the row's own lattice point, so each pixel row takes its own level: that is what makes a brushing.
        let v = iy as f32 / n as f32;
        for ix in 0..n {
            let u = (ix as f32 + 0.5) / n as f32;
            let row = value_xy(0.0, v, 1, lines, seed) - 0.5;
            let seg = value_xy(u, v, 20, lines, seed ^ 0x51) - 0.5;
            // The brushing is stronger in some broad patches than in others, as a hand-brushed sheet is.
            let patch = 0.6 + 0.8 * value_xy(u, (iy as f32 + 0.5) / n as f32, 3, 2, seed ^ 0x52);
            h[ix] = patch * (0.7 * row + 0.7 * seg);
        }
    });
    let mut rng = Rng::new(seed ^ 0x5C4A);
    // Scratches: short and light, nearly all in the brushing's direction.
    for _ in 0..SCRATCHES {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let a = if rng.unit() < 0.8 {
            rng.range(-0.07, 0.07)
        } else {
            rng.range(-0.3, 0.3)
        };
        let len = rng.range(25.0, 90.0);
        let (dx, dy) = (a.cos() * len, a.sin() * len);
        groove(
            f,
            [x, y],
            [x + dx, y + dy],
            rng.range(0.45, 0.7),
            rng.range(0.5, 0.9),
        );
    }
    // Dings: a couple of tiny dents, a few raised.
    for _ in 0..DINGS {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let sign = if rng.unit() < 0.5 { 1.0 } else { -1.0 };
        bowl_at(f, x, y, rng.range(1.2, 2.2), sign * rng.range(0.35, 0.7));
    }
}
