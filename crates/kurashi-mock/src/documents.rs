//! Document builders. Each shape is the one kurashid serves: `svc.brightness` follows
//! kurashi-services `brightness::read`, `bindings` follows kurashid `bindings::resolve` over
//! defaults only (no user config). The rest follows PROTOCOL §8.

use kurashi_core::Source;
use kurashi_schema::Registry;
use serde_json::{Map, Value, json};

/// Full scale of the fake backlight (what sysfs reports as `max_brightness`).
pub const BRIGHTNESS_MAX: u32 = 1000;

pub fn clock() -> Value {
    let now = chrono::Local::now();
    json!({
        "hh": now.format("%H").to_string(),
        "mm": now.format("%M").to_string(),
        "date": now.format("%Y-%m-%d").to_string(),
        "weekday": now.format("%a").to_string(),
    })
}

pub fn workspaces(outputs: &[String], focused_idx: u32) -> Value {
    let mut map = Map::new();
    for name in outputs
        .iter()
        .map(String::as_str)
        .chain(std::iter::once("*"))
    {
        let list: Vec<Value> = (1..=5)
            .map(|i| json!({"id": i, "idx": i, "focused": i == focused_idx, "occupied": i <= 3}))
            .collect();
        map.insert(name.to_string(), Value::Array(list));
    }
    json!({ "outputs": map })
}

/// Wa-iro (和色) dark tokens — the probe's theme document (DESIGN-SYSTEM §6).
pub fn theme() -> Value {
    json!({ "tokens": {
        "color.surface": "#1b1a1e",
        "color.surface_container": "#252329",
        "color.surface_container_high": "#2f2c33",
        "color.on_surface": "#e9e4d8",
        "color.on_surface_variant": "#b9b2a6",
        "color.outline": "#5a5560",
        "color.accent": "#c9404b",
        "color.on_accent": "#fff6f1",
        "color.secondary": "#5b7fa6",
        "color.tertiary": "#8fa868",
        "color.surface_alpha": 0.82,
        "radius.sm": 6, "radius.md": 12, "radius.lg": 18, "radius.full": 999,
        "space.xs": 4, "space.sm": 8, "space.md": 12, "space.lg": 16, "space.xl": 24,
        "font.family": "Inter", "font.family_jp": "Noto Sans CJK JP",
        "font.size.caption": 11, "font.size.label": 12, "font.size.body": 13, "font.size.title": 16,
        "bar.height": 36,
        "motion.quick_ms": 120, "motion.standard_ms": 220, "motion.emphasized_ms": 320,
        "motion.easing.enter": [0.05, 0.7, 0.1, 1.0],
        "motion.easing.exit": [0.3, 0.0, 0.8, 0.15],
        "blur": true
    }})
}

/// `svc.brightness` for a fake backlight at `value / BRIGHTNESS_MAX`.
pub fn brightness(value: u32) -> Value {
    json!({
        "present": true,
        "device": "mock",
        "value": value,
        "max": BRIGHTNESS_MAX,
        "percent": (f64::from(value) / f64::from(BRIGHTNESS_MAX) * 1000.0).round() / 10.0,
    })
}

/// `bindings`: every `<component>.input.<slot>` whose schema default is a non-empty action, as
/// `{action, source}`. Unbound slots are absent, never null. Derived from the registry, so the
/// mock cannot drift from the schema's island defaults.
pub fn bindings(registry: &Registry) -> Value {
    let mut out = Map::new();
    for meta in registry.iter() {
        let Some((component, slot)) = meta.key.split_once(".input.") else {
            continue;
        };
        let Some(action) = meta.default.as_str().filter(|a| !a.is_empty()) else {
            continue;
        };
        let source = serde_json::to_value(Source::Default).expect("source serializes");
        out.entry(component.to_owned())
            .or_insert_with(|| json!({}))
            .as_object_mut()
            .expect("object")
            .insert(slot.to_owned(), json!({"action": action, "source": source}));
    }
    Value::Object(out)
}
