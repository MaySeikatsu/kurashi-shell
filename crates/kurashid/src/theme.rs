//! The `theme` document (DESIGN-SYSTEM §1–§3): resolved config → `kurashi-theme` pipeline → flat
//! token map. Recomputed on config changes only; renderers never compute colours (rule 4).
//!
//! Token `decor.frame` (W25, K50, K53): the look in effect's `[slots] frame` — `theme.look` through
//! `kurashi_theme::appearance::find`, `""` for a look without one. The frontend loads the frame component of that
//! name (`frontend/components/frames/`); it is data, no renderer compares it (rule 4).
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
        chrome: match s(store, "theme.chrome").as_str() {
            "keycap" => kurashi_theme::Chrome::Keycap,
            "soft" => kurashi_theme::Chrome::Soft,
            "line" => kurashi_theme::Chrome::Line,
            _ => kurashi_theme::Chrome::Flat,
        },
        ..Axes::default()
    };
    let chain = families("theme.typography.family");
    if !chain.is_empty() {
        axes.font_chain = chain;
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

/// The look in effect's frame (`[slots] frame`), `""` when it has none (W25, K53).
fn decor_frame(store: &ConfigStore) -> String {
    kurashi_theme::appearance::find(
        kurashi_theme::appearance::Kind::Look,
        &s(store, "theme.look"),
    )
    .map(|d| d.frame)
    .unwrap_or_default()
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
            tokens.insert("blur".into(), json!(input.axes.blur));
            tokens.insert("decor.frame".into(), json!(decor_frame(store)));
            let mut notes: Vec<Value> = out
                .notes
                .iter()
                .map(|n| json!({"stage": n.stage, "text": n.text}))
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
                    "overrides": store.appearance_overrides(),
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
pub fn previews(store: &ConfigStore, fonts: &dyn FontProvider) -> Value {
    // The wallpaper's palette has no file to preview a look in; its looks show in the bundled default.
    let palette = match s(store, "theme.colors.palette") {
        p if kurashi_theme::bundled_names().contains(&p.as_str()) => p,
        _ => "wa-iro".to_owned(),
    };
    let scheme = s(store, "theme.colors.scheme");
    json!({
        "styles": style_previews(fonts),
        "looks": look_previews(&palette, &scheme, fonts),
        "palettes": palette_previews(&s(store, "theme.look"), &scheme, fonts),
    })
}

pub const PREVIEWS_DOC: &str = "theme.previews";

/// Register `theme` and recompute it whenever config changes.
pub fn register(
    hub: &Arc<Hub>,
    store: &Arc<ConfigStore>,
    fonts: Arc<dyn FontProvider + Send + Sync>,
) {
    let pic = wallpaper_picture(hub);
    hub.register(
        DOC,
        document_with(store, fonts.as_ref(), None, pic.as_deref()),
        None,
    );
    hub.register(PREVIEWS_DOC, previews(store, fonts.as_ref()), None);
    {
        let (hub, fonts) = (hub.clone(), fonts.clone());
        store.on_change(move |store| republish(&hub, store, fonts.as_ref()));
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
        let mut last = wallpaper_picture(&hub);
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
            let now = wallpaper_picture(&hub);
            if now == last {
                continue;
            }
            last = now.clone();
            if s(&store, "theme.colors.palette") != WALLPAPER_PALETTE {
                continue;
            }
            if let Some(path) = now {
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
    let want = exists && s(store, "theme.colors.palette") == WALLPAPER_PALETTE;
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
    let mut next = document_with(store, fonts, prev.as_ref(), pic.as_deref());
    if next.get("error").is_none()
        && let Some(o) = next.as_object_mut()
    {
        o.remove("error");
    }
    let _ = hub.set(DOC, next, None);
    let _ = hub.set(PREVIEWS_DOC, previews(store, fonts), None);
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
                "schema_version = 2\n[theme]\nstyle = \"yorha\"\nlook = \"win95\"\n",
            ),
            &fonts,
            None,
        );
        assert_eq!(doc["tokens"]["decor.frame"], "bevel");
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
        let shown = previews(&store_with(&root, "schema_version = 2\n"), &fonts);
        assert!(shown["styles"].as_array().unwrap().len() > 10);
        assert_eq!(shown["looks"].as_array().unwrap().len(), 17);
        assert!(shown["palettes"].as_array().unwrap().len() > 10);
        let _ = std::fs::remove_dir_all(&root);
    }

    /// K53: applying a style resets the appearance keys the user set and is one undoable change; a look keeps the
    /// style's palette.
    #[tokio::test]
    async fn applying_a_style_resets_appearance_and_keeps_the_rest() {
        let root = std::env::temp_dir().join(format!("kurashid-style-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = store_with(
            &root,
            "schema_version = 2\n[theme]\nstyle = \"sekai\"\nchrome = \"flat\"\ndensity = \"airy\"\n[theme.colors]\ncontrast = \"high\"\n[bar]\nheight = 40\n",
        );
        assert_eq!(
            store.appearance_overrides(),
            ["theme.density", "theme.chrome"]
        );
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
        // Not appearance: kept.
        assert_eq!(val("theme.colors.contrast").value, "high");
        assert_eq!(val("bar.height").value, 40);
        assert!(store.appearance_overrides().is_empty());
        actions
            .invoke("theme.look.apply", json!({"name": "sekai"}))
            .await
            .unwrap();
        assert_eq!(val("theme.chrome").value, "keycap");
        assert_eq!(val("theme.colors.palette").value, "win95");
        let _ = std::fs::remove_dir_all(&root);
    }
}
