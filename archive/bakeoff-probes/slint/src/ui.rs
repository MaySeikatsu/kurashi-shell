//! Slint source generation (runtime-loaded mod UI), theme token mapping, shader pixels.
use serde_json::Value as J;
use slint_interpreter::{Brush, Color, Value};
use std::collections::BTreeSet;

pub const UI_SRC: &str = include_str!("../ui/probe.slint");

fn sanitize(s: &str) -> String {
    s.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect()
}
pub fn mod_prop(wi: usize, key: &str) -> String {
    format!("m{wi}_{}", sanitize(key))
}

fn glyph(name: &str) -> &'static str {
    match name {
        "leaf" => "❀",
        "volume" => "♪",
        "wifi" => "≋",
        "battery" => "▮",
        _ => "•",
    }
}

fn gen_node(n: &J, wi: usize, out: &mut String, props: &mut BTreeSet<String>, depth: usize) {
    if depth > 24 {
        return;
    }
    let kids = |out: &mut String, props: &mut BTreeSet<String>| {
        for c in n.get("children").and_then(|c| c.as_array()).into_iter().flatten() {
            gen_node(c, wi, out, props, depth + 1);
        }
    };
    match n.get("type").and_then(|t| t.as_str()).unwrap_or("") {
        "row" => {
            out.push_str("HorizontalLayout { spacing: Theme.sp-sm; ");
            kids(out, props);
            out.push_str("} ");
        }
        "column" => {
            out.push_str("VerticalLayout { spacing: Theme.sp-xs; ");
            kids(out, props);
            out.push_str("} ");
        }
        "text" => {
            let expr = if let Some(b) = n.get("bind").and_then(|b| b.as_str()) {
                let p = mod_prop(wi, b);
                props.insert(p.clone());
                format!("root.{p}")
            } else {
                let t = n.get("text").and_then(|t| t.as_str()).unwrap_or("");
                format!("\"{}\"", t.replace('\\', "\\\\").replace('"', "\\\""))
            };
            out.push_str(&format!(
                "Text {{ text: {expr}; vertical-alignment: center; color: Theme.on-surface; \
                 font-family: Theme.font-jp; font-size: Theme.fs-body; }} "
            ));
        }
        "icon" => {
            let g = glyph(n.get("name").and_then(|t| t.as_str()).unwrap_or(""));
            out.push_str(&format!(
                "Text {{ text: \"{g}\"; vertical-alignment: center; color: Theme.accent; \
                 font-size: Theme.fs-title; }} "
            ));
        }
        _ => out.push_str("Rectangle { width: 0px; } "),
    }
}

/// Full interpreter source: the .slint file plus easing from tokens and the mod tree.
pub fn build_source(tokens: &J, widgets: &J) -> String {
    let e = tokens
        .get("motion.easing.enter")
        .and_then(|v| v.as_array())
        .filter(|a| a.len() == 4)
        .map(|a| a.iter().map(|x| format!("{:.4}", x.as_f64().unwrap_or(0.0))).collect::<Vec<_>>().join(", "))
        .unwrap_or_else(|| "0.05, 0.7, 0.1, 1.0".into());
    let mut props = BTreeSet::new();
    let mut tree = String::new();
    for (wi, w) in widgets.as_array().into_iter().flatten().enumerate() {
        if let Some(ui) = w.get("ui") {
            gen_node(ui, wi, &mut tree, &mut props, 0);
        }
    }
    let prop_src: String = props.iter().map(|p| format!("in property <string> {p}; ")).collect();
    UI_SRC
        .replace("@@EASE@@", &e)
        .replace("@@MOD_PROPS@@", &prop_src)
        .replace("@@MOD_WIDGETS@@", &tree)
}

fn parse_color(s: &str, alpha: f32) -> Option<Color> {
    let h = s.strip_prefix('#')?;
    let b = |i: usize| u8::from_str_radix(h.get(i..i + 2)?, 16).ok();
    let a = if h.len() >= 8 { b(6)? as f32 / 255.0 } else { 1.0 };
    Some(Color::from_argb_u8((a * alpha * 255.0).round() as u8, b(0)?, b(2)?, b(4)?))
}

/// theme.tokens -> (Theme global property, Value). Missing tokens keep the .slint fallbacks.
pub fn theme_props(tokens: &J) -> Vec<(&'static str, Value)> {
    let mut v = Vec::new();
    let surf_alpha = tokens.get("color.surface_alpha").and_then(|x| x.as_f64()).unwrap_or(1.0) as f32;
    for (tok, prop) in [
        ("color.surface", "surface"),
        ("color.surface_container", "surface-container"),
        ("color.surface_container_high", "surface-high"),
        ("color.on_surface", "on-surface"),
        ("color.on_surface_variant", "on-variant"),
        ("color.outline", "outline"),
        ("color.accent", "accent"),
        ("color.on_accent", "on-accent"),
    ] {
        if let Some(c) = tokens.get(tok).and_then(|x| x.as_str()).and_then(|s| {
            parse_color(s, if tok == "color.surface" { surf_alpha } else { 1.0 })
        }) {
            v.push((prop, Value::Brush(Brush::SolidColor(c))));
        }
    }
    for (tok, prop) in [
        ("radius.sm", "r-sm"),
        ("radius.md", "r-md"),
        ("radius.lg", "r-lg"),
        ("radius.full", "r-full"),
        ("space.xs", "sp-xs"),
        ("space.sm", "sp-sm"),
        ("space.md", "sp-md"),
        ("space.lg", "sp-lg"),
        ("space.xl", "sp-xl"),
        ("font.size.caption", "fs-caption"),
        ("font.size.label", "fs-label"),
        ("font.size.body", "fs-body"),
        ("font.size.title", "fs-title"),
        ("bar.height", "bar-height"),
        ("motion.quick_ms", "d-quick"),
        ("motion.standard_ms", "d-standard"),
        ("motion.emphasized_ms", "d-emph"),
    ] {
        if let Some(n) = tokens.get(tok).and_then(|x| x.as_f64()) {
            v.push((prop, Value::Number(n)));
        }
    }
    for (tok, prop) in [("font.family", "font"), ("font.family_jp", "font-jp")] {
        if let Some(s) = tokens.get(tok).and_then(|x| x.as_str()) {
            v.push((prop, Value::String(s.into())));
        }
    }
    v
}

pub fn token_f(tokens: &J, k: &str, d: f64) -> f64 {
    tokens.get(k).and_then(|x| x.as_f64()).unwrap_or(d)
}

/// Animated plasma for the popup "shader" area, computed on the CPU (Slint has no shader API).
pub fn shader_image(t: f32) -> slint_interpreter::Image {
    use slint_interpreter::{Rgba8Pixel, SharedPixelBuffer};
    let (w, h) = (200u32, 80u32);
    let mut buf = SharedPixelBuffer::<Rgba8Pixel>::new(w, h);
    for (i, p) in buf.make_mut_slice().iter_mut().enumerate() {
        let (x, y) = ((i as u32 % w) as f32 / 24.0, (i as u32 / w) as f32 / 24.0);
        let a = (x + t).sin() + (y * 1.3 - t * 0.7).sin() + ((x + y) * 0.8 + t * 0.5).sin();
        let v = (a + 3.0) / 6.0;
        *p = Rgba8Pixel {
            r: (60.0 + 140.0 * v) as u8,
            g: (30.0 + 60.0 * (1.0 - v)) as u8,
            b: (70.0 + 90.0 * (1.0 - v)) as u8,
            a: 255,
        };
    }
    slint_interpreter::Image::from_rgba8(buf)
}
