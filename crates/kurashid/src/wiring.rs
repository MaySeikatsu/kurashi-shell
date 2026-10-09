//! Startup wiring of the feature crates whose lifetime is the daemon's: launcher queries, the
//! notification server, the mods registry and the `runtime.ui` panel state.

use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::doctor::SharedFacts;
use crate::hub::Hub;
use crate::{Daemon, QueryFn};

fn cfg_bool(cfg: Option<&ConfigStore>, key: &str, dflt: bool) -> bool {
    cfg.and_then(|c| c.get(key, None))
        .and_then(|p| p.value.as_bool())
        .unwrap_or(dflt)
}

/// `runtime.ui` — daemon-owned panel state (ARCHITECTURE §4):
/// `{popup, panel, launcher}`. `panel` names what the Stage shows (`""` = nothing); `popup` mirrors
/// `panel != ""` for the probe-era frontend. Panels are exclusive; the launcher is its own surface.
pub fn ui(hub: &Arc<Hub>, actions: &mut ActionRegistry) {
    hub.register(
        "runtime.ui",
        json!({"popup": false, "panel": "", "launcher": false}),
        None,
    );
    let toggle_panel = |hub: Arc<Hub>, name: &'static str| {
        move |_| {
            let hub = hub.clone();
            async move {
                hub.update("runtime.ui", None, |d| {
                    let open = d["panel"].as_str() == Some(name);
                    d["panel"] = json!(if open { "" } else { name });
                    d["popup"] = json!(!open);
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        }
    };
    actions.register(
        "island.expand",
        "action.island.expand",
        toggle_panel(hub.clone(), "island"),
    );
    // Alias kept for the bake-off probes.
    actions.register(
        "probe.popup.toggle",
        "action.island.expand",
        toggle_panel(hub.clone(), "island"),
    );
    actions.register(
        "notifications.center",
        "action.notifications.center",
        toggle_panel(hub.clone(), "notifications"),
    );
    actions.register(
        "session.menu",
        "action.session.menu",
        toggle_panel(hub.clone(), "session"),
    );
    let h = hub.clone();
    actions.register("launcher.toggle", "action.launcher.toggle", move |_| {
        let hub = h.clone();
        async move {
            hub.update("runtime.ui", None, |d| {
                d["launcher"] = json!(!d["launcher"].as_bool().unwrap_or(false))
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
    let h = hub.clone();
    actions.register("ui.close", "action.ui.close", move |_| {
        let hub = h.clone();
        async move {
            hub.set(
                "runtime.ui",
                json!({"popup": false, "panel": "", "launcher": false}),
                None,
            )
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
}

/// Debounce for the applications-dir watcher; a package install touches many files in a burst.
const INDEX_DEBOUNCE: std::time::Duration = std::time::Duration::from_millis(500);

/// The applications-dir watcher lives only while the launcher is open (Ma, rule 5). Changes
/// made while it was closed are caught by one `reindex()` on the next open.
pub struct LauncherWatch {
    launcher: kurashi_launcher::Launcher,
    state: Mutex<WatchState>,
    debounce: std::time::Duration,
}

struct WatchState {
    watcher: Option<kurashi_launcher::Watcher>,
    /// The watcher stopped (or never ran) since the index was last known fresh.
    stale: bool,
}

impl LauncherWatch {
    pub fn new(launcher: kurashi_launcher::Launcher) -> Arc<Self> {
        Self::with_debounce(launcher, INDEX_DEBOUNCE)
    }

    pub fn with_debounce(
        launcher: kurashi_launcher::Launcher,
        debounce: std::time::Duration,
    ) -> Arc<Self> {
        // Stale from the start: nothing watched between daemon start and the first open.
        Arc::new(Self {
            launcher,
            state: Mutex::new(WatchState {
                watcher: None,
                stale: true,
            }),
            debounce,
        })
    }

    pub fn is_watching(&self) -> bool {
        self.state.lock().expect("watch lock").watcher.is_some()
    }

    /// Idempotent: called with the launcher's current visibility. Blocking (reindex, inotify).
    pub fn apply(&self, open: bool) {
        let mut st = self.state.lock().expect("watch lock");
        match (open, st.watcher.is_some()) {
            (true, false) => {
                // Watch first, then reindex, so a change between the two is not lost. The
                // watcher re-indexes by itself; the launcher queries on demand, so no push.
                match self.launcher.watch(self.debounce, || {}) {
                    Ok(w) => st.watcher = Some(w),
                    Err(e) => tracing::warn!(error = %e, "launcher index watcher unavailable"),
                }
                if st.stale {
                    self.launcher.reindex();
                    st.stale = false;
                }
            }
            (false, true) => {
                st.watcher = None; // dropping stops both threads
                st.stale = true;
            }
            (false, false) => st.stale = true,
            (true, true) => {}
        }
    }
}

/// Follows `runtime.ui.launcher` on the hub and drives the watcher. Event-driven, no polling.
fn watch_while_open(hub: Arc<Hub>, watch: Arc<LauncherWatch>) {
    let mut events = hub.events();
    tokio::spawn(async move {
        loop {
            match events.recv().await {
                Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(_) => return,
            }
            // Re-read instead of interpreting patches: lag-proof and cheap.
            let open = hub
                .snapshot("runtime.ui")
                .is_ok_and(|(_, d)| d["launcher"].as_bool() == Some(true));
            let w = watch.clone();
            if tokio::task::spawn_blocking(move || w.apply(open))
                .await
                .is_err()
            {
                return;
            }
        }
    });
}

/// `query kind:"launcher"` + `launcher.launch {id, files?}`.
pub fn launcher(daemon: &mut Daemon, cfg: Option<&ConfigStore>, state_dir: std::path::PathBuf) {
    use kurashi_launcher::{IndexConfig, LaunchOptions, Launcher};
    let terminal = cfg
        .and_then(|c| c.get("launcher.terminal", None))
        .and_then(|p| p.value.as_array().cloned())
        .map(|a| {
            a.iter()
                .filter_map(Value::as_str)
                .map(String::from)
                .collect()
        })
        .unwrap_or_else(|| vec!["foot".into(), "-e".into()]);
    let opts = LaunchOptions {
        terminal_cmd: terminal,
        systemd_scope: cfg_bool(cfg, "launcher.systemd_scope", true),
    };
    let launcher = Launcher::with_state_file(
        IndexConfig::from_env(),
        opts,
        state_dir.join("launcher.json"),
    );
    watch_while_open(daemon.hub.clone(), LauncherWatch::new(launcher.clone()));
    let l = launcher.clone();
    let query: QueryFn = Arc::new(move |q: &str| {
        l.query(q, 30)
            .into_iter()
            .filter_map(|r| serde_json::to_value(r).ok())
            .collect()
    });
    daemon.queries.insert("launcher".into(), query);
    daemon.actions.register(
        "launcher.launch",
        "action.launcher.launch",
        move |args: Value| {
            let launcher = launcher.clone();
            async move {
                let id = args["id"]
                    .as_str()
                    .ok_or_else(|| ActionError::Invalid("launcher.launch needs id".into()))?
                    .to_string();
                let files: Vec<String> = args["files"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(Value::as_str)
                            .map(String::from)
                            .collect()
                    })
                    .unwrap_or_default();
                let pid = tokio::task::spawn_blocking(move || launcher.launch(&id, &files))
                    .await
                    .map_err(|e| ActionError::Internal(e.to_string()))?
                    .map_err(|e| ActionError::Unavailable(e.to_string()))?;
                Ok(Some(json!({"pid": pid})))
            }
        },
    );
}

/// The notification server lives for the daemon's lifetime: owning the bus name is what lets
/// notifications arrive at all (the one deliberate exception to refcounted services).
struct NotifySink {
    hub: Arc<Hub>,
    island: Option<Arc<crate::island::IslandHost>>,
}

impl kurashi_services::DocSink for NotifySink {
    fn set(&self, doc: Value) {
        if let Some(island) = &self.island {
            let unread = doc["unread"].as_u64().unwrap_or(0);
            island.signal(kurashi_island::FaceSignal {
                face: "notifications".into(),
                relevance: if unread > 0 { 40 } else { 0 },
                condition: unread > 0,
                transient: None,
            });
        }
        let _ = self.hub.set("svc.notifications", doc, None);
    }
}

/// Does `conn` itself own `name` right now?
async fn name_owned_by(conn: &zbus::Connection, name: &str) -> bool {
    let Ok(dbus) = zbus::fdo::DBusProxy::new(conn).await else {
        return false;
    };
    let Ok(bus_name) = zbus::names::BusName::try_from(name) else {
        return false;
    };
    match (dbus.get_name_owner(bus_name).await, conn.unique_name()) {
        (Ok(owner), Some(me)) => owner.as_str() == me.as_str(),
        _ => false,
    }
}

pub fn notifications(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    cfg: Option<&ConfigStore>,
    cache_dir: std::path::PathBuf,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    notifications_with_facts(hub, actions, cfg, cache_dir, island, SharedFacts::default());
}

/// Like [`notifications`]; the task reports the session bus and the name ownership it actually
/// observed into the doctor's `facts`.
pub fn notifications_with_facts(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    cfg: Option<&ConfigStore>,
    cache_dir: std::path::PathBuf,
    island: Option<Arc<crate::island::IslandHost>>,
    facts: SharedFacts,
) {
    use kurashi_notify::{NotifyConfig, Server};
    hub.register(
        "svc.notifications",
        json!({"dnd": false, "unread": 0, "toasts": [], "items": []}),
        None,
    );
    if !cfg_bool(cfg, "notifications.server", true) {
        return;
    }
    let mut nc = NotifyConfig::new(cache_dir);
    nc.dnd = cfg_bool(cfg, "notifications.dnd", false);
    if let Some(n) = cfg
        .and_then(|c| c.get("notifications.history_max", None))
        .and_then(|p| p.value.as_u64())
    {
        nc.history_max = n as usize;
    }
    let commands: Arc<Mutex<Option<kurashi_notify::Commands>>> = Arc::default();
    {
        let (hub, commands) = (hub.clone(), commands.clone());
        tokio::spawn(async move {
            let conn = match zbus::Connection::session().await {
                Ok(c) => c,
                Err(e) => {
                    facts.update(|f| {
                        f.session_bus = Some(false);
                        f.notification_name_owned = Some(false);
                    });
                    return tracing::warn!(error = %e, "no session bus: notifications off");
                }
            };
            facts.update(|f| f.session_bus = Some(true));
            match Server::serve(conn.clone(), Arc::new(NotifySink { hub, island }), nc).await {
                Ok((handle, cmds)) => {
                    // `serve` succeeds even when another daemon holds the name (it never steals
                    // it), so ask the bus who owns it instead of assuming.
                    let owned = name_owned_by(&conn, "org.freedesktop.Notifications").await;
                    facts.update(|f| f.notification_name_owned = Some(owned));
                    *commands.lock().expect("notify lock") = Some(cmds);
                    // The server runs until the daemon exits.
                    std::mem::forget(handle);
                }
                Err(e) => {
                    facts.update(|f| f.notification_name_owned = Some(false));
                    tracing::warn!(error = %e, "notification server failed");
                }
            }
        });
    }
    let get = move || commands.lock().expect("notify lock").clone();
    let id_of = |v: &Value| v["id"].as_u64().map(|n| n as u32);
    let g = get.clone();
    actions.register("notify.dismiss", "action.notify.dismiss", move |v| {
        let c = g();
        async move {
            let c = c.ok_or_else(|| {
                ActionError::Unavailable("notification server not running".into())
            })?;
            match id_of(&v) {
                Some(id) => c.dismiss(id).await,
                None => c.dismiss_all().await,
            }
            Ok(None)
        }
    });
    let g = get.clone();
    actions.register("notify.invoke", "action.notify.invoke", move |v| {
        let c = g();
        async move {
            let c = c.ok_or_else(|| {
                ActionError::Unavailable("notification server not running".into())
            })?;
            let id =
                id_of(&v).ok_or_else(|| ActionError::Invalid("notify.invoke needs id".into()))?;
            c.invoke_action(id, v["key"].as_str().unwrap_or("default"))
                .await;
            Ok(None)
        }
    });
    let g = get.clone();
    actions.register("notify.dnd", "action.notify.dnd", move |v| {
        let c = g();
        async move {
            let c = c.ok_or_else(|| {
                ActionError::Unavailable("notification server not running".into())
            })?;
            c.set_dnd(v["on"].as_bool().unwrap_or(true));
            Ok(None)
        }
    });
    actions.register("notify.mark_read", "action.notify.mark_read", move |v| {
        let c = get();
        async move {
            let c = c.ok_or_else(|| {
                ActionError::Unavailable("notification server not running".into())
            })?;
            match id_of(&v) {
                Some(id) => c.mark_read(id),
                None => c.mark_all_read(),
            }
            Ok(None)
        }
    });
}

/// `mods` document + `mod.enable` / `mod.disable`. Contributions (faces, services, …) are
/// registered by later milestones; for now the registry and its honest catalog are live.
pub fn mods(hub: &Arc<Hub>, actions: &mut ActionRegistry, roots: Vec<std::path::PathBuf>) {
    use kurashi_mods::{Policy, Registry};
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).expect("crate version");
    let mut reg = Registry::discover(&roots, &version);
    for s in &reg.shadows {
        tracing::info!(?s, "user mod shadows a bundled one");
    }
    for (id, r) in reg.apply_defaults(&Policy {
        default_enabled: ["easter-eggs".to_string()].into(),
    }) {
        if let Err(e) = r {
            tracing::warn!(%id, error = e.i18n_key(), "mod not enabled");
        }
    }
    hub.register("mods", reg.doc(), None);
    let reg = Arc::new(Mutex::new(reg));
    for (action, enable) in [("mod.enable", true), ("mod.disable", false)] {
        let (hub, reg) = (hub.clone(), reg.clone());
        actions.register(action, &format!("action.{action}"), move |v: Value| {
            let (hub, reg) = (hub.clone(), reg.clone());
            async move {
                let id = v["id"]
                    .as_str()
                    .ok_or_else(|| ActionError::Invalid(format!("{action} needs id")))?;
                let doc = {
                    let mut r = reg.lock().expect("mods lock");
                    let res = if enable { r.enable(id) } else { r.disable(id) };
                    res.map_err(|e| ActionError::Invalid(e.i18n_key().to_string()))?;
                    r.doc()
                };
                let _ = hub.set("mods", doc, None);
                Ok(None)
            }
        });
    }
}

/// `svc.audio` (refcounted: the pulse connection and its thread exist only while watched) +
/// intent `audio.volume` (coalesced per frame by the daemon) + `audio.mute.toggle`.
pub struct AudioProvider {
    running: Mutex<Option<(kurashi_audio::AudioHandle, kurashi_audio::Commands)>>,
    /// Origin of the latest `audio.volume` intent: the server's change event that follows is
    /// patched with it, so the dragging slider recognises its own echo (PROTOCOL §4).
    last_origin: Arc<Mutex<Option<(String, std::time::Instant)>>>,
    island: Option<Arc<crate::island::IslandHost>>,
}

/// Echo window: a server round-trip is a few ms; anything later is someone else's change.
const ORIGIN_ECHO: std::time::Duration = std::time::Duration::from_millis(500);

struct AudioSink {
    hub: Arc<Hub>,
    last_origin: Arc<Mutex<Option<(String, std::time::Instant)>>>,
    island: Option<Arc<crate::island::IslandHost>>,
    /// (volume, muted) last seen; a change shows the island's transient `volume` face (OSD).
    last: Mutex<Option<(f64, bool)>>,
}

impl kurashi_services::DocSink for AudioSink {
    fn set(&self, doc: Value) {
        let now = (
            doc["volume"].as_f64().unwrap_or(0.0),
            doc["muted"].as_bool().unwrap_or(false),
        );
        let prev = self.last.lock().expect("audio last").replace(now);
        if let (Some(island), Some(prev)) = (&self.island, prev)
            && prev != now
        {
            island.signal(kurashi_island::FaceSignal {
                face: "volume".into(),
                relevance: 0,
                condition: true,
                transient: Some(kurashi_island::Transient {
                    kind: "volume".into(),
                    ttl_ms: 1500,
                    may_interrupt: true,
                }),
            });
        }
        let origin = self
            .last_origin
            .lock()
            .expect("origin lock")
            .as_ref()
            .filter(|(_, at)| at.elapsed() < ORIGIN_ECHO)
            .map(|(o, _)| o.clone());
        let _ = self.hub.set("svc.audio", doc, origin);
    }
}

impl crate::hub::Provider for AudioProvider {
    fn start(&self, hub: Arc<Hub>) {
        let (h, c) = kurashi_audio::start(Arc::new(AudioSink {
            hub,
            last_origin: self.last_origin.clone(),
            island: self.island.clone(),
            last: Mutex::new(None),
        }));
        *self.running.lock().expect("audio lock") = Some((h, c));
    }
    fn stop(&self) {
        // Dropping the handle joins the worker and closes the pulse connection.
        self.running.lock().expect("audio lock").take();
    }
}

impl AudioProvider {
    fn commands(&self) -> Option<kurashi_audio::Commands> {
        self.running
            .lock()
            .expect("audio lock")
            .as_ref()
            .map(|(_, c)| c.clone())
    }
}

pub fn audio(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    let provider = Arc::new(AudioProvider {
        running: Mutex::new(None),
        last_origin: Arc::default(),
        island,
    });
    hub.register(
        "svc.audio",
        json!({"available": false, "volume": 0, "muted": false, "sinks": []}),
        Some(provider.clone()),
    );
    let p = provider.clone();
    intents.register("audio.volume", move |v, origin| {
        if let (Some(c), Some(v)) = (p.commands(), v.as_f64()) {
            *p.last_origin.lock().expect("origin lock") =
                origin.map(|o| (o, std::time::Instant::now()));
            c.set_volume(v);
        }
    });
    actions.register("audio.mute.toggle", "action.audio.mute.toggle", move |_| {
        let c = provider.commands();
        async move {
            c.ok_or_else(|| ActionError::Unavailable("audio service not running".into()))?
                .toggle_mute();
            Ok(None)
        }
    });
}

/// Marks a locked session in the runtime dir (cleared on logout), so a daemon that restarts or
/// crashes while locked comes back **locked** — killing kurashid must never unlock the screen.
struct LockSink {
    hub: Arc<Hub>,
    marker: std::path::PathBuf,
}

impl kurashi_services::DocSink for LockSink {
    fn set(&self, doc: Value) {
        if doc["locked"].as_bool() == Some(true) {
            if let Some(dir) = self.marker.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            if let Err(e) = std::fs::write(&self.marker, b"") {
                tracing::error!(error = %e, "cannot persist lock state");
            }
        } else {
            let _ = std::fs::remove_file(&self.marker);
        }
        let _ = self.hub.set("runtime.lock", doc, None);
    }
}

/// `runtime.lock` + intents `lock.submit` / `lock.cancel` + action `session.lock` (K2: the secret
/// is handled only here and never logged; the frontend owns ext-session-lock).
pub fn lock(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    marker: std::path::PathBuf,
) {
    use kurashi_auth::{LockConfig, LockSession, PamAuthenticator, SystemClock};
    let user = std::env::var("USER").unwrap_or_default();
    let was_locked = marker.exists();
    hub.register(
        "runtime.lock",
        json!({"locked": was_locked, "busy": false, "failures": 0}),
        None,
    );
    let session = LockSession::new(
        user,
        Arc::new(PamAuthenticator::new("kurashi")),
        Arc::new(LockSink {
            hub: hub.clone(),
            marker,
        }),
        Arc::new(SystemClock::new()),
        LockConfig::default(),
    );
    if was_locked {
        tracing::warn!("previous instance was locked: starting locked");
        session.lock();
    }
    for name in ["lock.submit", "lock.cancel"] {
        let s = session.clone();
        intents.register(name, move |v, _| {
            let s = s.clone();
            tokio::spawn(async move {
                let _ = s.handle_intent(name, &v).await;
            });
        });
    }
    actions.register("session.lock", "action.session.lock", move |_| {
        let s = session.clone();
        async move {
            s.handle_action("session.lock");
            Ok(None)
        }
    });
}

/// Opens the bus the logind calls go to. Injected so tests never reach the real system bus.
pub type ConnectFn = Arc<
    dyn Fn() -> std::pin::Pin<
            Box<dyn std::future::Future<Output = zbus::Result<zbus::Connection>> + Send>,
        > + Send
        + Sync,
>;

/// Error text of the `invalid` reply when `{confirm: true}` is missing; the UI keys its confirm
/// step on it.
pub const CONFIRM_REQUIRED: &str = "session.confirm_required";

/// `session.{suspend,reboot,poweroff,logout}`: destructive, so each needs `{confirm: true}` in
/// its args. Talks to logind on the system bus.
pub fn session(actions: &mut ActionRegistry, facts: SharedFacts) {
    let connect: ConnectFn = Arc::new(|| Box::pin(zbus::Connection::system()));
    session_with(actions, facts, connect);
}

pub fn session_with(actions: &mut ActionRegistry, facts: SharedFacts, connect: ConnectFn) {
    const DEST: &str = "org.freedesktop.login1";
    // (action, object path, interface, method, takes the `interactive` bool)
    const CMDS: [(&str, &str, &str, &str, bool); 4] = [
        (
            "session.suspend",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "Suspend",
            true,
        ),
        (
            "session.reboot",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "Reboot",
            true,
        ),
        (
            "session.poweroff",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "PowerOff",
            true,
        ),
        // `auto` resolves to the caller's own session, so no session id lookup is needed.
        (
            "session.logout",
            "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session",
            "Terminate",
            false,
        ),
    ];
    // One short probe at startup so `doctor` can say whether logind is reachable at all; the
    // connection is dropped right away (Ma).
    {
        let (connect, facts) = (connect.clone(), facts.clone());
        tokio::spawn(async move {
            let ok = connect().await.is_ok();
            facts.update(|f| f.system_bus = Some(ok));
        });
    }
    for (id, path, iface, method, interactive) in CMDS {
        let (connect, facts) = (connect.clone(), facts.clone());
        actions.register(id, &format!("action.{id}"), move |args: Value| {
            let (connect, facts) = (connect.clone(), facts.clone());
            async move {
                // Checked before any bus traffic: an unconfirmed call must be inert.
                if args["confirm"].as_bool() != Some(true) {
                    return Err(ActionError::Invalid(CONFIRM_REQUIRED.into()));
                }
                let conn = connect().await.map_err(|e| {
                    facts.update(|f| f.system_bus = Some(false));
                    ActionError::Unavailable(e.to_string())
                })?;
                facts.update(|f| f.system_bus = Some(true));
                let reply = if interactive {
                    conn.call_method(Some(DEST), path, Some(iface), method, &(false,))
                        .await
                } else {
                    conn.call_method(Some(DEST), path, Some(iface), method, &())
                        .await
                };
                reply.map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    #[tokio::test]
    async fn lock_survives_daemon_restart() {
        let dir = std::env::temp_dir().join(format!("kurashid-lock-{}", std::process::id()));
        let marker = dir.join("locked");
        let _ = std::fs::remove_dir_all(&dir);

        // First instance locks.
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        lock(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            marker.clone(),
        );
        actions.invoke("session.lock", Value::Null).await.unwrap();
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], true);
        assert!(marker.exists(), "lock persisted");

        // "Restart": a fresh instance must come back locked.
        let hub2 = Hub::new();
        lock(
            &hub2,
            &mut ActionRegistry::default(),
            &mut crate::Intents::default(),
            marker.clone(),
        );
        assert_eq!(hub2.snapshot("runtime.lock").unwrap().1["locked"], true);
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("kurashid-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn desktop(dir: &std::path::Path, file: &str, name: &str) {
        std::fs::write(
            dir.join(file),
            format!("[Desktop Entry]\nType=Application\nName={name}\nExec=true\n"),
        )
        .unwrap();
    }

    fn launcher_over(dir: &std::path::Path) -> kurashi_launcher::Launcher {
        let cfg = kurashi_launcher::IndexConfig {
            dirs: vec![dir.to_path_buf()],
            locale: None,
            desktops: vec![],
            check_try_exec: false,
        };
        kurashi_launcher::Launcher::new(
            cfg,
            kurashi_launcher::LaunchOptions {
                terminal_cmd: vec![],
                systemd_scope: false,
            },
            kurashi_launcher::Frecency::memory(),
        )
    }

    async fn until(what: &str, mut f: impl FnMut() -> bool) {
        for _ in 0..200 {
            if f() {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        panic!("timed out waiting for {what}");
    }

    #[tokio::test]
    async fn launcher_watcher_follows_the_open_state() {
        let dir = temp_dir("apps");
        desktop(&dir, "a.desktop", "Alpha");
        let launcher = launcher_over(&dir);
        assert_eq!(launcher.len(), 1);
        let watch = LauncherWatch::with_debounce(launcher.clone(), Duration::from_millis(30));
        let hub = Hub::new();
        hub.register(
            "runtime.ui",
            json!({"popup": false, "panel": "", "launcher": false}),
            None,
        );
        watch_while_open(hub.clone(), watch.clone());
        assert!(!watch.is_watching(), "closed launcher: no watcher");

        // Opening starts the watcher (and the first open reindexes once).
        hub.update("runtime.ui", None, |d| d["launcher"] = json!(true))
            .unwrap();
        until("watcher started", || watch.is_watching()).await;
        desktop(&dir, "b.desktop", "Beta");
        until("live reindex", || launcher.len() == 2).await;

        // Closing stops it: a change while closed is not seen...
        hub.update("runtime.ui", None, |d| d["launcher"] = json!(false))
            .unwrap();
        until("watcher stopped", || !watch.is_watching()).await;
        desktop(&dir, "c.desktop", "Gamma");
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(launcher.len(), 2, "nothing watches while closed");

        // ...but the next open catches up with one reindex.
        hub.update("runtime.ui", None, |d| d["launcher"] = json!(true))
            .unwrap();
        until("catch-up reindex", || launcher.len() == 3).await;
        assert!(watch.is_watching());
        let _ = std::fs::remove_dir_all(&dir);
    }

    // ---- session actions against a private bus with a fake logind --------------------------

    struct Bus {
        child: std::process::Child,
        addr: String,
        dir: std::path::PathBuf,
    }

    impl Bus {
        fn start() -> Self {
            use std::io::{BufRead, BufReader};
            let dir = temp_dir("bus");
            let conf = dir.join("bus.conf");
            std::fs::write(
                &conf,
                format!(
                    r#"<busconfig><type>session</type>
<listen>unix:tmpdir={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                    dir.display()
                ),
            )
            .unwrap();
            let mut child = std::process::Command::new("dbus-daemon")
                .arg(format!("--config-file={}", conf.display()))
                .args(["--nofork", "--print-address"])
                .stdout(std::process::Stdio::piped())
                .spawn()
                .expect("dbus-daemon (run inside nix develop)");
            let mut addr = String::new();
            BufReader::new(child.stdout.as_mut().unwrap())
                .read_line(&mut addr)
                .unwrap();
            Self {
                child,
                addr: addr.trim().to_owned(),
                dir,
            }
        }

        async fn conn(&self) -> zbus::Connection {
            zbus::connection::Builder::address(self.addr.as_str())
                .unwrap()
                .build()
                .await
                .unwrap()
        }
    }

    impl Drop for Bus {
        fn drop(&mut self) {
            let _ = self.child.kill();
            let _ = self.child.wait();
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    struct FakeManager(Arc<Mutex<Vec<String>>>);
    #[zbus::interface(name = "org.freedesktop.login1.Manager")]
    impl FakeManager {
        fn suspend(&self, _i: bool) {
            self.0.lock().unwrap().push("Suspend".into());
        }
        fn reboot(&self, _i: bool) {
            self.0.lock().unwrap().push("Reboot".into());
        }
        fn power_off(&self, _i: bool) {
            self.0.lock().unwrap().push("PowerOff".into());
        }
    }

    struct FakeSession(Arc<Mutex<Vec<String>>>);
    #[zbus::interface(name = "org.freedesktop.login1.Session")]
    impl FakeSession {
        fn terminate(&self) {
            self.0.lock().unwrap().push("Terminate".into());
        }
    }

    #[tokio::test]
    async fn session_actions_need_confirmation_and_report_the_system_bus() {
        let bus = Bus::start();
        let calls = Arc::new(Mutex::new(Vec::<String>::new()));
        let srv = bus.conn().await;
        srv.object_server()
            .at("/org/freedesktop/login1", FakeManager(calls.clone()))
            .await
            .unwrap();
        srv.object_server()
            .at(
                "/org/freedesktop/login1/session/auto",
                FakeSession(calls.clone()),
            )
            .await
            .unwrap();
        srv.request_name("org.freedesktop.login1").await.unwrap();

        let facts = SharedFacts::default();
        let addr = bus.addr.clone();
        let connect: ConnectFn = Arc::new(move || {
            let addr = addr.clone();
            Box::pin(async move {
                zbus::connection::Builder::address(addr.as_str())?
                    .build()
                    .await
            })
        });
        let mut actions = ActionRegistry::default();
        session_with(&mut actions, facts.clone(), connect);
        until("probe reports", || facts.get().system_bus == Some(true)).await;

        for id in [
            "session.suspend",
            "session.reboot",
            "session.poweroff",
            "session.logout",
        ] {
            for args in [
                Value::Null,
                json!({}),
                json!({"confirm": false}),
                json!({"confirm": "yes"}),
            ] {
                assert_eq!(
                    actions.invoke(id, args).await,
                    Err(ActionError::Invalid(CONFIRM_REQUIRED.into())),
                    "{id} must demand confirmation"
                );
            }
        }
        assert!(
            calls.lock().unwrap().is_empty(),
            "unconfirmed calls are inert"
        );

        for id in [
            "session.suspend",
            "session.reboot",
            "session.poweroff",
            "session.logout",
        ] {
            actions.invoke(id, json!({"confirm": true})).await.unwrap();
        }
        assert_eq!(
            *calls.lock().unwrap(),
            vec!["Suspend", "Reboot", "PowerOff", "Terminate"]
        );
    }

    #[tokio::test]
    async fn session_actions_report_an_unreachable_bus() {
        let facts = SharedFacts::default();
        let connect: ConnectFn = Arc::new(|| {
            Box::pin(async { Err(zbus::Error::Failure("no system bus (test)".into())) })
        });
        let mut actions = ActionRegistry::default();
        session_with(&mut actions, facts.clone(), connect);
        until("probe reports", || facts.get().system_bus == Some(false)).await;
        assert!(matches!(
            actions
                .invoke("session.suspend", json!({"confirm": true}))
                .await,
            Err(ActionError::Unavailable(_))
        ));
    }
}
