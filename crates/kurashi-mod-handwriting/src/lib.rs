//! Handwriting: make your own font by drawing it (K94, I415; `docs/ux/handwriting.md`). Linked into kurashid by `native::linked_mods`; manifest and
//! QML in `mods/handwriting/`. The panel asks for letters one by one, each several times if you like; this crate keeps the strokes and makes
//! the fonts, and Font Mix (K93) mixes the versions into something that varies as a hand does.

pub mod font;
pub mod glyph;
pub mod store;

use std::sync::{Arc, Mutex};

use kurashi_mod_api::{ActionError, ModCtx, ModError, NativeMod, Publish, Settings};
use serde_json::{Value, json};
use tokio::sync::watch;

use glyph::Strokes;
use store::{DEFAULT_PEN, Options, Store};

#[derive(Default)]
pub struct HandwritingMod;

impl HandwritingMod {
    pub fn new() -> Self {
        Self
    }
}

struct Shared {
    store: Mutex<Store>,
    version: watch::Sender<u64>,
    settings: Settings,
}

/// The mod's settings as the store takes them.
fn options(s: &Settings) -> Options {
    let word = |k: &str| {
        s.get(k)
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_default()
    };
    let flag = |k: &str| s.get(k).and_then(|v| v.as_bool()).unwrap_or(true);
    Options {
        extended: word("letters") == "extended",
        pen: match word("default_pen").as_str() {
            "fine" => 32.0,
            "bold" => 84.0,
            _ => DEFAULT_PEN,
        },
        spacing: s.get("spacing").and_then(|v| v.as_f64()).unwrap_or(0.0),
        guides: flag("guides"),
        shadow: flag("shadow"),
        next_letter: flag("next_letter"),
    }
}

impl Shared {
    fn with<T>(&self, f: impl FnOnce(&mut Store) -> Result<T, String>) -> Result<T, ActionError> {
        let mut st = self.store.lock().expect("store lock");
        st.options = options(&self.settings);
        let r = f(&mut st).map_err(ActionError::Invalid);
        drop(st);
        self.version.send_modify(|v| *v += 1);
        r
    }
}

fn text(args: &Value, key: &str) -> Result<String, ActionError> {
    args.get(key)
        .and_then(Value::as_str)
        .map(String::from)
        .ok_or_else(|| ActionError::Invalid(format!("needs {key}")))
}
fn number(args: &Value, key: &str) -> Result<f64, ActionError> {
    args.get(key)
        .and_then(Value::as_f64)
        .ok_or_else(|| ActionError::Invalid(format!("needs {key}")))
}

async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let mut version = shared.version.subscribe();
    loop {
        let doc = {
            let mut st = shared.store.lock().expect("store lock");
            st.options = options(&settings);
            st.document()
        };
        publish(doc);
        tokio::select! {
            r = version.changed() => {
                if r.is_err() {
                    return;
                }
            }
            on = settings.changed() => {
                if !on {
                    return;
                }
            }
        }
    }
}

impl NativeMod for HandwritingMod {
    fn id(&self) -> &'static str {
        "handwriting"
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let (data, fonts) = Store::default_paths();
        let mut store = Store::load(data, fonts);
        let settings = ctx.settings().clone();
        store.options = options(&settings);
        let initial = store.document();
        let (version, _) = watch::channel(0);
        let shared = Arc::new(Shared {
            store: Mutex::new(store),
            version,
            settings,
        });

        // Fonts made with older outlines, off the daemon's start (a font's a few milliseconds, fontconfig's refresh longer).
        let s = shared.clone();
        std::thread::spawn(move || {
            let _ = s.with(|st| {
                let made = st.refresh();
                if !made.is_empty() {
                    tracing::info!(?made, "handwriting: fonts made again with simple outlines");
                }
                Ok(())
            });
        });

        let s = shared.clone();
        ctx.service("handwriting", initial, move |publish, settings| {
            run(s.clone(), publish, settings)
        })?;

        macro_rules! act {
            ($id:literal, $label:literal, |$st:ident, $args:ident| $body:expr) => {{
                let s = shared.clone();
                ctx.action($id, $label, move |$args: Value| {
                    let s = s.clone();
                    async move { s.with(|$st| $body) }
                })?;
            }};
        }
        act!(
            "handwriting.font.create",
            "mod-handwriting.action.create",
            |st, args| {
                let name = args
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned();
                st.create(&name).map(|id| Some(json!({"id": id})))
            }
        );
        act!(
            "handwriting.font.get",
            "mod-handwriting.action.get",
            |st, args| {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                let f = st.fonts.get(id).ok_or("handwriting.error.no_font")?;
                Ok(Some(json!({"glyphs": f.glyphs})))
            }
        );
        act!(
            "handwriting.font.delete",
            "mod-handwriting.action.delete",
            |st, args| {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                st.delete(id).map(|()| None)
            }
        );
        act!(
            "handwriting.font.versions",
            "mod-handwriting.action.versions",
            |st, args| {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                let n = args.get("count").and_then(Value::as_u64).unwrap_or(1) as u32;
                st.set_versions(id, n).map(|()| None)
            }
        );
        act!(
            "handwriting.font.pen",
            "mod-handwriting.action.pen",
            |st, args| {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                let pen = args
                    .get("pen")
                    .and_then(Value::as_f64)
                    .unwrap_or(store::DEFAULT_PEN);
                st.set_pen(id, pen).map(|()| None)
            }
        );
        act!(
            "handwriting.font.make",
            "mod-handwriting.action.make",
            |st, args| {
                let id = args.get("id").and_then(Value::as_str).unwrap_or("");
                st.make(id)
                    .map(|families| Some(json!({"families": families})))
            }
        );
        // (the one action whose arguments can be wrong in more than one way)
        let s = shared.clone();
        ctx.action(
            "handwriting.glyph.save",
            "mod-handwriting.action.save",
            move |args: Value| {
                let s = s.clone();
                async move {
                    let id = text(&args, "id")?;
                    let version = number(&args, "version")? as u32;
                    let c = text(&args, "char")?
                        .chars()
                        .next()
                        .ok_or_else(|| ActionError::Invalid("needs char".into()))?;
                    let strokes: Strokes =
                        serde_json::from_value(args.get("strokes").cloned().unwrap_or(Value::Null))
                            .map_err(|_| ActionError::Invalid("error.args.invalid".into()))?;
                    s.with(|st| st.save_glyph(&id, version, c, strokes).map(|()| None))
                }
            },
        )?;
        Ok(())
    }
}
