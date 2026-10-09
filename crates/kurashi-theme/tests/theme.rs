use std::path::PathBuf;

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
