//! Startup wiring of the feature crates whose lifetime is the daemon's: launcher queries, the
//! notification server, the mods registry and the `runtime.ui` panel state.

use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::Hub;
use crate::{Daemon, QueryFn};

fn cfg_bool(cfg: Option<&ConfigStore>, key: &str, dflt: bool) -> bool {
    cfg.and_then(|c| c.get(key, None))
        .and_then(|p| p.value.as_bool())
        .unwrap_or(dflt)
}

/// `runtime.ui` — daemon-owned panel state (ARCHITECTURE §4); `island.expand` toggles the
/// island's panel. `probe.popup.toggle` stays as an alias for the bake-off probes.
pub fn ui(hub: &Arc<Hub>, actions: &mut ActionRegistry) {
    hub.register("runtime.ui", json!({"popup": false}), None);
    for id in ["island.expand", "probe.popup.toggle"] {
        let hub = hub.clone();
        actions.register(id, &format!("action.{id}"), move |_| {
            let hub = hub.clone();
            async move {
                hub.update("runtime.ui", None, |d| {
                    d["popup"] = json!(!d["popup"].as_bool().unwrap_or(false))
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        });
    }
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

struct HubSink(Arc<Hub>, &'static str);
impl kurashi_services::DocSink for HubSink {
    fn set(&self, doc: Value) {
        let _ = self.0.set(self.1, doc, None);
    }
}

/// The notification server lives for the daemon's lifetime: owning the bus name is what lets
/// notifications arrive at all (the one deliberate exception to refcounted services).
pub fn notifications(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    cfg: Option<&ConfigStore>,
    cache_dir: std::path::PathBuf,
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
                Err(e) => return tracing::warn!(error = %e, "no session bus: notifications off"),
            };
            match Server::serve(conn, Arc::new(HubSink(hub, "svc.notifications")), nc).await {
                Ok((handle, cmds)) => {
                    *commands.lock().expect("notify lock") = Some(cmds);
                    // The server runs until the daemon exits.
                    std::mem::forget(handle);
                }
                Err(e) => tracing::warn!(error = %e, "notification server failed"),
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

/// `runtime.lock` + intents `lock.submit` / `lock.cancel` + action `session.lock` (K2: the secret
/// is handled only here and never logged; the frontend owns ext-session-lock).
pub fn lock(hub: &Arc<Hub>, actions: &mut ActionRegistry, intents: &mut crate::Intents) {
    use kurashi_auth::{LockConfig, LockSession, PamAuthenticator, SystemClock};
    let user = std::env::var("USER").unwrap_or_default();
    hub.register(
        "runtime.lock",
        json!({"locked": false, "busy": false, "failures": 0}),
        None,
    );
    let session = LockSession::new(
        user,
        Arc::new(PamAuthenticator::new("kurashi")),
        Arc::new(HubSink(hub.clone(), "runtime.lock")),
        Arc::new(SystemClock::new()),
        LockConfig::default(),
    );
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
