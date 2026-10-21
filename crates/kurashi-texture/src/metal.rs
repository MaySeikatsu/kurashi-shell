//! Scratched metal (`metal`): brushed streaks along x (fine lines a pixel apart, broader bands and long slow variation, all
//! stretched along the brushing), straight scratches of varied length, depth and angle, and a few soft dents. No ink: the
//! material is its gloss (high, K59).

use crate::generate::Field;
use crate::noise::{Rng, value_xy};
use crate::raster::{bowl_at, groove};

pub fn brushed(f: &mut Field, seed: u64) {
    let (n, l) = (f.n, f.logical);
    // Streaks: each row of the brushing has its own level (a pixel-thin line), broader bands run across several rows, and a
    // slow variation runs along the length. The lattices are stretched along x and fine along y.
    for iy in 0..n {
        for ix in 0..n {
            let (u, v) = (f.uv(ix), f.uv(iy));
            let s = 0.5 * (value_xy(u, v, 3, 480, seed) - 0.5)
                + 0.35 * (value_xy(u, v, 6, 160, seed ^ 0x01) - 0.5)
                + 0.25 * (value_xy(u, v, 2, 40, seed ^ 0x02) - 0.5);
            f.h[iy * n + ix] = 0.8 * s;
        }
    }
    let mut rng = Rng::new(seed ^ 0x5C4A);
    // Scratches: most run along the brushing, some cross it. Each is a groove of its own depth and width.
    for _ in 0..(l * l / 1300.0) as usize {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        let a = if rng.unit() < 0.7 {
            rng.range(-0.08, 0.08)
        } else {
            rng.range(0.0, std::f32::consts::PI)
        };
        let len = rng.range(18.0, 220.0);
        let (dx, dy) = (a.cos() * len, a.sin() * len);
        groove(
            f,
            [x, y],
            [x + dx, y + dy],
            rng.range(0.6, 1.4),
            rng.range(0.25, 1.0),
        );
    }
    // A few soft dents, raised or pressed.
    for _ in 0..6 {
        let (x, y) = (rng.range(0.0, l), rng.range(0.0, l));
        bowl_at(f, x, y, rng.range(5.0, 12.0), rng.range(-0.6, 0.6));
    }
}
