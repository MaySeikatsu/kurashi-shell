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
                    clear_sidebar(d);
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
                    clear_sidebar(d);
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
                clear_sidebar(d);
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
                clear_sidebar(d);
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
                let open = !d["launcher"].as_bool().unwrap_or(false);
                d["launcher"] = json!(open);
                // W29: the launcher and a sidebar are one at a time.
                if open {
                    clear_sidebar(d);
                }
            })
            .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
    // W29 (docs/ux/sidebar.md): the edge sidebars. `{side: "left"|"right", output?}`; `runtime.ui.sidebar` names the open
    // side and `sidebar_output` the output it is on (absent: the frontend's focused output). One at a time: opening a
    // sidebar closes the Stage's panel and the launcher, and opening those closes it. A left sidebar with no tab
    // configured (`sidebar.left = []`) is refused.
    let sidebar_open = |hub: Arc<Hub>, toggle: bool| {
        move |a: Value| {
            let hub = hub.clone();
            async move {
                let (side, output) = sidebar_args(&a)?;
                if side == "left" && left_sidebar_empty(&hub) {
                    return Err(ActionError::Invalid(SIDEBAR_NO_TABS.into()));
                }
                hub.update("runtime.ui", None, |d| {
                    let same = d["sidebar"].as_str() == Some(side)
                        && output
                            .as_deref()
                            .is_none_or(|o| d["sidebar_output"].as_str() == Some(o));
                    if toggle && same {
                        clear_sidebar(d);
                        return;
                    }
                    d["panel"] = json!("");
                    d["popup"] = json!(false);
                    d["tray"] = json!("");
                    d["face"] = json!("");
                    d["launcher"] = json!(false);
                    clear_peek(d);
                    d["sidebar"] = json!(side);
                    match &output {
                        Some(o) => d["sidebar_output"] = json!(o),
                        None if !same => {
                            if let Some(m) = d.as_object_mut() {
                                m.remove("sidebar_output");
                            }
                        }
                        None => {}
                    }
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        }
    };
    actions.register(
        "sidebar.toggle",
        "action.sidebar.toggle",
        sidebar_open(hub.clone(), true),
    );
    actions.register(
        "sidebar.open",
        "action.sidebar.open",
        sidebar_open(hub.clone(), false),
    );
    // I154: each side as an action of its own, without arguments — what the launcher's `>` commands and a plain bind
    // run (the frontend's focused output).
    for side in ["left", "right"] {
        let open = sidebar_open(hub.clone(), true);
        actions.register(
            &format!("sidebar.{side}.toggle"),
            &format!("action.sidebar.{side}.toggle"),
            move |_| open(json!({ "side": side })),
        );
    }
    let h = hub.clone();
    actions.register("sidebar.close", "action.sidebar.close", move |_| {
        let hub = h.clone();
        async move {
            hub.update("runtime.ui", None, clear_sidebar)
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
    // K47 (5): the frontend's polkit agent says a dialog is up (`{active: true}`) or gone (`{active: false}`), so the
    // island and the Stage can stay out of its way. UI state only: the flow itself is Quickshell's. Absent = false.
    let h = hub.clone();
    actions.register("ui.polkit", "action.ui.polkit", move |a| {
        let hub = h.clone();
        async move {
            let active = a["active"]
                .as_bool()
                .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
            hub.update("runtime.ui", None, |d| d["polkit"] = json!(active))
                .map_err(|e| ActionError::Internal(e.to_string()))?;
            Ok(None)
        }
    });
    let h = hub.clone();
    actions.register("ui.close", "action.ui.close", move |_| {
        let hub = h.clone();
        async move {
            // Closing the panels does not close a polkit dialog: its flag stays as the agent last said.
            let polkit = hub
                .snapshot("runtime.ui")
                .ok()
                .and_then(|(_, d)| d.get("polkit").cloned());
            let mut closed = ui_closed();
            if let Some(p) = polkit {
                closed["polkit"] = p;
            }
            hub.set("runtime.ui", closed, None)
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

/// Closes the sidebar in a `runtime.ui` value (W29): `sidebar` and `sidebar_output` are absent while none is open.
fn clear_sidebar(d: &mut Value) {
    if let Some(o) = d.as_object_mut() {
        o.remove("sidebar");
        o.remove("sidebar_output");
    }
}

/// `{side, output?}` of `sidebar.toggle` / `sidebar.open`: the side, and the output when one is named.
fn sidebar_args(a: &Value) -> Result<(&'static str, Option<String>), ActionError> {
    let invalid = || ActionError::Invalid(ARGS_INVALID.into());
    let side = match a["side"].as_str() {
        Some("left") => "left",
        Some("right") => "right",
        _ => return Err(invalid()),
    };
    let output = match a.get("output") {
        None => None,
        Some(Value::String(o)) if !o.is_empty() => Some(o.clone()),
        Some(_) => return Err(invalid()),
    };
    Ok((side, output))
}

/// Whether `sidebar.left` lists no tab in effect (the `config` document's value; unknown counts as not empty).
fn left_sidebar_empty(hub: &Hub) -> bool {
    hub.snapshot(crate::config::DOC).is_ok_and(|(_, d)| {
        d["values"]["sidebar.left"]["value"]
            .as_array()
            .is_some_and(Vec::is_empty)
    })
}

/// `sidebar.toggle` / `sidebar.open` of the left side while `sidebar.left` names no tab.
const SIDEBAR_NO_TABS: &str = "sidebar.error.no_tabs";

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

/// `query kind:"launcher"` + `launcher.launch {id, files?}`. W26: `launcher.keys` (opens the launcher on the keybind
/// cheat sheet, `runtime.ui.launcher_query = "?"`), `launcher.clip.thumb {id}` → `{path}`, `launcher.clip.delete {id}`,
/// `launcher.clip.pin {id}` → `{pinned}`, `launcher.clip.clear {}`.
pub fn launcher(daemon: &mut Daemon, cfg: Option<&ConfigStore>, state_dir: std::path::PathBuf) {
    use kurashi_launcher::clip::{Clip, ClipError};
    use kurashi_launcher::{Frecency, IndexConfig, LaunchOptions, Launcher};
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
    // The clipboard mode (W26): thumbnails in the cache, pins in the state dir; recent emoji (frecency) in the state
    // dir; the niri binds re-read only when their files change.
    let clip = Arc::new(Clip::new(
        crate::xdg_dir("cache").join("clip"),
        state_dir.join("clip-pins"),
    ));
    let emoji = Arc::new(Mutex::new(Frecency::load(state_dir.join("emoji.json"))));
    let keys = Arc::new(kurashi_launcher::keys::KeysCache::default());
    let now = || {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs())
    };
    // `launcher_query` (the text `launcher.keys` opens the launcher with) lasts while the launcher is open: once it
    // closes by any path, the key goes, so the next plain open starts empty.
    {
        let hub = daemon.hub.clone();
        let mut events = hub.events();
        tokio::spawn(async move {
            loop {
                match events.recv().await {
                    Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                    Err(_) => return,
                }
                let stale = hub.snapshot("runtime.ui").is_ok_and(|(_, d)| {
                    d["launcher"].as_bool() != Some(true) && d.get("launcher_query").is_some()
                });
                if stale {
                    let _ = hub.update("runtime.ui", None, |d| {
                        if let Some(o) = d.as_object_mut() {
                            o.remove("launcher_query");
                        }
                    });
                }
            }
        });
    }
    let l = launcher.clone();
    let (hub, actions, store) = (
        daemon.hub.clone(),
        daemon.actions.clone(),
        daemon.config.clone(),
    );
    let (q_clip, q_emoji) = (clip.clone(), emoji.clone());
    // The `>` commands' labels in the session language, kept per revision of the `i18n` document (one copy, not
    // one per keystroke).
    let labels: Arc<Mutex<(u64, std::collections::HashMap<String, String>)>> = Arc::default();
    // A query that is arithmetic gets its value as the first row (kind `calc`, id `calc:<value>`); launching it
    // copies the value (Capsule's inline calculator, K42 session).
    let query: QueryFn = Arc::new(move |q: &str| {
        // Prefix modes: `:` emoji (recent first), `;` the clipboard history, `>` commands (I126), `?` the keys (W26).
        if let Some(rest) = q.strip_prefix(':') {
            let f = q_emoji.lock().expect("emoji frecency");
            let t = now();
            let limit = if rest.trim().is_empty() { 240 } else { 160 };
            return kurashi_launcher::extras::emoji_rows(rest, limit, &|c| f.score(c, t));
        }
        if let Some(rest) = q.strip_prefix(';') {
            return q_clip.rows(rest.trim(), 60);
        }
        if let Some(rest) = q.strip_prefix('?') {
            let strings = hub
                .snapshot("i18n")
                .map(|(_, d)| d["strings"].clone())
                .unwrap_or_default();
            let tr = |k: &str| strings.get(k).and_then(Value::as_str).map(str::to_owned);
            let bindings = hub
                .snapshot(crate::bindings::DOC)
                .map(|(_, d)| d)
                .unwrap_or_default();
            let pointer = kurashi_launcher::keys::pointer_rows(&bindings, &tr);
            let nb = keys.binds(&kurashi_launcher::keys::niri_config_path());
            return kurashi_launcher::keys::key_rows(&nb, pointer, rest, &tr);
        }
        if let Some(rest) = q.strip_prefix('>') {
            let mut cache = labels.lock().expect("labels lock");
            if let Ok((rev, doc)) = hub.snapshot("i18n")
                && (cache.0 != rev || cache.1.is_empty())
            {
                cache.1 = kurashi_launcher::commands::COMMANDS
                    .iter()
                    .filter_map(|(id, _)| {
                        doc["strings"][format!("action.{id}")]
                            .as_str()
                            .map(|t| ((*id).to_owned(), t.to_owned()))
                    })
                    .collect();
                cache.0 = rev;
            }
            let names = cache.1.clone();
            drop(cache);
            let label = |id: &str| names.get(id).cloned().unwrap_or_else(|| id.to_owned());
            let registered = |id: &str| actions.contains(id);
            return kurashi_launcher::commands::command_rows(rest, &label, &registered);
        }
        let calc = kurashi_launcher::calc::eval(q)
            .map(|v| {
                let shown = kurashi_launcher::calc::format(v);
                json!({"id": format!("calc:{shown}"), "name": shown, "generic": q.trim(),
                       "icon": null, "kind": "calc", "score": 1.0})
            })
            .or_else(|| {
                // A unit conversion (I105): the row shows value and unit; launching copies the value.
                let (v, unit) = kurashi_launcher::calc::convert(q)?;
                let shown = kurashi_launcher::calc::format_unit(v);
                Some(
                    json!({"id": format!("calc:{shown}"), "name": format!("{shown} {unit}"),
                            "generic": q.trim(), "icon": null, "kind": "calc", "score": 1.0}),
                )
            });
        // Last, the web search row (I126), unless `launcher.web_search` is empty.
        let template = store
            .as_ref()
            .and_then(|c| c.get("launcher.web_search", None))
            .and_then(|p| p.value.as_str().map(String::from))
            .unwrap_or_default();
        calc.into_iter()
            .chain(
                l.query(q, 30)
                    .into_iter()
                    .filter_map(|r| serde_json::to_value(r).ok()),
            )
            .chain(kurashi_launcher::commands::web_row(q, &template))
            .collect()
    });
    daemon.queries.insert("launcher".into(), query);

    // A clipboard refusal as an action error: the kind picks the view's line, the key says which.
    fn clip_err(e: ClipError) -> ActionError {
        match e {
            ClipError::Missing(_) => ActionError::Unavailable("launcher.clip.unavailable".into()),
            ClipError::Gone => ActionError::Invalid("launcher.clip.error.gone".into()),
            ClipError::TooLarge => ActionError::Invalid("launcher.clip.error.too_large".into()),
            ClipError::NotImage => ActionError::Invalid("launcher.clip.error.not_image".into()),
            ClipError::PinsFull => ActionError::Invalid("launcher.clip.error.pins_full".into()),
            ClipError::Failed(m) => ActionError::Unavailable(m),
        }
    }
    // The entry an action names: the row id (`clip:<n>`, `clip:pin:<key>`) or the bare id.
    fn clip_id(args: &Value) -> Result<String, ActionError> {
        let id = args["id"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| ActionError::Invalid("error.args.invalid".into()))?;
        Ok(id.strip_prefix("clip:").unwrap_or(id).to_owned())
    }
    async fn blocking<T: Send + 'static>(
        f: impl FnOnce() -> Result<T, ClipError> + Send + 'static,
    ) -> Result<T, ActionError> {
        tokio::task::spawn_blocking(f)
            .await
            .map_err(|e| ActionError::Internal(e.to_string()))?
            .map_err(clip_err)
    }
    let c = clip.clone();
    daemon.actions.register(
        "launcher.clip.thumb",
        "action.launcher.clip.thumb",
        move |args: Value| {
            let c = c.clone();
            async move {
                let id = clip_id(&args)?;
                let path = blocking(move || c.thumb(&id)).await?;
                Ok(Some(json!({"path": path.display().to_string()})))
            }
        },
    );
    let c = clip.clone();
    daemon.actions.register(
        "launcher.clip.delete",
        "action.launcher.clip.delete",
        move |args: Value| {
            let c = c.clone();
            async move {
                let id = clip_id(&args)?;
                blocking(move || c.delete(&id)).await?;
                Ok(None)
            }
        },
    );
    let c = clip.clone();
    daemon.actions.register(
        "launcher.clip.pin",
        "action.launcher.clip.pin",
        move |args: Value| {
            let c = c.clone();
            async move {
                let id = clip_id(&args)?;
                let pinned = blocking(move || c.toggle_pin(&id)).await?;
                Ok(Some(json!({"pinned": pinned})))
            }
        },
    );
    let c = clip.clone();
    daemon.actions.register(
        "launcher.clip.clear",
        "action.launcher.clip.clear",
        move |_| {
            let c = c.clone();
            async move {
                blocking(move || c.clear()).await?;
                Ok(None)
            }
        },
    );
    // The cheat sheet: opens the launcher with `?`; again while it shows the sheet, closes it (a toggle for one key).
    let h = daemon.hub.clone();
    daemon
        .actions
        .register("launcher.keys", "action.launcher.keys", move |_| {
            let hub = h.clone();
            async move {
                hub.update("runtime.ui", None, |d| {
                    let showing = d["launcher"].as_bool() == Some(true)
                        && d["launcher_query"].as_str() == Some("?");
                    d["launcher"] = json!(!showing);
                    if showing {
                        if let Some(o) = d.as_object_mut() {
                            o.remove("launcher_query");
                        }
                    } else {
                        d["launcher_query"] = json!("?");
                        // W29: the launcher and a sidebar are one at a time.
                        clear_sidebar(d);
                    }
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
                Ok(None)
            }
        });
    let run_actions = daemon.actions.clone();
    daemon.actions.register(
        "launcher.launch",
        "action.launcher.launch",
        move |args: Value| {
            let launcher = launcher.clone();
            let actions = run_actions.clone();
            let (clip, emoji) = (clip.clone(), emoji.clone());
            async move {
                let id = args["id"]
                    .as_str()
                    .ok_or_else(|| ActionError::Invalid("launcher.launch needs id".into()))?
                    .to_string();
                // A `>` command runs its action; the web row opens its address in the default browser.
                if let Some(action) = id.strip_prefix("cmd:") {
                    return actions.invoke(action, json!({})).await;
                }
                if let Some(url) = id.strip_prefix("web:") {
                    return tokio::process::Command::new("xdg-open")
                        .arg(url)
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .spawn()
                        .map(|_| Some(json!({"opened": url})))
                        .map_err(|e| ActionError::Unavailable(format!("xdg-open: {e}")));
                }
                let files: Vec<String> = args["files"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(Value::as_str)
                            .map(String::from)
                            .collect()
                    })
                    .unwrap_or_default();
                if let Some(value) = id.strip_prefix("calc:") {
                    return copy_text(value)
                        .await
                        .map(|_| Some(json!({"copied": value})));
                }
                if let Some(value) = id.strip_prefix("emoji:") {
                    copy_text(value).await?;
                    emoji.lock().expect("emoji frecency").record(value, now());
                    return Ok(Some(json!({"copied": value})));
                }
                // A history entry or a pin, bytes and type kept (an image stays an image).
                if let Some(entry) = id.strip_prefix("clip:") {
                    let e = entry.to_owned();
                    blocking(move || clip.copy(&e)).await?;
                    return Ok(Some(json!({"copied": entry})));
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

    /// W29: a sidebar is one side on one output; the same toggle closes it, the other side or output switches; opening it
    /// closes the Stage's panel and the launcher, and opening those (or `ui.close`) closes it. `sidebar` and
    /// `sidebar_output` are absent while it is closed; a left sidebar without tabs is refused.
    #[tokio::test]
    async fn a_sidebar_is_exclusive_with_the_panels_and_the_launcher() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        ui(&hub, &mut actions);
        let ui_doc = || hub.snapshot("runtime.ui").unwrap().1;
        let right = json!({"side": "right", "output": "DP-1"});
        actions.invoke("quick.toggle", json!({})).await.unwrap();
        actions
            .invoke("sidebar.toggle", right.clone())
            .await
            .unwrap();
        assert_eq!(ui_doc()["sidebar"], "right");
        assert_eq!(ui_doc()["sidebar_output"], "DP-1");
        assert_eq!(
            ui_doc()["panel"],
            "",
            "opening a sidebar closes the quick card"
        );
        actions
            .invoke("sidebar.toggle", right.clone())
            .await
            .unwrap();
        assert!(ui_doc().get("sidebar").is_none() && ui_doc().get("sidebar_output").is_none());
        // Another output moves it; the toggle without an output closes it wherever it is.
        actions.invoke("sidebar.open", right.clone()).await.unwrap();
        actions
            .invoke("sidebar.toggle", json!({"side": "right", "output": "DP-2"}))
            .await
            .unwrap();
        assert_eq!(ui_doc()["sidebar_output"], "DP-2");
        actions
            .invoke("sidebar.toggle", json!({"side": "left"}))
            .await
            .unwrap();
        assert_eq!(ui_doc()["sidebar"], "left");
        assert!(
            ui_doc().get("sidebar_output").is_none(),
            "no output named: the focused one"
        );
        actions
            .invoke("sidebar.toggle", json!({"side": "left"}))
            .await
            .unwrap();
        assert!(ui_doc().get("sidebar").is_none());
        // The launcher and the panels close it; it closes them.
        actions.invoke("sidebar.open", right.clone()).await.unwrap();
        actions.invoke("launcher.toggle", json!({})).await.unwrap();
        assert!(ui_doc().get("sidebar").is_none());
        assert_eq!(ui_doc()["launcher"], true);
        actions.invoke("sidebar.open", right.clone()).await.unwrap();
        assert_eq!(ui_doc()["launcher"], false);
        actions.invoke("island.expand", json!({})).await.unwrap();
        assert!(ui_doc().get("sidebar").is_none());
        actions.invoke("sidebar.open", right.clone()).await.unwrap();
        actions.invoke("sidebar.close", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed());
        actions.invoke("sidebar.open", right.clone()).await.unwrap();
        actions.invoke("ui.close", json!({})).await.unwrap();
        assert_eq!(ui_doc(), ui_closed());
        // Bad arguments; a left sidebar the config gives no tab.
        for bad in [
            json!({}),
            json!({"side": "top"}),
            json!({"side": "left", "output": ""}),
        ] {
            assert!(actions.invoke("sidebar.toggle", bad).await.is_err());
        }
        hub.register(
            crate::config::DOC,
            json!({"values": {"sidebar.left": {"value": [], "source": "user"}}}),
            None,
        );
        match actions
            .invoke("sidebar.open", json!({"side": "left"}))
            .await
        {
            Err(ActionError::Invalid(k)) => assert_eq!(k, SIDEBAR_NO_TABS),
            other => panic!("expected the no-tabs refusal, got {other:?}"),
        }
        assert!(ui_doc().get("sidebar").is_none());
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

// ==== K47 (W23-system): idle, night light, keyboard layouts, screen recorder, screenshots ====================

/// A one-shot compositor action (niri: its own request connection, no event stream). `Err` is the log text.
pub type CompositorAct = Arc<
    dyn Fn(
            kurashi_compositor::Action,
        ) -> std::pin::Pin<Box<dyn Future<Output = Result<(), String>> + Send>>
        + Send
        + Sync,
>;
/// The focused output's name, asked of the compositor when a recording starts.
pub type FocusedOutputFn =
    Arc<dyn Fn() -> std::pin::Pin<Box<dyn Future<Output = Option<String>> + Send>> + Send + Sync>;

/// There is no compositor adapter to send the action to (no `NIRI_SOCKET`), or it refused.
pub const COMPOSITOR_UNAVAILABLE: &str = "error.compositor.unavailable";

/// [`CompositorAct`] over niri's socket.
pub fn niri_act(sock: std::path::PathBuf) -> CompositorAct {
    Arc::new(move |a| {
        let sock = sock.clone();
        Box::pin(async move {
            kurashi_compositor::niri::act_at(&sock, &a)
                .await
                .map_err(|e| e.to_string())
        })
    })
}

/// [`FocusedOutputFn`] over niri's socket.
pub fn niri_focused_output(sock: std::path::PathBuf) -> FocusedOutputFn {
    Arc::new(move || {
        let sock = sock.clone();
        Box::pin(async move {
            kurashi_compositor::niri::focused_output_at(&sock)
                .await
                .ok()
                .flatten()
        })
    })
}

async fn compositor_do(
    act: &Option<CompositorAct>,
    a: kurashi_compositor::Action,
) -> Result<(), ActionError> {
    let act = act
        .as_ref()
        .ok_or_else(|| ActionError::Unavailable(COMPOSITOR_UNAVAILABLE.into()))?;
    act(a).await.map_err(|e| {
        tracing::warn!(error = %e, "compositor action failed");
        ActionError::Unavailable(COMPOSITOR_UNAVAILABLE.into())
    })
}

/// `screenshot.screen`, `screenshot.window`, `screenshot.region` (K47): the compositor's own screenshots (niri: the
/// clipboard and its `screenshot-path`; `region` opens niri's screenshot UI).
pub fn screenshots(actions: &mut ActionRegistry, act: Option<CompositorAct>) {
    use kurashi_compositor::Action as A;
    for (id, a) in [
        ("screenshot.screen", A::ScreenshotScreen),
        ("screenshot.window", A::ScreenshotWindow),
        ("screenshot.region", A::ScreenshotRegion),
    ] {
        let act = act.clone();
        actions.register(id, &format!("action.{id}"), move |_| {
            let (act, a) = (act.clone(), a.clone());
            async move {
                compositor_do(&act, a).await?;
                Ok(None)
            }
        });
    }
}

// ---- svc.keyboard ------------------------------------------------------------------------------------------------

pub const KEYBOARD_DOC: &str = "svc.keyboard";

/// Short codes of common XKB layout names (Noctalia `Services/KeyboardLayoutService.qml`'s `layoutMap`).
const LAYOUT_CODES: [(&str, &str); 21] = [
    ("German", "de"),
    ("English (US)", "us"),
    ("English (UK)", "gb"),
    ("French", "fr"),
    ("Spanish", "es"),
    ("Italian", "it"),
    ("Portuguese (Brazil)", "br"),
    ("Portuguese", "pt"),
    ("Russian", "ru"),
    ("Polish", "pl"),
    ("Swedish", "se"),
    ("Norwegian", "no"),
    ("Danish", "dk"),
    ("Finnish", "fi"),
    ("Hungarian", "hu"),
    ("Turkish", "tr"),
    ("Czech", "cz"),
    ("Slovak", "sk"),
    ("Japanese", "jp"),
    ("Korean", "kr"),
    ("Chinese", "cn"),
];

/// The bar's short name of an XKB layout name: Noctalia's table, then the name without its variant
/// (`German (Neo 2)` → `de`), else the first two letters, lower case.
pub fn layout_short(name: &str) -> String {
    let code = |n: &str| LAYOUT_CODES.iter().find(|(k, _)| *k == n).map(|(_, c)| *c);
    if let Some(c) = code(name) {
        return c.into();
    }
    let base = name.split(" (").next().unwrap_or(name).trim();
    if let Some(c) = code(base) {
        return c.into();
    }
    base.chars()
        .filter(|c| c.is_alphanumeric())
        .take(2)
        .collect::<String>()
        .to_lowercase()
}

/// `{"layouts":[{"name","short"}],"current":i}`; no layouts until the compositor names them.
pub fn keyboard_doc(k: Option<&kurashi_compositor::KeyboardLayouts>) -> Value {
    match k {
        Some(k) => json!({
            "layouts": k.names.iter().map(|n| json!({"name": n, "short": layout_short(n)})).collect::<Vec<_>>(),
            "current": k.current,
        }),
        None => json!({"layouts": [], "current": 0}),
    }
}

/// `svc.keyboard` from the compositor's event stream, while subscribed (Ma: the stream exists only then).
pub struct KeyboardProvider<C> {
    factory: Arc<dyn Fn() -> C + Send + Sync>,
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl<C: kurashi_compositor::Compositor + 'static> KeyboardProvider<C> {
    pub fn new(factory: impl Fn() -> C + Send + Sync + 'static) -> Arc<Self> {
        Arc::new(KeyboardProvider {
            factory: Arc::new(factory),
            task: Mutex::new(None),
        })
    }
}

impl<C: kurashi_compositor::Compositor + 'static> crate::hub::Provider for KeyboardProvider<C> {
    fn start(&self, hub: Arc<Hub>) {
        use tokio_stream::StreamExt;
        let compositor = (self.factory)();
        let task = tokio::spawn(async move {
            let mut events = compositor.events();
            if let Ok(s) = compositor.snapshot().await {
                let _ = hub.set(KEYBOARD_DOC, keyboard_doc(s.keyboard.as_ref()), None);
            }
            while let Some(ev) = events.next().await {
                match ev {
                    kurashi_compositor::Event::Keyboard(k) => {
                        let _ = hub.set(KEYBOARD_DOC, keyboard_doc(k.as_ref()), None);
                    }
                    kurashi_compositor::Event::Resync => {
                        if let Ok(s) = compositor.snapshot().await {
                            let _ =
                                hub.push_snapshot(KEYBOARD_DOC, keyboard_doc(s.keyboard.as_ref()));
                        }
                    }
                    _ => {}
                }
            }
        });
        if let Some(old) = self.task.lock().expect("task lock").replace(task) {
            old.abort();
        }
    }

    fn stop(&self) {
        if let Some(t) = self.task.lock().expect("task lock").take() {
            t.abort();
        }
    }
}

/// `keyboard.set {index}` with an index that is no layout of the document.
pub const NO_SUCH_LAYOUT: &str = "error.keyboard.no_such_layout";

/// `svc.keyboard` (refcounted when there is a compositor) and `keyboard.next`, `keyboard.set {index}`.
pub fn keyboard(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    provider: Option<Arc<dyn crate::hub::Provider>>,
    act: Option<CompositorAct>,
) {
    use kurashi_compositor::{Action as A, LayoutTarget};
    hub.register(KEYBOARD_DOC, keyboard_doc(None), provider);
    let a = act.clone();
    actions.register("keyboard.next", "action.keyboard.next", move |_| {
        let a = a.clone();
        async move {
            compositor_do(&a, A::SwitchLayout(LayoutTarget::Next)).await?;
            Ok(None)
        }
    });
    let h = hub.clone();
    actions.register("keyboard.set", "action.keyboard.set", move |args: Value| {
        let (a, h) = (act.clone(), h.clone());
        async move {
            let index = args["index"]
                .as_u64()
                .and_then(|i| u8::try_from(i).ok())
                .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
            // While the document is watched it knows the layouts: an index past them is refused here.
            let known = h
                .snapshot(KEYBOARD_DOC)
                .ok()
                .and_then(|(_, d)| d["layouts"].as_array().map(Vec::len))
                .unwrap_or(0);
            if known > 0 && usize::from(index) >= known {
                return Err(ActionError::Invalid(NO_SUCH_LAYOUT.into()));
            }
            compositor_do(&a, A::SwitchLayout(LayoutTarget::Index(index))).await?;
            Ok(None)
        }
    });
}

// ---- svc.idle ----------------------------------------------------------------------------------------------------

pub const IDLE_DOC: &str = "svc.idle";

/// What the idle policy acts through.
pub struct IdleDeps {
    /// Screens off (niri `power-off-monitors`); `None` without a compositor adapter.
    pub act: Option<CompositorAct>,
    pub backlight_dir: std::path::PathBuf,
    /// The system bus: the backlight write and logind's inhibitors (suspend goes through `session.suspend`).
    pub system: ConnectFn,
}

enum IdleCmd {
    Settings(kurashi_services::idle::Settings),
    Caffeine(bool),
}

fn cfg_u32(c: &ConfigStore, key: &str, dflt: u32) -> u32 {
    c.get(key, None)
        .and_then(|p| p.value.as_u64())
        .and_then(|v| u32::try_from(v).ok())
        .unwrap_or(dflt)
}

fn idle_settings(c: Option<&ConfigStore>) -> kurashi_services::idle::Settings {
    let d = kurashi_services::idle::Settings::default();
    let Some(c) = c else { return d };
    kurashi_services::idle::Settings {
        enabled: cfg_bool(Some(c), "idle.enabled", d.enabled),
        dim_after: cfg_u32(c, "idle.dim_after", d.dim_after),
        lock_after: cfg_u32(c, "idle.lock_after", d.lock_after),
        screen_off_after: cfg_u32(c, "idle.screen_off_after", d.screen_off_after),
        suspend_after: cfg_u32(c, "idle.suspend_after", d.suspend_after),
        inhibit_while_media: cfg_bool(Some(c), "idle.inhibit_while_media", d.inhibit_while_media),
    }
}

/// The player that plays now in a `svc.media` document.
fn media_playing(d: &Value) -> Option<String> {
    d["players"]
        .as_array()?
        .iter()
        .find(|p| p["playing"] == true)
        .map(|p| p["name"].as_str().unwrap_or("media").to_owned())
}

async fn recv_or_pending<T>(rx: &mut Option<tokio::sync::mpsc::UnboundedReceiver<T>>) -> Option<T> {
    match rx {
        Some(rx) => rx.recv().await,
        None => std::future::pending().await,
    }
}

/// The optional `on` of a toggle action; without it, the opposite of `current`.
fn on_arg(args: &Value, current: bool) -> Result<bool, ActionError> {
    match args.get("on") {
        None | Some(Value::Null) => Ok(!current),
        Some(v) => v
            .as_bool()
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into())),
    }
}

/// `svc.idle` (K47) + `idle.caffeine {on?}`, `idle.lock_now`. A policy, not a refcounted service: it runs while
/// `idle.enabled` (the Wayland connection, logind's inhibitors and the media subscription exist only then) and acts
/// with nobody watching. See `kurashi_services::idle`.
pub fn idle(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    cfg: Option<Arc<ConfigStore>>,
    deps: IdleDeps,
) {
    use kurashi_services::idle::{self as policy, Policy};
    let settings = idle_settings(cfg.as_deref());
    hub.register(IDLE_DOC, Policy::new(settings.clone()).doc(), None);
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<IdleCmd>();
    if let Some(store) = &cfg {
        let tx = tx.clone();
        store.on_change(move |c| {
            let _ = tx.send(IdleCmd::Settings(idle_settings(Some(c))));
        });
    }
    {
        let hub = hub.clone();
        actions.register(
            "idle.caffeine",
            "action.idle.caffeine",
            move |args: Value| {
                let (hub, tx) = (hub.clone(), tx.clone());
                async move {
                    let current = hub
                        .snapshot(IDLE_DOC)
                        .is_ok_and(|(_, d)| d["caffeine"] == true);
                    let on = on_arg(&args, current)?;
                    tx.send(IdleCmd::Caffeine(on))
                        .map_err(|_| ActionError::Internal("idle policy stopped".into()))?;
                    Ok(None)
                }
            },
        );
    }
    let reg = actions.clone();
    actions.register("idle.lock_now", "action.idle.lock_now", move |_| {
        let reg = reg.clone();
        async move { reg.invoke("session.lock", json!({})).await }
    });

    let (hub, reg) = (hub.clone(), actions.clone());
    tokio::spawn(async move {
        let mut p = Policy::new(settings);
        let mut watcher: Option<kurashi_compositor::idle::IdleWatcher> = None;
        let mut idle_rx = None;
        let mut logind_rx: Option<tokio::sync::mpsc::UnboundedReceiver<Vec<policy::Inhibitor>>> =
            None;
        let mut logind_task: Option<tokio::task::JoinHandle<()>> = None;
        let mut media: Option<tokio::sync::broadcast::Receiver<Arc<kurashi_ipc::ServerMsg>>> = None;
        let mut armed: Option<Vec<u32>> = None;
        let mut saved_level: Option<f64> = None;
        // Started once per time idle is turned on: a missing protocol or bus is not looped on.
        let mut running = false;
        loop {
            let s = p.settings().clone();
            let mut steps = Vec::new();
            if s.enabled && !running {
                running = true;
                let (w, r) = kurashi_compositor::idle::IdleWatcher::spawn();
                watcher = Some(w);
                idle_rx = Some(r);
                armed = None;
                steps.extend(p.set_unavailable(None));
                let (ltx, lrx) = tokio::sync::mpsc::unbounded_channel();
                logind_rx = Some(lrx);
                let connect = deps.system.clone();
                logind_task = Some(tokio::spawn(async move {
                    match connect().await {
                        Ok(conn) => {
                            if let Err(e) = policy::follow_logind(conn, ltx).await {
                                tracing::debug!(error = %e, "logind idle inhibitors not followed");
                            }
                        }
                        Err(e) => {
                            tracing::debug!(error = %e, "no system bus: logind idle inhibitors unknown")
                        }
                    }
                }));
            } else if !s.enabled && running {
                running = false;
                watcher = None;
                idle_rx = None;
                logind_rx = None;
                if let Some(t) = logind_task.take() {
                    t.abort();
                }
                steps.extend(p.set_logind(Vec::new()));
                steps.extend(p.set_unavailable(None));
            }
            let want_media = s.enabled && s.inhibit_while_media;
            if want_media && media.is_none() {
                media = Some(hub.events());
                if let Ok((_, d)) = hub.subscribe(MEDIA_DOC) {
                    steps.extend(p.set_media(media_playing(&d)));
                }
            } else if !want_media && media.is_some() {
                media = None;
                hub.unsubscribe(MEDIA_DOC);
                steps.extend(p.set_media(None));
            }
            for step in steps {
                run_idle_step(step, &deps, &reg, &hub, &mut saved_level).await;
            }
            let timers = p.timers();
            if let Some(w) = &watcher
                && armed.as_ref() != Some(&timers)
            {
                w.arm(timers.clone());
                armed = Some(timers);
            }
            let _ = hub.set(IDLE_DOC, p.doc(), None);

            let steps = tokio::select! {
                cmd = rx.recv() => match cmd {
                    Some(IdleCmd::Settings(s)) if &s != p.settings() => p.set_settings(s),
                    Some(IdleCmd::Settings(_)) => Vec::new(),
                    Some(IdleCmd::Caffeine(on)) => p.set_caffeine(on),
                    None => break,
                },
                ev = recv_or_pending(&mut idle_rx) => {
                    use kurashi_compositor::idle::{IdleEvent, Unavailable};
                    match ev {
                        Some(IdleEvent::Idled(i)) => p.on_idle(i),
                        Some(IdleEvent::Resumed(_)) => p.on_resume(),
                        other => {
                            let reason = match other {
                                Some(IdleEvent::Unavailable(Unavailable::NoProtocol)) => policy::REASON_NO_PROTOCOL,
                                Some(IdleEvent::Unavailable(Unavailable::NoDisplay)) => policy::REASON_NO_DISPLAY,
                                _ => policy::REASON_LOST,
                            };
                            tracing::warn!(reason, "idle notifications unavailable");
                            watcher = None;
                            idle_rx = None;
                            p.set_unavailable(Some(reason))
                        }
                    }
                },
                list = recv_or_pending(&mut logind_rx) => match list {
                    Some(list) => p.set_logind(list),
                    None => {
                        logind_rx = None;
                        p.set_logind(Vec::new())
                    }
                },
                msg = async {
                    match media.as_mut() {
                        Some(m) => m.recv().await,
                        None => std::future::pending().await,
                    }
                } => {
                    use tokio::sync::broadcast::error::RecvError;
                    let relevant = match &msg {
                        Ok(m) => matches!(&**m, kurashi_ipc::ServerMsg::Patch { doc, .. }
                            | kurashi_ipc::ServerMsg::Snap { doc, .. } if doc == MEDIA_DOC),
                        Err(RecvError::Lagged(_)) => true,
                        Err(RecvError::Closed) => false,
                    };
                    match hub.snapshot(MEDIA_DOC) {
                        Ok((_, d)) if relevant => p.set_media(media_playing(&d)),
                        _ => Vec::new(),
                    }
                },
            };
            for step in steps {
                run_idle_step(step, &deps, &reg, &hub, &mut saved_level).await;
            }
        }
    });
}

async fn set_backlight(deps: &IdleDeps, hub: &Hub, level: f64) {
    let Some(plan) = backlight::plan(&deps.backlight_dir, Change::To(level)) else {
        return;
    };
    match (deps.system)().await {
        Ok(conn) => match plan.apply(&conn).await {
            // A running service keeps its document in step; otherwise it reads the level when it starts.
            Ok(doc) if hub.subscribers("svc.brightness") > 0 => {
                let _ = hub.set("svc.brightness", doc, None);
            }
            Ok(_) => {}
            Err(e) => tracing::warn!(error = %e, "idle: backlight write failed"),
        },
        Err(e) => tracing::warn!(error = %e, "idle: no system bus for the backlight"),
    }
}

async fn run_idle_step(
    step: kurashi_services::idle::Step,
    deps: &IdleDeps,
    reg: &ActionRegistry,
    hub: &Hub,
    saved: &mut Option<f64>,
) {
    use kurashi_services::idle::{DIM_FACTOR, Step, backlight_level};
    tracing::info!(?step, "idle");
    let done = match step {
        Step::Dim => {
            if let Some(level) = backlight_level(&deps.backlight_dir) {
                *saved = Some(level);
                set_backlight(deps, hub, level * DIM_FACTOR).await;
            }
            Ok(())
        }
        Step::Undim => {
            if let Some(level) = saved.take() {
                set_backlight(deps, hub, level).await;
            }
            Ok(())
        }
        Step::Lock => reg.invoke("session.lock", json!({})).await.map(|_| ()),
        Step::ScreenOff => {
            compositor_do(&deps.act, kurashi_compositor::Action::PowerOffMonitors).await
        }
        Step::Suspend => reg
            .invoke("session.suspend", json!({"confirm": true}))
            .await
            .map(|_| ()),
    };
    if let Err(e) = done {
        tracing::warn!(?step, error = %e, "idle step failed");
    }
}

// ---- svc.nightlight ----------------------------------------------------------------------------------------------

pub const NIGHT_DOC: &str = "svc.nightlight";

#[derive(Debug, Clone, PartialEq)]
struct NightConfig {
    enabled: bool,
    temperature: u32,
    schedule: String,
    start: String,
    end: String,
    /// The weather mod's place, for the sun schedule.
    place: Option<(f64, f64)>,
}

fn cfg_str(c: Option<&ConfigStore>, key: &str, dflt: &str) -> String {
    c.and_then(|c| c.get(key, None))
        .and_then(|p| p.value.as_str().map(str::to_owned))
        .unwrap_or_else(|| dflt.to_owned())
}

fn night_config(c: Option<&ConfigStore>) -> NightConfig {
    let places =
        kurashi_mod_weather::places::load(&crate::xdg_dir("state").join("weather/places.json"));
    let configured = cfg_str(c, "mods.weather.place", "");
    let place =
        kurashi_mod_weather::places::effective(&places, &configured, None).map(|p| (p.lat, p.lon));
    NightConfig {
        enabled: cfg_bool(c, "night_light.enabled", false),
        temperature: c.map_or(4000, |c| cfg_u32(c, "night_light.temperature", 4000)),
        schedule: cfg_str(c, "night_light.schedule", "manual"),
        start: cfg_str(c, "night_light.start", "20:00"),
        end: cfg_str(c, "night_light.end", "07:00"),
        place,
    }
}

/// The schedule, or the reason it cannot run.
fn night_schedule(c: &NightConfig) -> Result<kurashi_services::nightlight::Schedule, &'static str> {
    use kurashi_services::nightlight::{self as nl, Schedule};
    match c.schedule.as_str() {
        "always" => Ok(Schedule::Always),
        "sun" => c
            .place
            .map(|(lat, lon)| Schedule::Sun { lat, lon })
            .ok_or(nl::REASON_NO_PLACE),
        _ => match (nl::parse_hhmm(&c.start), nl::parse_hhmm(&c.end)) {
            (Some(start), Some(end)) => Ok(Schedule::Manual { start, end }),
            _ => Err(nl::REASON_BAD_TIME),
        },
    }
}

/// Local `(minute of the day, day of the year, UTC offset in minutes)`.
fn local_now() -> (u32, u32, i32) {
    use chrono::{Datelike, Timelike};
    let now = chrono::Local::now();
    (
        now.hour() * 60 + now.minute(),
        now.ordinal(),
        now.offset().local_minus_utc() / 60,
    )
}

/// Stops a supervised process (wlsunset, a recorder) with `sig`, then kills it after `grace`.
async fn stop_child(
    child: &mut tokio::process::Child,
    sig: rustix::process::Signal,
    grace: std::time::Duration,
) {
    if let Some(pid) = child
        .id()
        .and_then(|p| i32::try_from(p).ok())
        .and_then(rustix::process::Pid::from_raw)
    {
        let _ = rustix::process::kill_process(pid, sig);
    }
    if tokio::time::timeout(grace, child.wait()).await.is_err() {
        let _ = child.kill().await;
    }
}

/// `svc.nightlight` (K47) + `nightlight.toggle {on?}` (sets `night_light.enabled`). The daemon runs `wlsunset` while
/// enabled — no refcount: an effect that is on runs, off is no process. `active` follows the schedule with one timer to
/// the next change (no polling). See `kurashi_services::nightlight`.
pub fn nightlight(hub: &Arc<Hub>, actions: &mut ActionRegistry, cfg: Option<Arc<ConfigStore>>) {
    use kurashi_services::nightlight as nl;
    let initial = night_config(cfg.as_deref());
    hub.register(
        NIGHT_DOC,
        json!({"available": true, "enabled": false, "active": false,
               "temperature": initial.temperature, "schedule": initial.schedule}),
        None,
    );
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<NightConfig>();
    if let Some(store) = &cfg {
        store.on_change(move |c| {
            let _ = tx.send(night_config(Some(c)));
        });
    }
    let store = cfg.clone();
    let h = hub.clone();
    actions.register(
        "nightlight.toggle",
        "action.nightlight.toggle",
        move |args: Value| {
            let (store, h) = (store.clone(), h.clone());
            async move {
                let current = h
                    .snapshot(NIGHT_DOC)
                    .is_ok_and(|(_, d)| d["enabled"] == true);
                let on = on_arg(&args, current)?;
                let store =
                    store.ok_or_else(|| ActionError::Unavailable(SERVICE_NOT_RUNNING.into()))?;
                store
                    .apply(&[ApplyOp::Set {
                        set: "night_light.enabled".into(),
                        value: json!(on),
                        output: None,
                    }])
                    .map_err(|errs| {
                        ActionError::Invalid(
                            errs.first()
                                .map_or_else(|| ARGS_INVALID.into(), |e| e.code.clone()),
                        )
                    })?;
                Ok(None)
            }
        },
    );

    let hub = hub.clone();
    tokio::spawn(async move {
        let mut c = initial;
        let mut child: Option<(Vec<String>, tokio::process::Child)> = None;
        // The command line that ended by itself: not started again until the settings change.
        let mut exited: Option<Vec<String>> = None;
        loop {
            let path = std::env::var("PATH").unwrap_or_default();
            let program = kurashi_services::recorder::which("wlsunset", &path);
            let plan = match (c.enabled, &program, night_schedule(&c)) {
                (false, _, _) => Err(None),
                (true, None, _) => Err(Some(nl::REASON_MISSING)),
                (true, Some(_), Err(r)) => Err(Some(r)),
                (true, Some(_), Ok(s)) => Ok(s),
            };
            let want = plan.ok().map(|s| nl::command(c.temperature, s));
            if child.as_ref().map(|(a, _)| a) != want.as_ref() {
                if let Some((_, mut old)) = child.take() {
                    stop_child(
                        &mut old,
                        rustix::process::Signal::TERM,
                        std::time::Duration::from_secs(2),
                    )
                    .await;
                    tracing::info!("wlsunset stopped");
                }
                if let (Some(argv), Some(program)) = (&want, &program)
                    && exited.as_ref() != Some(argv)
                {
                    match tokio::process::Command::new(program)
                        .args(argv)
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .kill_on_drop(true)
                        .spawn()
                    {
                        Ok(ch) => {
                            tracing::info!(?argv, "wlsunset started");
                            child = Some((argv.clone(), ch));
                        }
                        Err(e) => {
                            tracing::warn!(error = %e, "wlsunset did not start");
                            exited = Some(argv.clone());
                        }
                    }
                }
            }
            let (now, doy, off) = local_now();
            let mut doc = json!({
                "available": true, "enabled": c.enabled, "active": false,
                "temperature": c.temperature, "schedule": c.schedule,
            });
            let mut wake: Option<u32> = None;
            match (plan, child.is_some()) {
                (Ok(s), true) => {
                    let (active, next) = nl::state_at(s, now, doy, off);
                    doc["active"] = json!(active);
                    if let Some(n) = next {
                        doc["next_change"] = json!(nl::hhmm(n));
                        wake = Some(nl::minutes_until(now, n));
                    }
                }
                (Ok(_), false) => {
                    doc["available"] = json!(false);
                    doc["reason"] = json!(nl::REASON_EXITED);
                }
                (Err(Some(r)), _) => {
                    doc["available"] = json!(false);
                    doc["reason"] = json!(r);
                }
                (Err(None), _) => {}
            }
            let _ = hub.set(NIGHT_DOC, doc, None);
            let sleep = async {
                match wake {
                    // To just past the change, so the schedule reads the new side.
                    Some(m) => {
                        tokio::time::sleep(std::time::Duration::from_secs(u64::from(m) * 60 + 1))
                            .await
                    }
                    None => std::future::pending().await,
                }
            };
            tokio::select! {
                next = rx.recv() => match next {
                    Some(n) => {
                        if n != c {
                            exited = None;
                        }
                        c = n;
                    }
                    None => break,
                },
                status = async {
                    match child.as_mut() {
                        Some((_, ch)) => ch.wait().await,
                        None => std::future::pending().await,
                    }
                } => {
                    tracing::warn!(?status, "wlsunset ended by itself");
                    exited = child.take().map(|(a, _)| a);
                }
                _ = sleep => {}
            }
        }
    });
}

// ---- svc.recorder ------------------------------------------------------------------------------------------------

pub const RECORDER_DOC: &str = "svc.recorder";
/// `recorder.start` while a recording runs, or `recorder.stop` while none does.
pub const RECORDER_BUSY: &str = "error.recorder.busy";
pub const RECORDER_IDLE: &str = "error.recorder.not_recording";

struct Recording {
    stop: Option<tokio::sync::oneshot::Sender<()>>,
    done: tokio::sync::watch::Receiver<bool>,
}

struct RecorderState {
    hub: Arc<Hub>,
    cfg: Option<Arc<ConfigStore>>,
    focused: Option<FocusedOutputFn>,
    now: Mutex<Option<Recording>>,
    texts: std::collections::BTreeMap<String, String>,
}

impl RecorderState {
    fn backend(&self) -> Option<kurashi_services::recorder::Backend> {
        let setting = cfg_str(self.cfg.as_deref(), "recorder.backend", "auto");
        kurashi_services::recorder::pick(&setting, &std::env::var("PATH").unwrap_or_default())
    }

    /// The document while nothing records (and the last file, if any).
    fn idle_doc(&self, last: Option<&str>) -> Value {
        let mut d = match self.backend() {
            Some(b) => json!({"available": true, "backend": b.program(), "recording": false}),
            None => json!({"available": false, "backend": "", "recording": false,
                           "reason": kurashi_services::recorder::REASON_MISSING}),
        };
        if let Some(f) = last {
            d["file"] = json!(f);
        }
        d
    }

    fn folder(&self) -> std::path::PathBuf {
        let set = cfg_str(self.cfg.as_deref(), "recorder.directory", "");
        let home = std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        if !set.is_empty() {
            return match set.strip_prefix("~/") {
                Some(rest) => home.join(rest),
                None => set.into(),
            };
        }
        let config_home = std::env::var_os("XDG_CONFIG_HOME")
            .filter(|v| !v.is_empty())
            .map_or_else(|| home.join(".config"), std::path::PathBuf::from);
        kurashi_services::recorder::videos_dir(&home, &config_home)
    }

    fn text(&self, key: &str) -> String {
        self.texts
            .get(key)
            .cloned()
            .unwrap_or_else(|| key.to_owned())
    }

    async fn start(self: &Arc<Self>, output: Option<String>) -> ActionResult {
        use kurashi_services::recorder as rec;
        if self.now.lock().expect("recorder lock").is_some() {
            return Err(ActionError::Invalid(RECORDER_BUSY.into()));
        }
        let backend = self
            .backend()
            .ok_or_else(|| ActionError::Unavailable(rec::REASON_MISSING.into()))?;
        let output = match output {
            Some(o) => Some(o),
            None => match &self.focused {
                Some(f) => f().await,
                None => None,
            },
        };
        let dir = self.folder();
        let _ = std::fs::create_dir_all(&dir);
        let stamp = chrono::Local::now().format("%Y-%m-%d_%H-%M-%S").to_string();
        let file = dir.join(rec::file_name(&stamp));
        let audio = cfg_bool(self.cfg.as_deref(), "recorder.audio", true);
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let (done_tx, done_rx) = tokio::sync::watch::channel(false);
        // Taken before the process starts, so a second start in between is refused, not doubled.
        {
            let mut now = self.now.lock().expect("recorder lock");
            if now.is_some() {
                return Err(ActionError::Invalid(RECORDER_BUSY.into()));
            }
            *now = Some(Recording {
                stop: Some(stop_tx),
                done: done_rx,
            });
        }
        let spawned = tokio::process::Command::new(backend.program())
            .args(backend.args(output.as_deref(), &file, audio))
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn();
        let mut child = match spawned {
            Ok(c) => c,
            Err(e) => {
                tracing::warn!(error = %e, program = backend.program(), "recorder did not start");
                *self.now.lock().expect("recorder lock") = None;
                return Err(ActionError::Unavailable(rec::REASON_FAILED.into()));
            }
        };
        let file_s = file.to_string_lossy().into_owned();
        let _ = self.hub.set(
            RECORDER_DOC,
            json!({"available": true, "backend": backend.program(), "recording": true,
                   "since_ms": unix_ms(), "file": file_s}),
            None,
        );
        let me = self.clone();
        tokio::spawn(async move {
            let status = tokio::select! {
                s = child.wait() => s.ok(),
                _ = stop_rx => {
                    // SIGINT: both recorders finish the file on it (Noctalia stops gpu-screen-recorder this way).
                    stop_child(&mut child, rustix::process::Signal::INT, std::time::Duration::from_secs(5)).await;
                    child.try_wait().ok().flatten()
                }
            };
            tracing::info!(?status, file = %file_s, "recording ended");
            let saved = std::fs::metadata(&file_s).is_ok_and(|m| m.len() > 0);
            let mut doc = me.idle_doc(saved.then_some(file_s.as_str()));
            if !saved {
                doc["reason"] = json!(rec::REASON_FAILED);
            }
            *me.now.lock().expect("recorder lock") = None;
            let _ = me.hub.set(RECORDER_DOC, doc, None);
            let _ = done_tx.send(true);
            let (summary, body) = if saved {
                (me.text("power.recorder.saved"), file_s.clone())
            } else {
                (me.text("power.recorder.failed"), String::new())
            };
            notify_self(&summary, &body).await;
        });
        Ok(None)
    }

    async fn stop(&self) -> ActionResult {
        let (stop, mut done) = {
            let mut now = self.now.lock().expect("recorder lock");
            let r = now
                .as_mut()
                .ok_or_else(|| ActionError::Invalid(RECORDER_IDLE.into()))?;
            (r.stop.take(), r.done.clone())
        };
        if let Some(s) = stop {
            let _ = s.send(());
        }
        // The reply comes once the file is finished (or the recorder was killed).
        let _ =
            tokio::time::timeout(std::time::Duration::from_secs(8), done.wait_for(|d| *d)).await;
        Ok(None)
    }
}

/// A notification through the session's notification server (ours, while it holds the name).
async fn notify_self(summary: &str, body: &str) {
    let Ok(conn) = zbus::Connection::session().await else {
        return;
    };
    let hints: std::collections::HashMap<&str, zbus::zvariant::Value> = Default::default();
    let r = conn
        .call_method(
            Some("org.freedesktop.Notifications"),
            "/org/freedesktop/Notifications",
            Some("org.freedesktop.Notifications"),
            "Notify",
            &(
                "Kurashi",
                0u32,
                "media-record",
                summary,
                body,
                Vec::<&str>::new(),
                hints,
                -1i32,
            ),
        )
        .await;
    if let Err(e) = r {
        tracing::debug!(error = %e, "recording notification not shown");
    }
}

/// `svc.recorder` (K47) + `recorder.start {output?}`, `recorder.stop`, `recorder.toggle`: a supervised
/// gpu-screen-recorder or wf-recorder (`kurashi_services::recorder`) that exists only while recording. When it ends,
/// a notification names the file.
pub fn recorder(
    hub: &Arc<Hub>,
    actions: &mut ActionRegistry,
    cfg: Option<Arc<ConfigStore>>,
    focused: Option<FocusedOutputFn>,
) {
    let st = Arc::new(RecorderState {
        hub: hub.clone(),
        cfg: cfg.clone(),
        focused,
        now: Mutex::new(None),
        texts: crate::i18n::load_locale(
            &crate::i18n::data_dir().join("i18n"),
            &crate::i18n::locale_from_env(),
        ),
    });
    hub.register(RECORDER_DOC, st.idle_doc(None), None);
    if let Some(store) = &cfg {
        let st = st.clone();
        store.on_change(move |_| {
            // The backend setting may have changed; a running recording keeps its document.
            if st.now.lock().expect("recorder lock").is_none() {
                let last = st
                    .hub
                    .snapshot(RECORDER_DOC)
                    .ok()
                    .and_then(|(_, d)| d["file"].as_str().map(str::to_owned));
                let _ = st.hub.set(RECORDER_DOC, st.idle_doc(last.as_deref()), None);
            }
        });
    }
    let s = st.clone();
    actions.register(
        "recorder.start",
        "action.recorder.start",
        move |args: Value| {
            let s = s.clone();
            async move {
                let output = args["output"].as_str().map(str::to_owned);
                s.start(output).await
            }
        },
    );
    let s = st.clone();
    actions.register("recorder.stop", "action.recorder.stop", move |_| {
        let s = s.clone();
        async move { s.stop().await }
    });
    actions.register("recorder.toggle", "action.recorder.toggle", move |_| {
        let s = st.clone();
        async move {
            let recording = s.now.lock().expect("recorder lock").is_some();
            if recording {
                s.stop().await
            } else {
                s.start(None).await
            }
        }
    });
}

// ---- svc.audio.spectrum (K48, W24-media) -----------------------------------------------------------------------

pub const SPECTRUM_DOC: &str = "svc.audio.spectrum";

/// Finds the cava program at each start (it may be installed while the daemon runs).
pub type SpectrumProgram = Arc<dyn Fn() -> Option<std::path::PathBuf> + Send + Sync>;

struct SpectrumSink(Arc<Hub>);

impl kurashi_services::DocSink for SpectrumSink {
    fn set(&self, doc: Value) {
        let _ = self.0.set(SPECTRUM_DOC, doc, None);
    }
}

/// `svc.audio.spectrum` while subscribed: cava runs from the first subscriber to the last (Ma), see
/// `kurashi_services::spectrum`.
struct SpectrumProvider {
    program: SpectrumProgram,
    running: Mutex<Option<kurashi_services::ServiceHandle>>,
}

impl crate::hub::Provider for SpectrumProvider {
    fn start(&self, hub: Arc<Hub>) {
        let h = kurashi_services::spectrum::start((self.program)(), Arc::new(SpectrumSink(hub)));
        *self.running.lock().expect("spectrum lock") = Some(h);
    }
    fn stop(&self) {
        // Dropping the handle aborts the reader and kills cava.
        self.running.lock().expect("spectrum lock").take();
    }
}

/// `svc.audio.spectrum` (K48): live audio levels from `cava` on the daemon's PATH, refcounted.
pub fn spectrum(hub: &Arc<Hub>) {
    spectrum_with(
        hub,
        Arc::new(|| kurashi_services::spectrum::which(&std::env::var("PATH").unwrap_or_default())),
    );
}

/// [`spectrum`] with the program lookup injected (tests run a fake cava).
pub fn spectrum_with(hub: &Arc<Hub>, program: SpectrumProgram) {
    use kurashi_services::spectrum as sp;
    // Before anything watches it: whether there is a cava to run, and no level yet.
    let initial = if program().is_some() {
        sp::doc_waiting()
    } else {
        sp::doc_unavailable(sp::REASON_MISSING)
    };
    hub.register(
        SPECTRUM_DOC,
        initial,
        Some(Arc::new(SpectrumProvider {
            program,
            running: Mutex::new(None),
        })),
    );
}

#[cfg(test)]
mod spectrum_tests {
    use super::*;

    /// A fake cava that prints one loud frame, then stays (as cava does while the audio is silent).
    fn fake_cava(dir: &std::path::Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let p = dir.join("cava");
        std::fs::write(
            &p,
            format!(
                "#!/bin/sh\necho $$ >> {}/pids\ncat >/dev/null\n\
                 echo '100;80;60;40;20;0;0;0;0;0;0;0;0;0;0;0;'\nexec sleep 30\n",
                dir.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        p
    }

    #[tokio::test]
    async fn cava_runs_only_while_the_document_is_watched() {
        let dir = std::env::temp_dir().join(format!("kurashi-spectrum-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let cava = fake_cava(&dir);
        let hub = Hub::new();
        spectrum_with(&hub, Arc::new(move || Some(cava.clone())));
        assert_eq!(hub.snapshot(SPECTRUM_DOC).unwrap().1["available"], true);
        assert!(
            !dir.join("pids").exists(),
            "nothing runs before a subscriber"
        );
        hub.subscribe(SPECTRUM_DOC).unwrap();
        let mut bars = Value::Null;
        for _ in 0..200 {
            bars = hub.snapshot(SPECTRUM_DOC).unwrap().1["bars"].clone();
            if bars[0] == 1.0 {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        assert_eq!(bars[0], 1.0);
        assert_eq!(bars[1], 0.8);
        assert_eq!(bars.as_array().unwrap().len(), 16);
        let pid: i32 = std::fs::read_to_string(dir.join("pids"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        hub.unsubscribe(SPECTRUM_DOC);
        let mut gone = false;
        for _ in 0..200 {
            let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
            if stat.is_empty() || stat.split_whitespace().nth(2) == Some("Z") {
                gone = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        let _ = std::fs::remove_dir_all(&dir);
        assert!(gone, "cava still runs after the last subscriber left");
    }

    #[tokio::test]
    async fn without_cava_the_document_says_why() {
        let hub = Hub::new();
        spectrum_with(&hub, Arc::new(|| None));
        let d = hub.snapshot(SPECTRUM_DOC).unwrap().1;
        assert_eq!(d["available"], false);
        assert_eq!(d["reason"], kurashi_services::spectrum::REASON_MISSING);
        hub.subscribe(SPECTRUM_DOC).unwrap();
        assert_eq!(hub.snapshot(SPECTRUM_DOC).unwrap().1["available"], false);
    }
}

#[cfg(test)]
mod power_tests {
    use super::*;

    #[test]
    fn layout_short_names() {
        assert_eq!(layout_short("English (US)"), "us");
        assert_eq!(layout_short("Japanese"), "jp");
        assert_eq!(layout_short("German (Neo 2)"), "de");
        assert_eq!(layout_short("Esperanto"), "es");
        let doc = keyboard_doc(Some(&kurashi_compositor::KeyboardLayouts {
            names: vec!["English (US)".into(), "Japanese".into()],
            current: 1,
        }));
        assert_eq!(
            doc,
            json!({"layouts": [{"name": "English (US)", "short": "us"}, {"name": "Japanese", "short": "jp"}], "current": 1})
        );
    }

    #[test]
    fn media_playing_names_the_player() {
        assert_eq!(
            media_playing(
                &json!({"players": [{"name": "mpv", "playing": false}, {"name": "Firefox", "playing": true}]})
            ),
            Some("Firefox".into())
        );
        assert_eq!(media_playing(&json!({"available": false})), None);
    }

    #[tokio::test]
    async fn actions_without_a_compositor_say_so() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        keyboard(&hub, &mut actions, None, None);
        screenshots(&mut actions, None);
        for id in [
            "keyboard.next",
            "screenshot.screen",
            "screenshot.window",
            "screenshot.region",
        ] {
            assert_eq!(
                actions.invoke(id, json!({})).await,
                Err(ActionError::Unavailable(COMPOSITOR_UNAVAILABLE.into())),
                "{id}"
            );
        }
        assert_eq!(
            actions.invoke("keyboard.set", json!({})).await,
            Err(ActionError::Invalid(ARGS_INVALID.into()))
        );
    }

    #[tokio::test]
    async fn screenshots_and_layouts_reach_the_compositor() {
        use kurashi_compositor::{Action as A, LayoutTarget};
        let seen: Arc<Mutex<Vec<A>>> = Arc::default();
        let s = seen.clone();
        let act: CompositorAct = Arc::new(move |a| {
            s.lock().unwrap().push(a);
            Box::pin(async { Ok(()) })
        });
        let mut actions = ActionRegistry::default();
        screenshots(&mut actions, Some(act.clone()));
        let hub = Hub::new();
        keyboard(&hub, &mut actions, None, Some(act));
        actions
            .invoke("screenshot.region", json!({}))
            .await
            .unwrap();
        actions
            .invoke("keyboard.set", json!({"index": 1}))
            .await
            .unwrap();
        assert_eq!(
            *seen.lock().unwrap(),
            vec![A::ScreenshotRegion, A::SwitchLayout(LayoutTarget::Index(1))]
        );
    }

    #[tokio::test]
    async fn caffeine_toggles_the_idle_document() {
        let hub = Hub::new();
        let mut actions = ActionRegistry::default();
        let connect: ConnectFn =
            Arc::new(|| Box::pin(async { Err(zbus::Error::Failure("no bus".into())) }));
        idle(
            &hub,
            &mut actions,
            None,
            IdleDeps {
                act: None,
                backlight_dir: "/nonexistent".into(),
                system: connect,
            },
        );
        let wait = |want: bool| {
            let hub = hub.clone();
            async move {
                for _ in 0..400 {
                    if hub.snapshot(IDLE_DOC).unwrap().1["caffeine"] == want {
                        return hub.snapshot(IDLE_DOC).unwrap().1;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(5)).await;
                }
                panic!("caffeine never became {want}");
            }
        };
        actions.invoke("idle.caffeine", json!({})).await.unwrap();
        let d = wait(true).await;
        assert_eq!(d["inhibited"], true);
        actions
            .invoke("idle.caffeine", json!({"on": false}))
            .await
            .unwrap();
        wait(false).await;
        assert_eq!(
            actions.invoke("idle.caffeine", json!({"on": "yes"})).await,
            Err(ActionError::Invalid(ARGS_INVALID.into()))
        );
    }
}
