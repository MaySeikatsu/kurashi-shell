//! The terminal (W83; docs/ux/terminal.md; MODS.md "Terminal"): a drop-down out of the bar or an edge, the same session in
//! the bar's card, a sidebar section and the web dock's Local pin. The daemon owns the sessions (which tabs exist, their
//! order and names), the places open and the one that shows the terminal (last opened wins), and the host's lifecycle;
//! the host (`qs-terminal`, mods/terminal/host/) owns the ptys while it runs and draws the text over the place's well;
//! the shell draws the places. Nothing runs while no session exists and no place is open (rule 5): the supervisor sleeps
//! until an action, a settings change or a host change, and the host is never stopped on an idle clock — that would
//! end the user's programs.

pub mod model;
pub mod settings;

use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use kurashi_mod_api::{
    ActionError, HostHandle, HostSpec, HostState, ModCtx, ModError, NativeMod, Publish, Settings,
    SettingsError, SettingsWriter,
};
use model::{Error, Model, Place, Rest};
use serde_json::{Value, json};
use settings::{Cfg, KEYS};
use tokio::runtime::Handle;
use tokio::sync::{Notify, watch};

/// The mod's id: its document is `mod.terminal`, its actions `terminal.*`.
const ID: &str = "terminal";

/// The terminal mod. Linked into kurashid by `native::linked()`.
pub struct TerminalMod {
    home: Option<PathBuf>,
}

impl TerminalMod {
    pub fn new() -> Self {
        Self { home: None }
    }

    /// With another home (tests: `~` and the favourites resolve against it).
    pub fn with_home(home: PathBuf) -> Self {
        Self { home: Some(home) }
    }
}

impl Default for TerminalMod {
    fn default() -> Self {
        Self::new()
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn forced_of(settings: &Settings) -> BTreeMap<String, String> {
    KEYS.iter()
        .filter_map(|k| Some(((*k).to_string(), settings.forced_by(k)?)))
        .collect()
}

impl NativeMod for TerminalMod {
    fn id(&self) -> &'static str {
        ID
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let runtime =
            Handle::try_current().map_err(|_| ModError::Failed("terminal.error.runtime".into()))?;
        let settings: Settings = ctx.settings().clone();
        let host = ctx.host(
            "terminal",
            HostSpec {
                binary: "qs-terminal".into(),
                args: vec!["-p".into(), "{mod_dir}/host/shell.qml".into()],
                env: BTreeMap::new(),
            },
        )?;
        let writer = ctx.settings_writer();
        let mut model = Model::new(
            Cfg::read(&settings),
            self.home.clone().unwrap_or_else(home_dir),
        );
        model.set_cfg(Cfg::read(&settings), forced_of(&settings));
        let initial = model.doc();
        let (doc, _) = watch::channel(initial.clone());
        let host_rx = host.state();
        let shared = Arc::new(Shared {
            model: Mutex::new(model),
            notify: Notify::new(),
            doc,
            host,
            writer,
        });

        let serve = shared.clone();
        ctx.service(ID, initial, move |publish: Publish, _settings| {
            let serve = serve.clone();
            async move {
                let mut rx = serve.doc.subscribe();
                loop {
                    let doc = rx.borrow_and_update().clone();
                    publish(doc);
                    if rx.changed().await.is_err() {
                        break;
                    }
                }
            }
        })?;
        register_actions(ctx, &shared)?;
        runtime.spawn(supervise(shared, settings, host_rx));
        Ok(())
    }
}

struct Shared {
    model: Mutex<Model>,
    notify: Notify,
    doc: watch::Sender<Value>,
    host: HostHandle,
    writer: SettingsWriter,
}

impl Shared {
    /// Runs `change` on the model, then starts or stops the host as the model wants and publishes the document.
    fn with_model<T>(&self, change: impl FnOnce(&mut Model) -> Result<T, Error>) -> Result<T, ActionError> {
        let result = {
            let mut m = self.model.lock().expect("model lock");
            let r = change(&mut m);
            self.settle(&mut m);
            r
        };
        self.notify.notify_one();
        result.map_err(error)
    }

    /// The host follows the model (started when a session or a place needs it; stopped when neither does), then the
    /// document is published when it changed.
    fn settle(&self, m: &mut Model) {
        let running = !matches!(
            m.host_state(),
            HostState::Off | HostState::Missing | HostState::Failed { .. }
        );
        if m.wants_host() && !running {
            self.host.start();
        } else if !m.wants_host() && running {
            m.note_stopping();
            self.host.stop();
        }
        let doc = m.doc();
        self.doc.send_if_modified(|cur| {
            if *cur == doc {
                false
            } else {
                *cur = doc;
                true
            }
        });
    }

    fn host_changed(&self) {
        let state = self.host.state().borrow().clone();
        let mut m = self.model.lock().expect("model lock");
        if m.set_host(state) {
            self.host.stop();
        }
        self.settle(&mut m);
    }

    fn reload(&self, settings: &Settings) {
        let mut m = self.model.lock().expect("model lock");
        m.set_cfg(Cfg::read(settings), forced_of(settings));
        self.settle(&mut m);
    }

    async fn write(&self, key: &str, value: Value) -> Result<Option<Value>, ActionError> {
        self.writer
            .set(key, value)
            .await
            .map_err(settings_error)?;
        Ok(None)
    }
}

fn error(e: Error) -> ActionError {
    ActionError::Invalid(e.key().into())
}

fn settings_error(e: SettingsError) -> ActionError {
    let key = e.i18n_key().to_string();
    match e {
        SettingsError::Unavailable => ActionError::Unavailable(key),
        _ => ActionError::Invalid(key),
    }
}

fn str_arg<'a>(args: &'a Value, key: &str) -> Option<&'a str> {
    args[key].as_str().filter(|s| !s.is_empty())
}

fn req<'a>(args: &'a Value, key: &str) -> Result<&'a str, Error> {
    str_arg(args, key).ok_or(Error::Argument)
}

/// `in`: `new` or `current`; absent → the setting `key` (`run_in`, `dir_opens`).
fn new_tab_arg(args: &Value, cfg: &Cfg, key: &str) -> Result<bool, Error> {
    let dflt = if key == "run_in" {
        cfg.run_in.as_str()
    } else {
        cfg.dir_opens.as_str()
    };
    match str_arg(args, "in").unwrap_or(dflt) {
        "new" => Ok(true),
        "current" => Ok(false),
        _ => Err(Error::Argument),
    }
}

fn rest_arg(args: &Value) -> Result<Option<Rest>, Error> {
    if args["on"].as_bool() != Some(true) {
        return Ok(None);
    }
    let n = |k: &str| args[k].as_f64().map(|v| v.round() as i64).ok_or(Error::Argument);
    let (width, height) = (n("width")?, n("height")?);
    if width <= 0 || height <= 0 {
        return Err(Error::Argument);
    }
    Ok(Some(Rest {
        output: req(args, "output")?.to_string(),
        x: n("x")?,
        y: n("y")?,
        width,
        height,
    }))
}

fn sync_action<F>(ctx: &mut ModCtx, s: &Arc<Shared>, id: &str, f: F) -> Result<(), ModError>
where
    F: Fn(&Shared, Value) -> Result<Option<Value>, ActionError> + Send + Sync + 'static,
{
    let s = s.clone();
    ctx.action(id, &format!("action.{id}"), move |args| {
        let result = f(s.as_ref(), args);
        async move { result }
    })
}

fn write_action<F, Fut>(ctx: &mut ModCtx, s: &Arc<Shared>, id: &str, f: F) -> Result<(), ModError>
where
    F: Fn(Arc<Shared>, Value) -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<Option<Value>, ActionError>> + Send + 'static,
{
    let s = s.clone();
    ctx.action(id, &format!("action.{id}"), move |args| f(s.clone(), args))
}

fn register_actions(ctx: &mut ModCtx, s: &Arc<Shared>) -> Result<(), ModError> {
    // The drop-down.
    sync_action(ctx, s, "terminal.toggle", |s, a| {
        s.with_model(|m| {
            m.toggle(str_arg(&a, "output"));
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.show", |s, a| {
        s.with_model(|m| {
            m.show(str_arg(&a, "output"));
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.hide", |s, _| {
        s.with_model(|m| {
            m.hide();
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.blur", |s, _| {
        s.with_model(|m| {
            m.blur();
            Ok(None)
        })
    })?;
    // A place's well: where it rests (`on`), moving (`on: false`), gone (`closed`).
    sync_action(ctx, s, "terminal.place", |s, a| {
        s.with_model(|m| {
            let p = Place::parse(req(&a, "where")?).ok_or(Error::Argument)?;
            let rest = rest_arg(&a)?;
            let closed = a["closed"].as_bool() == Some(true);
            let fresh = a["fresh"].as_bool() == Some(true);
            m.place(p, rest, closed, fresh);
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.bring", |s, a| {
        s.with_model(|m| {
            let p = Place::parse(req(&a, "where")?).ok_or(Error::Argument)?;
            m.bring(p);
            Ok(None)
        })
    })?;
    // Tabs.
    sync_action(ctx, s, "terminal.new_tab", |s, a| {
        s.with_model(|m| {
            let t = m.new_tab_in(str_arg(&a, "dir"))?;
            Ok(Some(json!({"tab": t})))
        })
    })?;
    sync_action(ctx, s, "terminal.close_tab", |s, a| {
        s.with_model(|m| {
            m.close_tab(req(&a, "tab")?)?;
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.select", |s, a| {
        s.with_model(|m| {
            if let Some(by) = a["step"].as_i64() {
                m.step(by);
            } else {
                m.select(req(&a, "tab")?)?;
            }
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.rename", |s, a| {
        s.with_model(|m| {
            m.rename(req(&a, "tab")?, a["title"].as_str().unwrap_or(""))?;
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.move_tab", |s, a| {
        s.with_model(|m| {
            let to = a["to"].as_i64().ok_or(Error::Argument)?;
            m.move_tab(req(&a, "tab")?, to)?;
            Ok(None)
        })
    })?;
    // Lines and directories: the bar's field, the launcher, the favourites.
    sync_action(ctx, s, "terminal.run", |s, a| {
        s.with_model(|m| {
            let new = new_tab_arg(&a, m.cfg(), "run_in")?;
            let tab = m.run(req(&a, "text")?, new)?;
            if a["show"].as_bool() == Some(true) {
                m.show(str_arg(&a, "output"));
            }
            Ok(Some(json!({"tab": tab})))
        })
    })?;
    sync_action(ctx, s, "terminal.open_dir", |s, a| {
        s.with_model(|m| {
            let new = new_tab_arg(&a, m.cfg(), "dir_opens")?;
            let tab = m.open_dir(req(&a, "path")?, new)?;
            if a["show"].as_bool() != Some(false) && m.shown_in().is_none() {
                m.show(str_arg(&a, "output"));
            }
            Ok(Some(json!({"tab": tab})))
        })
    })?;
    sync_action(ctx, s, "terminal.restart", |s, _| {
        s.with_model(|m| {
            m.restart();
            Ok(None)
        })
    })?;
    // The host's reports.
    sync_action(ctx, s, "terminal.host.title", |s, a| {
        s.with_model(|m| {
            m.host_title(
                req(&a, "tab")?,
                a["title"].as_str(),
                a["cwd"].as_str(),
                a["program"].as_str(),
            );
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.host.exited", |s, a| {
        s.with_model(|m| {
            m.host_exited(req(&a, "tab")?);
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.host.hover", |s, a| {
        s.with_model(|m| {
            m.set_pointer(a["on"].as_bool().ok_or(Error::Argument)?);
            Ok(None)
        })
    })?;
    sync_action(ctx, s, "terminal.host.ran", |s, a| {
        s.with_model(|m| {
            m.host_ran(a["run"].as_u64().ok_or(Error::Argument)?);
            Ok(None)
        })
    })?;
    // Settings writes: the pin, the height dragged on an output.
    write_action(ctx, s, "terminal.pin", |s, a| async move {
        let on = match a["on"].as_bool() {
            Some(on) => on,
            None => !s.model.lock().expect("model lock").cfg().pinned,
        };
        s.write("pinned", json!(on)).await
    })?;
    write_action(ctx, s, "terminal.resize", |s, a| async move {
        let output = req(&a, "output").map_err(error)?.to_string();
        let mut rows: Vec<Value> = {
            let m = s.model.lock().expect("model lock");
            m.cfg()
                .sizes
                .iter()
                .filter(|(o, _)| **o != output)
                .map(|(o, h)| json!({"output": o, "height": h}))
                .collect()
        };
        if let Some(h) = a["height"].as_f64() {
            rows.push(json!({"output": output, "height": (h.round() as i64).clamp(20, 95)}));
        }
        s.write("sizes", Value::Array(rows)).await
    })?;
    Ok(())
}

async fn supervise(shared: Arc<Shared>, mut settings: Settings, mut host: watch::Receiver<HostState>) {
    // (a state the daemon set before this ran is taken now)
    shared.host_changed();
    loop {
        tokio::select! {
            changed = settings.changed() => {
                if !changed {
                    break;
                }
                shared.reload(&settings);
            }
            r = host.changed() => {
                if r.is_err() {
                    break;
                }
                shared.host_changed();
            }
            () = shared.notify.notified() => {}
        }
    }
}
