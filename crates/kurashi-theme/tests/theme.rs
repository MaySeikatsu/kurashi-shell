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
    i.axes.radius_scale = 1.5;
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
            ] {
                let r = contrast(c(fg), c(bg));
                assert!(r >= 4.5, "{name} {scheme:?}: {fg}/{bg} = {r:.2}");
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
    for chrome in [Chrome::Flat, Chrome::Keycap, Chrome::Soft, Chrome::Line] {
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
        ] {
            assert!(t.contains_key(k), "{chrome:?} lacks {k}");
        }
        seen.insert(t["chrome.style"].as_str().unwrap().to_owned());
    }
    assert_eq!(seen.len(), 4);
}
