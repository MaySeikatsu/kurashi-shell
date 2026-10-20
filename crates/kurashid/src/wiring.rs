//! Startup wiring of the feature crates whose lifetime is the daemon's: launcher queries, the
//! notification server, the mods registry and the `runtime.ui` panel state.

use std::collections::BTreeSet;
use std::future::Future;
use std::sync::{Arc, Mutex};

use kurashi_ipc::ApplyOp;
use kurashi_services::brightness::{self as backlight, Change};
use kurashi_services::network::{ConnectError, WifiError};
use kurashi_services::power_profiles::ProfileError;
use serde_json::{Value, json};

use crate::actions::{ActionError, ActionRegistry, ActionResult};
use crate::config::ConfigStore;
use crate::doctor::SharedFacts;
use crate::hub::Hub;
use crate::island::IslandHost;
use crate::native::{Native, SLOTS_DOC};
use crate::services::{Bus, ConnectFn, ServiceProvider, ServiceTask};
use crate::{Daemon, QueryFn};

fn cfg_bool(cfg: Option<&ConfigStore>, key: &str, dflt: bool) -> bool {
    cfg.and_then(|c| c.get(key, None))
        .and_then(|p| p.value.as_bool())
        .unwrap_or(dflt)
}

/// `runtime.ui` — daemon-owned panel state (ARCHITECTURE §4):
/// `{popup, panel, launcher, tray, face}`. `panel` names what the Stage shows (`""` = nothing);
/// `popup` mirrors `panel != ""` for the probe-era frontend. Panels are exclusive; the launcher is
/// its own surface. `tray` is the item whose menu the `tray` panel shows (`""` otherwise, K23).
/// `face` is the island face whose expanded view the `island` panel shows (`""` otherwise, K24).
/// A native mod's panel is `mod:<id>:<panel>`, opened by `mod.panel.open` (K26, K28).
/// `peek` is the hover/focus peek the Stage shows while no panel is open (K35): absent, or
/// `{source, output, x, w}`; opening a panel removes it (documents carry no `null`, PROTOCOL §1).
pub fn ui(hub: &Arc<Hub>, actions: &mut ActionRegistry) {
    hub.register("runtime.ui", ui_closed(), None);
    let toggle_panel = |hub: Arc<Hub>, name: &'static str| {
        move |_| {
            let hub = hub.clone();
            async move {
                hub.update("runtime.ui", None, |d| {
                    let open = d["panel"].as_str() == Some(name);
                    d["panel"] = json!(if open { "" } else { name });
                    d["popup"] = json!(!open);
                    d["tray"] = json!("");
                    d["face"] = json!("");
                    clear_peek(d);
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        }
    };
    // K24: the island panel is the expanded view of the face the island shows when it opens,
    // latched while open, so the card never switches under the pointer when the arbiter moves on.
    // `{island?}` names the instance (default `main`); an island without a document opens with
    // face `""` (the frontend's generic card).
    let expand = |hub: Arc<Hub>| {
        move |a: Value| {
            let hub = hub.clone();
            async move {
                let island = match a.get("island") {
                    None => "main".to_string(),
                    Some(v) => v
                        .as_str()
                        .filter(|s| !s.is_empty())
                        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?
                        .to_string(),
                };
                let face = match hub.snapshot(&format!("runtime.island.{island}")) {
                    Ok((_, d)) => d["face"].as_str().unwrap_or("").to_string(),
                    Err(_) if a.get("island").is_none() => String::new(),
                    Err(_) => return Err(ActionError::Invalid(ARGS_INVALID.into())),
                };
                hub.update("runtime.ui", None, |d| {
                    let open = d["panel"].as_str() == Some("island");
                    d["panel"] = json!(if open { "" } else { "island" });
                    d["popup"] = json!(!open);
                    d["tray"] = json!("");
                    d["face"] = json!(if open { "" } else { face.as_str() });
                    clear_peek(d);
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        }
    };
    actions.register("island.expand", "action.island.expand", expand(hub.clone()));
    // Alias kept for the bake-off probes.
    actions.register(
        "probe.popup.toggle",
        "action.island.expand",
        expand(hub.clone()),
    );
    // K24: quick settings (Bluetooth now; network, audio devices, power later) are a Stage panel
    // opened from a bar widget, not the island.
    actions.register(
        "quick.toggle",
        "action.quick.toggle",
        toggle_panel(hub.clone(), "quick"),
    );
    // K26/K28: a mod's Stage panel `mod:<id>:<panel>`. Refused unless the mod is on and its manifest
    // provides `panel:<panel>`; the `mods` document is the registry as the frontend reads it.
    let h = hub.clone();
    actions.register("mod.panel.open", "action.mod.panel.open", move |a| {
        let hub = h.clone();
        async move {
            let id = str_arg(&a, "id")?;
            let panel = str_arg(&a, "panel")?;
            if id.is_empty() || panel.is_empty() {
                return Err(ActionError::Invalid(ARGS_INVALID.into()));
            }
            if !mod_offers_panel(&hub, &id, &panel) {
                return Err(ActionError::Invalid(PANEL_UNAVAILABLE.into()));
            }
            let name = format!("mod:{id}:{panel}");
            hub.update("runtime.ui", None, |d| {
                let open = d["panel"].as_str() == Some(name.as_str());
                d["panel"] = json!(if open { "" } else { name.as_str() });
                d["popup"] = json!(!open);
                d["tray"] = json!("");
                d["face"] = json!("");
                clear_peek(d);
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
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
    // K23: a tray item's menu is the Stage's `tray` panel. The same item again closes it; another
    // item switches to its menu. Not tied to svc.tray running: this is UI state only.
    let h = hub.clone();
    actions.register("tray.menu.open", "action.tray.menu.open", move |a| {
        let hub = h.clone();
        async move {
            let id = str_arg(&a, "id")?;
            if id.is_empty() {
                return Err(ActionError::Invalid(ARGS_INVALID.into()));
            }
            hub.update("runtime.ui", None, |d| {
                let open = d["panel"].as_str() == Some("tray") && d["tray"].as_str() == Some(&id);
                d["panel"] = json!(if open { "" } else { "tray" });
                d["popup"] = json!(!open);
                d["tray"] = json!(if open { "" } else { id.as_str() });
                d["face"] = json!("");
                clear_peek(d);
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
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
    // K35: a bar widget's (or the island's, or a tray item's) peek, shown by the Stage under the
    // widget: `{source, output, x, w}` sets it (x and w in the output's logical px), `{}` clears it.
    // Refused while a panel is open (the card is the bigger view) and for a mod source whose mod is
    // off or does not provide `peek:<name>`.
    let h = hub.clone();
    actions.register("ui.peek", "action.ui.peek", move |a| {
        let hub = h.clone();
        async move {
            let peek = peek_of(&hub, &a)?;
            let mut refused = false;
            hub.update("runtime.ui", None, |d| {
                if peek.is_some() && d["panel"].as_str().is_some_and(|p| !p.is_empty()) {
                    refused = true;
                    return;
                }
                match &peek {
                    Some(p) => d["peek"] = p.clone(),
                    None => clear_peek(d),
                }
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            if refused {
                return Err(ActionError::Invalid(PEEK_UNDER_CARD.into()));
            }
            Ok(None)
        }
    });
    let h = hub.clone();
    actions.register("ui.close", "action.ui.close", move |_| {
        let hub = h.clone();
        async move {
            hub.set("runtime.ui", ui_closed(), None)
                .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
}

/// `runtime.ui` with nothing open.
fn ui_closed() -> Value {
    json!({"popup": false, "panel": "", "launcher": false, "tray": "", "face": ""})
}

/// Removes the peek from a `runtime.ui` value (K35); absence is "no peek".
fn clear_peek(d: &mut Value) {
    if let Some(o) = d.as_object_mut() {
        o.remove("peek");
    }
}

/// The peek `ui.peek` asks for (K35): `None` clears it (no `source`, or an empty one). A source is
/// `mod:<id>:<name>` (the mod is on and provides `peek:<name>`), `tray:<item>` or `island:<instance>`.
fn peek_of(hub: &Hub, a: &Value) -> Result<Option<Value>, ActionError> {
    let source = a["source"].as_str().unwrap_or("");
    if source.is_empty() {
        return Ok(None);
    }
    let invalid = || ActionError::Invalid(ARGS_INVALID.into());
    let output = a["output"]
        .as_str()
        .filter(|o| !o.is_empty())
        .ok_or_else(invalid)?;
    let px = |k: &str| {
        a[k].as_f64()
            .filter(|v| v.is_finite() && *v >= 0.0)
            .ok_or_else(invalid)
    };
    let (x, w) = (px("x")?, px("w")?);
    // The bar's edge (I67): a side bar's peek also needs the widget's y and height; absent = a top bar.
    let edge = match a.get("edge") {
        None => None,
        Some(Value::String(e)) if matches!(e.as_str(), "top" | "bottom" | "left" | "right") => {
            Some(e.as_str())
        }
        Some(_) => return Err(invalid()),
    };
    let side = matches!(edge, Some("left" | "right"));
    let span = if side {
        Some((px("y")?, px("h")?))
    } else {
        None
    };
    let ok = match source.split_once(':') {
        Some(("mod", rest)) => match rest.split_once(':') {
            Some((id, name)) if !id.is_empty() && !name.is_empty() => {
                if !mod_provides(hub, id, &format!("peek:{name}")) {
                    return Err(ActionError::Invalid(PEEK_UNAVAILABLE.into()));
                }
                true
            }
            _ => false,
        },
        Some(("tray" | "island", rest)) => !rest.is_empty(),
        _ => false,
    };
    if !ok {
        return Err(invalid());
    }
    let mut peek = json!({"source": source, "output": output, "x": x, "w": w});
    if let Some(edge) = edge {
        peek["edge"] = json!(edge);
    }
    if let Some((y, h)) = span {
        peek["y"] = json!(y);
        peek["h"] = json!(h);
    }
    Ok(Some(peek))
}

/// `ui.peek` while a panel is open: the card is shown, a peek would sit on top of it.
const PEEK_UNDER_CARD: &str = "ui.error.peek_under_card";
/// `ui.peek` of a mod peek the mod does not offer, or whose mod is off.
const PEEK_UNAVAILABLE: &str = "mods.error.peek_unavailable";

/// `mod.panel.open` of a panel the mod does not offer, or whose mod is off.
const PANEL_UNAVAILABLE: &str = "mods.error.panel_unavailable";

/// Whether the `mods` document lists mod `id` as enabled, providing `panel:<panel>`.
fn mod_offers_panel(hub: &Hub, id: &str, panel: &str) -> bool {
    mod_provides(hub, id, &format!("panel:{panel}"))
}

/// Whether mod `id` is on and its manifest provides `want` (e.g. `panel:x`, `peek:x`).
fn mod_provides(hub: &Hub, id: &str, want: &str) -> bool {
    hub.snapshot("mods").is_ok_and(|(_, d)| {
        d["mods"].as_array().is_some_and(|mods| {
            mods.iter().any(|m| {
                m["id"] == id
                    && m["state"] == "enabled"
                    && m["provides"]
                        .as_array()
                        .is_some_and(|p| p.iter().any(|x| x == want))
            })
        })
    })
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
        // Starts closed, like the watcher: only a change of the launcher's state is acted on.
        // Every other hub event would otherwise cost a blocking task.
        let mut last = false;
        loop {
            match events.recv().await {
                Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                Err(_) => return,
            }
            // Re-read instead of interpreting patches: lag-proof and cheap.
            let open = hub
                .snapshot("runtime.ui")
                .is_ok_and(|(_, d)| d["launcher"].as_bool() == Some(true));
            if open == last {
                continue;
            }
            last = open;
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

/// Puts `text` on the Wayland clipboard with `wl-copy` (wl-clipboard); unavailable without it.
async fn copy_text(text: &str) -> Result<(), ActionError> {
    use tokio::io::AsyncWriteExt;
    let mut child = tokio::process::Command::new("wl-copy")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| ActionError::Unavailable(format!("wl-copy: {e}")))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(text.as_bytes())
            .await
            .map_err(|e| ActionError::Internal(e.to_string()))?;
    }
    // wl-copy forks to serve the clipboard; the parent exits at once.
    let _ = child.wait().await;
    Ok(())
}

/// Puts the cliphist entry `line` (its id) back on the clipboard: `cliphist decode` into `wl-copy`.
async fn copy_clip(line: &str) -> Result<(), ActionError> {
    if !line.chars().all(|c| c.is_ascii_digit()) {
        return Err(ActionError::Invalid("error.args.invalid".into()));
    }
    let out = tokio::process::Command::new("cliphist")
        .arg("decode")
        .arg(line)
        .output()
        .await
        .map_err(|e| ActionError::Unavailable(format!("cliphist: {e}")))?;
    if !out.status.success() {
        return Err(ActionError::Unavailable("cliphist decode failed".into()));
    }
    copy_text(&String::from_utf8_lossy(&out.stdout)).await
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
    // A query that is arithmetic gets its value as the first row (kind `calc`, id `calc:<value>`); launching it
    // copies the value (Capsule's inline calculator, K42 session).
    let query: QueryFn = Arc::new(move |q: &str| {
        // Prefix modes: `:` emoji, `;` the clipboard history.
        if let Some(rest) = q.strip_prefix(':') {
            return kurashi_launcher::extras::emoji_rows(rest, 40);
        }
        if let Some(rest) = q.strip_prefix(';') {
            return kurashi_launcher::extras::clip_rows(rest.trim(), 40);
        }
        let calc = kurashi_launcher::calc::eval(q).map(|v| {
            let shown = kurashi_launcher::calc::format(v);
            json!({"id": format!("calc:{shown}"), "name": shown, "generic": q.trim(),
                   "icon": null, "kind": "calc", "score": 1.0})
        });
        calc.into_iter()
            .chain(
                l.query(q, 30)
                    .into_iter()
                    .filter_map(|r| serde_json::to_value(r).ok()),
            )
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
                if let Some(value) = id.strip_prefix("calc:").or_else(|| id.strip_prefix("emoji:")) {
                    return copy_text(value).await.map(|_| Some(json!({"copied": value})));
                }
                if let Some(line) = id.strip_prefix("clip:") {
                    return copy_clip(line).await.map(|_| Some(json!({"copied": line})));
                }
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
            island.observe_notifications(&doc);
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
    notify_actions(actions, get);
}

/// The current wall-clock time in ms since the epoch (the `until` of `notify.dnd` is compared with it).
fn unix_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

/// The `notify.*` actions over the notification server's commands, which exist once it is up. Not
/// running is an error, never a start: the server holds the bus name for the daemon's lifetime.
pub fn notify_actions(
    actions: &mut ActionRegistry,
    get: impl Fn() -> Option<kurashi_notify::Commands> + Clone + Send + Sync + 'static,
) {
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
            let on = v["on"].as_bool().unwrap_or(true);
            match v.get("until") {
                None => c.set_dnd(on),
                Some(until) => {
                    // `until` is ms since the epoch: a do-not-disturb that is on and ends later on.
                    let until = until
                        .as_u64()
                        .filter(|u| on && *u > unix_ms())
                        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
                    c.set_dnd_until(until);
                }
            }
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

/// The registry (K25) and the native mods (K26) behind one lock: a reconcile, a `mod.*` action and a
/// subscription change all write the `mods` document the same way. Lock order: this lock, then the
/// hub (`update`), then the config (`adopt_mods`); config listeners run with no config lock held.
struct ModsState {
    reg: kurashi_mods::Registry,
    native: Native,
}

/// Brings the native mods and the `mods` document in line with the registry: the mod table goes to
/// the config, enabled native mods are activated and the others deactivated, the settings in effect
/// are pushed, and the document is published.
fn refresh(hub: &Hub, st: &mut ModsState, store: Option<&ConfigStore>) {
    // Before `sync`: a mod's keys must be known to the config store to read their values.
    if let Some(s) = store {
        s.adopt_mods(&st.reg);
    }
    st.native.sync(&mut st.reg, store);
    if let Some(s) = store {
        // Again: a refused enable turned the mod off after the first adoption.
        s.adopt_mods(&st.reg);
        st.native.feed(s);
        // K28 (3): the choice sources of the registry, with what the enabled mods offer now.
        s.set_mod_sources(st.native.source_offers(&st.reg));
    }
    let _ = hub.update("mods", None, |d| *d = st.native.document(&mut st.reg));
    let _ = hub.update(SLOTS_DOC, None, |d| *d = st.native.slots(&st.reg));
    // A mod panel cannot stay open once its mod is off: the frontend already dropped the component,
    // so `runtime.ui` would name a panel nothing draws (rule 2; found by the live all-mods test).
    let _ = hub.update("runtime.ui", None, |d| {
        let open_mod = d["panel"]
            .as_str()
            .and_then(|p| p.strip_prefix("mod:"))
            .and_then(|rest| rest.split(':').next())
            .map(str::to_string);
        if let Some(id) = open_mod {
            let on = st
                .reg
                .get(&id)
                .is_some_and(|e| e.state == kurashi_mods::ModState::Enabled);
            if !on {
                d["panel"] = json!("");
                d["popup"] = json!(false);
            }
        }
        // K35: likewise a mod's peek.
        let peek_mod = d["peek"]["source"]
            .as_str()
            .and_then(|p| p.strip_prefix("mod:"))
            .and_then(|rest| rest.split(':').next())
            .map(str::to_string);
        if let Some(id) = peek_mod {
            let on = st
                .reg
                .get(&id)
                .is_some_and(|e| e.state == kurashi_mods::ModState::Enabled);
            if !on {
                clear_peek(d);
            }
        }
    });
}

/// The mods registry, its `mods` document and the `mod.{load,unload,enable,disable}` actions
/// (K25). The actions are config writes on `mods.loaded` / `mods.enabled`; a listener reconciles
/// the registry after every config change, so an action, a file edit, an undo or a profile load
/// all end the same way. Without a config store the lists live in memory only.
pub fn mods(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    roots: Vec<std::path::PathBuf>,
    config: Option<Arc<crate::config::ConfigStore>>,
) {
    mods_native(hub, actions, roots, config, Vec::new(), None);
}

/// [`mods`] with the native mods linked into this daemon (K26): `native::linked()` in `main`, and
/// the island their faces join (K28).
pub fn mods_native(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    roots: Vec<std::path::PathBuf>,
    config: Option<Arc<crate::config::ConfigStore>>,
    linked: Vec<Box<dyn kurashi_mod_api::NativeMod>>,
    island: Option<Arc<IslandHost>>,
) {
    use kurashi_mods::{Policy, Registry};
    let version = semver::Version::parse(env!("CARGO_PKG_VERSION")).expect("crate version");
    let reg = Registry::discover(&roots, &version);
    for s in &reg.shadows {
        tracing::info!(?s, "user mod shadows a bundled one");
    }
    let mut st = ModsState {
        reg,
        native: Native::new(
            hub.clone(),
            actions.clone(),
            linked,
            island,
            config.as_ref().map(Arc::downgrade),
        ),
    };
    // Registered before the first refresh, which fills it in; the document is never read empty.
    hub.register("mods", json!({"mods": []}), None);
    hub.register(SLOTS_DOC, json!({}), None);
    match &config {
        Some(c) => {
            let (loaded, enabled) = lists_of(c);
            log_refused(st.reg.reconcile(&loaded, &enabled));
            c.sync_mods(&st.reg);
        }
        None => {
            let policy = Policy {
                default_enabled: Default::default(),
            };
            for (id, r) in st.reg.apply_defaults(&policy) {
                if let Err(e) = r {
                    tracing::warn!(%id, error = e.i18n_key(), "mod not enabled");
                }
            }
        }
    }
    refresh(hub, &mut st, config.as_deref());
    let state = Arc::new(Mutex::new(st));
    if let Some(c) = &config {
        let (hub, state) = (hub.clone(), state.clone());
        c.on_change(move |store| {
            let (loaded, enabled) = lists_of(store);
            let mut st = state.lock().expect("mods lock");
            log_refused(st.reg.reconcile(&loaded, &enabled));
            refresh(&hub, &mut st, Some(store));
        });
    }
    for op in [ModOp::Load, ModOp::Unload, ModOp::Enable, ModOp::Disable] {
        let (hub, state, config) = (hub.clone(), state.clone(), config.clone());
        actions.register(
            op.name(),
            &format!("action.{}", op.name()),
            move |v: Value| {
                let (hub, state, config) = (hub.clone(), state.clone(), config.clone());
                async move {
                    let id = v["id"]
                        .as_str()
                        .ok_or_else(|| ActionError::Invalid(format!("{} needs id", op.name())))?;
                    mod_action(op, id, &hub, &state, config.as_deref())
                }
            },
        );
    }
}

#[derive(Clone, Copy)]
enum ModOp {
    Load,
    Unload,
    Enable,
    Disable,
}

impl ModOp {
    fn name(self) -> &'static str {
        match self {
            ModOp::Load => "mod.load",
            ModOp::Unload => "mod.unload",
            ModOp::Enable => "mod.enable",
            ModOp::Disable => "mod.disable",
        }
    }
}

/// The lists as they take effect: (`mods.loaded`, `mods.enabled`).
fn lists_of(store: &crate::config::ConfigStore) -> (BTreeSet<String>, BTreeSet<String>) {
    (
        store.string_list("mods.loaded").into_iter().collect(),
        store.string_list("mods.enabled").into_iter().collect(),
    )
}

fn log_refused(refused: Vec<(String, kurashi_mods::ModsError)>) {
    for (id, e) in refused {
        tracing::warn!(%id, error = e.i18n_key(), "mod not enabled");
    }
}

/// One `mod.*` action. The registry first says whether the change can happen at all (unknown,
/// invalid, a provide another enabled mod holds): a refused change writes nothing. The change is
/// then a config write on the lists, one undoable transaction; the listener brings the registry,
/// the native mods and the `mods` document along. Without a config store the change is applied here.
fn mod_action(
    op: ModOp,
    id: &str,
    hub: &Hub,
    state: &Mutex<ModsState>,
    config: Option<&crate::config::ConfigStore>,
) -> ActionResult {
    use kurashi_mods::ModsError;
    let mut next = state.lock().expect("mods lock").reg.clone();
    let outcome = match op {
        ModOp::Load => next.load(id),
        ModOp::Unload => next.unload(id),
        ModOp::Enable => next.enable(id),
        ModOp::Disable => next.disable(id),
    };
    outcome.map_err(|e| {
        // An invalid mod is "not loadable" when it is the load that is refused.
        let key = match (op, &e) {
            (ModOp::Load, ModsError::Invalid(_)) => "mods.error.not_loadable",
            _ => e.i18n_key(),
        };
        ActionError::Invalid(key.into())
    })?;
    let Some(store) = config else {
        let mut st = state.lock().expect("mods lock");
        st.reg = next;
        refresh(hub, &mut st, None);
        return Ok(None);
    };
    let loaded = store.string_list("mods.loaded");
    let enabled = store.string_list("mods.enabled");
    let (new_loaded, new_enabled) = next_lists(op, id, loaded.clone(), enabled.clone());
    let mut ops = Vec::new();
    for (key, old, new) in [
        ("mods.loaded", &loaded, &new_loaded),
        ("mods.enabled", &enabled, &new_enabled),
    ] {
        if old == new {
            continue;
        }
        if store.is_forced(key) {
            return Err(ActionError::Invalid("config.error.forced".into()));
        }
        ops.push(ApplyOp::Set {
            set: key.into(),
            value: json!(new),
            output: None,
        });
    }
    if ops.is_empty() {
        return Ok(None);
    }
    store.apply(&ops).map_err(|errs| {
        let code = errs
            .first()
            .map_or("config.error.unrepresentable", |e| e.code.as_str());
        ActionError::Invalid(code.into())
    })?;
    Ok(None)
}

/// The lists after `op` (K25): load adds to `loaded`; enable adds to both; disable takes the id
/// off `enabled` only; unload takes it off both.
fn next_lists(
    op: ModOp,
    id: &str,
    loaded: Vec<String>,
    enabled: Vec<String>,
) -> (Vec<String>, Vec<String>) {
    fn with(mut list: Vec<String>, id: &str) -> Vec<String> {
        if !list.iter().any(|x| x == id) {
            list.push(id.to_string());
        }
        list
    }
    fn without(list: Vec<String>, id: &str) -> Vec<String> {
        list.into_iter().filter(|x| x != id).collect()
    }
    match op {
        ModOp::Load => (with(loaded, id), enabled),
        ModOp::Unload => (without(loaded, id), without(enabled, id)),
        ModOp::Enable => (with(loaded, id), with(enabled, id)),
        ModOp::Disable => (loaded, without(enabled, id)),
    }
}

/// `svc.audio` (refcounted: the pulse connection and its thread exist only while watched) +
/// intent `audio.volume` (coalesced per frame by the daemon) + `audio.mute.toggle` +
/// `audio.volume.{up,down}`, which step through the same worker so the `volume` OSD follows.
pub struct AudioProvider {
    running: Mutex<Option<(kurashi_audio::AudioHandle, kurashi_audio::Commands)>>,
    /// Origin of the latest `audio.volume` intent: the server's change event that follows is
    /// patched with it, so the dragging slider recognises its own echo (PROTOCOL §4).
    last_origin: Arc<Mutex<Option<(String, std::time::Instant)>>>,
    island: Option<Arc<crate::island::IslandHost>>,
    start: AudioStart,
    /// Volume the last key step asked for, and when. Key repeat outruns the server's change
    /// event, so a step builds on this while it is fresh instead of on the stale document.
    last_key: Mutex<Option<(f64, std::time::Instant)>>,
}

/// How the worker is started: the sound server in production, a fake backend in tests.
type AudioStart = Arc<
    dyn Fn(
            Arc<dyn kurashi_services::DocSink>,
        ) -> (kurashi_audio::AudioHandle, kurashi_audio::Commands)
        + Send
        + Sync,
>;

/// A key step is 5 % of full scale. It stops at 100 % (over-amplification stays a deliberate
/// slider gesture) and never lowers a volume that is already louder.
const VOLUME_STEP: f64 = 0.05;
const KEY_CEILING: f64 = 1.0;
/// Key repeat faster than this builds on the last key command, not on the server's document.
const KEY_CHAIN: std::time::Duration = std::time::Duration::from_millis(500);

/// Echo window: a server round-trip is a few ms; anything later is someone else's change.
const ORIGIN_ECHO: std::time::Duration = std::time::Duration::from_millis(500);

struct AudioSink {
    hub: Arc<Hub>,
    last_origin: Arc<Mutex<Option<(String, std::time::Instant)>>>,
    island: Option<Arc<crate::island::IslandHost>>,
}

impl kurashi_services::DocSink for AudioSink {
    fn set(&self, doc: Value) {
        // The volume OSD and a moved default output are the island's edges (island.rs).
        if let Some(island) = &self.island {
            island.observe_audio(&doc);
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
        let (h, c) = (self.start)(Arc::new(AudioSink {
            hub,
            last_origin: self.last_origin.clone(),
            island: self.island.clone(),
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

    /// The volume a key step starts from. Unavailable audio is an error, never a guessed volume.
    fn key_base(&self, hub: &Hub) -> Result<f64, ActionError> {
        let unavailable = || ActionError::Unavailable(AUDIO_UNAVAILABLE.into());
        let (_, doc) = hub.snapshot("svc.audio").map_err(|_| unavailable())?;
        if doc["available"].as_bool() != Some(true) {
            return Err(unavailable());
        }
        let fresh = *self.last_key.lock().expect("key lock");
        Ok(match fresh {
            Some((volume, at)) if at.elapsed() < KEY_CHAIN => volume,
            _ => doc["volume"].as_f64().unwrap_or(0.0),
        })
    }

    /// An id the picker or the mixer names must be in the current document. The worker drops an
    /// unknown id without a word, so the answer has to come from here (rule 2). Unavailable audio
    /// has no lists.
    fn known_in(&self, hub: &Hub, list: &str, id: u32, missing: &str) -> Result<(), ActionError> {
        let unavailable = || ActionError::Unavailable(AUDIO_UNAVAILABLE.into());
        let (_, doc) = hub.snapshot("svc.audio").map_err(|_| unavailable())?;
        if doc["available"].as_bool() != Some(true) {
            return Err(unavailable());
        }
        let known = doc[list].as_array().is_some_and(|items| {
            items
                .iter()
                .any(|s| s["id"].as_u64() == Some(u64::from(id)))
        });
        if known {
            Ok(())
        } else {
            Err(ActionError::Invalid(missing.into()))
        }
    }

    /// `audio.sink.default` names a sink of the current document.
    fn known_sink(&self, hub: &Hub, id: u32) -> Result<(), ActionError> {
        self.known_in(hub, "sinks", id, NO_SUCH_SINK)
    }
}

pub fn audio(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    audio_with(
        hub,
        actions,
        intents,
        island,
        Arc::new(kurashi_audio::start),
    );
}

/// [`audio`] with the worker's start injected: tests run the real command and event path over a
/// fake backend.
pub fn audio_with(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    island: Option<Arc<crate::island::IslandHost>>,
    start: AudioStart,
) {
    let provider = Arc::new(AudioProvider {
        running: Mutex::new(None),
        last_origin: Arc::default(),
        island,
        start,
        last_key: Mutex::new(None),
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
            // A slider move ends any key-repeat chain: the next key step starts from the slider.
            *p.last_key.lock().expect("key lock") = None;
            c.set_volume(v);
        }
    });
    for (id, sign) in [("audio.volume.up", 1.0), ("audio.volume.down", -1.0)] {
        let (p, hub) = (provider.clone(), hub.clone());
        actions.register(id, &format!("action.{id}"), move |args: Value| {
            let (p, hub) = (p.clone(), hub.clone());
            async move {
                let step = step_arg(&args, VOLUME_STEP)?;
                let c = p
                    .commands()
                    .ok_or_else(|| ActionError::Unavailable(AUDIO_UNAVAILABLE.into()))?;
                let base = p.key_base(&hub)?;
                let target = if sign > 0.0 {
                    (base + step).min(KEY_CEILING).max(base)
                } else {
                    (base - step).max(0.0)
                };
                *p.last_key.lock().expect("key lock") = Some((target, std::time::Instant::now()));
                c.set_volume(target);
                Ok(None)
            }
        });
    }
    // The output picker of the quick settings card (K24). Not running is an error, never a start.
    let (p, h) = (provider.clone(), hub.clone());
    actions.register(
        "audio.sink.default",
        "action.audio.sink.default",
        move |args: Value| {
            let (p, h) = (p.clone(), h.clone());
            async move {
                let id = args["id"]
                    .as_u64()
                    .and_then(|id| u32::try_from(id).ok())
                    .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
                let c = p
                    .commands()
                    .ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
                p.known_sink(&h, id)?;
                c.set_default_sink(id);
                Ok(None)
            }
        },
    );
    // The input picker and the per-app mixer (W13). Ids come from the current document, as for sinks.
    let (p, h) = (provider.clone(), hub.clone());
    actions.register(
        "audio.source.default",
        "action.audio.source.default",
        move |args: Value| {
            let (p, h) = (p.clone(), h.clone());
            async move {
                let id = id_arg(&args)?;
                let c = p
                    .commands()
                    .ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
                p.known_in(&h, "sources", id, NO_SUCH_SOURCE)?;
                c.set_default_source(id);
                Ok(None)
            }
        },
    );
    let (p, h) = (provider.clone(), hub.clone());
    actions.register(
        "audio.stream.volume",
        "action.audio.stream.volume",
        move |args: Value| {
            let (p, h) = (p.clone(), h.clone());
            async move {
                let id = id_arg(&args)?;
                // A level in `0..=MAX_VOLUME`, as the sliders send it; anything else is refused.
                let value = args["value"]
                    .as_f64()
                    .filter(|v| (0.0..=kurashi_audio::MAX_VOLUME).contains(v))
                    .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
                let c = p
                    .commands()
                    .ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
                p.known_in(&h, "streams", id, NO_SUCH_STREAM)?;
                c.set_stream_volume(id, value);
                Ok(None)
            }
        },
    );
    // `{id, on?}`: without `on` the stream's mute flips, as the worker reads it.
    let (p, h) = (provider.clone(), hub.clone());
    actions.register(
        "audio.stream.mute",
        "action.audio.stream.mute",
        move |args: Value| {
            let (p, h) = (p.clone(), h.clone());
            async move {
                let id = id_arg(&args)?;
                let on = match args.get("on") {
                    None => None,
                    Some(v) => Some(
                        v.as_bool()
                            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?,
                    ),
                };
                let c = p
                    .commands()
                    .ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
                p.known_in(&h, "streams", id, NO_SUCH_STREAM)?;
                match on {
                    Some(on) => c.set_stream_muted(id, on),
                    None => c.toggle_stream_mute(id),
                }
                Ok(None)
            }
        },
    );
    let p = provider.clone();
    actions.register(
        "audio.mic.mute.toggle",
        "action.audio.mic.mute.toggle",
        move |_| {
            let c = p.commands();
            async move {
                c.ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?
                    .toggle_source_mute();
                Ok(None)
            }
        },
    );
    actions.register("audio.mute.toggle", "action.audio.mute.toggle", move |_| {
        let c = provider.commands();
        async move {
            c.ok_or_else(|| ActionError::Unavailable("audio service not running".into()))?
                .toggle_mute();
            Ok(None)
        }
    });
}

/// The `id` argument of a device or stream action: a PulseAudio index.
fn id_arg(args: &Value) -> Result<u32, ActionError> {
    args["id"]
        .as_u64()
        .and_then(|id| u32::try_from(id).ok())
        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))
}

/// Error keys of the key actions; the frontend and the CLI render them (rule 8).
pub const AUDIO_UNAVAILABLE: &str = "error.audio.unavailable";
/// `audio.sink.default` with an id that is no sink of the current document.
pub const NO_SUCH_SINK: &str = "error.audio.no_such_sink";
/// `audio.source.default` with an id that is no input of the current document.
pub const NO_SUCH_SOURCE: &str = "error.audio.no_such_source";
/// `audio.stream.*` with an id that is no playing application of the current document.
pub const NO_SUCH_STREAM: &str = "error.audio.no_such_stream";
pub const NO_BACKLIGHT: &str = "error.brightness.no_device";
pub const STEP_RANGE: &str = "error.step.out_of_range";
/// `session.lock` without the PAM service is refused: nothing could unlock the screen afterwards.
pub const NO_PAM: &str = "error.lock.no_pam";

/// The optional `step` argument of a key action: a fraction in `0..=1`.
fn step_arg(args: &Value, default: f64) -> Result<f64, ActionError> {
    match args.get("step") {
        None => Ok(default),
        Some(v) => v
            .as_f64()
            .filter(|s| (0.0..=1.0).contains(s))
            .ok_or_else(|| ActionError::Invalid(STEP_RANGE.into())),
    }
}

/// Brightness key step: 5 % of the device maximum.
const BRIGHTNESS_STEP: f64 = 0.05;

/// `svc.brightness` (refcounted, read on demand) + actions `brightness.{up,down}` + intent
/// `brightness.set` (`0..=1`). Writes are one-shot and need no subscription (rule 5).
pub fn brightness(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    let connect: ConnectFn = Arc::new(|| Box::pin(zbus::Connection::system()));
    brightness_with(
        hub,
        actions,
        intents,
        island,
        backlight::DEFAULT_DIR.into(),
        connect,
    );
}

/// [`brightness`] with the backlight directory and the bus injected (tests).
pub fn brightness_with(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    island: Option<Arc<crate::island::IslandHost>>,
    dir: std::path::PathBuf,
    connect: ConnectFn,
) {
    let svc_dir = dir.clone();
    let provider = Arc::new(ServiceProvider::new(
        "svc.brightness",
        Bus::System,
        move |conn, sink| {
            let dir = svc_dir.clone();
            async move { backlight::start_at(conn, sink, dir).await }
        },
    ));
    hub.register("svc.brightness", json!({}), Some(provider.clone()));
    let writer = Arc::new(BrightnessWriter {
        hub: hub.clone(),
        provider,
        island,
        dir,
        connect,
        turn: tokio::sync::Mutex::new(()),
    });
    for (id, sign) in [("brightness.up", 1.0), ("brightness.down", -1.0)] {
        let w = writer.clone();
        actions.register(id, &format!("action.{id}"), move |args: Value| {
            let w = w.clone();
            async move {
                let step = step_arg(&args, BRIGHTNESS_STEP)?;
                w.apply(Change::By(sign * step), None).await?;
                Ok(None)
            }
        });
    }
    intents.register("brightness.set", move |v, origin| {
        // Intents have no reply: a value outside 0..=1 is dropped, a failed write shows no OSD.
        if let Some(level) = v.as_f64().filter(|l| (0.0..=1.0).contains(l)) {
            let w = writer.clone();
            tokio::spawn(async move {
                let _ = w.apply(Change::To(level), origin).await;
            });
        }
    });
}

/// Brightness writes. `turn` serialises them, so every step starts from the level the previous
/// one left in effect (key repeat). Only writers wait on it; readers never do.
struct BrightnessWriter {
    hub: Arc<Hub>,
    provider: Arc<ServiceProvider<backlight::Commands>>,
    island: Option<Arc<crate::island::IslandHost>>,
    dir: std::path::PathBuf,
    connect: ConnectFn,
    turn: tokio::sync::Mutex<()>,
}

impl BrightnessWriter {
    async fn apply(&self, change: Change, origin: Option<String>) -> Result<(), ActionError> {
        let _turn = self.turn.lock().await;
        let plan = backlight::plan(&self.dir, change)
            .ok_or_else(|| ActionError::Unavailable(NO_BACKLIGHT.into()))?;
        let conn = (self.connect)()
            .await
            .map_err(|e| ActionError::Unavailable(e.to_string()))?;
        let doc = plan
            .apply(&conn)
            .await
            .map_err(|e| ActionError::Internal(e.to_string()))?;
        // A running service keeps its document in step with the level now in effect.
        if self.provider.commands().is_some() {
            let _ = self.hub.set("svc.brightness", doc, origin);
        }
        if let Some(island) = &self.island {
            island.signal(kurashi_island::FaceSignal {
                face: "brightness".into(),
                relevance: 0,
                condition: true,
                transient: Some(kurashi_island::Transient {
                    kind: "brightness".into(),
                    ttl_ms: 1500,
                    may_interrupt: true,
                }),
            });
        }
        Ok(())
    }
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

/// Where PAM keeps its service files, and the service the lock screen authenticates against
/// (NixOS: `security.pam.services.kurashi`).
pub const PAM_DIR: &str = "/etc/pam.d";
pub const PAM_SERVICE: &str = "kurashi";

/// `runtime.lock` + intents `lock.submit` / `lock.cancel` + action `session.lock` (K2: the secret
/// is handled only here and never logged; the frontend owns ext-session-lock). The returned
/// session lets `main` cancel a conversation still waiting for a prompt at shutdown.
pub fn lock(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    marker: std::path::PathBuf,
    facts: SharedFacts,
) -> kurashi_auth::LockSession {
    lock_with(hub, actions, intents, marker, PAM_DIR.into(), facts)
}

/// [`lock`] with the PAM directory injected (tests).
pub fn lock_with(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    intents: &mut crate::Intents,
    marker: std::path::PathBuf,
    pam_dir: std::path::PathBuf,
    facts: SharedFacts,
) -> kurashi_auth::LockSession {
    use kurashi_auth::{LockConfig, LockSession, PamAuthenticator, SystemClock};
    let user = std::env::var("USER").unwrap_or_default();
    let was_locked = marker.exists();
    // Probed here, once, like the other startup facts; doctor reports it (K20 lockout guard).
    let pam_ok = kurashi_auth::service_configured(&pam_dir, PAM_SERVICE);
    facts.update(|f| f.pam_service = Some(pam_ok));
    hub.register(
        "runtime.lock",
        json!({"locked": was_locked, "busy": false, "failures": 0}),
        None,
    );
    let session = LockSession::new(
        user,
        Arc::new(PamAuthenticator::new(PAM_SERVICE)),
        Arc::new(LockSink {
            hub: hub.clone(),
            marker,
        }),
        Arc::new(SystemClock::new()),
        LockConfig::default(),
    );
    if was_locked {
        if !pam_ok {
            // Still locked: a restart must never unlock the screen. Only the module can fix it.
            tracing::error!(
                service = PAM_SERVICE,
                "previous instance was locked but its PAM service is missing: starting locked; \
                 enable programs.kurashi in the NixOS module"
            );
        }
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
    let handle = session.clone();
    actions.register("session.lock", "action.session.lock", move |_| {
        let (s, pam_dir) = (session.clone(), pam_dir.clone());
        async move {
            // Refused before any state changes: without the service nothing could unlock it.
            if !kurashi_auth::service_configured(&pam_dir, PAM_SERVICE) {
                return Err(ActionError::Unavailable(NO_PAM.into()));
            }
            s.handle_action("session.lock");
            Ok(None)
        }
    });
    handle
}

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

// ---- svc.tray and svc.bluetooth ----------------------------------------------------------------

/// Not subscribed (or still starting): nothing to talk to. Actions never start a service.
pub const SERVICE_NOT_RUNNING: &str = "error.service.not_running";
/// The service was reached but the request failed. The D-Bus text goes to the log, not the UI.
pub const SERVICE_CALL_FAILED: &str = "error.service.call_failed";
/// Arguments missing or of the wrong shape.
pub const ARGS_INVALID: &str = "error.args.invalid";

const TRAY_DOC: &str = "svc.tray";
const BLUETOOTH_DOC: &str = "svc.bluetooth";
const NETWORK_DOC: &str = "svc.network";
const NETWORK_SCAN_DOC: &str = "svc.network.scan";
const POWER_DOC: &str = "svc.power";

/// `network.*` keys (K24, quick settings): NetworkManager refused the change (polkit), or there is
/// no NetworkManager to change it.
pub const NETWORK_REFUSED: &str = "error.network.refused";
pub const NETWORK_UNAVAILABLE: &str = "error.network.unavailable";
/// `network.connect` to a network that is not saved: a secured one needs a password (not asked for
/// yet), an open one has no profile to join with yet, and one out of range cannot be joined.
pub const NETWORK_NEEDS_SECRET: &str = "error.network.needs_secret";
pub const NETWORK_NOT_SAVED: &str = "error.network.not_saved";
pub const NETWORK_NOT_FOUND: &str = "error.network.not_found";

/// The session bus, opened when a service starts (never at daemon startup).
fn session_bus() -> ConnectFn {
    Bus::Session.connect()
}

/// The system bus (BlueZ lives there), opened when the service starts.
fn system_bus() -> ConnectFn {
    Bus::System.connect()
}

/// `svc.tray` (StatusNotifierItem host on the session bus) and the `tray.*` actions.
pub fn tray(hub: &Arc<Hub>, actions: &mut ActionRegistry) {
    tray_with(hub, actions, session_bus());
}

/// [`tray`] with the bus injected (tests run it on a private dbus-daemon).
pub fn tray_with(hub: &Arc<Hub>, actions: &mut ActionRegistry, connect: ConnectFn) {
    // The tray's task does not mark its own outage, so the provider shows this when it ends.
    let idle = json!({"available": false, "items": []});
    let service = Arc::new(
        ServiceProvider::with_connect(TRAY_DOC, connect, kurashi_tray::start)
            .unavailable(idle.clone()),
    );
    hub.register(TRAY_DOC, idle, Some(service.clone()));
    service_action(
        actions,
        "tray.activate",
        service.clone(),
        |c, a| async move {
            let (id, x, y) = (str_arg(&a, "id")?, int_arg(&a, "x")?, int_arg(&a, "y")?);
            c.activate(&id, x, y).await.map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(
        actions,
        "tray.secondary",
        service.clone(),
        |c, a| async move {
            let (id, x, y) = (str_arg(&a, "id")?, int_arg(&a, "x")?, int_arg(&a, "y")?);
            c.secondary_activate(&id, x, y).await.map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(actions, "tray.scroll", service.clone(), |c, a| async move {
        let id = str_arg(&a, "id")?;
        let delta = int_arg(&a, "delta")?;
        let orientation = str_arg(&a, "orientation")?;
        if !matches!(orientation.as_str(), "horizontal" | "vertical") {
            return Err(ActionError::Invalid(ARGS_INVALID.into()));
        }
        c.scroll(&id, delta, &orientation)
            .await
            .map_err(call_failed)?;
        Ok(None)
    });
    service_action(actions, "tray.menu", service.clone(), |c, a| async move {
        let tree = c.menu(&str_arg(&a, "id")?).await.map_err(call_failed)?;
        Ok(Some(tree))
    });
    service_action(actions, "tray.menu_event", service, |c, a| async move {
        let (id, item) = (str_arg(&a, "id")?, int_arg(&a, "item")?);
        c.menu_event(&id, item).await.map_err(call_failed)?;
        Ok(None)
    });
}

/// `svc.bluetooth` (BlueZ on the system bus) and the `bluetooth.*` actions. The island reads its
/// connection edges from the document (island.rs).
pub fn bluetooth(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    bluetooth_observed(hub, actions, system_bus(), island);
}

/// [`bluetooth`] with the bus injected (tests).
pub fn bluetooth_with(hub: &Arc<Hub>, actions: &mut ActionRegistry, connect: ConnectFn) {
    bluetooth_observed(hub, actions, connect, None);
}

fn bluetooth_observed(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    connect: ConnectFn,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    let mut service =
        ServiceProvider::with_connect(BLUETOOTH_DOC, connect, kurashi_services::bluetooth::start);
    if let Some(island) = island {
        service = service.observe(move |doc| island.observe_bluetooth(doc));
    }
    let service = Arc::new(service);
    hub.register(
        BLUETOOTH_DOC,
        json!({"available": false}),
        Some(service.clone()),
    );
    service_action(
        actions,
        "bluetooth.power",
        service.clone(),
        |c, a| async move {
            c.set_powered(bool_arg(&a, "on")?)
                .await
                .map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(
        actions,
        "bluetooth.connect",
        service.clone(),
        |c, a| async move {
            c.connect(&str_arg(&a, "address")?)
                .await
                .map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(
        actions,
        "bluetooth.disconnect",
        service.clone(),
        |c, a| async move {
            c.disconnect(&str_arg(&a, "address")?)
                .await
                .map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(actions, "bluetooth.scan", service, |c, a| async move {
        let on = bool_arg(&a, "on")?;
        let result = if on {
            c.start_discovery().await
        } else {
            c.stop_discovery().await
        };
        result.map_err(call_failed)?;
        Ok(None)
    });
}

/// `svc.network` and `svc.network.scan` (NetworkManager on the system bus, both refcounted), and the
/// quick settings actions `network.{wifi,airplane,connect,disconnect}`.
pub fn network(hub: &Arc<Hub>, actions: &mut ActionRegistry) {
    network_with(hub, actions, system_bus());
}

/// [`network`] with the bus injected (tests run it on a private bus with a fake NetworkManager).
pub fn network_with(hub: &Arc<Hub>, actions: &mut ActionRegistry, connect: ConnectFn) {
    network_paced(hub, actions, connect, kurashi_services::network::SCAN_EVERY);
}

/// [`network_with`] with the scan cadence injected: tests count the rescans of a subscription.
pub fn network_paced(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    connect: ConnectFn,
    scan_every: std::time::Duration,
) {
    let service = Arc::new(ServiceProvider::with_connect(
        NETWORK_DOC,
        connect.clone(),
        kurashi_services::network::start,
    ));
    hub.register(
        NETWORK_DOC,
        json!({"state": "unknown"}),
        Some(service.clone()),
    );
    // Nothing is known before the first scan: the document is empty until it answers (rule 2).
    let scan = Arc::new(
        ServiceProvider::with_connect(NETWORK_SCAN_DOC, connect, move |c, s| {
            kurashi_services::network::start_scan_every(c, s, scan_every)
        })
        .unavailable(json!({"available": false, "reason": NETWORK_UNAVAILABLE})),
    );
    hub.register(NETWORK_SCAN_DOC, json!({}), Some(scan));
    service_action(
        actions,
        "network.wifi",
        service.clone(),
        |c, a| async move {
            let on = bool_arg(&a, "on")?;
            c.set_wifi_enabled(on).await.map_err(wifi_failed)?;
            Ok(None)
        },
    );
    service_action(
        actions,
        "network.airplane",
        service.clone(),
        |c, a| async move {
            let on = bool_arg(&a, "on")?;
            c.set_airplane(on).await.map_err(wifi_failed)?;
            Ok(None)
        },
    );
    service_action(
        actions,
        "network.connect",
        service.clone(),
        |c, a| async move {
            let ssid = str_arg(&a, "ssid")?;
            if ssid.is_empty() {
                return Err(ActionError::Invalid(ARGS_INVALID.into()));
            }
            c.connect(&ssid).await.map_err(|e| {
                ActionError::Unavailable(
                    match e {
                        ConnectError::Refused => NETWORK_REFUSED,
                        ConnectError::Unavailable => NETWORK_UNAVAILABLE,
                        ConnectError::NeedsSecret => NETWORK_NEEDS_SECRET,
                        ConnectError::NotSaved => NETWORK_NOT_SAVED,
                        ConnectError::NotFound => NETWORK_NOT_FOUND,
                    }
                    .into(),
                )
            })?;
            Ok(None)
        },
    );
    service_action(actions, "network.disconnect", service, |c, _a| async move {
        c.disconnect().await.map_err(wifi_failed)?;
        Ok(None)
    });
}

/// `svc.power` (UPower and power-profiles-daemon on the system bus, refcounted) and `power.profile`.
/// The island reads its charger and battery edges from the document (island.rs).
pub fn power(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    power_observed(hub, actions, system_bus(), island);
}

/// [`power`] with the bus injected (tests run it on a private bus with fake daemons).
pub fn power_with(hub: &Arc<Hub>, actions: &mut ActionRegistry, connect: ConnectFn) {
    power_observed(hub, actions, connect, None);
}

fn power_observed(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    connect: ConnectFn,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    let mut service =
        ServiceProvider::with_connect(POWER_DOC, connect, kurashi_services::power::start);
    if let Some(island) = island {
        service = service.observe(move |doc| island.observe_power(doc));
    }
    let service = Arc::new(service);
    hub.register(
        POWER_DOC,
        json!({
            "available": false,
            "present": false,
            "on_battery": false,
            "profile_reason": kurashi_services::power_profiles::UNAVAILABLE,
        }),
        Some(service.clone()),
    );
    service_action(actions, "power.profile", service, |c, a| async move {
        let name = str_arg(&a, "name")?;
        c.set_profile(&name).await.map_err(|e| match e {
            ProfileError::Unknown => ActionError::Invalid(NO_SUCH_PROFILE.into()),
            ProfileError::Refused => ActionError::Unavailable(POWER_REFUSED.into()),
            ProfileError::Unavailable => ActionError::Unavailable(POWER_UNAVAILABLE.into()),
        })?;
        Ok(None)
    });
}

/// `power.profile` with a name the profile daemon does not offer.
pub const NO_SUCH_PROFILE: &str = "error.power.no_such_profile";
/// The profile daemon refused the change (polkit), or is not there to make it.
pub const POWER_REFUSED: &str = "error.power.refused";
pub const POWER_UNAVAILABLE: &str = "error.power.unavailable";

/// A refused or failed radio or link change, as its key.
fn wifi_failed(e: WifiError) -> ActionError {
    ActionError::Unavailable(
        match e {
            WifiError::Refused => NETWORK_REFUSED,
            WifiError::Unavailable => NETWORK_UNAVAILABLE,
        }
        .into(),
    )
}

/// Registers `id` to run `run` on the service's commands. Not running is an error, never an
/// auto-start: a click must not wake a service nobody is watching (Ma, rule 5).
fn service_action<H, C, Fut>(
    actions: &mut ActionRegistry,
    id: &str,
    service: Arc<ServiceProvider<C, H>>,
    run: impl Fn(C, Value) -> Fut + Send + Sync + 'static,
) where
    H: ServiceTask,
    C: Clone + Send + 'static,
    Fut: Future<Output = ActionResult> + Send + 'static,
{
    let run = Arc::new(run);
    actions.register(id, &format!("action.{id}"), move |args: Value| {
        let (service, run) = (service.clone(), run.clone());
        async move {
            let commands = service
                .commands()
                .ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
            run(commands, args).await
        }
    });
}

/// Logs the raw error for diagnostics and returns the key the UI shows.
fn call_failed(e: impl std::fmt::Display) -> ActionError {
    tracing::warn!(error = %e, "service request failed");
    ActionError::Unavailable(SERVICE_CALL_FAILED.into())
}

fn str_arg(args: &Value, key: &str) -> Result<String, ActionError> {
    args[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))
}

fn int_arg(args: &Value, key: &str) -> Result<i32, ActionError> {
    args[key]
        .as_i64()
        .and_then(|v| i32::try_from(v).ok())
        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))
}

fn bool_arg(args: &Value, key: &str) -> Result<bool, ActionError> {
    args[key]
        .as_bool()
        .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))
}

const MEDIA_DOC: &str = "svc.media";
/// `media.seek` or `media.set_position` where the shown player does not allow a seek (`can.seek`
/// false), or `set_position` where the player names no track to address.
pub const MEDIA_CANNOT_SEEK: &str = "error.media.cannot_seek";
/// A media command while no player is shown.
pub const MEDIA_NO_PLAYER: &str = "error.media.no_player";
/// `media.player.select` with an id that is not a player of the document.
pub const MEDIA_NO_SUCH_PLAYER: &str = "error.media.no_such_player";

/// `svc.media` (MPRIS, refcounted) on the session bus, and its actions. The island follows it.
pub fn media(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    media_observed(hub, actions, session_bus(), island);
}

/// [`media`] with the bus injected (tests run it on a private bus with a fake player).
pub fn media_with(hub: &Arc<Hub>, actions: &mut ActionRegistry, connect: ConnectFn) {
    media_observed(hub, actions, connect, None);
}

fn media_observed(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    connect: ConnectFn,
    island: Option<Arc<crate::island::IslandHost>>,
) {
    let mut service =
        ServiceProvider::with_connect(MEDIA_DOC, connect, kurashi_services::media::start);
    if let Some(island) = island {
        service = service.observe(move |doc| island.observe_media(doc));
    }
    let service = Arc::new(service);
    hub.register(
        MEDIA_DOC,
        json!({
            "available": false,
            "playing": false,
            "players": [],
            "can": {"seek": false, "next": false, "prev": false, "play": false, "pause": false},
        }),
        Some(service.clone()),
    );
    service_action(
        actions,
        "media.play_pause",
        service.clone(),
        |c, _| async move {
            c.play_pause().await.map_err(call_failed)?;
            Ok(None)
        },
    );
    service_action(actions, "media.next", service.clone(), |c, _| async move {
        c.next().await.map_err(call_failed)?;
        Ok(None)
    });
    service_action(actions, "media.prev", service.clone(), |c, _| async move {
        c.prev().await.map_err(call_failed)?;
        Ok(None)
    });
    // `{offset_us}` seeks relative to the position; `{us}` sets it, on the shown track.
    service_action(actions, "media.seek", service.clone(), |c, a| async move {
        let offset_us = a["offset_us"]
            .as_i64()
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
        c.seek(offset_us).await.map_err(media_error)?;
        Ok(None)
    });
    service_action(
        actions,
        "media.set_position",
        service.clone(),
        |c, a| async move {
            let us = a["us"]
                .as_i64()
                .filter(|us| *us >= 0)
                .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
            c.set_position(us).await.map_err(media_error)?;
            Ok(None)
        },
    );
    let hub = hub.clone();
    service_action(actions, "media.player.select", service, move |c, a| {
        let hub = hub.clone();
        async move {
            let id = str_arg(&a, "id")?;
            media_player_known(&hub, &id)?;
            c.select_player(&id);
            Ok(None)
        }
    });
}

/// `media.player.select` names a player of the current document: the ones the view offers.
fn media_player_known(hub: &Hub, id: &str) -> Result<(), ActionError> {
    let (_, doc) = hub
        .snapshot(MEDIA_DOC)
        .map_err(|_| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
    let known = doc["players"]
        .as_array()
        .is_some_and(|players| players.iter().any(|p| p["id"].as_str() == Some(id)));
    if known {
        Ok(())
    } else {
        Err(ActionError::Invalid(MEDIA_NO_SUCH_PLAYER.into()))
    }
}

/// A refused media command as its key: no player to send it to, a player that does not allow the
/// seek (or cannot be addressed for one), or a call that failed.
fn media_error(e: kurashi_services::media::CommandError) -> ActionError {
    use kurashi_services::media::CommandError;
    match e {
        CommandError::NoPlayer => ActionError::Unavailable(MEDIA_NO_PLAYER.into()),
        CommandError::CannotSeek | CommandError::NoTrack => {
            ActionError::Unavailable(MEDIA_CANNOT_SEEK.into())
        }
        CommandError::Bus(e) => call_failed(e),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;

    use super::*;

    #[tokio::test]
    async fn lock_survives_daemon_restart() {
        let dir = std::env::temp_dir().join(format!("kurashid-lock-{}", std::process::id()));
        let marker = dir.join("locked");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("pam.d")).unwrap();
        std::fs::write(dir.join("pam.d").join("kurashi"), "").unwrap();

        // First instance locks.
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        lock_with(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            marker.clone(),
            dir.join("pam.d"),
            SharedFacts::default(),
        );
        actions.invoke("session.lock", Value::Null).await.unwrap();
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], true);
        assert!(marker.exists(), "lock persisted");

        // "Restart": a fresh instance must come back locked.
        let hub2 = Hub::new();
        lock_with(
            &hub2,
            &mut ActionRegistry::default(),
            &mut crate::Intents::default(),
            marker.clone(),
            dir.join("pam.d"),
            SharedFacts::default(),
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

    /// K20 lockout guard: a locked marker without the PAM service still starts locked (a restart
    /// never unlocks), and doctor says the screen cannot be unlocked.
    #[test]
    fn locked_marker_without_pam_service_starts_locked_and_doctor_says_why() {
        let dir = temp_dir("lockout");
        let marker = dir.join("locked");
        std::fs::write(&marker, b"").unwrap();

        let hub = Hub::new();
        let facts = SharedFacts::default();
        lock_with(
            &hub,
            &mut ActionRegistry::default(),
            &mut crate::Intents::default(),
            marker.clone(),
            dir.join("pam.d"),
            facts.clone(),
        );
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], true);
        let row = pam_row(&hub, &facts);
        assert_eq!(row["status"], "fail");
        assert_eq!(row["fix_key"], "doctor.pam_service.fix");

        // Unlocked start: the same missing service only disables locking, which doctor reports.
        std::fs::remove_file(&marker).unwrap();
        let hub = Hub::new();
        let facts = SharedFacts::default();
        lock_with(
            &hub,
            &mut ActionRegistry::default(),
            &mut crate::Intents::default(),
            marker.clone(),
            dir.join("pam.d"),
            facts.clone(),
        );
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], false);
        assert_eq!(pam_row(&hub, &facts)["status"], "warn");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The `pam_service` row of the doctor query, as the CLI receives it.
    fn pam_row(hub: &Arc<Hub>, facts: &SharedFacts) -> Value {
        let mut d = Daemon::new(
            hub.clone(),
            ActionRegistry::default(),
            crate::Intents::default(),
        );
        crate::doctor::register(&mut d, facts.clone());
        let query = d.queries.get("doctor").unwrap().clone();
        query("")
            .into_iter()
            .find(|r| r["id"] == "pam_service")
            .expect("pam_service row")
    }

    // ---- svc.tray and svc.bluetooth on a private bus ---------------------------------------

    /// Connections to `addr`; counts how often a service actually connected to it.
    fn private_bus(addr: String, connects: Arc<AtomicUsize>) -> ConnectFn {
        Arc::new(move || {
            let (addr, connects) = (addr.clone(), connects.clone());
            Box::pin(async move {
                connects.fetch_add(1, Ordering::SeqCst);
                zbus::connection::Builder::address(addr.as_str())?
                    .build()
                    .await
            })
        })
    }

    async fn owns(dbus: &zbus::fdo::DBusProxy<'_>, name: &str) -> bool {
        dbus.name_has_owner(zbus::names::BusName::try_from(name).unwrap())
            .await
            .unwrap()
    }

    /// Capped wait until `name` has (or has lost) an owner on the bus.
    async fn settle_owner(dbus: &zbus::fdo::DBusProxy<'_>, name: &str, want: bool) {
        for _ in 0..200 {
            if owns(dbus, name).await == want {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("{name} never became owned={want}");
    }

    /// Live client connections on the bus (unique names).
    async fn clients(dbus: &zbus::fdo::DBusProxy<'_>) -> usize {
        dbus.list_names()
            .await
            .unwrap()
            .iter()
            .filter(|n| n.as_str().starts_with(':'))
            .count()
    }

    async fn settle_clients(dbus: &zbus::fdo::DBusProxy<'_>, want: usize) {
        for _ in 0..200 {
            if clients(dbus).await == want {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("the service connection never closed");
    }

    /// K23: `tray.menu.open` opens the `tray` panel for one item; the same item closes it, another
    /// switches, and any other panel or `ui.close` clears the item.
    #[tokio::test]
    async fn tray_menu_is_an_exclusive_panel_with_its_item() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        ui(&hub, &mut actions);
        let ui_doc = || hub.snapshot("runtime.ui").unwrap().1;
        assert_eq!(ui_doc(), ui_closed());
        let open = |id: &str| json!({"id": id});

        actions.invoke("tray.menu.open", open("a")).await.unwrap();
        assert_eq!(
            ui_doc(),
            json!({"popup": true, "panel": "tray", "launcher": false, "tray": "a", "face": ""})
        );
        actions.invoke("tray.menu.open", open("b")).await.unwrap();
        assert_eq!(ui_doc()["tray"], "b", "another item switches the menu");
        actions.invoke("tray.menu.open", open("b")).await.unwrap();
        assert_eq!(ui_doc(), ui_closed(), "the same item closes it");

        actions.invoke("tray.menu.open", open("a")).await.unwrap();
        actions.invoke("island.expand", json!({})).await.unwrap();
        assert_eq!(ui_doc()["panel"], "island");
        assert_eq!(ui_doc()["tray"], "", "another panel clears the item");
        actions.invoke("tray.menu.open", open("a")).await.unwrap();
        actions.invoke("ui.close", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed());

        for bad in [json!({}), json!({"id": ""}), json!({"id": 3})] {
            assert_eq!(
                actions.invoke("tray.menu.open", bad).await,
                Err(ActionError::Invalid(ARGS_INVALID.into()))
            );
        }
    }

    /// I67: a peek names its bar's edge; a side bar's peek carries the widget's y and height.
    #[tokio::test]
    async fn a_side_bar_peek_carries_its_edge_and_span() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        ui(&hub, &mut actions);
        let ui_doc = || hub.snapshot("runtime.ui").unwrap().1;
        let side = json!({"source": "tray:nm", "output": "DP-1", "x": 0, "w": 40, "edge": "left", "y": 300, "h": 32});
        actions.invoke("ui.peek", side).await.unwrap();
        assert_eq!(
            ui_doc()["peek"],
            json!({"source": "tray:nm", "output": "DP-1", "x": 0.0, "w": 40.0, "edge": "left", "y": 300.0, "h": 32.0})
        );
        let bottom =
            json!({"source": "tray:nm", "output": "DP-1", "x": 10, "w": 40, "edge": "bottom"});
        actions.invoke("ui.peek", bottom).await.unwrap();
        assert_eq!(ui_doc()["peek"]["edge"], "bottom");
        assert!(
            ui_doc()["peek"].get("y").is_none(),
            "a top or bottom bar needs no span"
        );
        for bad in [
            json!({"source": "tray:nm", "output": "DP-1", "x": 0, "w": 40, "edge": "right"}),
            json!({"source": "tray:nm", "output": "DP-1", "x": 0, "w": 40, "edge": "middle"}),
        ] {
            assert!(actions.invoke("ui.peek", bad).await.is_err());
        }
    }

    /// K35: `ui.peek` sets and clears the peek; it is refused under an open card and for a mod
    /// that does not offer it; opening any panel clears it.
    #[tokio::test]
    async fn a_peek_shows_only_without_a_card_and_any_panel_clears_it() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        ui(&hub, &mut actions);
        hub.register(
            "mods",
            json!({"mods": [
                {"id": "sysmon", "state": "enabled", "provides": ["widget:sysmon", "peek:sysmon"]},
                {"id": "weather", "state": "available", "provides": ["peek:weather"]},
            ]}),
            None,
        );
        let ui_doc = || hub.snapshot("runtime.ui").unwrap().1;
        let peek = |source: &str| json!({"source": source, "output": "DP-1", "x": 1800, "w": 120});

        actions
            .invoke("ui.peek", peek("mod:sysmon:sysmon"))
            .await
            .unwrap();
        assert_eq!(
            ui_doc()["peek"],
            json!({"source": "mod:sysmon:sysmon", "output": "DP-1", "x": 1800.0, "w": 120.0})
        );
        actions
            .invoke("ui.peek", peek("tray:nm-applet"))
            .await
            .unwrap();
        assert_eq!(
            ui_doc()["peek"]["source"],
            "tray:nm-applet",
            "the latest wins"
        );
        actions.invoke("ui.peek", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed(), "an empty request clears it");

        assert_eq!(
            actions.invoke("ui.peek", peek("mod:weather:weather")).await,
            Err(ActionError::Invalid(PEEK_UNAVAILABLE.into())),
            "a mod that is off offers no peek"
        );
        assert_eq!(
            actions.invoke("ui.peek", peek("mod:sysmon:other")).await,
            Err(ActionError::Invalid(PEEK_UNAVAILABLE.into()))
        );
        for bad in [
            json!({"source": "nope"}),
            json!({"source": "mod:sysmon", "output": "DP-1", "x": 0, "w": 1}),
            json!({"source": "tray:a", "x": 0, "w": 1}),
            json!({"source": "tray:a", "output": "DP-1", "x": -1, "w": 1}),
            json!({"source": "island:", "output": "DP-1", "x": 0, "w": 1}),
        ] {
            assert_eq!(
                actions.invoke("ui.peek", bad).await,
                Err(ActionError::Invalid(ARGS_INVALID.into()))
            );
        }

        actions
            .invoke("ui.peek", peek("island:main"))
            .await
            .unwrap();
        actions.invoke("quick.toggle", json!({})).await.unwrap();
        assert_eq!(ui_doc()["peek"], Value::Null, "a panel clears the peek");
        assert_eq!(
            actions.invoke("ui.peek", peek("island:main")).await,
            Err(ActionError::Invalid(PEEK_UNDER_CARD.into())),
            "no peek over a card"
        );
        actions.invoke("ui.peek", json!({})).await.unwrap();
        assert_eq!(ui_doc()["panel"], "quick", "clearing never closes the card");
        actions.invoke("ui.close", json!({})).await.unwrap();
        actions
            .invoke("ui.peek", peek("island:main"))
            .await
            .unwrap();
        actions
            .invoke("tray.menu.open", json!({"id": "a"}))
            .await
            .unwrap();
        assert_eq!(ui_doc()["peek"], Value::Null);
    }

    /// K24: `island.expand` latches the face the island shows into `runtime.ui.face`; a face change
    /// while open does not switch the card; any other panel or close clears it; `quick.toggle` is
    /// an exclusive panel of its own.
    #[tokio::test]
    async fn island_expand_latches_the_shown_face() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        ui(&hub, &mut actions);
        let ui_doc = || hub.snapshot("runtime.ui").unwrap().1;

        actions.invoke("island.expand", json!({})).await.unwrap();
        assert_eq!(ui_doc()["panel"], "island");
        assert_eq!(ui_doc()["face"], "", "no island document: generic card");
        actions.invoke("ui.close", json!({})).await.unwrap();

        hub.register(
            "runtime.island.main",
            json!({"face": "media", "reason": "live"}),
            None,
        );
        actions.invoke("island.expand", json!({})).await.unwrap();
        assert_eq!(
            ui_doc(),
            json!({"popup": true, "panel": "island", "launcher": false, "tray": "", "face": "media"})
        );
        hub.set(
            "runtime.island.main",
            json!({"face": "volume", "reason": "transient"}),
            None,
        )
        .unwrap();
        assert_eq!(ui_doc()["face"], "media", "latched while open");
        actions.invoke("island.expand", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed(), "expand again closes");

        actions
            .invoke("island.expand", json!({"island": "main"}))
            .await
            .unwrap();
        assert_eq!(ui_doc()["face"], "volume");
        actions.invoke("quick.toggle", json!({})).await.unwrap();
        assert_eq!(ui_doc()["panel"], "quick");
        assert_eq!(ui_doc()["face"], "", "another panel clears the face");
        actions.invoke("quick.toggle", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed());

        for bad in [
            json!({"island": "nope"}),
            json!({"island": ""}),
            json!({"island": 1}),
        ] {
            assert_eq!(
                actions.invoke("island.expand", bad).await,
                Err(ActionError::Invalid(ARGS_INVALID.into()))
            );
        }
        assert_eq!(ui_doc(), ui_closed(), "a refused expand changes nothing");
    }

    /// The tray runs only while subscribed: the first subscribe takes the watcher name on the
    /// bus, the last unsubscribe releases it, and actions never start it.
    #[tokio::test]
    async fn tray_runs_only_while_subscribed() {
        const WATCHER: &str = "org.kde.StatusNotifierWatcher";
        let bus = Bus::start();
        let connects = Arc::new(AtomicUsize::new(0));
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        tray_with(
            &hub,
            &mut actions,
            private_bus(bus.addr.clone(), connects.clone()),
        );
        let item = json!({"id": ":1.9/StatusNotifierItem", "x": 0, "y": 0});
        assert_eq!(
            actions.invoke("tray.activate", item.clone()).await,
            Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
        );
        assert_eq!(
            connects.load(Ordering::SeqCst),
            0,
            "an action must not start the tray"
        );

        let observer = bus.conn().await;
        let dbus = zbus::fdo::DBusProxy::new(&observer).await.unwrap();
        hub.subscribe(TRAY_DOC).unwrap();
        hub.subscribe(TRAY_DOC).unwrap(); // a second subscriber shares the running service
        until("tray document", || {
            hub.snapshot(TRAY_DOC).unwrap().1["available"] == true
        })
        .await;
        settle_owner(&dbus, WATCHER, true).await;
        assert_eq!(
            connects.load(Ordering::SeqCst),
            1,
            "one start for two subscribers"
        );
        let menu = actions
            .invoke("tray.menu", json!({"id": ":1.9/StatusNotifierItem"}))
            .await;
        assert!(
            menu.unwrap().is_some(),
            "a running tray answers menu requests"
        );

        hub.unsubscribe(TRAY_DOC);
        assert!(owns(&dbus, WATCHER).await, "still subscribed once");
        hub.unsubscribe(TRAY_DOC);
        settle_owner(&dbus, WATCHER, false).await;
        assert_eq!(
            actions.invoke("tray.activate", item).await,
            Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
        );
    }

    /// Fake BlueZ: an ObjectManager and one powered adapter that accepts discovery calls.
    struct FakeAdapter;

    #[zbus::interface(name = "org.bluez.Adapter1")]
    impl FakeAdapter {
        #[zbus(property)]
        fn powered(&self) -> bool {
            true
        }
        #[zbus(property)]
        fn discovering(&self) -> bool {
            false
        }
        async fn start_discovery(&self) {}
        async fn stop_discovery(&self) {}
    }

    async fn serve_fake_bluez(bus: &Bus) -> zbus::Connection {
        let conn = bus.conn().await;
        conn.object_server()
            .at("/", zbus::fdo::ObjectManager)
            .await
            .unwrap();
        conn.object_server()
            .at("/org/bluez/hci0", FakeAdapter)
            .await
            .unwrap();
        conn.request_name("org.bluez").await.unwrap();
        conn
    }

    /// BlueZ is reached only while subscribed: the first subscribe connects and reads the adapter,
    /// the last unsubscribe drops the connection, and actions never start the service.
    #[tokio::test]
    async fn bluetooth_runs_only_while_subscribed() {
        let bus = Bus::start();
        let _bluez = serve_fake_bluez(&bus).await;
        let connects = Arc::new(AtomicUsize::new(0));
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        bluetooth_with(
            &hub,
            &mut actions,
            private_bus(bus.addr.clone(), connects.clone()),
        );
        let scan = json!({"on": true});
        assert_eq!(
            actions.invoke("bluetooth.scan", scan.clone()).await,
            Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
        );
        assert_eq!(
            connects.load(Ordering::SeqCst),
            0,
            "an action must not start BlueZ"
        );

        let observer = bus.conn().await;
        let dbus = zbus::fdo::DBusProxy::new(&observer).await.unwrap();
        let idle = clients(&dbus).await;
        hub.subscribe(BLUETOOTH_DOC).unwrap();
        until("bluetooth document", || {
            hub.snapshot(BLUETOOTH_DOC).unwrap().1["powered"] == true
        })
        .await;
        assert_eq!(connects.load(Ordering::SeqCst), 1);
        assert_eq!(
            clients(&dbus).await,
            idle + 1,
            "one connection while it runs"
        );
        assert_eq!(
            actions.invoke("bluetooth.scan", scan.clone()).await,
            Ok(None),
            "a running service takes the action"
        );

        hub.unsubscribe(BLUETOOTH_DOC);
        settle_clients(&dbus, idle).await;
        assert_eq!(
            actions.invoke("bluetooth.scan", scan).await,
            Err(ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))
        );
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
            // One directory per bus: tests run in parallel, and a shared one is torn down by
            // whichever bus drops first.
            static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
            let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            let dir = temp_dir(&format!("bus-{n}"));
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

    #[tokio::test]
    async fn lock_refuses_without_a_pam_service_and_stays_unlocked() {
        let dir = temp_dir("pam-missing");
        let marker = dir.join("locked");
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        lock_with(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            marker.clone(),
            dir.join("pam.d"),
            SharedFacts::default(),
        );
        assert_eq!(
            actions.invoke("session.lock", Value::Null).await,
            Err(ActionError::Unavailable(NO_PAM.into()))
        );
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], false);
        assert!(!marker.exists(), "a refused lock leaves no marker");

        // The check runs per request: once the service exists, the same action locks.
        std::fs::create_dir_all(dir.join("pam.d")).unwrap();
        std::fs::write(dir.join("pam.d").join("kurashi"), "").unwrap();
        assert_eq!(actions.invoke("session.lock", Value::Null).await, Ok(None));
        assert_eq!(hub.snapshot("runtime.lock").unwrap().1["locked"], true);
        let _ = std::fs::remove_dir_all(&dir);
    }

    // ---- brightness and volume keys --------------------------------------------------------

    fn island_host(hub: &Arc<Hub>, core: &[&str]) -> Arc<crate::island::IslandHost> {
        crate::island::IslandHost::new(
            hub.clone(),
            "main",
            kurashi_island::IslandConfig {
                faces: vec!["clock".into()],
                default: "clock".into(),
                interruptible_by: ["brightness".to_string(), "volume".to_string()].into(),
                ..Default::default()
            },
            core,
        )
    }

    fn island_face(hub: &Hub) -> Value {
        hub.snapshot("runtime.island.main").unwrap().1["face"].clone()
    }

    /// Fake logind: `SetBrightness` writes the sysfs file the real one would write.
    struct FakeBacklight(std::path::PathBuf);
    #[zbus::interface(name = "org.freedesktop.login1.Session")]
    impl FakeBacklight {
        fn set_brightness(&self, _subsystem: &str, name: &str, value: u32) {
            let _ = std::fs::write(self.0.join(name).join("brightness"), value.to_string());
        }
    }

    /// A private bus with a fake logind over a fake backlight at 50 of 100. The server connection
    /// keeps the fake alive; the `ConnectFn` opens client connections to the same bus.
    async fn backlight_rig() -> (Bus, zbus::Connection, std::path::PathBuf, ConnectFn) {
        let bus = Bus::start();
        // One directory per rig: the tests run in parallel and share this process id.
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let sysfs = temp_dir(&format!("backlight-{n}"));
        let dev = sysfs.join("intel_backlight");
        std::fs::create_dir_all(&dev).unwrap();
        std::fs::write(dev.join("max_brightness"), "100").unwrap();
        std::fs::write(dev.join("brightness"), "50").unwrap();
        let srv = bus.conn().await;
        srv.object_server()
            .at(
                "/org/freedesktop/login1/session/auto",
                FakeBacklight(sysfs.clone()),
            )
            .await
            .unwrap();
        srv.request_name("org.freedesktop.login1").await.unwrap();
        let addr = bus.addr.clone();
        let connect: ConnectFn = Arc::new(move || {
            let addr = addr.clone();
            Box::pin(async move {
                zbus::connection::Builder::address(addr.as_str())?
                    .build()
                    .await
            })
        });
        (bus, srv, sysfs, connect)
    }

    #[tokio::test]
    async fn brightness_keys_write_through_logind_and_signal_the_osd() {
        let (_bus, _srv, sysfs, connect) = backlight_rig().await;
        let dev = sysfs.join("intel_backlight");
        let hub = Hub::new();
        let island = island_host(&hub, &["clock", "brightness"]);
        let mut actions = ActionRegistry::default();
        brightness_with(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            Some(island),
            sysfs.clone(),
            connect,
        );
        let level = || std::fs::read_to_string(dev.join("brightness")).unwrap();

        actions.invoke("brightness.up", Value::Null).await.unwrap();
        assert_eq!(level(), "55");
        assert_eq!(island_face(&hub), "brightness");

        actions
            .invoke("brightness.down", json!({"step": 0.1}))
            .await
            .unwrap();
        assert_eq!(level(), "45");
        assert_eq!(
            actions.invoke("brightness.up", json!({"step": 2})).await,
            Err(ActionError::Invalid(STEP_RANGE.into()))
        );
        assert_eq!(level(), "45", "a refused step writes nothing");
        let _ = std::fs::remove_dir_all(&sysfs);
    }

    #[tokio::test]
    async fn brightness_set_intent_writes_the_level_and_drops_out_of_range_values() {
        let (_bus, _srv, sysfs, connect) = backlight_rig().await;
        let dev = sysfs.join("intel_backlight");
        let hub = Hub::new();
        let island = island_host(&hub, &["clock", "brightness"]);
        let mut actions = ActionRegistry::default();
        let mut intents = crate::Intents::default();
        brightness_with(
            &hub,
            &mut actions,
            &mut intents,
            Some(island),
            sysfs.clone(),
            connect,
        );
        let intents = Arc::new(intents);
        let level = || std::fs::read_to_string(dev.join("brightness")).unwrap();

        intents
            .submit("brightness.set", json!(0.25), None, false)
            .unwrap();
        until("level set by the intent", || level() == "25").await;
        assert_eq!(island_face(&hub), "brightness");

        // Intents have no reply: an out-of-range value is dropped without a write.
        intents
            .submit("brightness.set", json!(2), None, false)
            .unwrap();
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert_eq!(level(), "25");
        let _ = std::fs::remove_dir_all(&sysfs);
    }

    #[tokio::test]
    async fn brightness_without_a_device_errors_before_the_bus_and_shows_no_osd() {
        let hub = Hub::new();
        let empty = temp_dir("no-backlight");
        let connect: ConnectFn = Arc::new(|| {
            Box::pin(async {
                Err(zbus::Error::Failure(
                    "the bus must not be used (test)".into(),
                ))
            })
        });
        let mut actions = ActionRegistry::default();
        brightness_with(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            Some(island_host(&hub, &["clock", "brightness"])),
            empty.clone(),
            connect,
        );
        assert_eq!(
            actions.invoke("brightness.up", Value::Null).await,
            Err(ActionError::Unavailable(NO_BACKLIGHT.into()))
        );
        assert_eq!(island_face(&hub), "clock", "no device, no OSD");
        let _ = std::fs::remove_dir_all(&empty);
    }

    /// Stand-in for the sound server: `set_volume` is reported back through the notifier, as the
    /// pulse backend reports it, so the worker's change event (and with it the OSD) follows.
    struct FakeAudio {
        notifier: kurashi_audio::Notifier,
        volume: Arc<Mutex<f64>>,
    }

    impl kurashi_audio::Backend for FakeAudio {
        fn snapshot(&mut self) -> anyhow::Result<kurashi_audio::Snapshot> {
            let volume = *self.volume.lock().unwrap();
            Ok(kurashi_audio::Snapshot {
                sinks: vec![kurashi_audio::Device {
                    id: 1,
                    name: "fake".into(),
                    description: "fake sink".into(),
                    volume,
                    muted: false,
                }],
                default_sink: Some(1),
                ..Default::default()
            })
        }
        fn set_volume(&mut self, linear: f64) {
            *self.volume.lock().unwrap() = linear;
            self.notifier.notify();
        }
        fn set_muted(&mut self, _muted: bool) {}
        fn set_default_sink(&mut self, _id: u32) {}
        fn set_source_muted(&mut self, _muted: bool) {}
        fn set_default_source(&mut self, _id: u32) {}
        fn set_stream_volume(&mut self, _id: u32, _linear: f64) {}
        fn set_stream_muted(&mut self, _id: u32, _muted: bool) {}
    }

    #[tokio::test]
    async fn volume_keys_step_through_the_audio_path_and_signal_the_osd() {
        let hub = Hub::new();
        let island = island_host(&hub, &["clock", "volume"]);
        let mut actions = ActionRegistry::default();
        let volume = Arc::new(Mutex::new(0.5));
        let shared = volume.clone();
        let start: AudioStart = Arc::new(move |sink: Arc<dyn kurashi_services::DocSink>| {
            let shared = shared.clone();
            kurashi_audio::start_with(sink, move |notifier| {
                Ok(FakeAudio {
                    notifier,
                    volume: shared,
                })
            })
        });
        audio_with(
            &hub,
            &mut actions,
            &mut crate::Intents::default(),
            Some(island),
            start,
        );

        // No running service, no volume: an honest error rather than a guess.
        assert_eq!(
            actions.invoke("audio.volume.up", Value::Null).await,
            Err(ActionError::Unavailable(AUDIO_UNAVAILABLE.into()))
        );
        hub.subscribe("svc.audio").unwrap();
        until("audio service up", || {
            hub.snapshot("svc.audio").unwrap().1["available"] == true
        })
        .await;
        assert_eq!(island_face(&hub), "clock");

        actions
            .invoke("audio.volume.up", Value::Null)
            .await
            .unwrap();
        until("volume OSD", || island_face(&hub) == "volume").await;
        assert!((*volume.lock().unwrap() - 0.55).abs() < 1e-9);

        // A quick second step builds on the first one, not on the not-yet-updated document.
        actions
            .invoke("audio.volume.down", json!({"step": 0.1}))
            .await
            .unwrap();
        until("second step applied", || {
            (*volume.lock().unwrap() - 0.45).abs() < 1e-9
        })
        .await;
        hub.unsubscribe("svc.audio");
    }
}
