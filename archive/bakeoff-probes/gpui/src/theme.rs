//! Theme tokens (daemon `theme.tokens`) with fallbacks only for missing keys.

use gpui::{Hsla, Rgba};
use serde_json::Value;

#[derive(Clone, Default)]
pub struct Theme {
    tokens: serde_json::Map<String, Value>,
}

impl Theme {
    pub fn from_doc(doc: &Value) -> Self {
        Self { tokens: doc["tokens"].as_object().cloned().unwrap_or_default() }
    }
    pub fn num(&self, k: &str, d: f32) -> f32 {
        self.tokens.get(k).and_then(Value::as_f64).map(|v| v as f32).unwrap_or(d)
    }
    pub fn str(&self, k: &str, d: &str) -> String {
        self.tokens.get(k).and_then(Value::as_str).unwrap_or(d).to_string()
    }
    pub fn rgba(&self, k: &str, d: &str) -> Rgba {
        parse_hex(self.tokens.get(k).and_then(Value::as_str).unwrap_or(d))
    }
    pub fn color(&self, k: &str, d: &str) -> Hsla {
        self.rgba(k, d).into()
    }
    pub fn color_a(&self, k: &str, d: &str, a: f32) -> Hsla {
        let mut c = self.rgba(k, d);
        c.a = a;
        c.into()
    }
    pub fn surface(&self) -> Hsla {
        self.color_a("color.surface", "#1b1a1e", self.num("color.surface_alpha", 0.85))
    }
    pub fn bezier(&self, k: &str, d: [f32; 4]) -> [f32; 4] {
        let arr = self.tokens.get(k).and_then(Value::as_array);
        match arr {
            Some(a) if a.len() == 4 => {
                let f = |i: usize| a[i].as_f64().unwrap_or(0.0) as f32;
                [f(0), f(1), f(2), f(3)]
            }
            _ => d,
        }
    }
    pub fn family(&self) -> String {
        self.str("font.family", "sans-serif")
    }
    pub fn family_jp(&self) -> String {
        self.str("font.family_jp", "sans-serif")
    }
    /// Pick the font family for a string: Japanese text uses `font.family_jp`.
    pub fn family_for(&self, text: &str) -> String {
        if text.chars().any(|c| !c.is_ascii() && ('\u{3000}'..='\u{9fff}').contains(&c)) {
            self.family_jp()
        } else {
            self.family()
        }
    }
}

fn parse_hex(s: &str) -> Rgba {
    let h = s.trim_start_matches('#');
    let p = |i: usize| u8::from_str_radix(h.get(i..i + 2).unwrap_or("00"), 16).unwrap_or(0) as f32 / 255.0;
    Rgba { r: p(0), g: p(2), b: p(4), a: if h.len() >= 8 { p(6) } else { 1.0 } }
}

/// CSS cubic-bezier(x1,y1,x2,y2) evaluated at time fraction `x` in 0..=1.
pub fn bezier(b: [f32; 4], x: f32) -> f32 {
    let x = x.clamp(0.0, 1.0);
    let sample = |t: f32, a: f32, c: f32| {
        let u = 1.0 - t;
        3.0 * u * u * t * a + 3.0 * u * t * t * c + t * t * t
    };
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..24 {
        let mid = (lo + hi) / 2.0;
        if sample(mid, b[0], b[2]) < x { lo = mid } else { hi = mid }
    }
    sample((lo + hi) / 2.0, b[1], b[3])
}
