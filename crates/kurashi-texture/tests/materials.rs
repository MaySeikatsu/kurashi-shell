//! Acceptance for the materials (W31, K59): every kind, tinted and plain, with and without wrinkles, is deterministic and
//! seamless at its edges, averages near the flat value, carries no ink when the tint is off, prints its rulings at their
//! pitch, and is generated within the frame budget (the timing test is `#[ignore]`: run it with `--release -- --ignored`).

use kurashi_texture::{Kind, Params, Tile, generate, tile_file};

fn params(kind: Kind, tint: bool, wrinkles: f32) -> Params {
    Params {
        kind,
        wrinkles,
        tint,
        device_scale: 1.0,
        cracks: 0.0,
        crack_style: kurashi_texture::CrackStyle::Stone,
    }
}

/// Mean absolute difference of the height-derived channels (R, G, B) between two texels, averaged over the channels.
fn diff(a: [u8; 4], b: [u8; 4]) -> f32 {
    (0..3)
        .map(|c| (f32::from(a[c]) - f32::from(b[c])).abs())
        .sum::<f32>()
        / 3.0
}

/// The wrap seam against the interior, per axis: the mean difference across the edge the tile wraps at, over the mean
/// difference between interior neighbour columns (x) and rows (y). A seamless tile gives a ratio near 1.
fn seam_ratios(t: &Tile) -> (f32, f32) {
    let n = t.size;
    let px = |x: u32, y: u32| t.texel(x, y);
    let mut seam_x = 0.0;
    let mut seam_y = 0.0;
    for k in 0..n {
        seam_x += diff(px(n - 1, k), px(0, k));
        seam_y += diff(px(k, n - 1), px(k, 0));
    }
    let mut inner_x = 0.0;
    let mut inner_y = 0.0;
    for x in 0..n - 1 {
        for y in 0..n {
            inner_x += diff(px(x, y), px(x + 1, y));
            inner_y += diff(px(y, x), px(y, x + 1));
        }
    }
    let interior = ((n - 1) * n) as f32;
    (
        (seam_x / n as f32) / (inner_x / interior).max(1e-6),
        (seam_y / n as f32) / (inner_y / interior).max(1e-6),
    )
}

/// Every kind and variant the tests cover: tinted and plain, wrinkles 0 and 0.6.
fn variants() -> Vec<Params> {
    let mut v = Vec::new();
    for kind in Kind::ALL {
        for tint in [true, false] {
            for wrinkles in [0.0, 0.6] {
                v.push(params(kind, tint, wrinkles));
            }
        }
    }
    v
}

#[test]
fn every_variant_is_deterministic() {
    for p in variants() {
        let a = generate(&p);
        let b = generate(&p);
        assert!(
            a == b,
            "{:?} tint {} wrinkles {} is not deterministic",
            p.kind,
            p.tint,
            p.wrinkles
        );
    }
}

#[test]
fn every_variant_wraps_seamlessly() {
    let mut failures = Vec::new();
    for p in variants() {
        let t = generate(&p);
        let (rx, ry) = seam_ratios(&t);
        if rx > 1.5 || ry > 1.5 {
            failures.push(format!(
                "{:?} tint {} wrinkles {}: seam ratio x {rx:.2}, y {ry:.2}",
                p.kind, p.tint, p.wrinkles
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "seams over 1.5x the interior:\n{}",
        failures.join("\n")
    );
}

#[test]
fn every_variant_averages_near_the_flat_value() {
    for p in variants() {
        let t = generate(&p);
        let count = t.rgba.len() as f32 / 4.0;
        for c in 0..3 {
            let mean = t
                .rgba
                .chunks_exact(4)
                .map(|px| f32::from(px[c]))
                .sum::<f32>()
                / count;
            assert!(
                (mean - 128.0).abs() <= 6.0,
                "{:?} tint {} wrinkles {}: channel {c} averages {mean:.1}, not near 128",
                p.kind,
                p.tint,
                p.wrinkles
            );
        }
    }
}

#[test]
fn tint_off_carries_no_ink() {
    for kind in Kind::ALL {
        for wrinkles in [0.0, 0.6] {
            let t = generate(&params(kind, false, wrinkles));
            assert!(
                t.rgba.chunks_exact(4).all(|px| px[3] == 0),
                "{kind:?} with the tint off has ink (wrinkles {wrinkles})"
            );
        }
    }
}

#[test]
fn tint_on_prints_ink_only_where_the_material_has_some() {
    for kind in Kind::ALL {
        let t = generate(&params(kind, true, 0.0));
        let inked = t.rgba.chunks_exact(4).filter(|px| px[3] > 0).count();
        let has_ink = !matches!(kind, Kind::Wool | Kind::Metal | Kind::Leather);
        assert_eq!(inked > 0, has_ink, "{kind:?}: {inked} inked texels");
    }
}

#[test]
fn rulings_sit_at_their_pitch() {
    let n = 480usize;
    // Lines (and the lines of the grid): a 1 px line centred on 12 + 24k, so rows 11 and 12 of each pitch cell carry half
    // coverage each and every other row none.
    let lines = generate(&params(Kind::PaperLines, true, 0.0));
    let grid = generate(&params(Kind::PaperGrid, true, 0.0));
    for y in 0..n {
        let on = matches!(y % 24, 11 | 12);
        for x in [0usize, 7, 100, 333] {
            let a = lines.texel(x as u32, y as u32)[3];
            if on {
                assert!((120..=136).contains(&a), "lines row {y}: A {a}");
            } else {
                assert_eq!(a, 0, "lines row {y} off the ruling: A {a}");
            }
            let g = grid.texel(x as u32, y as u32)[3];
            let col_on = matches!(x % 24, 11 | 12);
            if on || col_on {
                assert!((120..=136).contains(&g), "grid ({x},{y}): A {g}");
            } else {
                assert_eq!(g, 0, "grid ({x},{y}) off the rulings: A {g}");
            }
        }
    }
    // Dots: a 2.2 px dot centred on each crossing (12 + 24i, 12 + 24j), full at its centre texels and empty between.
    let dots = generate(&params(Kind::PaperDots, true, 0.0));
    for j in 0..20 {
        for i in 0..20 {
            let (x, y) = (24 * i + 11, 24 * j + 11);
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let a = dots.texel((x + dx) as u32, (y + dy) as u32)[3];
                assert!(a >= 217, "dot ({}, {}): A {a}", x + dx, y + dy);
            }
            assert_eq!(
                dots.texel((x + 6) as u32, (y + 6) as u32)[3],
                0,
                "between dots at {x},{y}"
            );
        }
    }
}

#[test]
fn wrinkles_add_relief_and_zero_adds_nothing() {
    let flat = generate(&params(Kind::Paper, false, 0.0));
    let creased = generate(&params(Kind::Paper, false, 0.6));
    assert!(flat != creased, "wrinkles 0.6 changed nothing");
    // Zero is the base: the same bytes as a request without wrinkles at all.
    assert!(generate(&params(Kind::Paper, false, 0.0)) == flat);
}

#[test]
fn device_scale_scales_the_tile_and_keeps_its_logical_size() {
    for (scale, side) in [
        (1.0f32, 480u32),
        (1.5, 720),
        (2.0, 960),
        (2.5, 960),
        (4.0, 960),
    ] {
        let t = generate(&Params {
            kind: Kind::PaperDots,
            wrinkles: 0.0,
            tint: true,
            device_scale: scale,
            cracks: 0.0,
            crack_style: kurashi_texture::CrackStyle::Stone,
        });
        assert_eq!(t.size, side, "device scale {scale}");
        assert!(
            (t.logical * scale - t.size as f32).abs() < 1.0,
            "scale {scale}: logical {}",
            t.logical
        );
    }
}

#[test]
fn tile_files_are_loaded_from_the_cache_once_written() {
    let dir = tempfile::tempdir().unwrap();
    let p = params(Kind::Wood, true, 0.3);
    let (path, first) = tile_file(dir.path(), &p).unwrap();
    let written = std::fs::metadata(&path).unwrap().modified().unwrap();
    let (again, second) = tile_file(dir.path(), &p).unwrap();
    assert_eq!(path, again);
    assert!(
        first == second,
        "a cached tile differs from the generated one"
    );
    assert_eq!(
        std::fs::metadata(&path).unwrap().modified().unwrap(),
        written,
        "the cache was rewritten"
    );
}

/// FNV-1a over the tile's bytes: a checksum that does not change between Rust releases, unlike `DefaultHasher`.
fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325u64, |h, b| {
        (h ^ u64::from(*b)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// The ruled papers, the halftone, the leather and the stone were not changed by W31: their tiles keep the bytes the
/// generator made before it (checked against that commit). A change to the shared noise or the notebook sheet shows here.
#[test]
fn the_notebook_print_and_pebble_kinds_keep_their_bytes() {
    let golden = [
        (Kind::PaperDots, 0x07fb_17ae_dd5a_7958u64),
        (Kind::PaperLines, 0xc953_e343_ab7c_11cf),
        (Kind::PaperGrid, 0x80e9_1410_a94c_4d90),
        (Kind::Halftone, 0x4afa_1e18_b1ac_6b08),
        (Kind::Leather, 0x5b17_95c3_476a_2b98),
        (Kind::Stone, 0xa2e3_6515_052c_e072),
    ];
    for (kind, want) in golden {
        let got = fnv1a(&generate(&params(kind, true, 0.0)).rgba);
        assert_eq!(
            got, want,
            "{kind:?} no longer generates the bytes it had before W31"
        );
    }
}

/// Generation time per tile at device scale 1 (the card's budget: ≤ 300 ms in release, with wrinkles).
#[test]
#[ignore = "timing: run with --release -- --ignored"]
fn a_tile_generates_within_the_budget() {
    for kind in Kind::ALL {
        let p = params(kind, true, 0.6);
        let start = std::time::Instant::now();
        let t = generate(&p);
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        println!("{:<12} {ms:7.1} ms", kind.name());
        assert_eq!(t.size, 480);
        assert!(ms <= 300.0, "{kind:?} took {ms:.0} ms (budget 300 ms)");
    }
}

/// The oil paint (W31): its strokes cover part of the tile and leave the canvas showing between them, its seams are as tight
/// as the other materials', and its bytes are pinned, so a change to the generator is a conscious one.
#[test]
fn paint_covers_the_tile_edge_to_edge_and_wraps_tightly() {
    for wrinkles in [0.0, 0.6] {
        let t = generate(&params(Kind::Paint, true, wrinkles));
        let (rx, ry) = seam_ratios(&t);
        assert!(
            rx <= 1.35 && ry <= 1.35,
            "paint seam x {rx:.2} y {ry:.2} (wrinkles {wrinkles})"
        );
        // Bare canvas is where the pigment is almost absent (A < 64: under a quarter of the paint's full tone).
        let bare = t.rgba.chunks_exact(4).filter(|px| px[3] < 64).count() as f32
            / (t.size * t.size) as f32;
        assert!(
            bare <= 0.15,
            "paint leaves {bare:.3} of the tile bare (wrinkles {wrinkles})"
        );
    }
}

#[test]
fn paint_keeps_its_bytes() {
    let plain = fnv1a(&generate(&params(Kind::Paint, true, 0.0)).rgba);
    let creased = fnv1a(&generate(&params(Kind::Paint, true, 0.6)).rgba);
    assert_eq!(plain, 0xb7fd_c114_a8e2_1f31, "paint (wrinkles 0) changed");
    assert_eq!(
        creased, 0x70d0_1f26_8022_b827,
        "paint (wrinkles 0.6) changed"
    );
}
