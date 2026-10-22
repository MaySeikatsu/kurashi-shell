//! Cracks (`theme.texture.cracks`, `crack_style`, K61): a network of cracks cut into any material after its wrinkles. They
//! are relief only (no ink), and 0 adds nothing (the caller skips them).
//!
//! Both styles are built on a periodic Voronoi pattern whose borders are measured exactly (the distance to the bisector of
//! the two nearest sites, not `F2 − F1`), so a crack's width is in logical px.
//!
//! **Stone:** the pattern's input is bent twice — a slow warp makes the cells irregular, a fine one (two octaves a few px
//! across) makes the borders jagged — and only some borders crack (more of them as `cracks` rises), each with its own
//! width, tapering to a hairline where a slow field thins it. Hairline branches follow the borders of a finer pattern near
//! the main cracks. A crack is a V in section with slightly raised lips.
//!
//! **Glass:** an unbent pattern with straight borders: every cell a shard, tilted a little as its own plane (its normal
//! turns, so the light catches each shard differently), the shards' faces dropping into a thin deep line where they meet,
//! and fine radial and concentric (conchoidal) hairlines round some of the junctions where three shards meet.
//!
//! Every pattern is periodic in its cell index and every noise in the tile, so the sheet stays seamless.

use std::f32::consts::TAU;

use crate::CrackStyle;
use crate::generate::{Field, rows};
use crate::noise::{fbm_xy, hash, hash2, smoothstep, value_xy};

/// The main cracks' cells (logical px, about: a whole number of cells spans the tile).
const STONE_CELL: f32 = 60.0;
/// The branches' cells, as a fraction of the main cells.
const BRANCH: f32 = 0.42;
/// The shards (logical px) at `cracks` 0 and 1: more and smaller shards as the glass breaks further.
const SHARD: (f32, f32) = (120.0, 48.0);

/// A periodic Voronoi pattern: `period` cells a side of `cell` logical px, one jittered site each.
#[derive(Clone, Copy)]
struct Pattern {
    cell: f32,
    period: i64,
    jitter: f32,
    seed: u64,
}

/// The nearest site to a point and the borders round its cell.
struct Near {
    /// The nearest site (unwrapped logical px) and its cell (wrapped index).
    site: [f32; 2],
    id: i64,
    /// The distance to the nearest kept border, the cell across it, and that cell's site.
    edge: f32,
    across: i64,
    across_site: [f32; 2],
    /// The same for the next nearest kept border (a junction is where both are near).
    edge2: f32,
    across2: i64,
    across2_site: [f32; 2],
}

impl Pattern {
    fn new(cell: f32, logical: f32, jitter: f32, seed: u64) -> Pattern {
        let period = (logical / cell).round().max(2.0) as i64;
        Pattern {
            cell: logical / period as f32,
            period,
            jitter,
            seed,
        }
    }

    /// The site of cell `(cx, cy)` (unwrapped), and its wrapped index.
    fn site(&self, cx: i64, cy: i64) -> ([f32; 2], i64) {
        let (wx, wy) = (cx.rem_euclid(self.period), cy.rem_euclid(self.period));
        let (jx, jy) = hash2(wx, wy, self.seed);
        let k = self.jitter;
        (
            [
                (cx as f32 + 0.5 + k * (jx - 0.5)) * self.cell,
                (cy as f32 + 0.5 + k * (jy - 0.5)) * self.cell,
            ],
            wy * self.period + wx,
        )
    }

    /// The nearest site to `p` and the distance to its cell's two nearest borders for which `keep(id, across)` holds
    /// (`f32::MAX` when none is kept).
    fn near(&self, p: [f32; 2], keep: impl Fn(i64, i64) -> bool) -> Near {
        let (cx, cy) = (
            (p[0] / self.cell).floor() as i64,
            (p[1] / self.cell).floor() as i64,
        );
        let (mut best, mut site, mut id, mut home) = (f32::MAX, [0.0; 2], 0, (0, 0));
        for dy in -1..=1 {
            for dx in -1..=1 {
                let (s, i) = self.site(cx + dx, cy + dy);
                let d = (s[0] - p[0]).powi(2) + (s[1] - p[1]).powi(2);
                if d < best {
                    (best, site, id, home) = (d, s, i, (cx + dx, cy + dy));
                }
            }
        }
        let mut out = Near {
            site,
            id,
            edge: f32::MAX,
            across: -1,
            across_site: site,
            edge2: f32::MAX,
            across2: -1,
            across2_site: site,
        };
        for dy in -2..=2 {
            for dx in -2..=2 {
                if dx == 0 && dy == 0 {
                    continue;
                }
                let (s, i) = self.site(home.0 + dx, home.1 + dy);
                if !keep(id, i) {
                    continue;
                }
                // The distance from p to the bisector of `site` and `s`.
                let (rx, ry) = (s[0] - site[0], s[1] - site[1]);
                let len = (rx * rx + ry * ry).sqrt().max(1e-6);
                let (mx, my) = (0.5 * (s[0] + site[0]), 0.5 * (s[1] + site[1]));
                let d = ((mx - p[0]) * rx + (my - p[1]) * ry) / len;
                if d < out.edge {
                    (out.edge2, out.across2, out.across2_site) =
                        (out.edge, out.across, out.across_site);
                    (out.edge, out.across, out.across_site) = (d, i, s);
                } else if d < out.edge2 {
                    (out.edge2, out.across2, out.across2_site) = (d, i, s);
                }
            }
        }
        out
    }

    /// A value 0..1 of the border between cells `a` and `b` (the same from either side).
    fn border(&self, a: i64, b: i64, salt: u64) -> f32 {
        hash(a.min(b), a.max(b), self.seed ^ salt)
    }
}

/// A crack's section at `e` px from its line: 1 on the line, falling to 0 at `w` (at least half a texel, so a hairline
/// still marks the texel it crosses), a V with slightly rounded sides.
fn vee(e: f32, w: f32, texel: f32) -> f32 {
    let w = w + 0.5 * texel;
    if e >= w { 0.0 } else { (1.0 - e / w).powf(1.4) }
}

/// Cut the cracks of `amount` (0..1) into the height.
pub fn apply(f: &mut Field, seed: u64, amount: f32, style: CrackStyle) {
    match style {
        CrackStyle::Stone => stone(f, seed ^ 0xC4AC_0001, amount),
        CrackStyle::Glass => glass(f, seed ^ 0xC4AC_0002, amount),
    }
}

fn stone(f: &mut Field, seed: u64, amount: f32) {
    let (n, l, g) = (f.n, f.logical, f.grid());
    let texel = 1.0 / g.scale;
    let main = Pattern::new(STONE_CELL, l, 0.85, seed);
    let branch = Pattern::new(STONE_CELL * BRANCH, l, 0.9, seed ^ 0xB4);
    // The share of borders that crack: a few at a touch of cracks, nearly all at 1.
    let share = 0.3 + 0.65 * amount;
    let branch_share = 0.2 + 0.45 * amount;
    // The fine warp: lattices of whole periods, about 26 and 9 px across.
    let (j1, j2) = ((l / 26.0).round() as u32, (l / 9.0).round() as u32);
    let main_keep = |a: i64, b: i64| main.border(a, b, 0x5EED) < share;
    let branch_keep = |a: i64, b: i64| branch.border(a, b, 0x5EED) < branch_share;
    rows(n, f.threads, &mut f.h, |iy, row| {
        let v = g.uv(iy);
        for (ix, h) in row.iter_mut().enumerate() {
            let u = g.uv(ix);
            let (x, y) = (g.at(ix), g.at(iy));
            // The slow warp (cells of no regular shape) and the jag (borders that zigzag).
            let wx = 0.6 * main.cell * (fbm_xy(u, v, 4, 4, 3, seed ^ 0x11) - 0.5)
                + 3.0 * (value_xy(u, v, j1, j1, seed ^ 0x13) - 0.5)
                + 1.4 * (value_xy(u, v, j2, j2, seed ^ 0x15) - 0.5);
            let wy = 0.6 * main.cell * (fbm_xy(u, v, 4, 4, 3, seed ^ 0x12) - 0.5)
                + 3.0 * (value_xy(u, v, j1, j1, seed ^ 0x14) - 0.5)
                + 1.4 * (value_xy(u, v, j2, j2, seed ^ 0x16) - 0.5);
            let p = [x + wx, y + wy];
            let m = main.near(p, main_keep);
            // Each crack its own width; a slow field tapers it to a hairline and, where it is lowest, out.
            let own = main.border(m.id, m.across, 0xA11);
            let taper = smoothstep(0.2, 0.7, fbm_xy(u, v, 6, 6, 3, seed ^ 0x21));
            let fade = smoothstep(0.02, 0.25, taper + 0.3 * own);
            let w = (0.35 + 1.5 * taper * (0.5 + 0.5 * own)) * (0.7 + 0.6 * amount);
            let depth = (0.8 + 2.6 * amount) * (0.35 + 0.65 * taper) * fade;
            let mut cut = depth * vee(m.edge, w, texel);
            // The lips: the stone each side of a crack stands a little proud, then falls back.
            let lip = 0.2 * depth * (-((m.edge - 1.6 * w - 0.8) / (0.9 * w + 0.6)).powi(2)).exp();
            // Branches: hairlines along a finer pattern's borders, only near a main crack (they run off it).
            let b = branch.near([p[0] + 0.6 * wy, p[1] - 0.6 * wx], branch_keep);
            let near_main = (-(m.edge / (1.2 * branch.cell)).powi(2)).exp() * fade;
            let wb = 0.3 + 0.4 * amount;
            let db = (0.4 + 1.2 * amount)
                * near_main
                * (0.4 + 0.6 * branch.border(b.id, b.across, 0xA12));
            cut = cut.max(db * vee(b.edge, wb, texel));
            *h += lip - cut;
        }
    });
}

fn glass(f: &mut Field, seed: u64, amount: f32) {
    let (n, l, g) = (f.n, f.logical, f.grid());
    let texel = 1.0 / g.scale;
    let shards = Pattern::new(SHARD.0 + (SHARD.1 - SHARD.0) * amount, l, 0.95, seed);
    // Each shard's tilt (px per px) and the crack's depth.
    let tilt = 0.05 + 0.07 * amount;
    let depth = 1.0 + 2.2 * amount;
    // The share of junctions that carry radial and concentric hairlines.
    let star_share = 0.3 + 0.4 * amount;
    rows(n, f.threads, &mut f.h, |iy, row| {
        for (ix, h) in row.iter_mut().enumerate() {
            let (x, y) = (g.at(ix), g.at(iy));
            let p = [x, y];
            let s = shards.near(p, |_, _| true);
            // The shard's plane through its site: its own tilt and a small offset of height.
            let (ax, ay) = hash2(s.id, 7, seed ^ 0x71);
            let lift = hash(s.id, 9, seed ^ 0x73) - 0.5;
            let plane = tilt
                * ((2.0 * ax - 1.0) * (x - s.site[0]) + (2.0 * ay - 1.0) * (y - s.site[1]))
                + 0.6 * lift;
            // The faces drop into the crack: a thin deep line with a narrow chamfer either side, a little wider in places.
            let own = shards.border(s.id, s.across, 0xA21);
            let w = 0.7 + 0.5 * own;
            let face = smoothstep(0.0, w + 0.5 * texel, s.edge);
            let mut v = plane * face - depth * (1.0 - face);
            // Hairlines round a junction: rays from it and arcs about it, fading with the distance.
            let (j, r) = junction(s.site, s.across_site, s.across2_site, p);
            // The junction's own number: the same from each of its three shards.
            let mut tri = [s.id, s.across, s.across2];
            tri.sort_unstable();
            let cells = shards.period * shards.period;
            let jid = (tri[0] * cells + tri[1]) * cells + tri[2];
            let key = hash(jid, 0, seed ^ 0x5A);
            let reach = 0.6 * shards.cell;
            if key < star_share && r < reach && s.edge2 < reach {
                let fall = 1.0 - smoothstep(0.3 * reach, reach, r);
                let ang = (p[1] - j[1]).atan2(p[0] - j[0]);
                let rays = 7.0 + (6.0 * hash(jid, 1, seed)).floor();
                // The rays bend a little with the distance, as a fracture does.
                let a = ang / TAU * rays + 13.0 * hash(jid, 2, seed) + 0.012 * r;
                let ray = a.round();
                let to_ray = (a - ray).abs() * TAU / rays * r;
                let alive = hash(ray as i64, jid, seed ^ 0x77);
                let reach_ray = reach * (0.4 + 0.6 * alive);
                let mut hair = if alive < 0.75 && r < reach_ray {
                    vee(to_ray, 0.25, texel) * (1.0 - smoothstep(0.6 * reach_ray, reach_ray, r))
                } else {
                    0.0
                };
                // Conchoidal arcs: rings at three radii, each broken into arcs.
                for (k, frac) in [0.22f32, 0.43, 0.68].into_iter().enumerate() {
                    let rk = reach * frac * (0.85 + 0.3 * hash(k as i64, jid, seed ^ 0x79));
                    let arc = value_xy(ang / TAU, frac, 9, 1, seed ^ (0x7B + k as u64));
                    if arc > 0.45 {
                        hair = hair.max(
                            0.8 * vee((r - rk).abs(), 0.2, texel) * smoothstep(0.45, 0.55, arc),
                        );
                    }
                }
                v -= (0.5 + 0.9 * amount) * depth * 0.6 * hair * fall * face;
            }
            *h += v;
        }
    });
}

/// The junction of three shards whose sites are `a`, `b` and `c` (the centre of their circle), and the distance of `p`
/// from it.
fn junction(a: [f32; 2], b: [f32; 2], c: [f32; 2], p: [f32; 2]) -> ([f32; 2], f32) {
    let d = 2.0 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]));
    if d.abs() < 1e-6 {
        return (a, f32::MAX);
    }
    let (a2, b2, c2) = (
        a[0] * a[0] + a[1] * a[1],
        b[0] * b[0] + b[1] * b[1],
        c[0] * c[0] + c[1] * c[1],
    );
    let j = [
        (a2 * (b[1] - c[1]) + b2 * (c[1] - a[1]) + c2 * (a[1] - b[1])) / d,
        (a2 * (c[0] - b[0]) + b2 * (a[0] - c[0]) + c2 * (b[0] - a[0])) / d,
    ];
    (j, (p[0] - j[0]).hypot(p[1] - j[1]))
}
