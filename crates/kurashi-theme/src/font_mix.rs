//! The font mix (I176, K93; `docs/ux/fonts.md`): one generated font that holds the letters of several fonts and moves between them
//! by itself. Each letter has one glyph per font, in an order of its own, and a `calt` feature gives each letter of a word the next
//! phase, so "ll" never repeats a glyph and the shell's plain `Text` mixes with nothing else changing: elide, layout cost
//! and all its components stay as they are. A word starts at phase 0, so a word looks the same wherever it stands and a live
//! label does not re-mix when its neighbour changes. Sizes are matched to the first font by the height of each font's own "x"
//! (OS/2's are often wrong: Handlee's by half). Kerning and combining-mark positioning are not carried. Latin, Greek and Cyrillic
//! letters mix; digits and punctuation stay in the first font so a counter does not jump; other scripts fall through to the next font.

use kurbo::{BezPath, CubicBez, PathEl, Point};
use skrifa::instance::{LocationRef, Size};
use skrifa::outline::{DrawSettings, OutlinePen};
use skrifa::raw::TableProvider;
use skrifa::{FontRef, GlyphId, MetadataProvider};
use write_fonts::FontBuilder;
use write_fonts::tables::cmap::Cmap;
use write_fonts::tables::glyf::{Glyf, GlyfLocaBuilder, Glyph, SimpleGlyph};
use write_fonts::tables::gsub::{
    Gsub, SingleSubst, SubstitutionChainContext, SubstitutionLookup, SubstitutionLookupList,
};
use write_fonts::tables::head::Head;
use write_fonts::tables::hhea::Hhea;
use write_fonts::tables::hmtx::{Hmtx, LongMetric};
use write_fonts::tables::layout::{
    ChainedSequenceContext, ChainedSequenceContextFormat3, CoverageTable, Feature, FeatureList,
    FeatureRecord, LangSys, Lookup, LookupFlag, Script, ScriptList, ScriptRecord,
    SequenceLookupRecord,
};
use write_fonts::tables::loca::Loca;
use write_fonts::tables::maxp::Maxp;
use write_fonts::tables::name::{Name, NameRecord};
use write_fonts::tables::os2::Os2;
use write_fonts::tables::post::Post;
use write_fonts::types::{Fixed, GlyphId16, LongDateTime, NameId, Tag, Version16Dot16};

const UPM: u16 = 1000;
/// A font of this many faces is enough to read as a hand; more only grows the file.
pub const MAX_FONTS: usize = 8;

#[derive(Debug, PartialEq, Eq)]
pub enum MixError {
    /// Fewer than two fonts, or more than [`MAX_FONTS`].
    Count,
    /// A font could not be read, or has no "x" to measure.
    Unreadable(usize),
    /// A table did not build.
    Build(String),
}
impl std::fmt::Display for MixError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MixError::Count => write!(f, "a mix needs 2 to {MAX_FONTS} fonts"),
            MixError::Unreadable(i) => write!(f, "font {i} cannot be read"),
            MixError::Build(s) => write!(f, "{s}"),
        }
    }
}

/// A character kept from the first font that has it, and whether it mixes.
fn wanted(c: char) -> Option<bool> {
    let u = c as u32;
    let kept = matches!(u,
        0x20..=0x7e | 0xa0..=0x24f | 0x370..=0x52f | 0x1e00..=0x1fff | 0x2000..=0x206f | 0x20a0..=0x20cf
        | 0x2100..=0x2bff);
    kept.then(|| c.is_alphabetic() && u < 0x2000)
}

struct Src<'a> {
    font: FontRef<'a>,
    k: f64,
    charmap: skrifa::charmap::Charmap<'a>,
}

struct Pen {
    path: BezPath,
    k: f64,
    at: Point,
    start: Point,
}
impl Pen {
    fn p(&self, x: f32, y: f32) -> Point {
        Point::new(f64::from(x) * self.k, f64::from(y) * self.k)
    }
}
impl OutlinePen for Pen {
    fn move_to(&mut self, x: f32, y: f32) {
        let p = self.p(x, y);
        self.path.move_to(p);
        self.at = p;
        self.start = p;
    }
    fn line_to(&mut self, x: f32, y: f32) {
        let p = self.p(x, y);
        self.path.line_to(p);
        self.at = p;
    }
    fn quad_to(&mut self, cx: f32, cy: f32, x: f32, y: f32) {
        let (c, p) = (self.p(cx, cy), self.p(x, y));
        self.path.quad_to(c, p);
        self.at = p;
    }
    fn curve_to(&mut self, c0x: f32, c0y: f32, c1x: f32, c1y: f32, x: f32, y: f32) {
        // glyf holds quadratics: a CFF source's cubics to within a unit.
        let (c0, c1, p) = (self.p(c0x, c0y), self.p(c1x, c1y), self.p(x, y));
        for (_, _, q) in CubicBez::new(self.at, c0, c1, p).to_quads(1.0) {
            self.path.push(PathEl::QuadTo(q.p1, q.p2));
        }
        self.at = p;
    }
    fn close(&mut self) {
        self.path.close_path();
        self.at = self.start;
    }
}

fn outline(s: &Src<'_>, g: GlyphId) -> BezPath {
    let mut pen = Pen {
        path: BezPath::new(),
        k: s.k,
        at: Point::ZERO,
        start: Point::ZERO,
    };
    if let Some(o) = s.font.outline_glyphs().get(g) {
        let _ = o.draw(
            DrawSettings::unhinted(Size::unscaled(), LocationRef::default()),
            &mut pen,
        );
    }
    pen.path
}

/// The height of a font's own "x", in its units: what its letters look like, whatever its tables say.
fn x_height(font: &FontRef<'_>) -> Option<f64> {
    // (a font of someone's own handwriting may not have its "x" yet)
    let g = ['x', 'z', 'n', 'o', 'a', 'e']
        .iter()
        .find_map(|c| font.charmap().map(*c))?;
    let o = font.outline_glyphs().get(g)?;
    let mut pen = Pen {
        path: BezPath::new(),
        k: 1.0,
        at: Point::ZERO,
        start: Point::ZERO,
    };
    o.draw(
        DrawSettings::unhinted(Size::unscaled(), LocationRef::default()),
        &mut pen,
    )
    .ok()?;
    let top = kurbo::Shape::bounding_box(&pen.path).y1;
    (top > 0.0).then_some(top)
}

/// The file of a mix of `fonts` (the bytes and face of each, the first gives the metrics and everything that does not mix), named `family`.
/// The same input gives the same bytes.
pub fn build(fonts: &[(&[u8], u32)], family: &str) -> Result<Vec<u8>, MixError> {
    if fonts.len() < 2 || fonts.len() > MAX_FONTS {
        return Err(MixError::Count);
    }
    let build_err = |e: &dyn std::fmt::Debug| MixError::Build(format!("{e:?}"));
    let mut read = Vec::new();
    for (i, (data, face)) in fonts.iter().enumerate() {
        read.push(FontRef::from_index(data, *face).map_err(|_| MixError::Unreadable(i))?);
    }
    let heights: Vec<f64> = read
        .iter()
        .enumerate()
        .map(|(i, f)| x_height(f).ok_or(MixError::Unreadable(i)))
        .collect::<Result<_, _>>()?;
    let upem = |f: &FontRef<'_>| f.head().map_or(1000.0, |h| f64::from(h.units_per_em()));
    let target = heights[0] / upem(&read[0]);
    let sources: Vec<Src<'_>> = read
        .iter()
        .zip(&heights)
        .map(|(f, h)| Src {
            font: f.clone(),
            k: f64::from(UPM) / upem(f) * (target * upem(f) / h),
            charmap: f.charmap(),
        })
        .collect();
    let n = sources.len();

    // The characters, in order.
    let mut chars: Vec<char> = Vec::new();
    for s in &sources {
        for (u, _) in s.charmap.mappings() {
            if let Some(c) = char::from_u32(u)
                && wanted(c).is_some()
            {
                chars.push(c);
            }
        }
    }
    chars.sort_unstable();
    chars.dedup();

    // Glyph 0 .notdef; each letter one glyph per phase, the rest one.
    let mut glyf = GlyfLocaBuilder::new();
    let mut metrics: Vec<LongMetric> = Vec::new();
    let mut bbox = (0i16, 0i16, 0i16, 0i16);
    let (mut max_points, mut max_contours) = (0u16, 0u16);
    let mut add = |path: &BezPath, adv: f64| -> Result<u32, MixError> {
        let glyph = if path.elements().is_empty() {
            Glyph::Empty
        } else {
            SimpleGlyph::from_bezpath(path).map_or(Glyph::Empty, Glyph::Simple)
        };
        let lsb = match &glyph {
            Glyph::Simple(g) => {
                bbox.0 = bbox.0.min(g.bbox.x_min);
                bbox.1 = bbox.1.min(g.bbox.y_min);
                bbox.2 = bbox.2.max(g.bbox.x_max);
                bbox.3 = bbox.3.max(g.bbox.y_max);
                max_contours = max_contours.max(g.contours.len() as u16);
                max_points = max_points.max(g.contours.iter().map(|c| c.len() as u16).sum());
                g.bbox.x_min
            }
            _ => 0,
        };
        glyf.add_glyph(&glyph).map_err(|e| build_err(&e))?;
        metrics.push(LongMetric {
            advance: adv.round().clamp(0.0, 65535.0) as u16,
            side_bearing: lsb,
        });
        Ok(metrics.len() as u32 - 1)
    };
    add(&BezPath::new(), 500.0)?;

    let advance_of = |s: &Src<'_>, g: GlyphId| {
        f64::from(
            s.font
                .glyph_metrics(Size::unscaled(), LocationRef::default())
                .advance_width(g)
                .unwrap_or(0.0),
        ) * s.k
    };
    let mut cmap: Vec<(char, GlyphId)> = Vec::with_capacity(chars.len());
    // phases[p]: letter glyphs at phase p, in the same order.
    let mut phases: Vec<Vec<GlyphId16>> = vec![Vec::new(); n];
    for &c in &chars {
        let have: Vec<(usize, GlyphId)> = sources
            .iter()
            .enumerate()
            .filter_map(|(i, s)| s.charmap.map(c).map(|g| (i, g)))
            .collect();
        let Some(&(first, first_g)) = have.first() else {
            continue;
        };
        if wanted(c) == Some(true) && have.len() > 1 {
            // Its own start, so the fonts do not simply cycle down a word: a fixed hash, the same on every build.
            let start = ((c as u32).wrapping_mul(2_654_435_761) >> 7) as usize;
            for (p, list) in phases.iter_mut().enumerate() {
                let (i, g) = have[(start + p) % have.len()];
                let id = add(&outline(&sources[i], g), advance_of(&sources[i], g))?;
                if p == 0 {
                    cmap.push((c, GlyphId::new(id)));
                }
                list.push(GlyphId16::new(id as u16));
            }
        } else {
            let s = &sources[first];
            let id = add(&outline(s, first_g), advance_of(s, first_g))?;
            cmap.push((c, GlyphId::new(id)));
        }
    }
    let count = metrics.len();
    if count > usize::from(u16::MAX) {
        return Err(MixError::Build("too many glyphs".into()));
    }
    let (glyf_table, loca_table, loca_format): (Glyf, Loca, _) = glyf.build();

    // `calt`: after a letter at phase p, a letter at phase 0 becomes phase p + 1. One lookup of such rules, read left to right so
    // each rule sees the glyph the last one made; a single substitution for each phase.
    let cover = |p: usize| -> CoverageTable { phases[p].iter().copied().collect() };
    let mut lookups: Vec<SubstitutionLookup> = Vec::new();
    let rules: Vec<SubstitutionChainContext> = (0..n - 1)
        .map(|p| {
            let f3 = ChainedSequenceContextFormat3::new(
                vec![cover(p)],
                vec![cover(0)],
                vec![],
                vec![SequenceLookupRecord::new(0, (p + 1) as u16)],
            );
            SubstitutionChainContext::from(ChainedSequenceContext::Format3(f3))
        })
        .collect();
    lookups.push(SubstitutionLookup::ChainContextual(Lookup::new(
        LookupFlag::empty(),
        rules,
    )));
    for map in phases.iter().skip(1) {
        let single = SingleSubst::format_2(cover(0), map.clone());
        lookups.push(SubstitutionLookup::Single(Lookup::new(
            LookupFlag::empty(),
            vec![single],
        )));
    }
    let scripts = ["DFLT", "latn", "cyrl", "grek"]
        .iter()
        .map(|t| {
            ScriptRecord::new(
                Tag::new(t.as_bytes().try_into().expect("four bytes")),
                Script::new(Some(LangSys::new(vec![0])), vec![]),
            )
        })
        .collect();
    let gsub = Gsub::new(
        ScriptList::new(scripts),
        FeatureList::new(vec![FeatureRecord::new(
            Tag::new(b"calt"),
            Feature::new(None, vec![0]),
        )]),
        SubstitutionLookupList::new(lookups),
    );

    // Metrics from the first font, scaled.
    let k = sources[0].k;
    let hhea0 = read[0].hhea().map_err(|_| MixError::Unreadable(0))?;
    let scale = |v: i16| (f64::from(v) * k).round() as i16;
    let (asc, desc, gap) = (
        scale(hhea0.ascender().to_i16()),
        scale(hhea0.descender().to_i16()),
        scale(hhea0.line_gap().to_i16()),
    );
    let xh = (heights[0] * k).round() as i16;
    let cap = read[0]
        .charmap()
        .map('H')
        .map(|g| {
            kurbo::Shape::bounding_box(&outline(&sources[0], g))
                .y1
                .round() as i16
        })
        .unwrap_or(xh);

    let head = Head {
        font_revision: Fixed::from_f64(1.0),
        units_per_em: UPM,
        created: LongDateTime::new(0),
        modified: LongDateTime::new(0),
        x_min: bbox.0,
        y_min: bbox.1,
        x_max: bbox.2,
        y_max: bbox.3,
        lowest_rec_ppem: 6,
        font_direction_hint: 2,
        index_to_loc_format: loca_format as i16,
        ..Default::default()
    };
    let hhea = Hhea {
        ascender: asc.into(),
        descender: desc.into(),
        line_gap: gap.into(),
        advance_width_max: metrics.iter().map(|m| m.advance).max().unwrap_or(0).into(),
        min_left_side_bearing: bbox.0.into(),
        x_max_extent: bbox.2.into(),
        caret_slope_rise: 1,
        number_of_h_metrics: count as u16,
        ..Default::default()
    };
    let maxp = Maxp {
        num_glyphs: count as u16,
        max_points: Some(max_points),
        max_contours: Some(max_contours),
        max_composite_points: Some(0),
        max_composite_contours: Some(0),
        max_zones: Some(1),
        max_twilight_points: Some(0),
        max_storage: Some(0),
        max_function_defs: Some(0),
        max_instruction_defs: Some(0),
        max_stack_elements: Some(0),
        max_size_of_instructions: Some(0),
        max_component_elements: Some(0),
        max_component_depth: Some(0),
    };
    let os2 = Os2 {
        us_weight_class: 400,
        us_width_class: 5,
        s_typo_ascender: asc,
        s_typo_descender: desc,
        s_typo_line_gap: gap,
        us_win_ascent: asc.max(0) as u16,
        us_win_descent: desc.unsigned_abs(),
        sx_height: Some(xh),
        s_cap_height: Some(cap),
        us_default_char: Some(0),
        us_break_char: Some(32),
        us_max_context: Some(2),
        ul_code_page_range_1: Some(1),
        ul_code_page_range_2: Some(0),
        ul_unicode_range_1: 1,
        fs_selection: write_fonts::tables::os2::SelectionFlags::REGULAR,
        ach_vend_id: Tag::new(b"KRSH"),
        ..Default::default()
    };
    let name_of =
        |id: u16, s: &str| NameRecord::new(3, 1, 0x409, NameId::new(id), s.to_owned().into());
    let mut names = vec![
        name_of(1, family),
        name_of(2, "Regular"),
        name_of(4, family),
        name_of(5, "Version 1.000"),
        name_of(6, &family.replace(' ', "")),
        name_of(
            10,
            "A mix of fonts for this machine, generated by kurashi-shell.",
        ),
    ];
    names.sort();
    let name = Name::new(names);
    let cmap_table = Cmap::from_mappings(cmap).map_err(|e| build_err(&e))?;
    let hmtx = Hmtx::new(metrics, vec![]);
    let post = Post {
        version: Version16Dot16::VERSION_3_0,
        ..Default::default()
    };

    let mut out = FontBuilder::new();
    out.add_table(&head).map_err(|e| build_err(&e))?;
    out.add_table(&hhea).map_err(|e| build_err(&e))?;
    out.add_table(&maxp).map_err(|e| build_err(&e))?;
    out.add_table(&os2).map_err(|e| build_err(&e))?;
    out.add_table(&hmtx).map_err(|e| build_err(&e))?;
    out.add_table(&cmap_table).map_err(|e| build_err(&e))?;
    out.add_table(&loca_table).map_err(|e| build_err(&e))?;
    out.add_table(&glyf_table).map_err(|e| build_err(&e))?;
    out.add_table(&name).map_err(|e| build_err(&e))?;
    out.add_table(&post).map_err(|e| build_err(&e))?;
    out.add_table(&gsub).map_err(|e| build_err(&e))?;
    Ok(out.build())
}

#[cfg(test)]
mod tests {
    use super::*;
    use skrifa::raw::types::GlyphId as Gid;
    use write_fonts::tables::glyf::Bbox;

    /// A small font: every letter of "alxHnW" and the digits a box of its own height, `tall` the "x" (in units of `upem`).
    fn font(upem: u16, tall: f64, width: f64) -> Vec<u8> {
        let mut glyf = GlyfLocaBuilder::new();
        let mut metrics = vec![LongMetric {
            advance: 500,
            side_bearing: 0,
        }];
        glyf.add_glyph(&Glyph::Empty).unwrap();
        let mut cmap = Vec::new();
        for (i, c) in "alxHnW019.".chars().enumerate() {
            let mut p = BezPath::new();
            let h = if c.is_uppercase() { tall * 1.4 } else { tall };
            p.move_to((0.0, 0.0));
            p.line_to((width, 0.0));
            p.line_to((width, h));
            p.line_to((0.0, h));
            p.close_path();
            let g = SimpleGlyph::from_bezpath(&p).unwrap();
            glyf.add_glyph(&Glyph::Simple(g)).unwrap();
            metrics.push(LongMetric {
                advance: (width * 1.2) as u16,
                side_bearing: 0,
            });
            cmap.push((c, GlyphId::new(i as u32 + 1)));
        }
        let (g, l, fmt): (Glyf, Loca, _) = glyf.build();
        let n = metrics.len() as u16;
        let mut b = FontBuilder::new();
        let head = Head {
            units_per_em: upem,
            font_revision: Fixed::from_f64(1.0),
            index_to_loc_format: fmt as i16,
            ..Default::default()
        };
        let hhea = Hhea {
            ascender: (upem as i16 * 3 / 4).into(),
            descender: (-(upem as i16) / 4).into(),
            number_of_h_metrics: n,
            ..Default::default()
        };
        let maxp = Maxp {
            num_glyphs: n,
            max_points: Some(4),
            max_contours: Some(1),
            max_composite_points: Some(0),
            max_composite_contours: Some(0),
            max_zones: Some(1),
            max_twilight_points: Some(0),
            max_storage: Some(0),
            max_function_defs: Some(0),
            max_instruction_defs: Some(0),
            max_stack_elements: Some(0),
            max_size_of_instructions: Some(0),
            max_component_elements: Some(0),
            max_component_depth: Some(0),
        };
        b.add_table(&head).unwrap();
        b.add_table(&hhea).unwrap();
        b.add_table(&maxp).unwrap();
        b.add_table(&Hmtx::new(metrics, vec![])).unwrap();
        b.add_table(&Cmap::from_mappings(cmap).unwrap()).unwrap();
        b.add_table(&l).unwrap();
        b.add_table(&g).unwrap();
        b.build()
    }
    fn top(data: &[u8], c: char) -> f64 {
        let f = FontRef::new(data).unwrap();
        x_top(&f, f.charmap().map(c).unwrap())
    }
    fn x_top(f: &FontRef<'_>, g: Gid) -> f64 {
        let mut pen = Pen {
            path: BezPath::new(),
            k: 1.0,
            at: Point::ZERO,
            start: Point::ZERO,
        };
        f.outline_glyphs()
            .get(g)
            .unwrap()
            .draw(
                DrawSettings::unhinted(Size::unscaled(), LocationRef::default()),
                &mut pen,
            )
            .unwrap();
        kurbo::Shape::bounding_box(&pen.path).y1
    }
    fn calt_rules(data: &[u8]) -> usize {
        use skrifa::raw::tables::gsub::SubstitutionLookup as L;
        let f = FontRef::new(data).unwrap();
        let gsub = f.gsub().unwrap();
        let features = gsub.feature_list().unwrap();
        assert!(
            features
                .feature_records()
                .iter()
                .any(|r| r.feature_tag() == Tag::new(b"calt"))
        );
        let lookups = gsub.lookup_list().unwrap();
        match lookups.lookups().get(0).unwrap() {
            L::ChainContextual(l) => l.subtables().iter().count(),
            _ => panic!("the first lookup is not the chain"),
        }
    }

    #[test]
    fn it_needs_two_to_eight_readable_fonts() {
        let a = font(1000, 500.0, 400.0);
        assert_eq!(build(&[(&a, 0)], "M"), Err(MixError::Count));
        let many: Vec<(&[u8], u32)> = (0..=MAX_FONTS).map(|_| (a.as_slice(), 0)).collect();
        assert_eq!(build(&many, "M"), Err(MixError::Count));
        assert_eq!(
            build(&[(&a, 0), (b"not a font", 0)], "M"),
            Err(MixError::Unreadable(1))
        );
    }

    #[test]
    fn the_same_fonts_give_the_same_file() {
        let (a, b) = (font(1000, 500.0, 400.0), font(2048, 900.0, 800.0));
        assert_eq!(
            build(&[(&a, 0), (&b, 0)], "M").unwrap(),
            build(&[(&a, 0), (&b, 0)], "M").unwrap()
        );
    }

    /// Whatever the fonts' units, every letter's x-height lands on the first font's.
    #[test]
    fn x_heights_are_matched_to_the_first_font() {
        let (a, b, c) = (
            font(1000, 500.0, 400.0),
            font(2048, 800.0, 800.0),
            font(1000, 250.0, 300.0),
        );
        let m = build(&[(&a, 0), (&b, 0), (&c, 0)], "Mix").unwrap();
        let f = FontRef::new(&m).unwrap();
        assert_eq!(f.head().unwrap().units_per_em(), UPM);
        // One glyph per phase for the letters, one each for the digits and the point; .notdef.
        assert_eq!(f.maxp().unwrap().num_glyphs(), 1 + 6 * 3 + 4);
        let x = f.charmap().map('x').unwrap();
        assert!((x_top(&f, x) - 500.0).abs() <= 1.0, "{}", x_top(&f, x));
        // every phase of "x" has that height
        for offset in 0..3u32 {
            assert!((x_top(&f, Gid::new(x.to_u32() + offset)) - 500.0).abs() <= 1.0);
        }
        // (a capital in proportion: the sources' 1.4)
        assert!((top(&m, 'H') - 700.0).abs() <= 2.0, "{}", top(&m, 'H'));
    }

    #[test]
    fn calt_has_a_rule_for_each_step_between_the_fonts() {
        let (a, b, c) = (
            font(1000, 500.0, 400.0),
            font(1000, 480.0, 380.0),
            font(1000, 520.0, 420.0),
        );
        assert_eq!(calt_rules(&build(&[(&a, 0), (&b, 0)], "M").unwrap()), 1);
        assert_eq!(
            calt_rules(&build(&[(&a, 0), (&b, 0), (&c, 0)], "M").unwrap()),
            2
        );
    }

    /// A counter must not jump: digits and punctuation are one glyph, the first font's.
    #[test]
    fn only_letters_mix() {
        assert_eq!(wanted('a'), Some(true));
        assert_eq!(wanted('Я'), Some(true));
        assert_eq!(wanted('1'), Some(false));
        assert_eq!(wanted('.'), Some(false));
        assert_eq!(wanted('暮'), None);
        let (a, b) = (font(1000, 500.0, 400.0), font(1000, 400.0, 900.0));
        let m = build(&[(&a, 0), (&b, 0)], "M").unwrap();
        let f = FontRef::new(&m).unwrap();
        let adv = f.glyph_metrics(Size::unscaled(), LocationRef::default());
        assert_eq!(
            adv.advance_width(f.charmap().map('1').unwrap()),
            Some(480.0)
        );
    }

    /// The glyphs a real shaper gives (`calt` is on by default, in HarfBuzz as in Qt).
    fn shaped(data: &[u8], text: &str) -> Vec<u32> {
        let font = harfrust::Font::new(data.to_vec(), 0).unwrap();
        let shaper = harfrust::ShaperFont::new(&font);
        let mut buf = harfrust::Buffer::new();
        buf.push_str(text);
        buf.guess_segment_properties();
        harfrust::shape(&shaper, &mut buf, harfrust::ShapeOptions::default()).unwrap();
        buf.glyph_infos().iter().map(|g| g.glyph_id).collect()
    }

    /// What the feature is for: a letter twice running is never one glyph, three fonts go round, a word starts over, and a word
    /// is the same wherever it stands. A digit is always its one glyph.
    #[test]
    fn a_shaper_moves_on_a_font_per_letter_and_starts_over_per_word() {
        let (a, b, c) = (
            font(1000, 500.0, 400.0),
            font(1000, 480.0, 380.0),
            font(1000, 520.0, 420.0),
        );
        let m = build(&[(&a, 0), (&b, 0), (&c, 0)], "M").unwrap();
        let ll = shaped(&m, "ll");
        assert_ne!(ll[0], ll[1]);
        let lll = shaped(&m, "lll");
        assert!(
            lll[0] != lll[1] && lll[1] != lll[2] && lll[0] != lll[2],
            "{lll:?}"
        );
        // the fourth letter is at phase 0 again
        assert_eq!(shaped(&m, "llll")[3], lll[0]);
        let word = shaped(&m, "all");
        let two = shaped(&m, "all all");
        assert_eq!(&two[..3], &word[..]);
        assert_eq!(&two[4..], &word[..]);
        let digits = shaped(&m, "00");
        assert_eq!(digits[0], digits[1]);
        // the same input, the same glyphs: a label never re-mixes
        assert_eq!(shaped(&m, "all"), shaped(&m, "all"));
    }

    #[test]
    fn the_family_is_named() {
        let (a, b) = (font(1000, 500.0, 400.0), font(1000, 400.0, 900.0));
        let m = build(&[(&a, 0), (&b, 0)], "Kurashi Mix abc").unwrap();
        let f = FontRef::new(&m).unwrap();
        let name = f
            .localized_strings(skrifa::string::StringId::FAMILY_NAME)
            .english_or_first()
            .unwrap()
            .to_string();
        assert_eq!(name, "Kurashi Mix abc");
        let _ = Bbox::default();
    }
}
