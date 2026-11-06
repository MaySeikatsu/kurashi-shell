//! A font file from a hand's drawn letters (K94). Plain on purpose: glyphs, a character map and metrics, nothing a shaper has to think
//! about. A character nobody drew is not in the map, so the toolkit falls back to the next font for it, as with any font that lacks one.

use std::collections::BTreeMap;

use kurbo::BezPath;
use write_fonts::FontBuilder;
use write_fonts::tables::cmap::Cmap;
use write_fonts::tables::glyf::{Glyf, GlyfLocaBuilder, Glyph, SimpleGlyph};
use write_fonts::tables::head::Head;
use write_fonts::tables::hhea::Hhea;
use write_fonts::tables::hmtx::{Hmtx, LongMetric};
use write_fonts::tables::loca::Loca;
use write_fonts::tables::maxp::Maxp;
use write_fonts::tables::name::{Name, NameRecord};
use write_fonts::tables::os2::{Os2, SelectionFlags};
use write_fonts::tables::post::Post;
use write_fonts::types::{Fixed, GlyphId, LongDateTime, NameId, Tag, Version16Dot16};

use crate::glyph::{BEARING, Strokes, outline};

const UPM: u16 = 1000;
/// The box's lines, in font units: where the drawing box guides the hand. The font's own line height comes from them.
pub const CAP: i16 = 720;
pub const X_HEIGHT: i16 = 480;
pub const ASCENT: i16 = 1000;
pub const DESCENT: i16 = -300;
const SPACE: u16 = 300;

/// The font of these letters, or `None` with none drawn.
pub fn build(
    letters: &BTreeMap<char, &Strokes>,
    pen: f64,
    family: &str,
) -> Result<Option<Vec<u8>>, String> {
    let err = |e: &dyn std::fmt::Debug| format!("{e:?}");
    let mut glyf = GlyfLocaBuilder::new();
    let mut metrics = vec![LongMetric {
        advance: 500,
        side_bearing: 0,
    }];
    glyf.add_glyph(&Glyph::Empty).map_err(|e| err(&e))?;
    metrics.push(LongMetric {
        advance: SPACE,
        side_bearing: 0,
    });
    glyf.add_glyph(&Glyph::Empty).map_err(|e| err(&e))?;
    let mut cmap: Vec<(char, GlyphId)> = vec![(' ', GlyphId::new(1))];
    let (mut bbox, mut points, mut contours) = ((0i16, 0i16, 0i16, 0i16), 0u16, 0u16);
    let mut drawn = 0;
    for (&c, strokes) in letters {
        let Some((path, x0, x1)) = outline(strokes, pen) else {
            continue;
        };
        // To start at its bearing, wherever in the box it was drawn across.
        let shift = kurbo::Affine::translate((BEARING - x0, 0.0));
        let moved: BezPath = shift * path;
        let g = SimpleGlyph::from_bezpath(&moved).map_err(|e| format!("{c}: {e:?}"))?;
        let g = SimpleGlyph {
            overlaps: true,
            ..g
        };
        bbox = (
            bbox.0.min(g.bbox.x_min),
            bbox.1.min(g.bbox.y_min),
            bbox.2.max(g.bbox.x_max),
            bbox.3.max(g.bbox.y_max),
        );
        contours = contours.max(g.contours.len() as u16);
        points = points.max(g.contours.iter().map(|c| c.len() as u16).sum());
        metrics.push(LongMetric {
            advance: (x1 - x0 + 2.0 * BEARING).round().clamp(0.0, 4000.0) as u16,
            side_bearing: g.bbox.x_min,
        });
        glyf.add_glyph(&Glyph::Simple(g)).map_err(|e| err(&e))?;
        cmap.push((c, GlyphId::new(metrics.len() as u32 - 1)));
        drawn += 1;
    }
    if drawn == 0 {
        return Ok(None);
    }
    let count = metrics.len() as u16;
    let (glyf_t, loca_t, fmt): (Glyf, Loca, _) = glyf.build();
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
        index_to_loc_format: fmt as i16,
        ..Default::default()
    };
    let hhea = Hhea {
        ascender: ASCENT.into(),
        descender: DESCENT.into(),
        advance_width_max: metrics.iter().map(|m| m.advance).max().unwrap_or(0).into(),
        min_left_side_bearing: bbox.0.into(),
        x_max_extent: bbox.2.into(),
        caret_slope_rise: 1,
        number_of_h_metrics: count,
        ..Default::default()
    };
    let maxp = Maxp {
        num_glyphs: count,
        max_points: Some(points),
        max_contours: Some(contours),
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
        s_typo_ascender: ASCENT,
        s_typo_descender: DESCENT,
        us_win_ascent: ASCENT as u16,
        us_win_descent: DESCENT.unsigned_abs(),
        sx_height: Some(X_HEIGHT),
        s_cap_height: Some(CAP),
        us_default_char: Some(0),
        us_break_char: Some(32),
        us_max_context: Some(0),
        ul_code_page_range_1: Some(1),
        ul_code_page_range_2: Some(0),
        ul_unicode_range_1: 1,
        fs_selection: SelectionFlags::REGULAR,
        ach_vend_id: Tag::new(b"KRSH"),
        ..Default::default()
    };
    let rec = |id: u16, s: &str| NameRecord::new(3, 1, 0x409, NameId::new(id), s.to_owned().into());
    let mut names = vec![
        rec(1, family),
        rec(2, "Regular"),
        rec(4, family),
        rec(5, "Version 1.000"),
        rec(6, &family.replace(' ', "")),
        rec(10, "Drawn by hand in kurashi-shell."),
    ];
    names.sort();
    let post = Post {
        version: Version16Dot16::VERSION_3_0,
        ..Default::default()
    };
    let map = Cmap::from_mappings(cmap).map_err(|e| err(&e))?;
    let hmtx = Hmtx::new(metrics, vec![]);
    let mut out = FontBuilder::new();
    out.add_table(&head).map_err(|e| err(&e))?;
    out.add_table(&hhea).map_err(|e| err(&e))?;
    out.add_table(&maxp).map_err(|e| err(&e))?;
    out.add_table(&os2).map_err(|e| err(&e))?;
    out.add_table(&hmtx).map_err(|e| err(&e))?;
    out.add_table(&map).map_err(|e| err(&e))?;
    out.add_table(&loca_t).map_err(|e| err(&e))?;
    out.add_table(&glyf_t).map_err(|e| err(&e))?;
    out.add_table(&Name::new(names)).map_err(|e| err(&e))?;
    out.add_table(&post).map_err(|e| err(&e))?;
    Ok(Some(out.build()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use skrifa::instance::{LocationRef, Size};
    use skrifa::{FontRef, MetadataProvider};

    fn letter(w: f64) -> Strokes {
        vec![vec![[300.0, 0.0], [300.0 + w, 480.0]]]
    }

    #[test]
    fn nothing_drawn_is_no_font() {
        assert_eq!(build(&BTreeMap::new(), 60.0, "F"), Ok(None));
    }

    #[test]
    fn a_letter_is_as_wide_as_it_was_drawn_and_where_it_was_drawn_in_height() {
        let (a, b) = (letter(100.0), letter(300.0));
        let mut m = BTreeMap::new();
        m.insert('a', &a);
        m.insert('b', &b);
        let data = build(&m, 40.0, "My Hand").unwrap().unwrap();
        let f = FontRef::new(&data).unwrap();
        let metrics = f.glyph_metrics(Size::unscaled(), LocationRef::default());
        let adv = |c| metrics.advance_width(f.charmap().map(c).unwrap()).unwrap();
        assert!(adv('b') - adv('a') > 195.0, "{} {}", adv('a'), adv('b'));
        assert_eq!(adv(' '), f32::from(SPACE));
        // not drawn: not in the font, so the toolkit falls back for it
        assert!(f.charmap().map('c').is_none());
        let name = f
            .localized_strings(skrifa::string::StringId::FAMILY_NAME)
            .english_or_first()
            .unwrap()
            .to_string();
        assert_eq!(name, "My Hand");
    }

    /// A real shaper reads it, and letters not drawn come out as "no glyph", which is what makes a toolkit fall back.
    #[test]
    fn a_shaper_reads_it() {
        let a = letter(100.0);
        let mut m = BTreeMap::new();
        m.insert('a', &a);
        let data = build(&m, 40.0, "F").unwrap().unwrap();
        let font = harfrust::Font::new(data, 0).unwrap();
        let shaper = harfrust::ShaperFont::new(&font);
        let mut buf = harfrust::Buffer::new();
        buf.push_str("a z");
        buf.guess_segment_properties();
        harfrust::shape(&shaper, &mut buf, harfrust::ShapeOptions::default()).unwrap();
        let g: Vec<u32> = buf.glyph_infos().iter().map(|g| g.glyph_id).collect();
        assert_ne!(g[0], 0);
        assert_eq!(g[1], 1);
        assert_eq!(g[2], 0);
    }
}
