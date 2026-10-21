//! Periodic noise: every function here wraps at the tile's edge, so tiles repeat without a seam.

/// A small deterministic hash (splitmix64) of a lattice point and a seed.
pub fn hash(x: i64, y: i64, seed: u64) -> f32 {
    let mut z = seed
        ^ (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z >> 40) as f32 / (1u64 << 24) as f32
}

fn smooth(t: f32) -> f32 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

/// Value noise in 0..1 at `(u, v)` (0..1 over the tile) on a `period` × `period` lattice that wraps.
pub fn value(u: f32, v: f32, period: u32, seed: u64) -> f32 {
    let p = period.max(1) as i64;
    let (x, y) = (u * period as f32, v * period as f32);
    let (x0, y0) = (x.floor(), y.floor());
    let (tx, ty) = (smooth(x - x0), smooth(y - y0));
    let (xi, yi) = (x0 as i64, y0 as i64);
    let h = |dx: i64, dy: i64| hash((xi + dx).rem_euclid(p), (yi + dy).rem_euclid(p), seed);
    let top = h(0, 0) * (1.0 - tx) + h(1, 0) * tx;
    let bot = h(0, 1) * (1.0 - tx) + h(1, 1) * tx;
    top * (1.0 - ty) + bot * ty
}

/// Fractal sum of [`value`] octaves, 0..1.
pub fn fbm(u: f32, v: f32, period: u32, octaves: u32, seed: u64) -> f32 {
    let (mut sum, mut amp, mut norm, mut per) = (0.0, 1.0, 0.0, period);
    for o in 0..octaves {
        sum += amp * value(u, v, per, seed.wrapping_add(u64::from(o) * 7919));
        norm += amp;
        amp *= 0.5;
        per *= 2;
    }
    sum / norm
}
