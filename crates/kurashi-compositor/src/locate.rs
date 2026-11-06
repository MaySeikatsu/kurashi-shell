//! Where niri's tiled windows stand in a still (I284; `docs/ux/hover-previews.md`). niri's IPC names a tiled window's column,
//! place in it and size, not where it stands on screen: the view's scroll is not told (`tile_pos_in_workspace_view` is
//! floating windows' only, as of 26.04), and neither are the gaps. So they are read from the still: the columns' edges
//! are a known pattern with two unknowns, the scroll and the gap, and the focused column is on screen. Each candidate is scored
//! by how strong the still's vertical edges are where it would put the pattern's edges; rows likewise. A pattern that does
//! not stand out is `None`: no crop, never a wrong one (Shōjiki: a preview that shows another window is worse than none).

/// A window as niri's IPC gives it, in logical px.
#[derive(Debug, Clone, PartialEq)]
pub struct WindowGeom {
    pub id: u64,
    pub workspace: Option<u64>,
    /// 1-based column and place in it; `None` floating.
    pub column: Option<(usize, usize)>,
    pub tile: (f64, f64),
    pub window: (f64, f64),
    pub offset_in_tile: (f64, f64),
    /// Floating windows: where the tile stands in the workspace view.
    pub floating_at: Option<(f64, f64)>,
    /// The workspace's active window, the one niri keeps on screen (focused or not: every output has one).
    pub active: bool,
}

/// A still in grey, one sample per logical px.
pub struct Grey {
    pub w: usize,
    pub h: usize,
    pub px: Vec<u8>,
}
impl Grey {
    /// `rgbx` of `dw × dh` device px, sampled down to `w × h` logical px.
    pub fn from_rgbx(rgbx: &[u8], dw: usize, dh: usize, w: usize, h: usize) -> Self {
        let mut px = Vec::with_capacity(w * h);
        for y in 0..h {
            let sy = y * dh / h.max(1);
            for x in 0..w {
                let sx = x * dw / w.max(1);
                let i = (sy * dw + sx) * 4;
                let (r, g, b) = (
                    u32::from(rgbx[i]),
                    u32::from(rgbx[i + 1]),
                    u32::from(rgbx[i + 2]),
                );
                px.push(((r * 54 + g * 183 + b * 19) >> 8) as u8);
            }
        }
        Grey { w, h, px }
    }
    fn at(&self, x: usize, y: usize) -> i32 {
        i32::from(self.px[y * self.w + x])
    }
}

/// How much stronger than any other candidate the best must be.
const STANDS_OUT: f64 = 1.15;
/// The weakest edge worth trusting, as the share of its length that shows a step (a pattern needs two such).
const WEAKEST: f64 = 0.35;
/// A step across an edge: this much difference (of 255). Counted, not summed: a window's edge runs its whole length, where
/// lines of text, however bright, are broken up.
const STEP: i32 = 6;
/// The largest gap searched (niri's default is 16).
const MAX_GAP: usize = 64;

/// How much of the line at each x shows a step, over rows `y0..y1` (0 … 1).
fn vertical_edges(g: &Grey, y0: usize, y1: usize) -> Vec<f64> {
    let mut out = vec![0.0; g.w + 1];
    let (y0, y1) = (y0.min(g.h), y1.min(g.h));
    let rows = (y0..y1).step_by(4).count().max(1) as f64;
    for (x, o) in out.iter_mut().enumerate().take(g.w).skip(1) {
        let mut sum = 0;
        for y in (y0..y1).step_by(4) {
            sum += i32::from((g.at(x, y) - g.at(x - 1, y)).abs() >= STEP);
        }
        *o = f64::from(sum) / rows;
    }
    out
}
/// The same across rows, over columns `x0..x1`.
fn horizontal_edges(g: &Grey, x0: usize, x1: usize) -> Vec<f64> {
    let mut out = vec![0.0; g.h + 1];
    let (x0, x1) = (x0.min(g.w), x1.min(g.w));
    let cols = (x0..x1).step_by(4).count().max(1) as f64;
    for (y, o) in out.iter_mut().enumerate().take(g.h).skip(1) {
        let mut sum = 0;
        for x in (x0..x1).step_by(4) {
            sum += i32::from((g.at(x, y) - g.at(x, y - 1)).abs() >= STEP);
        }
        *o = f64::from(sum) / cols;
    }
    out
}
/// The profile at `x`, nearly as good a px either side (a fractional scale rounds an edge by one), so an exact hit wins.
fn at(p: &[f64], x: i64) -> f64 {
    let Ok(i) = usize::try_from(x) else {
        return 0.0;
    };
    if i >= p.len() {
        return 0.0;
    }
    let lo = p[i.saturating_sub(1)];
    let hi = p[(i + 1).min(p.len() - 1)];
    p[i].max(lo * 0.9).max(hi * 0.9)
}

/// The best of the scored candidates, if it stands out from those further than `near` from it.
fn best_of(scores: &[(i64, usize, f64)], near: i64) -> Option<(i64, usize)> {
    let &(v, g, s) = scores.iter().max_by(|a, b| a.2.total_cmp(&b.2))?;
    if scores.len() == 1 {
        return Some((v, g));
    }
    if s <= 0.0 {
        return None;
    }
    let rival = scores
        .iter()
        .filter(|c| (c.0 - v).abs() > near)
        .map(|c| c.2)
        .fold(0.0_f64, f64::max);
    (s >= rival * STANDS_OUT).then_some((v, g))
}

/// Where the tiles of one workspace stand in `still`: `(id, x, y)` of each window's geometry whose tile lies wholly on
/// screen. `focused_column`: 1-based, the column niri keeps on screen. Floating windows stand where niri says. Tiled ones
/// are absent when the pattern does not stand out.
pub fn locate(
    still: &Grey,
    windows: &[WindowGeom],
    focused_column: Option<usize>,
) -> Vec<(u64, f64, f64)> {
    let mut out = Vec::new();
    for w in windows {
        if let Some((x, y)) = w.floating_at {
            out.push((w.id, x + w.offset_in_tile.0, y + w.offset_in_tile.1));
        }
    }
    let tiled: Vec<&WindowGeom> = windows.iter().filter(|w| w.column.is_some()).collect();
    if tiled.is_empty() {
        return out;
    }
    let Some(columns) = tiled.iter().filter_map(|w| w.column.map(|c| c.0)).max() else {
        return out;
    };
    // Each column's width, in order; a column with no window (can't be, but a stale list) has none.
    let mut widths = vec![0.0_f64; columns];
    let mut stacks: Vec<Vec<&WindowGeom>> = vec![Vec::new(); columns];
    for w in &tiled {
        let (c, _) = w.column.expect("tiled");
        widths[c - 1] = widths[c - 1].max(w.tile.0);
        stacks[c - 1].push(w);
    }
    for s in &mut stacks {
        s.sort_by_key(|w| w.column.expect("tiled").1);
    }
    let width = still.w as i64;
    let height = still.h as i64;
    let Some(focus) = focused_column.filter(|f| (1..=columns).contains(f)) else {
        return out;
    };

    // --- across: the scroll and the gap ---
    let vert = vertical_edges(still, still.h / 8, still.h * 7 / 8);
    let gaps = if columns > 1 { 0..=MAX_GAP } else { 0..=0 };
    let mut scores = Vec::new();
    for gap in gaps {
        let start = |c: usize| -> f64 { widths[..c].iter().sum::<f64>() + (c as f64) * gap as f64 };
        let fx = start(focus - 1) as i64;
        let fw = widths[focus - 1] as i64;
        // The focused column is on screen: wholly, or filling it when it is wider.
        let (lo, hi) = if fw <= width {
            (fx + fw - width, fx)
        } else {
            (fx, fx + fw - width)
        };
        for view in lo..=hi {
            // Each edge in view once (two columns without a gap share one), summed: a candidate that explains more of the
            // still's edges beats one that only explains some of them well.
            let mut edges: Vec<i64> = Vec::with_capacity(columns * 2);
            for (c, w) in widths.iter().enumerate() {
                let x0 = start(c) as i64 - view;
                for e in [x0, x0 + *w as i64] {
                    if e > 0 && e < width && !edges.iter().any(|o| (o - e).abs() <= 1) {
                        edges.push(e);
                    }
                }
            }
            let score = edges.iter().map(|&e| at(&vert, e)).sum::<f64>();
            scores.push((view, gap, score));
        }
    }
    // One candidate only: a column that fills the screen.
    let single = scores.len() == 1;
    let Some((view, gap)) = best_of(&scores, 3) else {
        return out;
    };
    if !single {
        let best = scores
            .iter()
            .find(|c| c.0 == view && c.1 == gap)
            .map_or(0.0, |c| c.2);
        // (at least one whole edge's worth, and the mean of those in view: below)
        if best < 2.0 * WEAKEST {
            return out;
        }
    }

    // --- down: the top of the working area, the same gap ---
    let start = |c: usize| -> f64 { widths[..c].iter().sum::<f64>() + (c as f64) * gap as f64 };
    let shown: Vec<usize> = (0..columns)
        .filter(|&c| {
            let x0 = start(c) as i64 - view;
            x0 >= -1 && x0 + widths[c] as i64 <= width + 1
        })
        .collect();
    let (x0, x1) = shown.iter().fold((still.w, 0), |(a, b), &c| {
        let l = (start(c) as i64 - view).max(0) as usize;
        let r = ((start(c) as i64 - view) + widths[c] as i64).max(0) as usize;
        (a.min(l), b.max(r))
    });
    let hor = horizontal_edges(still, x0, x1);
    let total = |c: usize, g: f64| -> f64 {
        stacks[c].iter().map(|w| w.tile.1).sum::<f64>()
            + g * stacks[c].len().saturating_sub(1) as f64
    };
    let tall = shown
        .iter()
        .map(|&c| total(c, gap as f64))
        .fold(0.0, f64::max) as i64;
    let mut downs = Vec::new();
    for top in 0..=(height - tall).max(0) {
        let mut edges: Vec<i64> = Vec::new();
        for &c in &shown {
            let mut y = top as f64;
            for w in &stacks[c] {
                for e in [y as i64, (y + w.tile.1) as i64] {
                    if e > 0 && e < height && !edges.iter().any(|o| (o - e).abs() <= 1) {
                        edges.push(e);
                    }
                }
                y += w.tile.1 + gap as f64;
            }
        }
        let score = edges.iter().map(|&e| at(&hor, e)).sum::<f64>();
        downs.push((top, 0, score));
    }
    let Some((top, _)) = best_of(&downs, 3) else {
        return out;
    };
    if downs.len() > 1 && downs.iter().find(|c| c.0 == top).map_or(0.0, |c| c.2) < 2.0 * WEAKEST {
        return out;
    }

    for &c in &shown {
        let x = start(c) - view as f64;
        let mut y = top as f64;
        for w in &stacks[c] {
            out.push((w.id, x + w.offset_in_tile.0, y + w.offset_in_tile.1));
            y += w.tile.1 + gap as f64;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn geom(id: u64, col: usize, row: usize, w: f64, h: f64) -> WindowGeom {
        WindowGeom {
            id,
            workspace: Some(1),
            column: Some((col, row)),
            tile: (w, h),
            window: (w - 4.0, h - 4.0),
            offset_in_tile: (2.0, 2.0),
            floating_at: None,
            active: false,
        }
    }
    /// A wallpaper with some texture, windows as flat rects of their own grey, with text-like lines in them.
    fn scene(w: usize, h: usize, rects: &[(i64, i64, i64, i64, u8)]) -> Grey {
        let mut px = vec![0u8; w * h];
        for y in 0..h {
            for x in 0..w {
                px[y * w + x] = 90 + (((x / 37) ^ (y / 23)) % 3) as u8 * 4;
            }
        }
        for &(x0, y0, rw, rh, v) in rects {
            for y in y0.max(0)..(y0 + rh).min(h as i64) {
                for x in x0.max(0)..(x0 + rw).min(w as i64) {
                    let line =
                        (y - y0) % 18 < 10 && (x - x0) % 97 < 70 && x - x0 > 12 && (y - y0) > 20;
                    px[y as usize * w + x as usize] = if line { v.wrapping_add(90) } else { v };
                }
            }
        }
        Grey { w, h, px }
    }

    #[test]
    fn one_column_is_read_from_its_edges() {
        let g = scene(1920, 1080, &[(300, 40, 960, 1024, 30)]);
        let got = locate(&g, &[geom(7, 1, 1, 960.0, 1024.0)], Some(1));
        assert_eq!(got, vec![(7, 302.0, 42.0)]);
    }

    #[test]
    fn columns_give_the_scroll_and_the_gap() {
        // Three columns, a gap of 16, scrolled so the second is on screen with part of the third.
        let g = scene(
            1920,
            1080,
            &[
                (-500, 8, 800, 1064, 40),
                (316, 8, 900, 1064, 30),
                (1232, 8, 800, 1064, 50),
            ],
        );
        let ws = [
            geom(1, 1, 1, 800.0, 1064.0),
            geom(2, 2, 1, 900.0, 1064.0),
            geom(3, 3, 1, 800.0, 1064.0),
        ];
        let got = locate(&g, &ws, Some(2));
        // Only the column wholly on screen has a place: the others would be cropped.
        assert_eq!(got, vec![(2, 318.0, 10.0)]);
    }

    #[test]
    fn a_stack_in_a_column_has_its_rows() {
        let g = scene(
            1920,
            1080,
            &[
                (100, 30, 800, 500, 30),
                (100, 546, 800, 500, 60),
                (916, 30, 800, 1016, 45),
            ],
        );
        let ws = [
            geom(1, 1, 1, 800.0, 500.0),
            geom(2, 1, 2, 800.0, 500.0),
            geom(3, 2, 1, 800.0, 1016.0),
        ];
        let mut got = locate(&g, &ws, Some(1));
        got.sort_by_key(|a| a.0);
        assert_eq!(
            got,
            vec![(1, 102.0, 32.0), (2, 102.0, 548.0), (3, 918.0, 32.0)]
        );
    }

    /// Nothing tells the window from the wallpaper: no place, not a guess.
    #[test]
    fn a_pattern_that_does_not_stand_out_is_none() {
        let flat = Grey {
            w: 800,
            h: 600,
            px: vec![40; 800 * 600],
        };
        assert!(locate(&flat, &[geom(1, 1, 1, 400.0, 500.0)], Some(1)).is_empty());
    }

    #[test]
    fn a_column_that_fills_the_output_needs_no_search_across() {
        let g = scene(1000, 800, &[(0, 20, 1000, 760, 30)]);
        assert_eq!(
            locate(&g, &[geom(1, 1, 1, 1000.0, 760.0)], Some(1)),
            vec![(1, 2.0, 22.0)]
        );
    }

    #[test]
    fn floating_windows_stand_where_niri_says() {
        let g = Grey {
            w: 100,
            h: 100,
            px: vec![0; 10000],
        };
        let w = WindowGeom {
            floating_at: Some((10.0, 20.0)),
            column: None,
            ..geom(5, 1, 1, 50.0, 50.0)
        };
        assert_eq!(locate(&g, &[w], None), vec![(5, 12.0, 22.0)]);
    }

    #[test]
    fn no_focused_column_is_no_place() {
        let g = scene(800, 600, &[(100, 30, 400, 500, 30)]);
        assert!(locate(&g, &[geom(1, 1, 1, 400.0, 500.0)], None).is_empty());
    }
}
