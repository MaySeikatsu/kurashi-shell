//! Periodic noise: every function here wraps at the tile's edge, so tiles repeat without a seam. Lattice periods
//! are whole numbers of cells per tile, so a feature at period `p` tiles exactly when the tile holds `p` of them.

/// A small deterministic hash (splitmix64) of a lattice point and a seed, 0..1.
pub fn hash(x: i64, y: i64, seed: u64) -> f32 {
    let mut z = seed
        ^ (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z >> 40) as f32 / (1u64 << 24) as f32
}

/// Two decorrelated hashes of a lattice point (a feature's offset in a cell).
pub fn hash2(x: i64, y: i64, seed: u64) -> (f32, f32) {
    (hash(x, y, seed), hash(x, y, seed ^ 0xD1B5_4A32_D192_ED03))
}

fn smooth(t: f32) -> f32 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

/// Value noise in 0..1 at `(u, v)` (0..1 over the tile) on a `px` × `py` lattice that wraps.
pub fn value_xy(u: f32, v: f32, px: u32, py: u32, seed: u64) -> f32 {
    let (px, py) = (px.max(1) as i64, py.max(1) as i64);
    let (x, y) = (u * px as f32, v * py as f32);
    let (x0, y0) = (x.floor(), y.floor());
    let (tx, ty) = (smooth(x - x0), smooth(y - y0));
    let (xi, yi) = (x0 as i64, y0 as i64);
    let h = |dx: i64, dy: i64| hash((xi + dx).rem_euclid(px), (yi + dy).rem_euclid(py), seed);
    let top = h(0, 0) * (1.0 - tx) + h(1, 0) * tx;
    let bot = h(0, 1) * (1.0 - tx) + h(1, 1) * tx;
    top * (1.0 - ty) + bot * ty
}

/// Fractal sum of [`value_xy`] octaves (each octave doubles both periods), 0..1.
pub fn fbm_xy(u: f32, v: f32, px: u32, py: u32, octaves: u32, seed: u64) -> f32 {
    let (mut sum, mut amp, mut norm, mut per_x, mut per_y) = (0.0, 1.0, 0.0, px, py);
    for o in 0..octaves {
        sum += amp * value_xy(u, v, per_x, per_y, seed.wrapping_add(u64::from(o) * 7919));
        norm += amp;
        amp *= 0.5;
        per_x *= 2;
        per_y *= 2;
    }
    sum / norm
}

/// The two nearest feature points of a periodic cellular (Worley) pattern, in cell units, and a random value of the
/// nearest cell (`id`, 0..1: which cells get a crack, a pore, a speck).
#[derive(Clone, Copy, Debug)]
pub struct Cells {
    pub f1: f32,
    pub f2: f32,
    pub id: f32,
}

/// Cellular noise on a `period` × `period` grid of cells (one feature point each, jittered inside its cell).
pub fn cells(u: f32, v: f32, period: u32, seed: u64) -> Cells {
    let p = period.max(1) as i64;
    let (x, y) = (u * p as f32, v * p as f32);
    let (xi, yi) = (x.floor() as i64, y.floor() as i64);
    let (mut f1, mut f2, mut id) = (f32::MAX, f32::MAX, 0.0);
    for dy in -1..=1 {
        for dx in -1..=1 {
            let (cx, cy) = (xi + dx, yi + dy);
            let (wx, wy) = (cx.rem_euclid(p), cy.rem_euclid(p));
            let (jx, jy) = hash2(wx, wy, seed);
            let (fx, fy) = (cx as f32 + jx, cy as f32 + jy);
            let d = ((fx - x).powi(2) + (fy - y).powi(2)).sqrt();
            if d < f1 {
                f2 = f1;
                f1 = d;
                id = hash(wx, wy, seed ^ 0x51ED_0F00);
            } else if d < f2 {
                f2 = d;
            }
        }
    }
    Cells { f1, f2, id }
}

/// Smoothstep between `a` and `b`.
pub fn smoothstep(a: f32, b: f32, t: f32) -> f32 {
    let k = ((t - a) / (b - a)).clamp(0.0, 1.0);
    k * k * (3.0 - 2.0 * k)
}

/// A seeded stream of numbers for placing marks (splitmix64): the same seed places the same marks.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(seed ^ 0x9E37_79B9_7F4A_7C15)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// 0..1.
    pub fn unit(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / (1u64 << 24) as f32
    }

    /// `a`..`b`.
    pub fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.unit()
    }
}
