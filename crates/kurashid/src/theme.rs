//! The `theme` document (DESIGN-SYSTEM §1–§3): resolved config → `kurashi-theme` pipeline → flat
//! token map. Recomputed on config changes only; renderers never compute colours (rule 4).

use std::sync::Arc;

use kurashi_theme::{
    Axes, Colorblind, ContrastLevel, Density, FontProvider, Material, MotionProfile, Scheme, Shape,
    Source, ThemeInput,
};
use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "theme";

fn s(store: &ConfigStore, key: &str) -> String {
    store
        .get(key, None)
        .and_then(|p| p.value.as_str().map(String::from))
        .unwrap_or_default()
}
fn f(store: &ConfigStore, key: &str, dflt: f64) -> f64 {
    store
        .get(key, None)
        .and_then(|p| p.value.as_f64())
        .unwrap_or(dflt)
}
fn b(store: &ConfigStore, key: &str) -> bool {
    store
        .get(key, None)
        .and_then(|p| p.value.as_bool())
        .unwrap_or(false)
}

fn today() -> kurashi_theme::season::Date {
    use chrono::Datelike;
    let d = chrono::Local::now().date_naive();
    kurashi_theme::season::Date {
        year: d.year(),
        month: d.month() as u8,
        day: d.day() as u8,
    }
}

/// Map resolved config (provenance already applied: a11y forcing, profiles, …) onto the input.
pub fn input_from(store: &ConfigStore) -> ThemeInput {
    let families = |key: &str| -> Vec<String> {
        store
            .get(key, None)
            .and_then(|p| p.value.as_array().cloned())
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .map(String::from)
                    .collect()
            })
            .unwrap_or_default()
    };
    let mut axes = Axes {
        shape: match s(store, "theme.shape.corners").as_str() {
            "none" => Shape::None,
            "squircle" => Shape::Squircle,
            _ => Shape::Rounded,
        },
        radius_scale: f(store, "theme.shape.radius_scale", 1.0),
        material: match s(store, "theme.material.kind").as_str() {
            "solid" => Material::Solid,
            "glass" => Material::Glass,
            _ => Material::Translucent,
        },
        opacity: f(store, "theme.material.opacity", 0.85),
        blur: b(store, "theme.material.blur"),
        motion: match s(store, "theme.motion.profile").as_str() {
            "none" => MotionProfile::None,
            "lively" => MotionProfile::Lively,
            _ => MotionProfile::Calm,
        },
        motion_speed: f(store, "theme.motion.speed", 1.0),
        density: match s(store, "theme.density").as_str() {
            "compact" => Density::Compact,
            "airy" => Density::Airy,
            _ => Density::Regular,
        },
        type_scale: f(store, "theme.typography.scale", 1.0),
        ..Axes::default()
    };
    let chain = families("theme.typography.family");
    if !chain.is_empty() {
        axes.font_chain = chain;
    }
    if b(store, "a11y.large_text") {
        axes.type_scale = axes.type_scale.max(1.25);
    }
    ThemeInput {
        source: Source::Palette(s(store, "theme.colors.palette")),
        scheme: if s(store, "theme.colors.scheme") == "light" {
            Scheme::Light
        } else {
            Scheme::Dark
        },
        contrast: match s(store, "theme.colors.contrast").as_str() {
            "high" => ContrastLevel::High,
            "medium" => ContrastLevel::Medium,
            _ => ContrastLevel::Standard,
        },
        season: b(store, "theme.colors.season").then(today),
        colorblind: match s(store, "theme.colors.colorblind").as_str() {
            "protanopia" => Colorblind::Protanopia,
            "deuteranopia" => Colorblind::Deuteranopia,
            "tritanopia" => Colorblind::Tritanopia,
            _ => Colorblind::None,
        },
        oled: b(store, "theme.colors.oled"),
        axes,
        ..ThemeInput::default()
    }
}

/// Document value; on a pipeline error (e.g. unknown palette) the previous theme stays and the
/// error is reported in `error` — never a half-applied theme.
pub fn document(store: &ConfigStore, fonts: &dyn FontProvider, previous: Option<&Value>) -> Value {
    let input = input_from(store);
    match kurashi_theme::resolve(&input, fonts) {
        Ok(out) => {
            let mut tokens = serde_json::Map::from_iter(out.tokens);
            // Config-owned sizes the frontend binds as tokens (PROTOCOL §8).
            if let Some(h) = store.get("bar.height", None) {
                tokens.insert("bar.height".into(), h.value);
            }
            tokens.insert("blur".into(), json!(input.axes.blur));
            let notes: Vec<Value> = out
                .notes
                .iter()
                .map(|n| json!({"stage": n.stage, "text": n.text}))
                .collect();
            json!({"tokens": tokens, "notes": notes})
        }
        Err(e) => {
            tracing::warn!(error = %e, "theme resolution failed; keeping previous theme");
            let mut prev = previous.cloned().unwrap_or_else(|| json!({"tokens": {}}));
            prev["error"] = json!(e.to_string());
            prev
        }
    }
}

/// Register `theme` and recompute it whenever config changes.
pub fn register(
    hub: &Arc<Hub>,
    store: &Arc<ConfigStore>,
    fonts: Arc<dyn FontProvider + Send + Sync>,
) {
    hub.register(DOC, document(store, fonts.as_ref(), None), None);
    let hub = hub.clone();
    store.on_change(move |store| {
        let prev = hub.snapshot(DOC).ok().map(|(_, v)| v);
        let mut next = document(store, fonts.as_ref(), prev.as_ref());
        if next.get("error").is_none()
            && let Some(o) = next.as_object_mut()
        {
            o.remove("error");
        }
        let _ = hub.set(DOC, next, None);
    });
}
