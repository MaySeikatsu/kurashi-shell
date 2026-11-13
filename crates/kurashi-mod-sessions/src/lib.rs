//! Work sessions (W86; docs/ux/sessions.md; MODS.md "Sessions"): noren's sessions and folders in the launcher (K150), the
//! "Open in…" step (the in-shell terminal, the default terminal window, each installed terminal), and the desk saved and
//! restored with a project. A first-party mod over noren, which most people do not have: without it the mod enables,
//! stays inert and says why (Shōjiki), and names the Home-Manager option that ships it.
//!
//! Nothing runs while nobody asks (rule 5): noren's list is read on enable, on a launcher query when the copy is older
//! than five seconds (in the background), when the section opens and after an action — never on a timer.

pub mod desk;
pub mod model;
pub mod noren;
pub mod settings;
pub mod terminals;

use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use kurashi_mod_api::{
    ActionError, Choice, ChoicesHandle, LauncherRow, LauncherSpec, ModCtx, ModError, NativeMod,
    Publish, Settings, SettingsWriter,
};
use model::{Effect, Error, Model, Persisted, Row};
use noren::{Kind, Runner, State};
use serde_json::{Value, json};
use settings::{Cfg, KEYS};
use tokio::runtime::Handle;
use tokio::sync::watch;

/// The mod's id: its document is `mod.sessions`, its actions `sessions.*`.
const ID: &str = "sessions";
/// A copy of noren's list older than this is read again on the next launcher query.
const STALE: Duration = Duration::from_secs(5);
/// A launched window of a desk is awaited this long.
const LAUNCH_WAIT: Duration = Duration::from_secs(8);

/// The sessions mod. Linked into kurashid by `native::linked()`.
pub struct SessionsMod {
    home: Option<PathBuf>,
    state_dir: Option<PathBuf>,
    runner: Option<Arc<dyn Runner>>,
    desktop: Option<Option<Arc<dyn desk::Desktop>>>,
}

impl SessionsMod {
    pub fn new() -> Self {
        Self {
            home: None,
            state_dir: None,
            runner: None,
            desktop: None,
        }
    }

    /// Tests: another home, state folder, noren runner and compositor.
    pub fn with(
        home: PathBuf,
        state_dir: PathBuf,
        runner: Arc<dyn Runner>,
        desktop: Option<Arc<dyn desk::Desktop>>,
    ) -> Self {
        Self {
            home: Some(home),
            state_dir: Some(state_dir),
            runner: Some(runner),
            desktop: Some(desktop),
        }
    }
}

impl Default for SessionsMod {
    fn default() -> Self {
        Self::new()
    }
}

fn env_dir(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback)
        })
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn forced_of(settings: &Settings) -> BTreeMap<String, String> {
    KEYS.iter()
        .filter_map(|k| Some(((*k).to_string(), settings.forced_by(k)?)))
        .collect()
}

struct Shared {
    model: Mutex<Model>,
    doc: watch::Sender<Value>,
    writer: SettingsWriter,
    runner: Arc<dyn Runner>,
    desktop: Option<Arc<dyn desk::Desktop>>,
    state_file: PathBuf,
    runtime: Handle,
    refreshing: AtomicBool,
    listed: Mutex<Option<Instant>>,
    choices: Mutex<Option<ChoicesHandle>>,
}

impl Shared {
    fn publish(&self) {
        let d = self.model.lock().expect("model lock").doc();
        self.doc.send_if_modified(|old| {
            if *old == d {
                false
            } else {
                *old = d;
                true
            }
        });
    }

    fn with_model<T>(&self, f: impl FnOnce(&mut Model) -> T) -> T {
        let r = f(&mut self.model.lock().expect("model lock"));
        self.publish();
        r
    }

    fn persist(&self) {
        let p = self.model.lock().expect("model lock").persisted.clone();
        if let Some(dir) = self.state_file.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = self.state_file.with_extension("json.tmp");
        if let Ok(text) = serde_json::to_string_pretty(&p)
            && std::fs::write(&tmp, text).is_ok()
        {
            let _ = std::fs::rename(&tmp, &self.state_file);
        }
    }

    fn stale(&self) -> bool {
        self.listed
            .lock()
            .expect("listed lock")
            .is_none_or(|t| t.elapsed() > STALE)
    }
}

/// Read noren's list again (and look for noren and the terminals), off the runtime; one at a time.
fn refresh(s: &Arc<Shared>) {
    if s.refreshing.swap(true, Ordering::SeqCst) {
        return;
    }
    let s2 = s.clone();
    s.runtime.spawn(async move {
        let s3 = s2.clone();
        let _ = tokio::task::spawn_blocking(move || {
            let s = s3;
            let cfg = s.model.lock().expect("model lock").cfg().clone();
            let path_env = std::env::var("PATH").ok();
            let program = noren::resolve(&cfg.command, path_env.as_deref());
            let terminals = terminals::installed(path_env.as_deref());
            let window = terminals::window(
                &cfg.window_command,
                std::env::var("TERMINAL").ok().as_deref(),
                &terminals,
                path_env.as_deref(),
            );
            let list = program.as_ref().map(|p| {
                s.runner
                    .run(p, &["list", &cfg.list])
                    .map(|out| noren::parse(&out, &|p| std::path::Path::new(p).is_dir()))
            });
            s.with_model(|m| {
                m.program = program;
                m.terminals = terminals;
                m.window = window;
                match list {
                    None => m.set_missing(),
                    Some(r) => m.set_list(r),
                }
            });
            *s.listed.lock().expect("listed lock") = Some(Instant::now());
        })
        .await;
        s2.refreshing.store(false, Ordering::SeqCst);
        if let Some(c) = s2.choices.lock().expect("choices lock").as_ref() {
            c.choices_changed();
        }
    });
}

fn spawn_detached(argv: &[String], cwd: Option<&str>) -> Result<(), String> {
    let (program, args) = argv.split_first().ok_or("empty command")?;
    let mut c = tokio::process::Command::new(program);
    c.args(args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        // (its own group: it outlives the daemon's signals, as an app the launcher starts)
        .process_group(0);
    if let Some(d) = cwd.filter(|d| std::path::Path::new(d).is_dir()) {
        c.current_dir(d);
    }
    let mut child = c.spawn().map_err(|e| format!("{program}: {e}"))?;
    tokio::spawn(async move {
        let _ = child.wait().await;
    });
    Ok(())
}

async fn run_effects(s: &Arc<Shared>, fx: Vec<Effect>) -> Result<(), ActionError> {
    for f in fx {
        match f {
            Effect::Spawn { argv, cwd } => {
                spawn_detached(&argv, cwd.as_deref()).map_err(|e| {
                    s.with_model(|m| m.notice = Some(("sessions.notice.spawn".into(), Some(e))));
                    ActionError::Unavailable("sessions.error.spawn".into())
                })?;
            }
            Effect::Refresh => refresh(s),
            Effect::Persist => s.persist(),
            Effect::Remember(rows) => {
                if let Err(e) = s.writer.set("projects", rows).await {
                    s.with_model(|m| {
                        m.notice = Some((e.i18n_key().to_string(), None));
                    });
                }
            }
            Effect::Restore { project } => restore(s, project),
        }
    }
    Ok(())
}

/// Put a desk back, off the runtime (it may wait for launched windows).
fn restore(s: &Arc<Shared>, project: String) {
    let Some(d) = s.desktop.clone() else {
        s.with_model(|m| m.notice = Some(("sessions.desk.needs_niri".into(), None)));
        return;
    };
    let Some(saved) = s
        .model
        .lock()
        .expect("model lock")
        .persisted
        .desks
        .get(&project)
        .cloned()
    else {
        return;
    };
    s.with_model(|m| {
        m.restoring = true;
        m.restore_extras(&project);
    });
    let s2 = s.clone();
    let rt = s.runtime.clone();
    s.runtime.spawn(async move {
        let r = tokio::task::spawn_blocking(move || {
            let launch = |w: &desk::SavedWindow| {
                let rt = rt.clone();
                let (argv, cwd) = (w.command.clone(), w.cwd.clone());
                rt.block_on(async move { spawn_detached(&argv, cwd.as_deref()) })
            };
            desk::restore(&saved, d.as_ref(), &launch, LAUNCH_WAIT)
        })
        .await
        .unwrap_or_else(|e| Err(e.to_string()));
        s2.with_model(|m| {
            m.restoring = false;
            m.notice = Some(match r {
                Ok(r) if r.failed.is_empty() => ("sessions.notice.restored".into(), None),
                Ok(r) => (
                    "sessions.notice.not_opened".into(),
                    Some(r.failed.join(", ")),
                ),
                Err(e) => ("sessions.notice.restore_failed".into(), Some(e)),
            });
        });
    });
}

fn error(e: Error) -> ActionError {
    if e.invalid() {
        ActionError::Invalid(e.key().into())
    } else {
        ActionError::Unavailable(e.key().into())
    }
}

fn action<F, Fut>(ctx: &mut ModCtx, s: &Arc<Shared>, id: &str, f: F) -> Result<(), ModError>
where
    F: Fn(Arc<Shared>, Value) -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<Option<Value>, ActionError>> + Send + 'static,
{
    let s = s.clone();
    ctx.action(id, &format!("action.{id}"), move |args| f(s.clone(), args))
}

/// The project an action names (`project`), else the current one.
fn project_arg(s: &Shared, args: &Value) -> Result<String, ActionError> {
    if let Some(p) = args["project"].as_str() {
        return Ok(p.to_string());
    }
    s.model
        .lock()
        .expect("model lock")
        .current()
        .map(|(p, _)| p.clone())
        .ok_or_else(|| ActionError::Unavailable("sessions.error.no_project".into()))
}

/// noren once more (`pin`, `kill`, `snapshot`) on an entry, then the list again.
async fn noren_verb(
    s: Arc<Shared>,
    args: Value,
    verb: &'static str,
) -> Result<Option<Value>, ActionError> {
    let (program, target, kind) = {
        let m = s.model.lock().expect("model lock");
        let key = args["key"].as_str().ok_or_else(|| error(Error::Argument))?;
        let e = m
            .entries()
            .iter()
            .find(|e| e.key == key)
            .cloned()
            .ok_or_else(|| error(Error::Unknown))?;
        let p = m.program.clone().ok_or_else(|| error(Error::NoNoren))?;
        (p, e.target().to_string(), e.kind)
    };
    if verb != "pin" && kind == Kind::Folder {
        return Err(error(Error::Argument));
    }
    let runner = s.runner.clone();
    let out = tokio::task::spawn_blocking(move || {
        let mut a: Vec<&str> = vec![verb, &target];
        if verb == "kill" {
            a.push("--yes");
        }
        runner.run(&program, &a)
    })
    .await
    .map_err(|e| ActionError::Internal(e.to_string()))?;
    *s.listed.lock().expect("listed lock") = None;
    refresh(&s);
    match out {
        Ok(_) => Ok(None),
        Err(e) => {
            s.with_model(|m| m.notice = Some(("sessions.notice.noren".into(), Some(e))));
            Err(ActionError::Unavailable("sessions.error.noren".into()))
        }
    }
}

fn register_actions(ctx: &mut ModCtx, s: &Arc<Shared>) -> Result<(), ModError> {
    action(ctx, s, "sessions.refresh", |s, _| async move {
        *s.listed.lock().expect("listed lock") = None;
        refresh(&s);
        Ok(None)
    })?;
    action(ctx, s, "sessions.open", |s, a| async move {
        let r = s.with_model(|m| m.open(&a, now()));
        let (reply, fx) = r.map_err(error)?;
        run_effects(&s, fx).await?;
        Ok(reply)
    })?;
    action(ctx, s, "sessions.choose", |s, a| async move {
        let fx = s.with_model(|m| m.choose(&a, now())).map_err(error)?;
        run_effects(&s, fx).await?;
        Ok(None)
    })?;
    action(ctx, s, "sessions.cancel", |s, _| async move {
        s.with_model(Model::cancel);
        Ok(None)
    })?;
    action(ctx, s, "sessions.forget", |s, a| async move {
        let p = a["project"]
            .as_str()
            .ok_or_else(|| error(Error::Argument))?;
        let fx = s.model.lock().expect("model lock").forget(p);
        run_effects(&s, fx.into_iter().collect()).await?;
        Ok(None)
    })?;
    action(ctx, s, "sessions.handed", |s, a| async move {
        let seq = a["seq"].as_u64().ok_or_else(|| error(Error::Argument))?;
        s.with_model(|m| m.handed(seq));
        Ok(None)
    })?;
    action(ctx, s, "sessions.undelivered", |s, a| async move {
        s.with_model(|m| m.undelivered(&a)).map_err(error)?;
        Ok(None)
    })?;
    // noren missing: the launcher's row leads to the mod's Settings page, where the reason and the option are.
    action(ctx, s, "sessions.help", |s, _| async move {
        s.with_model(|m| m.handoff("settings.open", json!({"page": "mods.sessions"})));
        Ok(None)
    })?;
    action(ctx, s, "sessions.pin", |s, a| noren_verb(s, a, "pin"))?;
    action(ctx, s, "sessions.kill", |s, a| noren_verb(s, a, "kill"))?;
    action(ctx, s, "sessions.snapshot", |s, a| {
        noren_verb(s, a, "snapshot")
    })?;
    // The desk.
    action(ctx, s, "sessions.desk.save", |s, a| async move {
        let d = s
            .desktop
            .clone()
            .ok_or_else(|| ActionError::Unavailable("sessions.desk.needs_niri".into()))?;
        let project = project_arg(&s, &a)?;
        let desk = tokio::task::spawn_blocking(move || {
            let (spaces, windows) = d.list()?;
            desk::capture(&spaces, &windows, &desk::proc_info, now()).map_err(String::from)
        })
        .await
        .map_err(|e| ActionError::Internal(e.to_string()))?
        .map_err(ActionError::Unavailable)?;
        let n = desk.windows.len();
        s.with_model(|m| m.saved(project.clone(), desk));
        s.persist();
        Ok(Some(json!({"project": project, "windows": n})))
    })?;
    action(ctx, s, "sessions.desk.extras", |s, a| async move {
        s.with_model(|m| m.extras(&a)).map_err(error)?;
        s.persist();
        Ok(None)
    })?;
    action(ctx, s, "sessions.desk.restore", |s, a| async move {
        let project = project_arg(&s, &a)?;
        if !s
            .model
            .lock()
            .expect("model lock")
            .persisted
            .desks
            .contains_key(&project)
        {
            return Err(error(Error::NoDesk));
        }
        if s.desktop.is_none() {
            return Err(ActionError::Unavailable("sessions.desk.needs_niri".into()));
        }
        restore(&s, project);
        Ok(None)
    })?;
    action(ctx, s, "sessions.desk.forget", |s, a| async move {
        let project = project_arg(&s, &a)?;
        if !s.with_model(|m| m.forget_desk(&project)) {
            return Err(error(Error::NoDesk));
        }
        s.persist();
        Ok(None)
    })?;
    Ok(())
}

fn icon(e: &noren::Entry) -> &'static str {
    if e.pinned {
        return "push_pin";
    }
    match (e.kind, e.state) {
        (_, State::Attached) => "terminal",
        (_, State::Running) => "play_arrow",
        (_, State::Exited) => "history",
        (Kind::Config, _) => "settings",
        _ => "folder",
    }
}

fn launcher_rows(s: &Arc<Shared>, text: &str) -> Vec<LauncherRow> {
    if s.stale() {
        refresh(s);
    }
    let m = s.model.lock().expect("model lock");
    let prefixed = !m.cfg().launcher_prefix.trim().is_empty();
    m.launcher(text, prefixed, now())
        .into_iter()
        .map(|r| match r {
            Row::Entry { entry, sub } => LauncherRow {
                key: entry.key.clone(),
                name: entry.name.clone(),
                sub,
                icon: icon(&entry).into(),
                action: "sessions.open".into(),
                args: json!({"key": entry.key}),
            },
            Row::SaveDesk { project, name } => LauncherRow {
                key: "save-desk".into(),
                name,
                sub: "sessions.launcher.save_desk".into(),
                icon: "save".into(),
                action: "sessions.desk.save".into(),
                args: json!({"project": project}),
            },
            Row::Missing => LauncherRow {
                key: "missing".into(),
                name: "noren".into(),
                sub: "sessions.launcher.missing".into(),
                icon: "work".into(),
                action: "sessions.help".into(),
                args: json!({}),
            },
            Row::Empty => LauncherRow {
                key: "empty".into(),
                name: "noren".into(),
                sub: "sessions.launcher.empty".into(),
                icon: "work".into(),
                action: "sessions.refresh".into(),
                args: json!({}),
            },
        })
        .collect()
}

/// `open_in`'s choices (`sessions.targets`): ask, the in-shell terminal, the window, each installed terminal.
fn target_choices(s: &Shared) -> Vec<Choice> {
    let m = s.model.lock().expect("model lock");
    let mut v = vec![
        Choice::new(model::ASK, "mods.sessions.open_in.ask"),
        Choice::new(model::KURASHI, "sessions.target.kurashi"),
    ];
    let w = Choice::new(model::WINDOW, "sessions.target.window");
    v.push(match m.target_reason(model::WINDOW) {
        Some(r) => w.unavailable(r),
        None => w,
    });
    v.extend(m.terminals.iter().map(|t| Choice::new(&t.id, &t.id)));
    // A terminal chosen earlier and gone since stays in the list, not selectable (Shōjiki).
    let open_in = m.cfg().open_in.clone();
    if !v.iter().any(|c| c.value == open_in) && terminals::known(&open_in) {
        v.push(Choice::new(&open_in, &open_in).unavailable("sessions.target.not_installed"));
    }
    v
}

impl NativeMod for SessionsMod {
    fn id(&self) -> &'static str {
        ID
    }

    fn enable(&self, ctx: &mut ModCtx) -> Result<(), ModError> {
        let runtime =
            Handle::try_current().map_err(|_| ModError::Failed("sessions.error.runtime".into()))?;
        let settings: Settings = ctx.settings().clone();
        let home = self
            .home
            .clone()
            .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()));
        let state_dir = self.state_dir.clone().unwrap_or_else(|| {
            env_dir("XDG_STATE_HOME", ".local/state")
                .join("kurashi")
                .join(ID)
        });
        let state_file = state_dir.join("state.json");
        let mut model = Model::new(Cfg::read(&settings), home.to_string_lossy().into_owned());
        model.set_cfg(Cfg::read(&settings), forced_of(&settings));
        model.persisted = std::fs::read_to_string(&state_file)
            .ok()
            .and_then(|t| serde_json::from_str::<Persisted>(&t).ok())
            .unwrap_or_default();
        let desktop: Option<Arc<dyn desk::Desktop>> = match &self.desktop {
            Some(d) => d.clone(),
            None => desk::Niri::from_env().map(|n| Arc::new(n) as Arc<dyn desk::Desktop>),
        };
        model.desk_reason = desktop.is_none().then_some("sessions.desk.needs_niri");
        let initial = model.doc();
        let (doc, _) = watch::channel(initial.clone());
        let shared = Arc::new(Shared {
            model: Mutex::new(model),
            doc,
            writer: ctx.settings_writer(),
            runner: self.runner.clone().unwrap_or_else(|| {
                Arc::new(noren::Exec {
                    timeout: Duration::from_secs(5),
                })
            }),
            desktop,
            state_file,
            runtime: runtime.clone(),
            refreshing: AtomicBool::new(false),
            listed: Mutex::new(None),
            choices: Mutex::new(None),
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
        let (pre, rows) = (shared.clone(), shared.clone());
        ctx.launcher(
            "sessions",
            LauncherSpec {
                prefix: Arc::new(move || {
                    let p = pre
                        .model
                        .lock()
                        .expect("model lock")
                        .cfg()
                        .launcher_prefix
                        .trim()
                        .to_string();
                    (!p.is_empty()).then_some(p)
                }),
                query: Arc::new(move |text| launcher_rows(&rows, text)),
            },
        )?;
        let ch = shared.clone();
        let handle = ctx.choices("sessions.targets", move || target_choices(&ch))?;
        *shared.choices.lock().expect("choices lock") = Some(handle);

        refresh(&shared);
        let watch = shared.clone();
        let mut settings = settings;
        runtime.spawn(async move {
            while settings.changed().await {
                let cfg = Cfg::read(&settings);
                let again = {
                    let mut m = watch.model.lock().expect("model lock");
                    let again = m.cfg().command != cfg.command
                        || m.cfg().list != cfg.list
                        || m.cfg().window_command != cfg.window_command;
                    m.set_cfg(cfg, forced_of(&settings));
                    again
                };
                watch.publish();
                if again {
                    *watch.listed.lock().expect("listed lock") = None;
                    refresh(&watch);
                }
            }
        });
        Ok(())
    }
}

#[cfg(test)]
mod tests;
