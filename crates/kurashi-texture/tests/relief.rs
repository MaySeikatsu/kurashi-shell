//! Acceptance for wave 32 (K61, W32-texture-gen): the brush, the cracks in both styles, the height map and its relief, and
//! the parallel generator (I171) giving the same bytes as one thread.

use kurashi_texture::{CrackStyle, Kind, Params, Tile, generate, generate_threads};

fn params(kind: Kind, cracks: f32, style: CrackStyle) -> Params {
    Params {
        kind,
        wrinkles: 0.0,
        tint: true,
        device_scale: 1.0,
        cracks,
        crack_style: style,
    }
}

/// The wrap seam against the interior (R, G, B), the larger of the two axes: the mean difference across the edge the tile
/// wraps at over the largest such difference between two neighbouring interior columns (rows). A seam stands out above
/// every interior line (ratio > 1); a crack that happens to run along the edge does not, since one runs along some
/// interior line as well.
fn seam(t: &Tile) -> f32 {
    let n = t.size;
    let d = |a: [u8; 4], b: [u8; 4]| {
        (0..3)
            .map(|c| (f32::from(a[c]) - f32::from(b[c])).abs())
            .sum::<f32>()
    };
    let line = |a: u32, b: u32, cols: bool| {
        (0..n)
            .map(|k| {
                if cols {
                    d(t.texel(a, k), t.texel(b, k))
                } else {
                    d(t.texel(k, a), t.texel(k, b))
                }
            })
            .sum::<f32>()
    };
    [true, false]
        .map(|cols| {
            let inner = (0..n - 1)
                .map(|a| line(a, a + 1, cols))
                .fold(1e-6, f32::max);
            line(n - 1, 0, cols) / inner
        })
        .into_iter()
        .fold(0.0, f32::max)
}

#[test]
fn many_threads_make_the_bytes_of_one() {
    for kind in Kind::ALL {
        for (cracks, style) in [
            (0.0, CrackStyle::Stone),
            (0.5, CrackStyle::Stone),
            (0.5, CrackStyle::Glass),
        ] {
            let p = Params {
                wrinkles: 0.3,
                ..params(kind, cracks, style)
            };
            assert!(
                generate_threads(&p, 1) == generate_threads(&p, 7),
                "{kind:?} cracks {cracks} {style:?}: 7 threads differ from 1"
            );
        }
    }
}

#[test]
fn every_kind_cracks_in_both_styles_seamlessly_and_deterministically() {
    for kind in Kind::ALL {
        let plain = generate(&params(kind, 0.0, CrackStyle::Stone));
        // Zero cracks are no cracks, whatever the style.
        assert!(
            plain == generate(&params(kind, 0.0, CrackStyle::Glass)),
            "{kind:?}: cracks 0 depends on the style"
        );
        for style in [CrackStyle::Stone, CrackStyle::Glass] {
            let p = params(kind, 0.5, style);
            let t = generate(&p);
            assert!(t == generate(&p), "{kind:?} {style:?} is not deterministic");
            assert!(t != plain, "{kind:?} {style:?}: cracks 0.5 changed nothing");
            let r = seam(&t);
            assert!(r <= 1.0, "{kind:?} {style:?}: seam ratio {r:.2}");
            assert!(
                t.rgba
                    .chunks_exact(4)
                    .zip(plain.rgba.chunks_exact(4))
                    .all(|(a, b)| a[3] == b[3]),
                "{kind:?} {style:?}: the cracks changed the ink"
            );
        }
    }
}

#[test]
fn every_kind_has_heights_and_a_plausible_relief() {
    for kind in Kind::ALL {
        for (cracks, style) in [
            (0.0, CrackStyle::Stone),
            (0.5, CrackStyle::Stone),
            (0.5, CrackStyle::Glass),
        ] {
            let t = generate(&params(kind, cracks, style));
            assert_eq!(t.height.len(), (t.size * t.size) as usize);
            assert!(
                t.relief > 0.05 && t.relief < 16.0,
                "{kind:?} cracks {cracks} {style:?}: relief {}",
                t.relief
            );
            // Percentile-normalised: the map spans its range and is not crushed against either end by a spike.
            let lo = t.height.iter().filter(|h| **h == 0).count() as f32;
            let hi = t.height.iter().filter(|h| **h == 255).count() as f32;
            let len = t.height.len() as f32;
            assert!(
                lo > 0.0 && hi > 0.0,
                "{kind:?}: the heights do not span 0..255"
            );
            assert!(
                lo / len < 0.02 && hi / len < 0.02,
                "{kind:?}: clipped {lo} / {hi}"
            );
            let mean = t.height.iter().map(|h| f32::from(*h)).sum::<f32>() / len;
            assert!(
                (20.0..235.0).contains(&mean),
                "{kind:?}: mean height {mean:.0}"
            );
        }
    }
    // The order of the materials' depth: paper is a fraction of a px, paint and brush a few px, cracks deepen any.
    let relief = |k: Kind| generate(&params(k, 0.0, CrackStyle::Stone)).relief;
    assert!(
        relief(Kind::PaperDots) < 1.0,
        "paper_dots {}",
        relief(Kind::PaperDots)
    );
    assert!(relief(Kind::Paper) < 1.2, "paper {}", relief(Kind::Paper));
    for k in [Kind::Paint, Kind::Brush] {
        assert!((2.0..8.0).contains(&relief(k)), "{k:?} {}", relief(k));
    }
    for style in [CrackStyle::Stone, CrackStyle::Glass] {
        let cracked = generate(&params(Kind::PaperDots, 0.5, style)).relief;
        assert!(
            cracked > relief(Kind::PaperDots) * 1.5,
            "{style:?} {cracked}"
        );
    }
}

/// The brush covers the whole sheet: no bare canvas between the strokes (the pigment is nearly everywhere), and it wraps
/// as tightly as the paint.
#[test]
fn the_brush_covers_the_sheet_and_wraps_tightly() {
    for wrinkles in [0.0, 0.6] {
        let t = generate(&Params {
            wrinkles,
            ..params(Kind::Brush, 0.0, CrackStyle::Stone)
        });
        let r = seam(&t);
        assert!(r <= 1.0, "brush seam {r:.2} (wrinkles {wrinkles})");
        let bare = t.rgba.chunks_exact(4).filter(|px| px[3] < 64).count() as f32
            / (t.size * t.size) as f32;
        assert!(bare <= 0.01, "brush leaves {bare:.4} of the tile bare");
    }
}
