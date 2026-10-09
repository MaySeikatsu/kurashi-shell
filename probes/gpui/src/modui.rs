//! Generic runtime renderer for mod widget `ui` trees (row / column / text+bind / icon).
//! Pure data → elements; works for trees never seen at compile time.

use gpui::{AnyElement, div, prelude::*, px};
use serde_json::Value;

use crate::theme::Theme;

fn glyph(name: &str) -> &'static str {
    match name {
        "leaf" => "❦",
        "volume" => "♪",
        "clock" => "◷",
        "bell" => "♢",
        _ => "◆",
    }
}

pub fn build(node: &Value, state: &Value, th: &Theme, fs: f32) -> AnyElement {
    let kids = |n: &Value| -> Vec<AnyElement> {
        n["children"]
            .as_array()
            .map(|a| a.iter().map(|c| build(c, state, th, fs)).collect())
            .unwrap_or_default()
    };
    let gap = px(th.num("space.xs", 4.0));
    match node["type"].as_str().unwrap_or("") {
        "row" => div().flex().flex_row().items_center().gap(gap).children(kids(node)).into_any_element(),
        "column" => div().flex().flex_col().gap(gap).children(kids(node)).into_any_element(),
        "text" => {
            let txt = match node["bind"].as_str() {
                Some(k) => match &state[k] {
                    Value::String(s) => s.clone(),
                    Value::Null => String::new(),
                    v => v.to_string(),
                },
                None => node["text"].as_str().unwrap_or("").to_string(),
            };
            let fam = th.family_for(&txt);
            div().font_family(fam).whitespace_nowrap().child(txt).into_any_element()
        }
        "icon" => div()
            .text_color(th.color("color.tertiary", "#8fa868"))
            .child(glyph(node["name"].as_str().unwrap_or("")))
            .into_any_element(),
        other => div().child(format!("<{other}?>")).into_any_element(),
    }
}
