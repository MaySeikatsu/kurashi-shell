use std::path::PathBuf;
use std::sync::Arc;

use kurashi_theme::color::{Rgb, contrast};
use kurashi_theme::season::{Date, solar_term, warmth};
use kurashi_theme::stages::{self, aa_pairs, machado, simulate};
use kurashi_theme::*;

fn fonts() -> FakeFonts {
    FakeFonts::new(&["Inter", "Noto Sans CJK JP"])
}

fn input(name: &str, scheme: Scheme) -> ThemeInput {
    ThemeInput {
        source: Source::Palette(name.into()),
        scheme,
        ..Default::default()
    }
}

fn golden(name: &str, tokens: &TokenMap) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(name);
    let actual = serde_json::to_string_pretty(tokens).unwrap() + "\n";
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        std::fs::write(&path, actual).unwrap();
        return;
    }
    let want = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| panic!("missing {} (run with UPDATE_GOLDEN=1)", path.display()));
    assert_eq!(
        want, actual,
        "golden mismatch for {name}; UPDATE_GOLDEN=1 to regenerate"
    );
}

#[test]
fn golden_wa_iro_dark() {
    golden(
        "wa-iro-dark.json",
        &resolve(&input("wa-iro", Scheme::Dark), &fonts())
            .unwrap()
            .tokens,
    );
}

#[test]
fn golden_wa_iro_light() {
    golden(
        "wa-iro-light.json",
        &resolve(&input("wa-iro", Scheme::Light), &fonts())
            .unwrap()
            .tokens,
    );
}

#[test]
fn every_palette_scheme_contrast_passes_aa_after_wcag() {
    let sources = [
        Colorblind::None,
        Colorblind::Protanopia,
        Colorblind::Deuteranopia,
        Colorblind::Tritanopia,
    ];
    for name in bundled_names() {
        for scheme in [Scheme::Dark, Scheme::Light] {
            for level in [
                ContrastLevel::Standard,
                ContrastLevel::Medium,
                ContrastLevel::High,
            ] {
                for cb in sources {
                    for oled in [false, true] {
                        let mut i = input(name, scheme);
                        i.contrast = level;
                        i.colorblind = cb;
                        i.oled = oled;
                        i.season = Some(Date::new(2026, 7, 25));
                        let (p, _) = resolve_palette(&i).unwrap();
                        for (fg, bg, min) in aa_pairs() {
                            let r = contrast(p.get(fg), p.get(bg));
                            assert!(
                                r >= min,
                                "{name} {scheme:?} {level:?} {cb:?} oled={oled}: {fg}/{bg} = {r:.2} < {min}"
                            );
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn wcag_reports_what_it_changed() {
    let mut i = input("wa-iro", Scheme::Dark);
    i.source = Source::PaletteToml(
        r##"name = "t"
[dark]
surface = "#1b1a1e"
on_surface = "#e9e4d8"
accent = "#c9404b"
secondary = "#5b7fa6"
tertiary = "#8fa868"
warning = "#e0a33b"
on_accent = "#f0e0e0"
"##
        .into(),
    );
    let out = resolve(&i, &fonts()).unwrap();
    let n = out
        .notes
        .iter()
        .find(|n| n.stage == "wcag" && n.text.contains("on_accent"))
        .expect("on_accent fixed");
    assert!(n.text.contains("#f0e0e0 →"), "{}", n.text);
    // And with the stage off nothing is touched.
    i.wcag = false;
    let off = resolve(&i, &fonts()).unwrap();
    assert_eq!(off.tokens["color.on_accent"], "#f0e0e0");
}

#[test]
fn outline_frames_containers_at_ui_contrast() {
    // Cards, the lock box and the stage are outlined on surface_container (UX review R.2 item 5).
    assert!(aa_pairs().contains(&("outline", "surface_container", stages::UI)));
    for scheme in [Scheme::Dark, Scheme::Light] {
        let p = resolve_palette(&input("wa-iro", scheme)).unwrap().0;
        let r = contrast(p.get("outline"), p.get("surface_container"));
        assert!(
            r >= stages::UI,
            "wa-iro {scheme:?}: outline on surface_container {r:.2}"
        );
    }
}

#[test]
fn tokens_contain_every_mock_theme_doc_key() {
    let src = include_str!("../../kurashi-mock/src/documents.rs");
    let start = src
        .find("pub fn theme()")
        .expect("theme() in mock documents");
    // The body ends where the next top-level fn begins.
    let body = &src[start
        ..src[start + 1..]
            .find("\npub fn ")
            .map_or(src.len(), |e| start + 1 + e)];
    let mut keys = vec![];
    let b = body.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'"' {
            if let Some(end) = body[i + 1..].find('"') {
                let s = &body[i + 1..i + 1 + end];
                if body[i + 2 + end..].starts_with(':') && s != "tokens" {
                    keys.push(s.to_string());
                }
                i += end + 2;
                continue;
            }
        }
        i += 1;
    }
    assert!(keys.len() > 25, "key scan broke: {keys:?}");
    let out = resolve(&ThemeInput::default(), &fonts()).unwrap();
    for k in keys {
        assert!(out.tokens.contains_key(&k), "missing token {k}");
    }
}

#[test]
fn machado_matrix_sanity() {
    for k in [
        Colorblind::Protanopia,
        Colorblind::Deuteranopia,
        Colorblind::Tritanopia,
    ] {
        let m = machado(k).unwrap();
        for row in m {
            let s: f64 = row.iter().sum();
            assert!((s - 1.0).abs() < 1e-5, "{k:?} row sums to {s}");
        }
        // Greys and white are invariant.
        for c in [Rgb(0, 0, 0), Rgb(128, 128, 128), Rgb(255, 255, 255)] {
            let s = simulate(c, k);
            for (a, b) in [(s.0, c.0), (s.1, c.1), (s.2, c.2)] {
                assert!(a.abs_diff(b) <= 1, "{k:?} moved grey {c} -> {s}");
            }
        }
    }
    // A protanope sees pure red as dark yellowish-brown: far less red, some green.
    let r = simulate(Rgb(255, 0, 0), Colorblind::Protanopia);
    assert!(r.0 < 150 && r.1 > 0);
    assert_eq!(machado(Colorblind::None), None);
}

#[test]
fn daltonize_changes_chroma_roles_only() {
    let mut i = input("wa-iro", Scheme::Dark);
    let base = resolve_palette(&i).unwrap().0;
    i.colorblind = Colorblind::Deuteranopia;
    i.wcag = false;
    let cb = resolve_palette(&i).unwrap().0;
    assert_eq!(base.get("surface"), cb.get("surface"));
    assert_ne!(base.get("success"), cb.get("success"));
}

#[test]
fn season_is_deterministic_and_off_by_default() {
    let d = Date::new(2026, 2, 4);
    assert_eq!(solar_term(d).ja, "立春");
    assert_eq!(solar_term(Date::new(2026, 1, 3)).ja, "冬至");
    assert_eq!(solar_term(Date::new(2026, 7, 22)).ja, "小暑");
    assert_eq!(solar_term(Date::new(2026, 12, 31)).ja, "冬至");
    assert!(warmth(solar_term(Date::new(2026, 7, 23))) > 0.95);
    assert!(warmth(solar_term(Date::new(2026, 1, 20))) < -0.95);

    let base = input("wa-iro", Scheme::Dark);
    let mut a = base.clone();
    a.season = Some(Date::new(2026, 7, 23));
    let (p1, n1) = resolve_palette(&a).unwrap();
    let (p2, n2) = resolve_palette(&a).unwrap();
    assert_eq!(p1, p2);
    assert_eq!(n1, n2);
    assert!(
        n1.iter()
            .any(|n| n.stage == "season" && n.text.contains("大暑"))
    );

    let (off, offn) = resolve_palette(&base).unwrap();
    assert!(offn.iter().any(|n| n.text == "season: off"));
    assert_ne!(off, p1, "season must change something");
    let mut w = base;
    w.season = Some(Date::new(2026, 1, 20));
    assert_ne!(
        resolve_palette(&w).unwrap().0,
        p1,
        "winter differs from summer"
    );
}

#[test]
fn wallpaper_source_via_material_colors() {
    // 16x16: 3/4 teal, 1/4 grey.
    let mut rgba = vec![];
    for i in 0..256 {
        rgba.extend_from_slice(if i % 4 == 3 {
            &[128, 128, 128, 255]
        } else {
            &[0x1a, 0x9e, 0x8f, 255]
        });
    }
    let w = Wallpaper {
        width: 16,
        height: 16,
        rgba,
    };
    for scheme in [Scheme::Dark, Scheme::Light] {
        let i = ThemeInput {
            source: Source::Wallpaper(w.clone()),
            scheme,
            ..Default::default()
        };
        let out = resolve(&i, &fonts()).unwrap();
        let (h, s, _) = out.palette.get("accent").to_hsl();
        assert!(
            (140.0..200.0).contains(&h) && s > 0.1,
            "accent hue {h} sat {s} not teal-ish"
        );
        assert!(
            out.notes
                .iter()
                .any(|n| n.text.starts_with("source: wallpaper"))
        );
        for (fg, bg, min) in aa_pairs() {
            assert!(
                contrast(out.palette.get(fg), out.palette.get(bg)) >= min,
                "{fg}/{bg}"
            );
        }
    }
    let bad = Wallpaper {
        width: 4,
        height: 4,
        rgba: vec![0; 3],
    };
    assert!(stages::from_wallpaper(&bad).is_err());
}

/// A 64 px picture on disk, one colour per pixel column or row as `px` says.
fn write_picture(dir: &std::path::Path, name: &str, px: impl Fn(u32, u32) -> [u8; 3]) -> PathBuf {
    let path = dir.join(name);
    image::RgbImage::from_fn(64, 64, |x, y| image::Rgb(px(x, y)))
        .save(&path)
        .unwrap();
    path
}

fn scratch_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("kurashi-theme-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// The `wallpaper` source from picture files: each fixture's accent follows its own hue, in both
/// schemes, and the AA pairs hold whatever the picture is.
#[test]
fn wallpaper_file_gives_a_palette_from_fixture_pictures() {
    let dir = scratch_dir("fixtures");
    let teal = write_picture(&dir, "teal.png", |x, _| {
        if x % 4 == 3 {
            [128, 128, 128]
        } else {
            [0x1a, 0x9e, 0x8f]
        }
    });
    let red = write_picture(&dir, "red.png", |x, _| {
        if x < 40 {
            [0xc8, 0x28, 0x28]
        } else {
            [0xe0, 0x7a, 0x30]
        }
    });
    // Each picture's accent hue must fall in its family.
    type HueFamily = fn(f64) -> bool;
    let teal_family: HueFamily = |h| (140.0..200.0).contains(&h);
    let red_family: HueFamily = |h| !(40.0..340.0).contains(&h);
    let fixtures = [(teal, teal_family), (red, red_family)];
    for scheme in [Scheme::Dark, Scheme::Light] {
        for (path, hue_ok) in &fixtures {
            let i = ThemeInput {
                source: Source::WallpaperFile(path.clone()),
                scheme,
                ..Default::default()
            };
            let out = resolve(&i, &fonts()).unwrap();
            let (h, s, _) = out.palette.get("accent").to_hsl();
            assert!(
                hue_ok(h) && s > 0.1,
                "{}: accent hue {h:.0} sat {s:.2}",
                path.display()
            );
            assert!(
                out.notes
                    .iter()
                    .any(|n| n.text.starts_with("source: wallpaper")
                        && n.text.contains("seed colour")),
                "the provenance names the picture's seed"
            );
            for (fg, bg, min) in aa_pairs() {
                assert!(
                    contrast(out.palette.get(fg), out.palette.get(bg)) >= min,
                    "{fg}/{bg}"
                );
            }
        }
    }
}

/// A picture without colour has no scheme to build: the palette in effect is `wa-iro`, and the
/// provenance says so (Shōjiki), instead of Material's fallback blue.
#[test]
fn a_monochrome_picture_falls_back_to_wa_iro_and_says_so() {
    let dir = scratch_dir("mono");
    let grey = write_picture(&dir, "grey.png", |x, _| {
        let v = (x * 255 / 63) as u8;
        [v, v, v]
    });
    let i = ThemeInput {
        source: Source::WallpaperFile(grey),
        ..Default::default()
    };
    let (palette, notes) = resolve_palette(&i).unwrap();
    assert_eq!(palette.name, "wa-iro", "the name is the palette in effect");
    assert!(
        notes
            .iter()
            .any(|n| n.text.contains("monochrome") && n.text.contains("wa-iro")),
        "{notes:?}"
    );
    assert_eq!(
        palette,
        resolve_palette(&input("wa-iro", Scheme::Dark)).unwrap().0
    );
}

/// The extraction is cached by path, mtime and size: a second request is the same value, and an
/// edited picture (new mtime) is extracted again.
#[test]
fn wallpaper_file_is_extracted_once_per_path_mtime_and_size() {
    let dir = scratch_dir("cache");
    let p = write_picture(&dir, "a.png", |_, _| [200, 40, 40]);
    let first = stages::wallpaper_file(&p).unwrap();
    let again = stages::wallpaper_file(&p).unwrap();
    assert!(
        Arc::ptr_eq(&first, &again),
        "same path, mtime and size: cached"
    );
    write_picture(&dir, "a.png", |_, _| [40, 40, 200]);
    let later = std::time::SystemTime::now() + std::time::Duration::from_secs(60);
    std::fs::File::options()
        .write(true)
        .open(&p)
        .unwrap()
        .set_modified(later)
        .unwrap();
    let edited = stages::wallpaper_file(&p).unwrap();
    assert!(
        !Arc::ptr_eq(&first, &edited),
        "a new mtime is a new extraction"
    );
    assert_ne!(first.seed, edited.seed);
}

#[test]
fn an_unreadable_picture_is_an_error_not_a_panic() {
    let dir = scratch_dir("bad");
    assert!(matches!(
        stages::wallpaper_file(&dir.join("gone.png")),
        Err(ThemeError::Image(_))
    ));
    let junk = dir.join("junk.png");
    std::fs::write(&junk, b"not a picture").unwrap();
    assert!(matches!(
        stages::wallpaper_file(&junk),
        Err(ThemeError::Image(_))
    ));
}

/// I27: the warn role is text-grade (4.5:1) on the surface, in every palette and scheme.
#[test]
fn status_warn_is_aa_text_on_the_surface() {
    for name in bundled_names() {
        for scheme in [Scheme::Dark, Scheme::Light] {
            let t = resolve(&input(name, scheme), &fonts()).unwrap().tokens;
            let c = |k: &str| Rgb::parse(t[k].as_str().unwrap()).unwrap();
            let r = contrast(c("color.status.warn"), c("color.surface"));
            assert!(r >= 4.5, "{name} {scheme:?}: color.status.warn = {r:.2}");
        }
    }
}

#[test]
fn axes_scales() {
    let mut i = ThemeInput::default();
    i.axes.shape = Shape::None;
    i.axes.motion = MotionProfile::None;
    i.axes.density = Density::Compact;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["radius.md"], 0);
    assert_eq!(t["radius.full"], 0);
    assert_eq!(t["radius.circle"], 999);
    assert_eq!(t["motion.standard_ms"], 0);
    assert_eq!(t["space.md"], 9);
    assert!(t["control.height"].as_i64().unwrap() >= 32);

    let mut i = ThemeInput::default();
    i.axes.motion_speed = 2.0;
    i.axes.motion = MotionProfile::Calm;
    i.axes.radius = 27.0;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["motion.standard_ms"], 110);
    assert_eq!(t["radius.md"], 18);
    assert_eq!(
        t["motion.easing.enter"],
        serde_json::json!([0.05, 0.7, 0.1, 1.0])
    );

    i.axes.material = Material::Solid;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["color.surface_alpha"], 1.0);
    assert_eq!(t["blur"], false);
}

/// I300: `shape.squircle_k` maps `theme.shape.squircle` 0..1 onto 0.5523..0.98; the default is today's 0.88.
#[test]
fn squircle_k_follows_the_curve_setting() {
    let mut i = ThemeInput::default();
    for (v, k) in [(0.0, 0.5523), (0.5, 0.7662), (0.77, 0.8816), (1.0, 0.98)] {
        i.axes.squircle = v;
        let t = resolve(&i, &fonts()).unwrap().tokens;
        assert_eq!(t["shape.squircle_k"], serde_json::json!(k), "squircle {v}");
    }
    // Emitted under every corner style (the frontend reads it only under squircle).
    i.axes.squircle = 0.77;
    for shape in [Shape::None, Shape::Rounded, Shape::Squircle] {
        i.axes.shape = shape;
        let t = resolve(&i, &fonts()).unwrap().tokens;
        assert_eq!(t["shape.squircle_k"], serde_json::json!(0.8816));
    }
    assert_eq!(ThemeInput::default().axes.squircle, 0.77);
    assert!((tokens::squircle_k(0.77) - 0.88).abs() < 0.005);
}

/// I303: `frame.outline` is the chrome's own default under `auto` (keycap and line on, flat and soft off), else the
/// setting.
#[test]
fn frame_outline_per_chrome_and_setting() {
    let mut i = ThemeInput::default();
    for (chrome, auto) in [
        (Chrome::Flat, false),
        (Chrome::Keycap, true),
        (Chrome::Soft, false),
        (Chrome::Line, true),
    ] {
        i.axes.chrome = chrome;
        for (setting, want) in [
            (FrameOutline::Auto, auto),
            (FrameOutline::On, true),
            (FrameOutline::Off, false),
        ] {
            i.axes.frame_outline = setting;
            let t = resolve(&i, &fonts()).unwrap().tokens;
            assert_eq!(t["frame.outline"], want, "{chrome:?} × {setting:?}");
        }
    }
}

/// I297: translucent blurs when the switch is on (what glass did), never without it; solid never blurs.
#[test]
fn translucent_blurs_only_with_the_switch() {
    let mut i = ThemeInput::default();
    i.axes.material = Material::Translucent;
    i.axes.opacity = 0.6;
    for blur in [true, false] {
        i.axes.blur = blur;
        let t = resolve(&i, &fonts()).unwrap().tokens;
        assert_eq!(t["blur"], blur);
        assert_eq!(t["color.surface_alpha"], 0.6);
    }
    i.axes.material = Material::Solid;
    i.axes.blur = true;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["blur"], false);
}

#[test]
fn oled_and_overrides() {
    let mut i = input("wa-iro", Scheme::Dark);
    i.oled = true;
    i.overrides
        .insert("popup.bg".into(), serde_json::json!("#101010"));
    let out = resolve(&i, &fonts()).unwrap();
    assert_eq!(out.tokens["color.surface"], "#000000");
    assert_eq!(out.tokens["bar.bg"], "#000000");
    assert_eq!(out.tokens["popup.bg"], "#101010");
    assert!(out.notes.iter().any(|n| n.stage == "override"));
    i.overrides
        .insert("nope.bg".into(), serde_json::json!("#000"));
    assert!(matches!(
        resolve(&i, &fonts()),
        Err(ThemeError::UnknownOverride(_))
    ));
}

#[test]
fn component_pairs_meet_aa() {
    for name in bundled_names() {
        for scheme in [Scheme::Dark, Scheme::Light] {
            let t = resolve(&input(name, scheme), &fonts()).unwrap().tokens;
            let c = |k: &str| Rgb::parse(t[k].as_str().unwrap()).unwrap();
            for (fg, bg) in [
                ("bar.fg", "bar.bg"),
                ("island.fg", "island.bg"),
                ("popup.fg", "popup.bg"),
                ("osd.fg", "osd.bg"),
                ("button.fg", "button.bg"),
                ("button.primary.fg", "button.primary.bg"),
                ("button.primary.fg", "button.primary.bg.hover"),
                ("button.primary.fg", "button.primary.bg.pressed"),
                ("tooltip.fg", "tooltip.bg"),
                ("quick.tile.on.fg", "quick.tile.on.bg"),
            ] {
                let r = contrast(c(fg), c(bg));
                assert!(r >= 4.5, "{name} {scheme:?}: {fg}/{bg} = {r:.2}");
            }
        }
    }
}

/// K66 (row 104): a quick tile's on state reads at AA on its container at every contrast level, not only the default.
#[test]
fn quick_tile_on_state_meets_aa_at_every_contrast_level() {
    for name in bundled_names() {
        for scheme in [Scheme::Dark, Scheme::Light] {
            for level in [
                ContrastLevel::Standard,
                ContrastLevel::Medium,
                ContrastLevel::High,
            ] {
                let mut i = input(name, scheme);
                i.contrast = level;
                let t = resolve(&i, &fonts()).unwrap().tokens;
                let c = |k: &str| Rgb::parse(t[k].as_str().unwrap()).unwrap();
                let r = contrast(c("quick.tile.on.fg"), c("quick.tile.on.bg"));
                assert!(
                    r >= 4.5,
                    "{name} {scheme:?} {level:?}: on-state label {r:.2}"
                );
            }
        }
    }
}

/// K25: the mod state marks are graphics, so each reaches 3:1 on the surface, in every palette
/// and scheme (the `color.status.*` tokens are derived, not palette roles).
#[test]
fn status_marks_reach_3_to_1_on_the_surface() {
    for name in bundled_names() {
        for scheme in [Scheme::Dark, Scheme::Light] {
            let t = resolve(&input(name, scheme), &fonts()).unwrap().tokens;
            let c = |k: &str| Rgb::parse(t[k].as_str().unwrap()).unwrap();
            for mark in ["color.status.on", "color.status.off"] {
                let r = contrast(c(mark), c("color.surface"));
                assert!(r >= 3.0, "{name} {scheme:?}: {mark} = {r:.2}");
            }
        }
    }
}

#[test]
fn fonts_resolve_first_installed() {
    let mut i = ThemeInput::default();
    i.axes.font_chain = vec!["Missing Sans".into(), "Inter".into()];
    let out = resolve(&i, &fonts()).unwrap();
    assert_eq!(out.tokens["font.family"], "Inter");
    assert!(
        out.notes
            .iter()
            .any(|n| n.text.contains("Missing Sans not installed"))
    );
    let fc = FcList::from_output(
        "Noto Sans CJK JP,Noto Sans CJK JP Regular\nInter\nDejaVu Sans\\-Mono\n",
    );
    assert!(fc.is_installed("inter") && fc.is_installed("DejaVu Sans-Mono"));
    assert!(!fc.is_installed("Comic Sans"));
}

#[test]
fn bad_palettes_are_rejected() {
    assert!(matches!(
        PaletteSet::from_toml("name='x'\n[dark]\nsurface='#000'"),
        Err(ThemeError::BadColor(_))
    ));
    assert!(matches!(
        PaletteSet::from_toml("name='x'\n[dark]\nbogus='#000000'"),
        Err(ThemeError::UnknownRole(_))
    ));
    let i = ThemeInput {
        source: Source::PaletteToml("name='x'\n[dark]\nsurface='#000000'".into()),
        ..Default::default()
    };
    assert!(matches!(
        resolve_palette(&i),
        Err(ThemeError::MissingRole(_))
    ));
    assert!(matches!(
        bundled("nope"),
        Err(ThemeError::UnknownPalette(_))
    ));
}

#[test]
fn styles_and_looks_change_looks_never_layout() {
    // K45, K53: packs name theme keys only; bar edge/height, desk cards and the island stay the user's.
    use kurashi_theme::appearance::{Kind, all_in, find, layer};
    for kind in [Kind::Look, Kind::Style] {
        for p in all_in(kind, &[]) {
            for (key, _) in &p.recipe {
                assert!(key.starts_with("theme."), "{} sets {key}", p.name);
            }
        }
    }
    let washi = find(Kind::Style, "washi").unwrap();
    let entries = layer(Some(&washi), find(Kind::Look, &washi.look).as_ref());
    assert!(entries.iter().all(|(k, _, _)| k.starts_with("theme.")));
    assert!(find(Kind::Style, "none").is_none());
    let p = style_preview("washi", &fonts()).unwrap();
    assert_eq!(p["look"], "washi");
    assert_eq!(p["category"], "inspired");
    assert!(look_preview("sekai", "kanso", "dark", &fonts()).is_some());
}

#[test]
fn every_chrome_has_its_own_token_set() {
    let mut seen = std::collections::BTreeSet::new();
    for chrome in [
        Chrome::Flat,
        Chrome::Keycap,
        Chrome::Soft,
        Chrome::Line,
        Chrome::Bevel,
    ] {
        let mut i = input("wa-iro", Scheme::Dark);
        i.axes.chrome = chrome;
        let t = resolve(&i, &fonts()).unwrap().tokens;
        for k in [
            "chrome.outline",
            "chrome.ring",
            "chrome.shadow",
            "chrome.soft",
            "chrome.press_scale",
            "chrome.groups",
            "chrome.outline_color",
            "icon.fill",
            "icon.weight",
            "shadow.dx",
            "shadow.dy",
            "shadow.alpha_scale",
        ] {
            assert!(t.contains_key(k), "{chrome:?} lacks {k}");
        }
        // K67: at the defaults the shadow is today's — straight down, the hard shadow's or the soft one's length.
        let n = |k: &str| t[k].as_f64().unwrap();
        assert_eq!(n("shadow.dx"), 0.0, "{chrome:?}");
        assert_eq!(
            n("shadow.dy"),
            n("chrome.shadow").max(n("chrome.soft_dy")),
            "{chrome:?}"
        );
        assert_eq!(n("shadow.alpha_scale"), 1.0, "{chrome:?}");
        seen.insert(t["chrome.style"].as_str().unwrap().to_owned());
        // W53.0a: only the bevel chrome has bevel lines; its colours are always there (a sunken well's).
        assert_eq!(
            n("bevel.width") > 0.0,
            chrome == Chrome::Bevel,
            "{chrome:?}"
        );
        assert_eq!(
            n("bevel.press_offset") > 0.0,
            chrome == Chrome::Bevel,
            "{chrome:?}"
        );
        for k in ["bevel.light", "bevel.light2", "bevel.dark2", "bevel.dark"] {
            assert!(t[k].as_str().unwrap().starts_with('#'), "{chrome:?} {k}");
        }
    }
    assert_eq!(seen.len(), 5);
}

/// W53.0a (K80 amends K42): high contrast keeps a bevel, in the contrast palette's ink, and turns the decorative
/// materials (glow, bloom, sheen) off.
#[test]
fn high_contrast_keeps_the_bevel_in_its_ink_and_drops_glow() {
    let mut i = input("win95", Scheme::Light);
    i.axes.chrome = Chrome::Bevel;
    i.decor.metrics = [
        ("material.glow".to_owned(), serde_json::json!(0.6)),
        ("material.sheen".to_owned(), serde_json::json!(0.4)),
    ]
    .into_iter()
    .collect();
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["bevel.width"], 1);
    assert_eq!(t["glow.strength"], 0.6);
    assert_eq!(t["sheen.strength"], 0.4);
    assert_ne!(t["bevel.light"], t["bevel.dark"]);
    i.contrast = ContrastLevel::High;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["bevel.width"], 1);
    assert_eq!(t["bevel.light"], t["color.on_surface"]);
    assert_eq!(t["bevel.dark"], t["color.on_surface"]);
    assert_ne!(t["bevel.light2"], t["bevel.dark2"]);
    assert_eq!(t["glow.strength"], 0.0);
    assert_eq!(t["sheen.strength"], 0.0);
}

fn decor_of(src: &str) -> Decor {
    use kurashi_theme::appearance::{Kind, parse};
    let p = parse(Kind::Look, src, "x", false).unwrap();
    assert!(p.refused.is_empty(), "{:?}", p.refused);
    p.decor_input()
}

/// W53.0a: `[slots]` and `[decor]` as data — validated against one list, every default filled in, roles published as
/// their colours, nested tables flattened.
#[test]
fn decor_is_validated_data_with_every_default() {
    use kurashi_theme::appearance::{DECOR_KEYS, Kind, SLOTS, parse};
    let p = parse(
        Kind::Look,
        "[slots]\ntitle = \"caption\"\nwings = \"x\"\n[decor]\n\"title.height\" = 18\n\"title.fill\" = [\"title\"]\n\
         \"menu.row\" = 400\n\"focus.style\" = \"sparkly\"\n\"nope\" = 1\n\"tooltip.fill\" = \"info\"\n\
         [decor.scroll]\nwidth = 16\narrows = true\n",
        "x",
        false,
    )
    .unwrap();
    let mut refused = p.refused.clone();
    refused.sort();
    assert_eq!(
        refused,
        [
            "decor.focus.style",
            "decor.menu.row",
            "decor.nope",
            "slots.wings"
        ]
    );
    assert_eq!(p.slots["title"], "caption");
    assert_eq!(p.decor["scroll.width"], 16);
    assert_eq!(p.decor["scroll.arrows"], true);
    // A style carries no decor of its own; a slot name never leaves its directory.
    assert!(parse(Kind::Style, "[decor]\npixel = 2\n", "x", false).is_err());
    assert!(parse(Kind::Look, "[slots]\ntitle = \"../x\"\n", "x", false).is_err());
    let mut i = input("wa-iro", Scheme::Dark);
    i.decor = p.decor_input();
    let t = resolve(&i, &fonts()).unwrap().tokens;
    for s in SLOTS {
        assert!(t.contains_key(&format!("decor.{s}")), "{s}");
    }
    for d in DECOR_KEYS {
        assert!(t.contains_key(&format!("decor.{}", d.key)), "{}", d.key);
    }
    assert_eq!(t["decor.title"], "caption");
    assert_eq!(t["decor.frame"], "");
    assert_eq!(t["decor.title.height"], 18);
    assert_eq!(t["decor.title.fill"], serde_json::json!([t["color.title"]]));
    assert_eq!(t["decor.tooltip.fill"], t["color.info"]);
    // Left out: the defaults (a role default as its colour, "" as "").
    assert_eq!(t["decor.menu.row"], 0);
    assert_eq!(t["decor.tooltip.on"], "");
    assert_eq!(t["decor.border.color"], t["color.outline"]);
    // W53.2: a part's own face resolves to its first installed family, "" without one (the theme's then).
    assert_eq!(t["decor.bar"], "");
    assert_eq!(t["font.title"], "");
    assert_eq!(t["font.start"], "");
    i.decor = decor_of("[decor]\n\"title.family\" = [\"Trebuchet MS\", \"Inter\"]\n\"start.fill\" = [\"secondary\"]\n");
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["font.title"], "Inter");
    assert_eq!(t["decor.start.fill"], serde_json::json!([t["color.secondary"]]));
}

/// W53.0a: the motion personality — a look's own curves and durations, the rubber band, the stepped staircase — and
/// reduce motion (profile none) still wins over all of them.
#[test]
fn motion_styles_curves_and_steps() {
    let mut i = input("wa-iro", Scheme::Dark);
    let k74 = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(k74["motion.kind"], "timed");
    assert_eq!(k74["motion.style"], "grow");
    i.decor = decor_of(
        "[decor]\n\"motion.open_ms\" = 300\n\"motion.open_curve\" = [0.2, 0.0, 0.0, 1.0]\n\"motion.style\" = \"rubber\"\n",
    );
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["motion.timed.open_ms"], 300);
    assert_eq!(
        t["motion.timed.open_curve"],
        serde_json::json!([0.2, 0.0, 0.0, 1.0, 1.0, 1.0])
    );
    assert_eq!(
        t["motion.timed.fast_curve"],
        serde_json::json!([0.34, 1.56, 0.64, 1.0, 1.0, 1.0])
    );
    assert_eq!(
        t["motion.timed.close_curve"],
        k74["motion.timed.close_curve"]
    );
    i.decor = decor_of("[decor]\n\"motion.style\" = \"stepped\"\n\"motion.steps\" = 5\n");
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["motion.kind"], "stepped");
    let c: Vec<f64> = t["motion.timed.open_curve"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_f64().unwrap())
        .collect();
    // 500 ms in holds of 5 frames at 60 Hz: 6 steps, two straight segments each, ending at 1, 1; x never goes back.
    assert_eq!(c.len(), 6 * 12);
    assert_eq!(&c[c.len() - 2..], &[1.0, 1.0]);
    let xs: Vec<f64> = c.chunks(2).map(|p| p[0]).collect();
    assert!(xs.windows(2).all(|w| w[1] >= w[0]), "{xs:?}");
    i.axes.motion = MotionProfile::None;
    let t = resolve(&i, &fonts()).unwrap().tokens;
    assert_eq!(t["motion.kind"], "none");
    assert_eq!(t["motion.style"], "none");
    assert_eq!(t["motion.timed.open_ms"], 0);
}

/// W53.0a: bitmap type sits on its grid; a style's own icon font wins when installed and the shell's is its fallback.
#[test]
fn pixel_type_and_a_styles_icon_font() {
    let mut i = input("wa-iro", Scheme::Dark);
    i.decor = decor_of(
        "[decor]\n\"type.pixel\" = true\n\"type.pixel_step\" = 8\n\"icons.family\" = [\"Pixel Symbols\"]\n\"icon.size\" = 16\n",
    );
    let fonts = FakeFonts::new(&["Inter", "Pixel Symbols", "Material Symbols Rounded"]);
    let t = resolve(&i, &fonts).unwrap().tokens;
    assert_eq!(t["font.pixel"], true);
    for n in ["caption", "label", "body", "title", "display"] {
        let v = t[&format!("font.size.{n}")].as_i64().unwrap();
        assert_eq!(v % 8, 0, "{n} {v}");
    }
    assert_eq!(t["font.icons"], "Pixel Symbols");
    assert_eq!(t["font.icons_fallback"], "Material Symbols Rounded");
    assert_eq!(t["icon.size"], 16);
    // Not installed: the shell's own, as before.
    let t = resolve(&i, &FakeFonts::new(&["Material Symbols Rounded"]))
        .unwrap()
        .tokens;
    assert_eq!(t["font.icons"], "Material Symbols Rounded");
}

/// W53.0a, rule 4: no renderer compares a style's, look's or palette's name — identity is slots and tokens. Scans the
/// QML for a comparison with a bundled pack name in quotes (`=== "win95"`, `== 'kanso'`, `case "sekai":`).
#[test]
fn no_renderer_compares_a_pack_name() {
    use kurashi_theme::appearance::{Kind, all_in};
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut names: Vec<String> = all_in(Kind::Look, &[])
        .into_iter()
        .chain(all_in(Kind::Style, &[]))
        .map(|p| p.name)
        .chain(bundled_names().into_iter().map(String::from))
        .collect();
    names.sort();
    names.dedup();
    // Names that are also ordinary words of other enums (material kinds, chromes) are not identities.
    names.retain(|n| !["soft", "material", "glass", "terminal"].contains(&n.as_str()));
    let mut bad = vec![];
    let mut stack = vec![
        root.join("frontend"),
        root.join("settings"),
        root.join("greeter"),
    ];
    while let Some(dir) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&dir) else {
            continue;
        };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                if !p.ends_with("shots") {
                    stack.push(p);
                }
                continue;
            }
            if p.extension().is_none_or(|x| x != "qml" && x != "js") {
                continue;
            }
            let src = std::fs::read_to_string(&p).unwrap_or_default();
            for (no, line) in src.lines().enumerate() {
                let code = line.split("//").next().unwrap_or_default();
                for n in &names {
                    for q in ['"', '\''] {
                        let lit = format!("{q}{n}{q}");
                        let Some(at) = code.find(&lit) else { continue };
                        let before = code[..at].trim_end();
                        let after = code[at + lit.len()..].trim_start();
                        if before.ends_with("==")
                            || before.ends_with("!=")
                            || before.ends_with("case")
                            || after.starts_with("==")
                            || after.starts_with("!=")
                        {
                            bad.push(format!("{}:{}: {}", p.display(), no + 1, line.trim()));
                        }
                    }
                }
            }
        }
    }
    assert!(
        bad.is_empty(),
        "renderers compare pack names:\n{}",
        bad.join("\n")
    );
}

#[test]
fn every_bundled_palette_has_both_schemes_as_written() {
    // K53 (user, session 11): every palette has a light and a dark mode, authored — not derived from the other one.
    // (Contrast in both is `every_palette_scheme_contrast_passes_aa_after_wcag`.)
    for name in bundled_names() {
        let set = bundled(name).unwrap();
        assert!(
            set.dark.is_some() && set.light.is_some(),
            "{name} lacks a scheme"
        );
        if std::env::var_os("KURASHI_PRINT_WCAG").is_some() {
            for scheme in [Scheme::Dark, Scheme::Light] {
                let out = resolve(&input(name, scheme), &fonts()).unwrap();
                for n in out.notes.iter().filter(|n| n.stage == "wcag") {
                    eprintln!("{name} {scheme:?}: {}", n.text);
                }
            }
        }
    }
}

/// The input a style resolves to on its own (its look's and its own recipe; the user's values left out), for the
/// per-style goldens: every key the theme crate reads from a pack.
fn style_input(name: &str) -> ThemeInput {
    use kurashi_theme::appearance::{Kind, find, layer};
    let style = find(Kind::Style, name).unwrap();
    let look = find(Kind::Look, &style.look);
    let mut i = ThemeInput {
        decor: look.as_ref().map(|l| l.decor_input()).unwrap_or_default(),
        ..Default::default()
    };
    for (key, v, _) in layer(Some(&style), look.as_ref()) {
        let s = v.as_str().unwrap_or_default().to_owned();
        let f = v.as_f64().unwrap_or_default();
        let list = || -> Vec<String> {
            v.as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default()
        };
        match key.as_str() {
            "theme.colors.palette" => i.source = Source::Palette(s),
            "theme.colors.scheme" => {
                i.scheme = if s == "light" {
                    Scheme::Light
                } else {
                    Scheme::Dark
                }
            }
            "theme.colors.ink" if s != "palette" => i.ink = Ink::Named(s),
            "theme.chrome" => i.axes.chrome = Chrome::parse(&s),
            "theme.material.kind" => {
                i.axes.material = if s == "solid" {
                    Material::Solid
                } else {
                    Material::Translucent
                }
            }
            "theme.material.opacity" => i.axes.opacity = f,
            "theme.material.blur" => i.axes.blur = v.as_bool().unwrap_or(false),
            "theme.shape.corners" => {
                i.axes.shape = match s.as_str() {
                    "none" => Shape::None,
                    "squircle" => Shape::Squircle,
                    _ => Shape::Rounded,
                }
            }
            "theme.shape.radius" => i.axes.radius = f,
            "theme.shape.squircle" => i.axes.squircle = f,
            "theme.motion.profile" => {
                i.axes.motion = match s.as_str() {
                    "none" => MotionProfile::None,
                    "calm" => MotionProfile::Calm,
                    "lively" => MotionProfile::Lively,
                    _ => MotionProfile::Expressive,
                }
            }
            "theme.motion.speed" => i.axes.motion_speed = f,
            "theme.density" => {
                i.axes.density = match s.as_str() {
                    "compact" => Density::Compact,
                    "airy" => Density::Airy,
                    _ => Density::Regular,
                }
            }
            "theme.outline_ink" => i.axes.outline_ink = s,
            "theme.typography.family" => i.axes.font_chain = list(),
            "theme.typography.family_jp" => i.axes.font_chain_jp = list(),
            _ => {}
        }
    }
    i
}

/// Every bundled style's tokens (W53.0a): a change to the design system shows here as added keys only, unless it means
/// to change a style (a family card then reviews its own file's diff).
#[test]
fn golden_every_style() {
    use kurashi_theme::appearance::{Kind, all_in};
    for s in all_in(Kind::Style, &[]) {
        golden(
            &format!("styles/{}.json", s.name),
            &resolve(&style_input(&s.name), &fonts()).unwrap().tokens,
        );
    }
}
