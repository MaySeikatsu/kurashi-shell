//! The `theme` document (DESIGN-SYSTEM §1–§3): resolved config → `kurashi-theme` pipeline → flat
//! token map. Recomputed on config changes only; renderers never compute colours (rule 4).
//!
//! Tokens `decor.<slot>` and `decor.<key>` (W25, K50, K53, W53.0a): the look in effect's `[slots]` (`frame`, `title`,
//! …) and `[decor]` metrics — `theme.look` through `kurashi_theme::appearance::find`, every default filled in by the
//! theme crate. The frontend's hosts load the component of that name (`frontend/components/frames/`,
//! `frontend/components/decor/<slot>/`); it is data, no renderer compares it (rule 4).
//!
//! K53: the document also carries the preview cards of every style (`styles`) and look (`looks`, drawn in the palette
//! and scheme in effect: a look has no colours) and `appearance {style, look, palette, overrides}` — the keys that
//! differ from the style, for Settings' "changed from the style" line.

use std::sync::Arc;

use kurashi_theme::{
    Axes, Colorblind, ContrastLevel, Density, FontProvider, Material, MotionProfile, Scheme, Shape,
    Source, ThemeInput,
};
use serde_json::{Value, json};

use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "theme";

pub(crate) fn s(store: &ConfigStore, key: &str) -> String {
    store
        .get(key, None)
        .and_then(|p| p.value.as_str().map(String::from))
        .unwrap_or_default()
}
pub(crate) fn f(store: &ConfigStore, key: &str, dflt: f64) -> f64 {
    store
        .get(key, None)
        .and_then(|p| p.value.as_f64())
        .unwrap_or(dflt)
}
pub(crate) fn b(store: &ConfigStore, key: &str) -> bool {
    store
        .get(key, None)
        .and_then(|p| p.value.as_bool())
        .unwrap_or(false)
}

/// What the seasonal tint does today (I281): the solar term, the season it is nearest, how far hues lean and toward
/// which hue. `{}` while the tint is off.
fn season_detail(date: Option<kurashi_theme::season::Date>) -> Value {
    let Some(d) = date else { return json!({}) };
    let term = kurashi_theme::season::solar_term(d);
    let (hue, near) = kurashi_theme::season::season_hue(term);
    json!({
        "term": term.ja,
        "romaji": term.romaji,
        "season": near,
        "hue": hue.round(),
        "strength": (kurashi_theme::stages::SEASON_STRENGTH * 100.0).round(),
    })
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

/// The wallpaper mod's document (K26): its `theme.image` is the picture palette `wallpaper` uses (K34).
pub const WALLPAPER_DOC: &str = "mod.wallpaper";
/// The palette name that takes the colours of the wallpaper picture (K34).
pub const WALLPAPER_PALETTE: &str = "wallpaper";

/// The picture palette `wallpaper` takes its colours from: the wallpaper mod's `theme.image`, while
/// the mod is on and has applied a picture with its theme. Only a document with a subscriber counts:
/// the mod's service fills the hub only then, so an unwatched snapshot may be stale (Shōjiki).
pub fn wallpaper_picture(hub: &Hub) -> Option<std::path::PathBuf> {
    if hub.subscribers(WALLPAPER_DOC) == 0 {
        return None;
    }
    let (_, doc) = hub.snapshot(WALLPAPER_DOC).ok()?;
    doc["theme"]["image"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(Into::into)
}

/// K55: the scheme a mode resolves to, with why: `""` (dark or light chosen), `os` / `os_unknown` (mode `auto`: the
/// portal's preference, or none — then dark), `wallpaper` / `wallpaper_waiting` (mode `wallpaper`: the picture's
/// mean lightness, or no picture yet — then dark).
pub fn effective_scheme(
    store: &ConfigStore,
    picture: Option<&std::path::Path>,
) -> (Scheme, &'static str) {
    use crate::os_scheme::{Pref, get};
    match s(store, "theme.colors.scheme").as_str() {
        "light" => (Scheme::Light, ""),
        "auto" => match get() {
            Pref::Light => (Scheme::Light, "os"),
            Pref::Dark => (Scheme::Dark, "os"),
            // I156: no preference anywhere — light by day, dark at night.
            Pref::Unknown => match crate::texture::is_day(store, chrono::Local::now()) {
                (true, "sun") => (Scheme::Light, "os_unknown_sun"),
                (false, "sun") => (Scheme::Dark, "os_unknown_sun"),
                (true, _) => (Scheme::Light, "os_unknown_day"),
                (false, _) => (Scheme::Dark, "os_unknown_day"),
            },
        },
        "wallpaper" => match picture.and_then(|p| kurashi_theme::stages::wallpaper_file(p).ok()) {
            Some(x) if x.is_light() => (Scheme::Light, "wallpaper"),
            Some(_) => (Scheme::Dark, "wallpaper"),
            None => (Scheme::Dark, "wallpaper_waiting"),
        },
        _ => (Scheme::Dark, ""),
    }
}

/// The theme's 5-minute tick is wanted: the daytime light, or scheme `auto` following the day (I156).
fn wants_tick(store: &ConfigStore) -> bool {
    crate::texture::wants_sun(store)
        || (s(store, "theme.colors.scheme") == "auto"
            && crate::os_scheme::get() == crate::os_scheme::Pref::Unknown)
}

fn scheme_name(s: Scheme) -> &'static str {
    match s {
        Scheme::Light => "light",
        Scheme::Dark => "dark",
    }
}

/// Whether the theme needs the wallpaper's picture: palette `wallpaper` or scheme `wallpaper` (K34, K55).
fn wants_picture(store: &ConfigStore) -> bool {
    s(store, "theme.colors.palette") == WALLPAPER_PALETTE
        || s(store, "theme.colors.scheme") == WALLPAPER_PALETTE
        || crate::texture::wants_wallpaper(store)
}

/// The picture the wallpaper shows now, for its light (K59): the theme's picture, else the first output's.
pub fn wallpaper_shown(hub: &Hub) -> Option<std::path::PathBuf> {
    if hub.subscribers(WALLPAPER_DOC) == 0 {
        return None;
    }
    let (_, doc) = hub.snapshot(WALLPAPER_DOC).ok()?;
    doc["theme"]["image"]
        .as_str()
        .or_else(|| {
            doc["outputs"]
                .as_object()?
                .values()
                .find_map(|o| o["path"].as_str())
        })
        .filter(|s| !s.is_empty())
        .map(Into::into)
}

/// Map resolved config (provenance already applied: a11y forcing, profiles, …) onto the input.
pub fn input_from(store: &ConfigStore) -> ThemeInput {
    input_with(store, None)
}

/// [`input_from`] with the wallpaper picture (K34): palette `wallpaper` reads the picture, or falls
/// back to the default palette while there is none (the document says so in `notes`).
pub fn input_with(store: &ConfigStore, picture: Option<&std::path::Path>) -> ThemeInput {
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
        radius: f(store, "theme.shape.radius", 18.0),
        squircle: f(store, "theme.shape.squircle", 0.77),
        material: if s(store, "theme.material.kind") == "solid" {
            Material::Solid
        } else {
            Material::Translucent
        },
        opacity: f(store, "theme.material.opacity", 0.85),
        blur: b(store, "theme.material.blur"),
        motion: match s(store, "theme.motion.profile").as_str() {
            "none" => MotionProfile::None,
            "lively" => MotionProfile::Lively,
            "calm" => MotionProfile::Calm,
            _ => MotionProfile::Expressive,
        },
        motion_speed: f(store, "theme.motion.speed", 1.0),
        density: match s(store, "theme.density").as_str() {
            "compact" => Density::Compact,
            "airy" => Density::Airy,
            _ => Density::Regular,
        },
        type_scale: f(store, "theme.typography.scale", 1.0),
        chrome: kurashi_theme::Chrome::parse(&s(store, "theme.chrome")),
        frame_outline: match s(store, "theme.frame_outline").as_str() {
            "on" => kurashi_theme::FrameOutline::On,
            "off" => kurashi_theme::FrameOutline::Off,
            _ => kurashi_theme::FrameOutline::Auto,
        },
        outline_ink: match s(store, "theme.outline_ink").as_str() {
            v @ ("text" | "accent") => v.into(),
            _ => "outline".into(),
        },
        elevation: s(store, "theme.material.elevation"),
        elevation_strength: f(store, "theme.material.elevation_strength", 1.0),
        elevation_pointer: b(store, "theme.material.elevation_pointer"),
        ..Axes::default()
    };
    let chain = families("theme.typography.family");
    if !chain.is_empty() {
        axes.font_chain = chain;
    }
    let chain_jp = families("theme.typography.family_jp");
    if !chain_jp.is_empty() {
        axes.font_chain_jp = chain_jp;
    }
    if b(store, "a11y.large_text") {
        axes.type_scale = axes.type_scale.max(1.25);
    }
    let palette = s(store, "theme.colors.palette");
    let source = match (palette.as_str(), picture) {
        (WALLPAPER_PALETTE, Some(path)) => Source::WallpaperFile(path.to_path_buf()),
        (WALLPAPER_PALETTE, None) => ThemeInput::default().source,
        _ => Source::Palette(palette),
    };
    ThemeInput {
        source,
        scheme: effective_scheme(store, picture).0,
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
        ink: match s(store, "theme.colors.ink").as_str() {
            "" | "palette" => kurashi_theme::Ink::Palette,
            "custom" => kurashi_theme::color::Rgb::parse(&s(store, "theme.colors.ink_custom"))
                .map_or(kurashi_theme::Ink::Palette, kurashi_theme::Ink::Custom),
            name => kurashi_theme::Ink::Named(name.to_owned()),
        },
        axes,
        // W53.0a: the look in effect's slots and `[decor]` (its frame was `decor.frame` before; the same value).
        decor: look_decor(store),
        ..ThemeInput::default()
    }
}

/// `styles` (K45, I104, K53): each style's own look, for Settings' preview cards. Packs and the installed fonts do not
/// change while the daemon runs, so they are resolved once.
fn style_previews(fonts: &dyn FontProvider) -> Value {
    static PREVIEWS: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    PREVIEWS
        .get_or_init(|| {
            use kurashi_theme::appearance::{Kind, all};
            Value::Array(
                all(Kind::Style)
                    .iter()
                    .filter_map(|p| kurashi_theme::style_preview(&p.name, fonts))
                    .collect(),
            )
        })
        .clone()
}

/// `looks` (K53): each look in the palette and scheme in effect, resolved once per pair.
fn look_previews(palette: &str, scheme: &str, fonts: &dyn FontProvider) -> Value {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};
    static CACHE: OnceLock<Mutex<HashMap<(String, String), Value>>> = OnceLock::new();
    let key = (palette.to_owned(), scheme.to_owned());
    let mut cache = CACHE
        .get_or_init(Default::default)
        .lock()
        .expect("look previews");
    cache
        .entry(key)
        .or_insert_with(|| {
            use kurashi_theme::appearance::{Kind, all};
            Value::Array(
                all(Kind::Look)
                    .iter()
                    .filter_map(|p| kurashi_theme::look_preview(&p.name, palette, scheme, fonts))
                    .collect(),
            )
        })
        .clone()
}

/// `palettes` (K53): each bundled palette in the look and scheme in effect, resolved once per pair.
fn palette_previews(look: &str, scheme: &str, fonts: &dyn FontProvider) -> Value {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};
    static CACHE: OnceLock<Mutex<HashMap<(String, String), Value>>> = OnceLock::new();
    let key = (look.to_owned(), scheme.to_owned());
    let mut cache = CACHE
        .get_or_init(Default::default)
        .lock()
        .expect("palette previews");
    cache
        .entry(key)
        .or_insert_with(|| {
            Value::Array(
                kurashi_theme::bundled_names()
                    .iter()
                    .filter_map(|n| kurashi_theme::palette_preview(n, look, scheme, fonts))
                    .collect(),
            )
        })
        .clone()
}

/// The look in effect's decor pack (`[slots]`, `[decor]`; W25, K53, W53.0a): the defaults for a look that is not there.
fn look_decor(store: &ConfigStore) -> kurashi_theme::Decor {
    kurashi_theme::appearance::find(
        kurashi_theme::appearance::Kind::Look,
        &s(store, "theme.look"),
    )
    .map(|d| d.decor_input())
    .unwrap_or_default()
}

/// K60: each named ink's shade in a scheme, for Settings' swatches.
fn inks(dark: bool) -> Value {
    ["blue", "black", "sepia", "red", "green", "violet"]
        .iter()
        .filter_map(|n| {
            kurashi_theme::stages::ink_color(n, dark).map(|c| ((*n).to_owned(), json!(c.hex())))
        })
        .collect::<serde_json::Map<String, Value>>()
        .into()
}

/// A switch that is on and in effect: not waiting on its `requires` (K21), so a value the UI shows as inert never acts.
fn on_in_effect(store: &ConfigStore, key: &str) -> bool {
    store.get(key, None).is_some_and(|p| {
        p.value.as_bool() == Some(true) && p.reason.as_deref() != Some("settings.inert.requires")
    })
}

/// K67: the shadow vector with the user's strength and direction, or — `theme.material.shadow_follow`, in effect only
/// with a material — away from the light in effect (`light.dir`, already in `t`: for a pointer or spotlight that is
/// where the lamp rests, so shadows never move with the pointer). After the texture tokens; a theme override of a
/// `shadow.*` key keeps its value.
fn shadow_tokens(store: &ConfigStore, t: &mut serde_json::Map<String, Value>, input: &ThemeInput) {
    let light = on_in_effect(store, "theme.material.shadow_follow")
        .then(|| t.get("light.dir").and_then(Value::as_array).cloned())
        .flatten()
        .and_then(|a| {
            let v: Vec<f64> = a.iter().filter_map(Value::as_f64).collect();
            (v.len() == 3).then(|| [v[0], v[1], v[2]])
        });
    let spec = kurashi_theme::tokens::Shadow {
        strength: f(store, "theme.material.shadow", 1.0),
        angle: f(store, "theme.material.shadow_angle", 180.0),
        light,
    };
    let mut map: kurashi_theme::TokenMap = t
        .iter()
        .filter(|(k, _)| k.starts_with("chrome."))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    kurashi_theme::tokens::shadow_tokens(&mut map, &spec);
    for k in ["shadow.dx", "shadow.dy", "shadow.alpha_scale"] {
        if !input.overrides.contains_key(k)
            && let Some(v) = map.remove(k)
        {
            t.insert(k.into(), v);
        }
    }
    // W57 (K78): the surfaces' elevation falls along `elevation.dir` = [x, y, length factor]: away from the light in
    // effect under `follow` (the light is shell-wide: any chrome, any material; longer when it stands low), else along
    // the shadow direction. The pointer's lamp turns it in the frontend (`elevation.pointer`).
    let follow = t.get("elevation.mode").and_then(Value::as_str) == Some("follow");
    let light_dir = t
        .get("light.dir")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_f64).collect::<Vec<f64>>())
        .filter(|v| v.len() == 3)
        .map(|v| [v[0], v[1], v[2]]);
    let (u, k) = light_dir
        .filter(|_| follow)
        .and_then(kurashi_theme::tokens::shadow_from_light)
        .unwrap_or_else(|| (kurashi_theme::tokens::shadow_unit(spec.angle), 1.0));
    let r = |v: f64| (v * 1000.0).round() / 1000.0 + 0.0;
    if !input.overrides.contains_key("elevation.dir") {
        t.insert(
            "elevation.dir".into(),
            serde_json::json!([r(u[0]), r(u[1]), r(k)]),
        );
    }
}

/// Document value; on a pipeline error (e.g. unknown palette) the previous theme stays and the
/// error is reported in `error` — never a half-applied theme.
pub fn document(store: &ConfigStore, fonts: &dyn FontProvider, previous: Option<&Value>) -> Value {
    document_with(store, fonts, previous, None)
}

/// [`document`] with the wallpaper picture for palette `wallpaper` (K34).
pub fn document_with(
    store: &ConfigStore,
    fonts: &dyn FontProvider,
    previous: Option<&Value>,
    picture: Option<&std::path::Path>,
) -> Value {
    let input = input_with(store, picture);
    let waiting = s(store, "theme.colors.palette") == WALLPAPER_PALETTE && picture.is_none();
    match kurashi_theme::resolve(&input, fonts) {
        Ok(out) => {
            let mut tokens = serde_json::Map::from_iter(out.tokens);
            // Config-owned sizes the frontend binds as tokens (PROTOCOL §8).
            if let Some(h) = store.get("bar.height", None) {
                tokens.insert("bar.height".into(), h.value);
            }
            // K62: the pen — how outlines and (through a layer) text are drawn; values in effect (a11y forces them).
            tokens.insert("pen.line".into(), json!(s(store, "theme.pen.line")));
            for k in [
                "pressure",
                "breaks",
                "fade",
                "wobble",
                "text_pressure",
                "text_breaks",
                "text_fade",
                "text_wobble",
            ] {
                tokens.insert(
                    format!("pen.{k}"),
                    json!(f(store, &format!("theme.pen.{k}"), 0.0)),
                );
            }
            let texture_notes = crate::texture::tokens(store, &mut tokens, chrono::Local::now());
            shadow_tokens(store, &mut tokens, &input);
            let mut notes: Vec<Value> = out
                .notes
                .iter()
                .map(|n| json!({"stage": n.stage, "text": n.text}))
                .chain(
                    texture_notes
                        .into_iter()
                        .map(|text| json!({"stage": "texture", "text": text})),
                )
                .collect();
            // Shōjiki: the theme says it is not the wallpaper's yet, instead of looking like it.
            if waiting {
                notes.push(json!({"stage": "source", "text": "theme.note.wallpaper_waiting"}));
            }
            json!({
                "tokens": tokens,
                "notes": notes,
                "appearance": {
                    "style": s(store, "theme.style"),
                    "look": s(store, "theme.look"),
                    "palette": s(store, "theme.colors.palette"),
                    "scheme": s(store, "theme.colors.scheme"),
                    "scheme_effective": scheme_name(input.scheme),
                    "scheme_detail": effective_scheme(store, picture).1,
                    "scheme_before": store.scheme_before(),
                    "texture_before": store.texture_before(),
                    // K59: why the daytime light is where it is (`sun`: the weather mod's place, `day`: a 06:00–18:00
                    // day without one; `""` for the other modes); K60: each ink's shade in the scheme in effect.
                    "light_detail": crate::texture::light(store, chrono::Local::now()).detail,
                    "inks": inks(input.scheme == Scheme::Dark),
                    // K61 (row 340): each light colour as resolved, for Settings' swatches.
                    "light_colors": crate::texture::light_colors(store, chrono::Local::now()),
                    "overrides": store.appearance_overrides(),
                    // I281: the season the colours lean toward today, for Settings' line under the switch ({} while off).
                    "season": season_detail(input.season),
                },
            })
        }
        Err(e) => {
            tracing::warn!(error = %e, "theme resolution failed; keeping previous theme");
            let mut prev = previous.cloned().unwrap_or_else(|| json!({"tokens": {}}));
            prev["error"] = json!(e.to_string());
            prev
        }
    }
}

/// `theme.previews` (K53): the preview cards of every style, look (in the palette and scheme in effect) and palette (in
/// the look and scheme in effect) — a document of its own, so only Settings, which shows them, receives them.
pub fn previews(
    store: &ConfigStore,
    fonts: &dyn FontProvider,
    picture: Option<&std::path::Path>,
) -> Value {
    // The wallpaper's palette has no file to preview a look in; its looks show in the bundled default.
    let palette = match s(store, "theme.colors.palette") {
        p if kurashi_theme::bundled_names().contains(&p.as_str()) => p,
        _ => "wa-iro".to_owned(),
    };
    let scheme = scheme_name(effective_scheme(store, picture).0);
    json!({
        "styles": style_previews(fonts),
        "looks": look_previews(&palette, scheme, fonts),
        "palettes": palette_previews(&s(store, "theme.look"), scheme, fonts),
    })
}

pub const PREVIEWS_DOC: &str = "theme.previews";

/// Starts and stops the material swatches with the previews' first and last subscriber.
struct SwatchWatch;

impl crate::hub::Provider for SwatchWatch {
    fn start(&self, _hub: Arc<Hub>) {
        crate::texture::want_swatches(true);
    }

    fn stop(&self) {
        crate::texture::want_swatches(false);
    }
}

/// Register `theme` and recompute it whenever config changes.
pub fn register(
    hub: &Arc<Hub>,
    store: &Arc<ConfigStore>,
    fonts: Arc<dyn FontProvider + Send + Sync>,
) {
    let pic = wallpaper_picture(hub);
    crate::texture::set_wallpaper(wallpaper_shown(hub));
    let first = document_with(store, fonts.as_ref(), None, pic.as_deref());
    if let Some(tokens) = first.get("tokens").and_then(Value::as_object) {
        crate::texture::update_bake(store, tokens);
    }
    let mut shown = previews(store, fonts.as_ref(), pic.as_deref());
    if let Some(tokens) = first.get("tokens").and_then(Value::as_object) {
        shown["textures"] = crate::texture::swatches(store, tokens);
    }
    hub.register(DOC, first, None);
    // K59: the material swatches are made only while someone (Settings) watches the previews.
    hub.register(PREVIEWS_DOC, shown, Some(Arc::new(SwatchWatch)));
    // K55: scheme `auto` follows the portal's preference, watched only while that mode is chosen.
    let watcher = Arc::new(crate::os_scheme::Watcher::default());
    let follow = {
        let (hub, store, fonts) = (hub.clone(), Arc::downgrade(store), fonts.clone());
        let again: Arc<dyn Fn() + Send + Sync> = Arc::new(move || {
            if let Some(store) = store.upgrade() {
                republish(&hub, &store, fonts.as_ref());
            }
        });
        let watcher = watcher.clone();
        move |store: &ConfigStore| {
            watcher.want(s(store, "theme.colors.scheme") == "auto", again.clone());
        }
    };
    follow(store);
    // K59: a texture tile became ready, or the outputs' scale changed.
    {
        let (hub, store, fonts) = (hub.clone(), Arc::downgrade(store), fonts.clone());
        crate::texture::on_ready(Arc::new(move || {
            if let Some(store) = store.upgrade() {
                republish(&hub, &store, fonts.as_ref());
            }
        }));
    }
    // K59: the daytime light moves with the sun — a 5-minute tick, only while that light is chosen (Ma); I156: also
    // while scheme `auto` has no system preference and follows the day.
    let (sun_tx, mut sun_rx) = tokio::sync::watch::channel(wants_tick(store));
    {
        let (hub, fonts) = (hub.clone(), fonts.clone());
        store.on_change(move |store| {
            follow(store);
            sun_tx.send_if_modified(|on| {
                let want = wants_tick(store);
                std::mem::replace(on, want) != want
            });
            republish(&hub, store, fonts.as_ref());
        });
    }
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        let (hub, store, fonts) = (hub.clone(), Arc::downgrade(store), fonts.clone());
        rt.spawn(async move {
            loop {
                if !*sun_rx.borrow_and_update() {
                    if sun_rx.changed().await.is_err() {
                        break;
                    }
                    continue;
                }
                tokio::select! {
                    () = tokio::time::sleep(std::time::Duration::from_secs(300)) => {
                        let Some(store) = store.upgrade() else { break };
                        republish(&hub, &store, fonts.as_ref());
                    }
                    r = sun_rx.changed() => if r.is_err() { break },
                }
            }
        });
    }
    // K49: the chosen apps follow the theme document.
    crate::theme_export::register(hub, store);
    // W28: the greeter's copy of this look (greeter_cache.rs).
    crate::greeter_cache::register(hub);
    // K34: palette `wallpaper` follows the wallpaper mod's picture. Event-driven (the hub's change
    // stream, filtered to the mod's document, `mods` and `config`); nothing runs while neither the
    // picture nor the palette changes (Ma). The picture is extracted on a blocking thread first, so
    // the republish hits the cache.
    let Ok(rt) = tokio::runtime::Handle::try_current() else {
        return;
    };
    let (hub, store) = (hub.clone(), store.clone());
    let mut events = hub.events();
    rt.spawn(async move {
        let mut held = false;
        hold_wallpaper(&hub, &store, &mut held);
        let mut last = (wallpaper_picture(&hub), wallpaper_shown(&hub));
        loop {
            match events.recv().await {
                Ok(msg) => match msg.as_ref() {
                    kurashi_ipc::ServerMsg::Snap { doc, .. }
                    | kurashi_ipc::ServerMsg::Patch { doc, .. }
                        if [WALLPAPER_DOC, "mods", crate::config::DOC].contains(&doc.as_str()) => {}
                    _ => continue,
                },
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
            hold_wallpaper(&hub, &store, &mut held);
            let now = (wallpaper_picture(&hub), wallpaper_shown(&hub));
            if now == last {
                continue;
            }
            last = now.clone();
            if !wants_picture(&store) {
                continue;
            }
            if let Some(path) = now.0 {
                let _ = tokio::task::spawn_blocking(move || {
                    kurashi_theme::stages::wallpaper_file(&path)
                })
                .await;
            }
            republish(&hub, &store, fonts.as_ref());
        }
    });
}

/// Holds a subscription to the wallpaper mod's document while palette `wallpaper` is chosen and the
/// mod serves it: its service fills the hub only for subscribers. A disable drops the document with
/// its subscribers, so a hold whose document is gone (or registered again, unwatched) is renewed.
fn hold_wallpaper(hub: &Hub, store: &ConfigStore, held: &mut bool) {
    let exists = hub.snapshot(WALLPAPER_DOC).is_ok();
    if *held && (!exists || hub.subscribers(WALLPAPER_DOC) == 0) {
        *held = false;
    }
    let want = exists && wants_picture(store);
    if want && !*held {
        *held = hub.subscribe(WALLPAPER_DOC).is_ok();
    } else if !want && *held {
        hub.unsubscribe(WALLPAPER_DOC);
        *held = false;
    }
}

fn republish(hub: &Hub, store: &ConfigStore, fonts: &(dyn FontProvider + Send + Sync)) {
    let prev = hub.snapshot(DOC).ok().map(|(_, v)| v);
    let pic = wallpaper_picture(hub);
    crate::texture::set_wallpaper(wallpaper_shown(hub));
    let mut next = document_with(store, fonts, prev.as_ref(), pic.as_deref());
    if next.get("error").is_none()
        && let Some(o) = next.as_object_mut()
    {
        o.remove("error");
    }
    let mut shown = previews(store, fonts, pic.as_deref());
    if let Some(tokens) = next.get("tokens").and_then(Value::as_object) {
        crate::texture::update_bake(store, tokens);
        shown["textures"] = crate::texture::swatches(store, tokens);
    }
    let _ = hub.set(DOC, next, None);
    let _ = hub.set(PREVIEWS_DOC, shown, None);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store_with(root: &std::path::Path, toml: &str) -> std::sync::Arc<ConfigStore> {
        std::fs::create_dir_all(root.join("config")).unwrap();
        std::fs::write(root.join("config/config.toml"), toml).unwrap();
        ConfigStore::open(
            Hub::new(),
            kurashi_schema::v1::registry(),
            kurashi_config::Paths::rooted(root),
            kurashi_config::Options::default(),
        )
    }

    /// W25, K53: the look in effect's frame travels as `decor.frame`; a look without one is `""`. A v1 file's
    /// `theme.decor` is migrated to the style of that name.
    #[test]
    fn decor_frame_token_follows_the_look_in_effect() {
        let root = std::env::temp_dir().join(format!("kurashid-frame-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let fonts = kurashi_theme::FakeFonts::new(&["Inter"]);
        let store = store_with(&root, "[theme]\ndecor = \"yorha\"\n");
        let doc = document(&store, &fonts, None);
        assert_eq!(doc["tokens"]["decor.frame"], "yorha", "{}", doc["error"]);
        assert_eq!(doc["appearance"]["style"], "yorha");
        // The style's own palette is in effect, at the theme layer.
        assert_eq!(doc["tokens"]["color.surface"], "#c9c5b0");
        assert!(
            doc["appearance"]["overrides"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        // A look picked over the style: its frame, the style's palette still.
        let doc = document(
            &store_with(
                &root,
                "schema_version = 2\n[theme]\nstyle = \"yorha\"\nlook = \"luna\"\n",
            ),
            &fonts,
            None,
        );
        // (win95 drew its edge with the bevel frame until W53.1 gave it the bevel chrome: luna keeps a frame.)
        assert_eq!(doc["tokens"]["decor.frame"], "luna");
        assert_eq!(doc["tokens"]["color.surface"], "#c9c5b0");
        assert_eq!(doc["appearance"]["overrides"], json!(["theme.look"]));
        let doc = document(
            &store_with(&root, "schema_version = 2\n[theme]\nstyle = \"sekai\"\n"),
            &fonts,
            None,
        );
        assert_eq!(doc["tokens"]["decor.frame"], "");
        let doc = document(
            &store_with(&root, "schema_version = 2\n[theme]\nstyle = \"none\"\n"),
            &fonts,
            None,
        );
        assert_eq!(doc["tokens"]["decor.frame"], "");
        assert_eq!(doc["appearance"]["look"], "kanso");
        let shown = previews(&store_with(&root, "schema_version = 2\n"), &fonts, None);
        assert!(shown["styles"].as_array().unwrap().len() > 10);
        assert_eq!(shown["looks"].as_array().unwrap().len(), 18);
        assert!(shown["palettes"].as_array().unwrap().len() > 10);
        let _ = std::fs::remove_dir_all(&root);
    }

    /// K67: the shadow vector — today's at the defaults; the user's strength and direction; away from the light (its
    /// resting direction for the pointer) only while following is in effect (a material is on).
    #[test]
    fn theme_shadow_tokens_follow_the_settings_and_the_light() {
        let root = std::env::temp_dir().join(format!("kurashid-shadow-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let fonts = kurashi_theme::FakeFonts::new(&["Inter"]);
        let tok = |toml: &str| {
            let doc = document(
                &store_with(
                    &root,
                    &format!("schema_version = 2\n[theme]\nstyle = \"none\"\n{toml}"),
                ),
                &fonts,
                None,
            );
            let t = &doc["tokens"];
            let n = |k: &str| t[k].as_f64().unwrap_or_else(|| panic!("{k}: {}", t[k]));
            (n("shadow.dx"), n("shadow.dy"), n("shadow.alpha_scale"))
        };
        // Defaults: straight down at the look's own length (keycap 4 px, soft 6 px, flat none).
        assert_eq!(tok("chrome = \"keycap\"\n"), (0.0, 4.0, 1.0));
        assert_eq!(tok("chrome = \"soft\"\n"), (0.0, 6.0, 1.0));
        assert_eq!(tok(""), (0.0, 0.0, 1.0));
        // Down to the right, twice as strong.
        let (dx, dy, a) =
            tok("chrome = \"keycap\"\n[theme.material]\nshadow = 2.0\nshadow_angle = 135\n");
        assert!(
            (dx - 5.66).abs() < 0.01 && (dy - 5.66).abs() < 0.01 && a == 2.0,
            "{dx} {dy}"
        );
        assert_eq!(
            tok("chrome = \"keycap\"\n[theme.material]\nshadow = 0.0\n"),
            (0.0, 0.0, 0.0)
        );
        // Following without a material is inert: the static direction stays.
        let follow =
            "chrome = \"keycap\"\n[theme.material]\nshadow_follow = true\nshadow_angle = 90\n";
        assert_eq!(tok(follow), (4.0, 0.0, 1.0));
        // With one, away from the light: from the top right (45°) the shadow falls down to the left.
        let lit = |mode: &str, angle: u32, elevation: u32| {
            tok(&format!(
                "{follow}[theme.texture]\nkind = \"paper\"\n[theme.light]\nmode = \"{mode}\"\nangle = {angle}\nelevation = {elevation}\n"
            ))
        };
        let (dx, dy, _) = lit("static", 45, 40);
        assert!(dx < -2.8 && dy > 2.8, "{dx} {dy}");
        let (dx, dy, _) = lit("static", 315, 40);
        assert!(dx > 2.8 && dy > 2.8, "{dx} {dy}");
        // A low light lengthens it (capped at twice); the pointer's lamp casts from where it rests.
        let (_, low, _) = lit("static", 0, 10);
        assert!((low - 8.0).abs() < 0.01, "{low}");
        assert_eq!(lit("pointer", 315, 40), lit("static", 315, 40));
        let _ = std::fs::remove_dir_all(&root);
    }

    /// K53: applying a style resets the appearance keys the user set and is one undoable change; a look keeps the
    /// style's palette.
    /// K55: the modes resolve with their reason; `wallpaper` reads the picture's lightness.
    #[test]
    fn scheme_modes_resolve_with_their_reason() {
        let root = std::env::temp_dir().join(format!("kurashid-modes-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let with = |mode: &str| {
            store_with(
                &root,
                &format!(
                    "schema_version = 2\n[theme]\nstyle = \"none\"\n[theme.colors]\nscheme = \"{mode}\"\n"
                ),
            )
        };
        assert_eq!(effective_scheme(&with("light"), None), (Scheme::Light, ""));
        assert_eq!(effective_scheme(&with("dark"), None), (Scheme::Dark, ""));
        assert_eq!(
            effective_scheme(&with("wallpaper"), None),
            (Scheme::Dark, "wallpaper_waiting")
        );
        // A pale picture is light, a dark one dark.
        for (rgb, want) in [
            ([235u8, 230, 220], Scheme::Light),
            ([30u8, 34, 48], Scheme::Dark),
        ] {
            let pic = root.join(format!("pic-{}.png", rgb[0]));
            image::RgbImage::from_fn(32, 32, |x, _| {
                image::Rgb([rgb[0], rgb[1].saturating_sub(x as u8), rgb[2]])
            })
            .save(&pic)
            .unwrap();
            assert_eq!(
                effective_scheme(&with("wallpaper"), Some(&pic)),
                (want, "wallpaper")
            );
        }
        // No portal in a test: `auto` is dark and says the system has no preference (unless the portal test runs).
        let (_, why) = effective_scheme(&with("auto"), None);
        assert!(why.starts_with("os_unknown") || why == "os", "{why}");
        // Schema default with no style: auto.
        let store = store_with(&root, "schema_version = 2\n[theme]\nstyle = \"none\"\n");
        assert_eq!(s(&store, "theme.colors.scheme"), "auto");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[tokio::test]
    async fn applying_a_style_resets_appearance_and_keeps_the_rest() {
        let root = std::env::temp_dir().join(format!("kurashid-style-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = store_with(
            &root,
            "schema_version = 2\n[theme]\nstyle = \"sekai\"\nchrome = \"flat\"\ndensity = \"airy\"\n[theme.colors]\ncontrast = \"high\"\nscheme = \"dark\"\n[bar]\nheight = 40\n",
        );
        assert_eq!(
            store.appearance_overrides(),
            ["theme.colors.scheme", "theme.density", "theme.chrome"]
        );
        assert_eq!(store.scheme_before(), None, "the user's own mode holds");
        let mut actions = crate::actions::ActionRegistry::default();
        store.register_actions(&mut actions);
        actions
            .invoke("theme.style.apply", json!({"name": "win95"}))
            .await
            .unwrap();
        let val = |k: &str| store.get(k, None).unwrap();
        assert_eq!(val("theme.style").value, "win95");
        assert_eq!(
            val("theme.chrome").source,
            kurashi_config::Source::Theme("look:win95".into())
        );
        assert_eq!(
            val("theme.density").source,
            kurashi_config::Source::Theme("style:win95".into())
        );
        // Not reset: accessibility, layout.
        assert_eq!(val("theme.colors.contrast").value, "high");
        assert_eq!(val("bar.height").value, 40);
        assert!(store.appearance_overrides().is_empty());
        // K55: light or dark follows the style; the user's dark is kept to go back to.
        assert_eq!(val("theme.colors.scheme").value, "light");
        assert_eq!(
            val("theme.colors.scheme").source,
            kurashi_config::Source::Theme("style:win95".into())
        );
        assert_eq!(store.scheme_before().as_deref(), Some("dark"));
        let fonts = kurashi_theme::FakeFonts::new(&["Inter"]);
        let doc = document(&store, &fonts, None);
        assert_eq!(doc["appearance"]["scheme_before"], "dark");
        assert_eq!(doc["appearance"]["scheme_effective"], "light");
        // A second style keeps the user's mode, not the first style's.
        actions
            .invoke("theme.style.apply", json!({"name": "sekai"}))
            .await
            .unwrap();
        assert_eq!(store.scheme_before().as_deref(), Some("dark"));
        actions
            .invoke("theme.scheme.restore", json!({}))
            .await
            .unwrap();
        assert_eq!(val("theme.colors.scheme").value, "dark");
        assert_eq!(
            val("theme.colors.scheme").source,
            kurashi_config::Source::User
        );
        assert_eq!(store.scheme_before(), None);
        assert!(
            actions
                .invoke("theme.scheme.restore", json!({}))
                .await
                .is_err(),
            "nothing to go back to while the user's mode holds"
        );
        actions
            .invoke("theme.style.apply", json!({"name": "win95"}))
            .await
            .unwrap();
        actions
            .invoke("theme.look.apply", json!({"name": "sekai"}))
            .await
            .unwrap();
        assert_eq!(val("theme.chrome").value, "keycap");
        assert_eq!(val("theme.colors.palette").value, "win95");
        let _ = std::fs::remove_dir_all(&root);
    }
}
