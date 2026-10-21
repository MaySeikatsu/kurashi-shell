//! Drawing the marks a material is made of (fibres, threads, pores, scratches, rulings) into a [`Field`]. A mark is drawn
//! at its logical position and its texels wrap at the tile's edge, so a mark that crosses the seam appears on both sides
//! and the tile repeats without a join.

use crate::generate::Field;

/// The texels whose centres lie in the logical box `[x0, x1] × [y0, y1]` (unwrapped positions; the index wraps), with
/// each texel's logical centre `(x, y)` for `g(index, x, y)`.
pub fn texels(
    n: usize,
    scale: f32,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    mut g: impl FnMut(usize, f32, f32),
) {
    let ni = n as isize;
    let (ix0, ix1) = ((x0 * scale).floor() as isize, (x1 * scale).ceil() as isize);
    let (iy0, iy1) = ((y0 * scale).floor() as isize, (y1 * scale).ceil() as isize);
    for iy in iy0..=iy1 {
        let y = (iy as f32 + 0.5) / scale;
        let row = iy.rem_euclid(ni) as usize * n;
        for ix in ix0..=ix1 {
            let x = (ix as f32 + 0.5) / scale;
            g(row + ix.rem_euclid(ni) as usize, x, y);
        }
    }
}

/// Coverage of one texel (side `texel` logical px) by a band of half-width `half` whose centre is `d` away: the box
/// filter over the texel, so a 1 px line straddling two texels shades both at half strength.
pub fn band(d: f32, half: f32, texel: f32) -> f32 {
    ((half + texel * 0.5 - d) / texel).clamp(0.0, 1.0)
}

/// The smooth dent profile: 1 at the centre, 0 at `t` = 1, with soft shoulders (no kink).
pub fn bowl(t: f32) -> f32 {
    if t >= 1.0 {
        0.0
    } else {
        let k = 1.0 - t * t;
        k * k
    }
}

/// Distance from `(x, y)` to the polyline `pts`.
pub fn dist_poly(pts: &[[f32; 2]], x: f32, y: f32) -> f32 {
    let mut best = f32::MAX;
    for w in pts.windows(2) {
        best = best.min(dist_seg(w[0], w[1], x, y));
    }
    best
}

/// Distance from `(x, y)` to the segment `a`–`b`.
pub fn dist_seg(a: [f32; 2], b: [f32; 2], x: f32, y: f32) -> f32 {
    let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
    let l2 = (dx * dx + dy * dy).max(1e-9);
    let t = (((x - a[0]) * dx + (y - a[1]) * dy) / l2).clamp(0.0, 1.0);
    let (px, py) = (a[0] + dx * t - x, a[1] + dy * t - y);
    (px * px + py * py).sqrt()
}

/// Points of the quadratic curve `p0` → `p2` bent by control point `c`, `k` segments.
pub fn arc(p0: [f32; 2], c: [f32; 2], p2: [f32; 2], k: usize) -> Vec<[f32; 2]> {
    (0..=k)
        .map(|i| {
            let t = i as f32 / k as f32;
            let m = 1.0 - t;
            [
                m * m * p0[0] + 2.0 * m * t * c[0] + t * t * p2[0],
                m * m * p0[1] + 2.0 * m * t * c[1] + t * t * p2[1],
            ]
        })
        .collect()
}

/// The bounding box of points, grown by `r`: `(x0, y0, x1, y1)`.
fn bounds(pts: &[[f32; 2]], r: f32) -> (f32, f32, f32, f32) {
    let (mut x0, mut y0, mut x1, mut y1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for p in pts {
        x0 = x0.min(p[0]);
        y0 = y0.min(p[1]);
        x1 = x1.max(p[0]);
        y1 = y1.max(p[1]);
    }
    (x0 - r, y0 - r, x1 + r, y1 + r)
}

/// A round tube along the polyline `pts`, radius `w`, crest height `h` (logical px). The height takes the maximum over
/// the tubes already drawn; the ink takes the maximum of `ink` × the tube's coverage (0 draws no ink).
pub fn tube(f: &mut Field, pts: &[[f32; 2]], w: f32, h: f32, ink: f32) {
    let texel = 1.0 / f.scale;
    let (x0, y0, x1, y1) = bounds(pts, w + texel);
    let (n, scale) = (f.n, f.scale);
    texels(n, scale, x0, y0, x1, y1, |i, x, y| {
        let d = dist_poly(pts, x, y);
        if d >= w + texel {
            return;
        }
        let t = (d / w).min(1.0);
        let crest = h * (1.0 - t * t).sqrt();
        if crest > f.h[i] {
            f.h[i] = crest;
        }
        if ink > 0.0 {
            let cov = band(d, w, texel) * ink;
            if cov > f.ink[i] {
                f.ink[i] = cov;
            }
        }
    });
}

/// A round strand along the polyline `pts`, radius `w`, crest height `h`, added to the height: it stands off whatever is
/// under it, so it shows on the top of a thread too.
pub fn tube_add(f: &mut Field, pts: &[[f32; 2]], w: f32, h: f32) {
    let texel = 1.0 / f.scale;
    let (x0, y0, x1, y1) = bounds(pts, w + texel);
    let (n, scale) = (f.n, f.scale);
    texels(n, scale, x0, y0, x1, y1, |i, x, y| {
        let d = dist_poly(pts, x, y);
        if d < w {
            f.h[i] += h * (1.0 - (d / w) * (d / w)).sqrt();
        }
    });
}

/// A round dent of radius `r` and depth `depth` (logical px) at `(cx, cy)`, soft-shouldered, summed into the height.
pub fn bowl_at(f: &mut Field, cx: f32, cy: f32, r: f32, depth: f32) {
    let (n, scale) = (f.n, f.scale);
    texels(n, scale, cx - r, cy - r, cx + r, cy + r, |i, x, y| {
        let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt();
        f.h[i] -= depth * bowl(d / r);
    });
}

/// A scratch along the segment `a`–`b`: half-width `w`, depth `depth`, a V in cross-section (its edges catch the light
/// as sharp lines), summed into the height.
pub fn groove(f: &mut Field, a: [f32; 2], b: [f32; 2], w: f32, depth: f32) {
    let (n, scale) = (f.n, f.scale);
    let (x0, y0, x1, y1) = bounds(&[a, b], w * 2.0);
    texels(n, scale, x0, y0, x1, y1, |i, x, y| {
        let d = dist_seg(a, b, x, y);
        if d < w {
            f.h[i] -= depth * (1.0 - d / w);
        }
    });
}
