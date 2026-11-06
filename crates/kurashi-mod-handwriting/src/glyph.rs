//! From what a hand drew to a glyph (K94). A letter is strokes of points in font units, y up, the baseline at 0, as the drawing box
//! measures them. Each stroke becomes a smooth path through its points, then the outline of that path at the pen's width. The letter stands
//! where it was drawn in height, which is what the box's lines are for; across, it is moved to start at a side bearing, and its advance is its
//! ink and the two bearings, so a letter is as wide as it was written.

use kurbo::{BezPath, Cap, CubicBez, Join, PathEl, Point, Stroke, StrokeOpts, stroke};

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

/// A path's cubics as quadratics, whole contours closed: what `glyf` holds.
fn quadratic(path: &BezPath) -> BezPath {
    let mut out = BezPath::new();
    let (mut at, mut start) = (Point::ZERO, Point::ZERO);
    let mut open = false;
    for el in path.elements() {
        match *el {
            PathEl::MoveTo(p) => {
                if open {
                    out.close_path();
                }
                out.move_to(p);
                at = p;
                start = p;
                open = true;
            }
            PathEl::LineTo(p) => {
                out.line_to(p);
                at = p;
            }
            PathEl::QuadTo(c, p) => {
                out.quad_to(c, p);
                at = p;
            }
            PathEl::CurveTo(c0, c1, p) => {
                for (_, _, q) in CubicBez::new(at, c0, c1, p).to_quads(TOLERANCE) {
                    out.quad_to(q.p1, q.p2);
                }
                at = p;
            }
            PathEl::ClosePath => {
                out.close_path();
                at = start;
                open = false;
            }
        }
    }
    if open {
        out.close_path();
    }
    out
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
    if all.elements().is_empty() {
        return None;
    }
    let bounds = kurbo::Shape::bounding_box(&all);
    Some((quadratic(&all), bounds.x0, bounds.x1))
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

    #[test]
    fn points_on_top_of_each_other_are_thinned_but_the_last_stays() {
        let t = thin(
            &[[0.0, 0.0], [0.5, 0.0], [1.0, 0.0], [10.0, 0.0], [10.5, 0.0]],
            2.0,
        );
        assert_eq!(t, vec![[0.0, 0.0], [10.0, 0.0], [10.5, 0.0]]);
    }
}
