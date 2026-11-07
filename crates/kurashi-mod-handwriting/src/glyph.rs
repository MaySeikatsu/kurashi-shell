//! From what a hand drew to a glyph (K94). A letter is strokes of points in font units, y up, the baseline at 0, as the drawing box
//! measures them. Each stroke becomes a smooth path through its points, then the outline of that path at the pen's width. The letter stands
//! where it was drawn in height, which is what the box's lines are for; across, it is moved to start at a side bearing, and its advance is its
//! ink and the two bearings, so a letter is as wide as it was written. What leaves here is simple polygons (`simple`).

use i_overlay::core::fill_rule::FillRule;
use i_overlay::core::overlay::{ContourDirection, IntOverlayOptions};
use i_overlay::core::simplify::Simplify;
use i_overlay::i_float::int::point::IntPoint;
use i_overlay::i_shape::int::shape::IntContour;
use kurbo::{BezPath, Cap, Join, PathEl, Point, Stroke, StrokeOpts, stroke};

/// The space either side of a letter.
pub const BEARING: f64 = 45.0;
/// How closely the outline follows the stroke, in font units.
const TOLERANCE: f64 = 1.0;

pub type Strokes = Vec<Vec<[f64; 2]>>;

/// A path through a stroke's points: straight to the first midpoint, then a curve about each point to the next midpoint, so the line a
/// hand wobbled along comes out as a line, not a polygon.
fn smooth(points: &[[f64; 2]]) -> BezPath {
    let mut path = BezPath::new();
    let p = |i: usize| Point::new(points[i][0], points[i][1]);
    path.move_to(p(0));
    if points.len() == 2 {
        path.line_to(p(1));
        return path;
    }
    for i in 1..points.len() - 1 {
        let mid = p(i).midpoint(p(i + 1));
        path.quad_to(p(i), mid);
    }
    path.line_to(p(points.len() - 1));
    path
}

/// Points closer together than this say nothing a pen's width can show.
fn thin(points: &[[f64; 2]], min: f64) -> Vec<[f64; 2]> {
    let mut out: Vec<[f64; 2]> = Vec::with_capacity(points.len());
    for (i, q) in points.iter().enumerate() {
        let far = out
            .last()
            .is_none_or(|l| (l[0] - q[0]).hypot(l[1] - q[1]) >= min);
        if far || i + 1 == points.len() {
            out.push(*q);
        }
    }
    out
}

fn circle(c: [f64; 2], r: f64) -> BezPath {
    let k = 0.5523 * r;
    let (x, y) = (c[0], c[1]);
    let mut p = BezPath::new();
    p.move_to((x + r, y));
    p.curve_to((x + r, y + k), (x + k, y + r), (x, y + r));
    p.curve_to((x - k, y + r), (x - r, y + k), (x - r, y));
    p.curve_to((x - r, y - k), (x - k, y - r), (x, y - r));
    p.curve_to((x + k, y - r), (x + r, y - k), (x + r, y));
    p.close_path();
    p
}

/// How closely the polygons follow the curves, in font units: a thousandth of the height of the text, never seen.
const FLATTEN: f64 = 0.5;
/// Slivers smaller than this (square font units) are what a crossing leaves, never ink.
const SLIVER: u64 = 8;

/// The ink of a letter as simple polygons: no contour crosses itself or another, and nothing overlaps. A pen line that doubles back
/// strokes to an outline that crosses itself with points on top of each other, and text renderers differ on what to do with that:
/// Qt's distance fields crash on some, and take the whole shell with them, however the letter was drawn. So what goes into a font is
/// always the union of what was drawn, on the font's own integer grid.
fn simple(path: &BezPath) -> Vec<IntContour> {
    let mut contours: Vec<IntContour> = Vec::new();
    let mut now: IntContour = Vec::new();
    let flush = |c: &mut IntContour, all: &mut Vec<IntContour>| {
        if c.first() == c.last() {
            c.pop();
        }
        if c.len() >= 3 {
            all.push(std::mem::take(c));
        } else {
            c.clear();
        }
    };
    kurbo::flatten(path.elements().iter().copied(), FLATTEN, |el| match el {
        PathEl::MoveTo(p) => {
            flush(&mut now, &mut contours);
            now.push(IntPoint::new(p.x.round() as i32, p.y.round() as i32));
        }
        PathEl::LineTo(p) => {
            let q = IntPoint::new(p.x.round() as i32, p.y.round() as i32);
            if now.last() != Some(&q) {
                now.push(q);
            }
        }
        PathEl::ClosePath => flush(&mut now, &mut contours),
        _ => {}
    });
    flush(&mut now, &mut contours);
    let options = IntOverlayOptions {
        output_direction: ContourDirection::Clockwise,
        min_output_area: SLIVER,
        ogc: true,
        ..IntOverlayOptions::default()
    };
    contours
        .simplify(FillRule::NonZero, options)
        .into_iter()
        .flatten()
        .collect()
}

/// The outline of a drawn letter at this pen's width, and its bounds across: `None` with nothing drawn.
pub fn outline(strokes: &Strokes, pen: f64) -> Option<(BezPath, f64, f64)> {
    let mut all = BezPath::new();
    let style = Stroke::new(pen)
        .with_caps(Cap::Round)
        .with_join(Join::Round);
    for raw in strokes {
        let points = thin(raw, 2.0);
        if points.is_empty() {
            continue;
        }
        // (a tap is a dot: an i's, a full stop)
        if points.len() == 1 {
            all.extend(circle(points[0], pen / 2.0).elements().iter().copied());
            continue;
        }
        let path = smooth(&points);
        let out = stroke(
            path.elements().iter().copied(),
            &style,
            &StrokeOpts::default(),
            TOLERANCE,
        );
        all.extend(out.elements().iter().copied());
    }
    let contours = simple(&all);
    let (mut x0, mut x1) = (i32::MAX, i32::MIN);
    let mut out = BezPath::new();
    for c in &contours {
        for (i, p) in c.iter().enumerate() {
            x0 = x0.min(p.x);
            x1 = x1.max(p.x);
            let q = (f64::from(p.x), f64::from(p.y));
            if i == 0 {
                out.move_to(q);
            } else {
                out.line_to(q);
            }
        }
        out.close_path();
    }
    if contours.is_empty() {
        return None;
    }
    Some((out, f64::from(x0), f64::from(x1)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_drawn_is_no_outline() {
        assert!(outline(&vec![], 60.0).is_none());
        assert!(outline(&vec![vec![]], 60.0).is_none());
    }

    #[test]
    fn a_tap_is_a_dot_the_pens_width() {
        let (p, x0, x1) = outline(&vec![vec![[100.0, 200.0]]], 60.0).unwrap();
        assert!(
            (x0 - 70.0).abs() < 1.0 && (x1 - 130.0).abs() < 1.0,
            "{x0} {x1}"
        );
        assert!(
            p.elements()
                .iter()
                .all(|e| !matches!(e, PathEl::CurveTo(..)))
        );
    }

    #[test]
    fn a_stroke_is_as_wide_as_it_was_drawn_and_all_quadratic() {
        let s = vec![vec![
            [0.0, 0.0],
            [100.0, 100.0],
            [200.0, 0.0],
            [300.0, 100.0],
        ]];
        let (p, x0, x1) = outline(&s, 40.0).unwrap();
        assert!((x0 + 20.0).abs() < 2.0, "{x0}");
        assert!((x1 - 320.0).abs() < 2.0, "{x1}");
        assert!(
            p.elements()
                .iter()
                .all(|e| !matches!(e, PathEl::CurveTo(..)))
        );
        assert!(matches!(p.elements().last(), Some(PathEl::ClosePath)));
    }

    /// Every edge of an outline, as pairs of points.
    fn edges(p: &BezPath) -> Vec<(Point, Point)> {
        let (mut out, mut at, mut start) = (Vec::new(), Point::ZERO, Point::ZERO);
        for el in p.elements() {
            match *el {
                PathEl::MoveTo(q) => {
                    at = q;
                    start = q;
                }
                PathEl::LineTo(q) => {
                    out.push((at, q));
                    at = q;
                }
                PathEl::ClosePath => out.push((at, start)),
                _ => panic!("only lines: {el:?}"),
            }
        }
        out
    }

    /// Whether two edges cross at a point inside both (sharing an end is not a crossing).
    fn cross(a: (Point, Point), b: (Point, Point)) -> bool {
        let side =
            |o: Point, p: Point, q: Point| (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
        let (d1, d2) = (side(b.0, b.1, a.0), side(b.0, b.1, a.1));
        let (d3, d4) = (side(a.0, a.1, b.0), side(a.0, a.1, b.1));
        d1 * d2 < 0.0 && d3 * d4 < 0.0
    }

    /// A pen doing its worst: back on itself, in tight zigzags, round and round on one spot, along its own line.
    fn scribbles() -> Vec<Strokes> {
        let hairpin: Vec<[f64; 2]> = vec![
            [100.0, 100.0],
            [300.0, 100.0],
            [304.0, 100.0],
            [100.0, 102.0],
            [300.0, 104.0],
            [100.0, 100.0],
        ];
        let zigzag: Vec<[f64; 2]> = (0..40)
            .map(|i| {
                [
                    100.0 + f64::from(i) * 4.0,
                    if i % 2 == 0 { 100.0 } else { 400.0 },
                ]
            })
            .collect();
        let spiral: Vec<[f64; 2]> = (0..120)
            .map(|i| {
                let t = f64::from(i) * 0.4;
                [300.0 + (30.0 + t) * t.cos(), 300.0 + (30.0 + t) * t.sin()]
            })
            .collect();
        let again: Vec<[f64; 2]> = (0..30)
            .map(|i| {
                if i % 2 == 0 {
                    [100.0, 100.0]
                } else {
                    [110.0, 100.0]
                }
            })
            .collect();
        let tail: Vec<[f64; 2]> = vec![
            [488.0, 95.0],
            [472.0, 93.0],
            [458.0, 92.0],
            [449.0, 91.0],
            [453.0, 91.0],
            [509.0, 84.0],
        ];
        vec![
            vec![hairpin.clone()],
            vec![zigzag.clone()],
            vec![spiral.clone()],
            vec![again],
            vec![tail],
            vec![hairpin, zigzag, spiral],
        ]
    }

    #[test]
    fn no_outline_crosses_itself_however_it_was_drawn() {
        for pen in [8.0, 32.0, 56.0, 84.0, 160.0] {
            for s in scribbles() {
                let (p, _, _) = outline(&s, pen).unwrap();
                let e = edges(&p);
                assert!(e.iter().all(|(a, b)| a != b), "a point on top of another");
                for i in 0..e.len() {
                    for j in i + 1..e.len() {
                        assert!(
                            !cross(e[i], e[j]),
                            "pen {pen}: {:?} crosses {:?}",
                            e[i],
                            e[j]
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn a_shaped_letter_keeps_its_hole() {
        // An o: a ring, whose counter must stay open.
        let ring: Vec<[f64; 2]> = (0..=60)
            .map(|i| {
                let t = f64::from(i) * std::f64::consts::TAU / 60.0;
                [200.0 + 150.0 * t.cos(), 200.0 + 150.0 * t.sin()]
            })
            .collect();
        let (p, _, _) = outline(&vec![ring], 40.0).unwrap();
        let closes = p
            .elements()
            .iter()
            .filter(|e| matches!(e, PathEl::ClosePath))
            .count();
        assert_eq!(closes, 2, "an outside and a counter");
    }

    #[test]
    fn points_on_top_of_each_other_are_thinned_but_the_last_stays() {
        let t = thin(
            &[[0.0, 0.0], [0.5, 0.0], [1.0, 0.0], [10.0, 0.0], [10.5, 0.0]],
            2.0,
        );
        assert_eq!(t, vec![[0.0, 0.0], [10.0, 0.0], [10.5, 0.0]]);
    }
}
