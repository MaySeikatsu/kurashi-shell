//! Wrinkles (`theme.texture.wrinkles`, K59): crumpled facets, the sharp creases between them, and a few long folds, added
//! to any material's height. Zero adds nothing (the caller skips it).
//!
//! Facets: each cell of a 24 px grid holds a tilted plane. The facet height is the plane of each nearby cell weighted by
//! its distance to the cell's site (a Gaussian over 5 × 5 cells, which is continuous and periodic: no step at a cell's
//! edge). Creases: the distance between the nearest two sites of the same pattern is zero along the edges between facets,
//! so `−(F2 − F1)` is a sharp valley wherever two facets meet, as in crumpled paper. Folds: triangle waves along integer
//! wave vectors, so each fold is a straight crease that runs across the tile and wraps; a slow mask keeps them in some
//! places only.

use crate::Kind;
use crate::generate::{Field, rows};
use crate::noise::{cells, fbm_xy, hash, hash2, smoothstep};

/// The facets' size, logical px (a divisor of every tile: 480 / 24 = 20 across).
const FACET: f32 = 24.0;
/// Each facet's tilt: the planes' gradients, in logical px per px.
const TILT: f32 = 0.07;
/// The reach of a facet's influence, logical px: a plane gives way to its neighbour over about 5 px, so facets read flat.
const REACH: f32 = 0.2 * FACET;
/// The folds: wave vector (integers), phase, weight.
const FOLDS: [(f32, f32, f32, f32); 4] = [
    (1.0, 0.0, 0.0, 1.0),
    (0.0, 1.0, 0.3, 0.8),
    (1.0, 1.0, 0.7, 0.9),
    (1.0, -2.0, 0.1, 0.6),
];

/// The relief of the crumple at full strength, logical px, per material (crumpled foil is thinner than creased leather).
pub fn depth(kind: Kind) -> f32 {
    match kind {
        Kind::Metal => 1.2,
        Kind::Leather => 1.8,
        Kind::Stone => 2.0,
        _ => 1.4,
    }
}

/// Subtract the mean and divide by the spread, so the part of the wrinkle has unit deviation.
fn normalise(v: &mut [f32]) {
    let len = v.len() as f32;
    let mean = v.iter().sum::<f32>() / len;
    let sd = (v.iter().map(|x| (x - mean) * (x - mean)).sum::<f32>() / len)
        .sqrt()
        .max(1e-6);
    for x in v.iter_mut() {
        *x = (*x - mean) / sd;
    }
}

/// Triangle wave: 1 on the integers (a sharp ridge), 0 halfway between (a sharp valley).
fn tri(t: f32) -> f32 {
    (2.0 * t.rem_euclid(1.0) - 1.0).abs()
}

/// Add the wrinkles of `amount` (0..1) to the height, at `depth` logical px for full strength.
pub fn apply(f: &mut Field, seed: u64, amount: f32, depth: f32) {
    let (n, l) = (f.n, f.logical);
    let np = (l / FACET).round() as usize;
    let seed_sites = seed ^ 0xFA;
    // Each wrapped cell's site jitter, plane gradient (0..1 each) and offset, looked up by the cell's index.
    let table: Vec<[f32; 5]> = (0..np * np)
        .map(|c| {
            let (wx, wy) = ((c % np) as i64, (c / np) as i64);
            let (jx, jy) = hash2(wx, wy, seed_sites);
            let (ax, ay) = hash2(wx, wy, seed ^ 0xFB);
            [jx, jy, ax, ay, hash(wx, wy, seed ^ 0xFC) - 0.5]
        })
        .collect();
    // Facets, creases and folds of every texel, before each is normalised.
    let mut parts = vec![[0f32; 3]; n * n];
    let g = f.grid();
    rows(n, f.threads, &mut parts, |iy, row| {
        let y = g.at(iy);
        let cy = (y / FACET).floor() as i64;
        for (ix, part) in row.iter_mut().enumerate() {
            let x = g.at(ix);
            let cx = (x / FACET).floor() as i64;
            let (u, v) = (g.uv(ix), g.uv(iy));
            // Facets: a weighted blend of the planes of the cells around, periodic in the cell index.
            let (mut sum, mut weight) = (0.0f32, 0.0f32);
            for dy in -2..=2 {
                for dx in -2..=2 {
                    let (gx, gy) = (cx + dx, cy + dy);
                    let t = table[gy.rem_euclid(np as i64) as usize * np
                        + gx.rem_euclid(np as i64) as usize];
                    let (sx, sy) = ((gx as f32 + t[0]) * FACET, (gy as f32 + t[1]) * FACET);
                    let plane = t[4]
                        + TILT * (2.0 * t[2] - 1.0) * (x - sx)
                        + TILT * (2.0 * t[3] - 1.0) * (y - sy);
                    let d2 = (x - sx) * (x - sx) + (y - sy) * (y - sy);
                    let w = (-d2 / (REACH * REACH)).exp();
                    sum += w * plane;
                    weight += w;
                }
            }
            part[0] = sum / weight.max(1e-12);
            // Creases: zero on the edges between the facets of the same sites, a sharp valley there.
            let edge = cells(u, v, np as u32, seed_sites);
            part[1] = -(edge.f2 - edge.f1);
            // Folds: long straight creases across the tile, in some places only.
            let mut fold = 0.0;
            for (kx, ky, phase, weight) in FOLDS {
                fold += weight * tri(kx * u + ky * v + phase);
            }
            let mask = smoothstep(0.3, 0.7, fbm_xy(u, v, 2, 2, 2, seed ^ 0x3F));
            part[2] = fold * mask;
        }
    });
    let mut facets: Vec<f32> = parts.iter().map(|p| p[0]).collect();
    let mut creases: Vec<f32> = parts.iter().map(|p| p[1]).collect();
    let mut folds: Vec<f32> = parts.iter().map(|p| p[2]).collect();
    normalise(&mut facets);
    normalise(&mut creases);
    normalise(&mut folds);
    let scale = amount * depth;
    for (k, h) in f.h.iter_mut().enumerate() {
        *h += scale * (0.3 * facets[k] + 0.5 * creases[k] + 0.2 * folds[k]);
    }
}
