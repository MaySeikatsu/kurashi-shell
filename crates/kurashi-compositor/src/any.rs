//! The adapter choice (W26, ARCHITECTURE §7): which compositor kurashid talks to, an [`AnyCompositor`] that
//! implements the trait by delegation (the trait is not object-safe, so no `dyn`), the one-shot actions for the
//! daemon's other services, and what Sway and Hyprland share: the mirrored state, the reconnect loop, the
//! external screenshot tools and the screens-off wake guard.
//!
//! Choice: `KURASHI_COMPOSITOR` (`niri`, `hyprland`, `sway`, `none`, `auto`) overrides; otherwise `NIRI_SOCKET` →
//! niri, `HYPRLAND_INSTANCE_SIGNATURE` → Hyprland, `SWAYSOCK` → Sway, else none (WormShell
//! `docs/10-compositor-adapter.md` §8 order: nested sessions keep the innermost-first niri, then Hyprland, then Sway).

use std::{
    ffi::OsString,
    path::{Path, PathBuf},
    pin::Pin,
    sync::{Arc, Mutex},
    time::Duration,
};

use tokio::sync::{broadcast, watch};
use tokio_stream::{Stream, StreamExt, wrappers::BroadcastStream};

use crate::{
    Action, Capabilities, Compositor, CompositorState, Error, Event, Result, diff, hyprland,
    niri::{self, NiriCompositor},
    sway,
};

/// The environment variable that overrides the detection.
pub const OVERRIDE_ENV: &str = "KURASHI_COMPOSITOR";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Niri,
    Hyprland,
    Sway,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Niri => "niri",
            Kind::Hyprland => "hyprland",
            Kind::Sway => "sway",
        }
    }
}

/// A compositor to talk to: its kind and where. niri and Sway: the socket; Hyprland: the instance directory
/// that holds `.socket.sock` (requests) and `.socket2.sock` (events).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub kind: Kind,
    pub path: PathBuf,
}

/// The adapter for this session's environment, or `None` (the daemon runs on; its documents say unavailable).
pub fn detect() -> Option<Target> {
    detect_with(|k| std::env::var_os(k))
}

/// [`detect`] over any environment (tests). Empty values count as unset.
pub fn detect_with(env: impl Fn(&str) -> Option<OsString>) -> Option<Target> {
    let get = |k: &str| env(k).filter(|v| !v.is_empty());
    let niri = || {
        get("NIRI_SOCKET").map(|p| Target {
            kind: Kind::Niri,
            path: p.into(),
        })
    };
    let hypr = || {
        get("HYPRLAND_INSTANCE_SIGNATURE").map(|sig| Target {
            kind: Kind::Hyprland,
            path: hyprland::instance_dir(&sig, get("XDG_RUNTIME_DIR")),
        })
    };
    let sway = || {
        get("SWAYSOCK").map(|p| Target {
            kind: Kind::Sway,
            path: p.into(),
        })
    };
    let choice = get(OVERRIDE_ENV).and_then(|v| v.into_string().ok());
    match choice.as_deref().map(str::trim) {
        Some("niri") => niri(),
        Some("hyprland") => hypr(),
        Some("sway") => sway(),
        Some("none") => None,
        Some("auto") | None => niri().or_else(hypr).or_else(sway),
        Some(other) => {
            tracing::warn!(
                value = other,
                "{OVERRIDE_ENV}: unknown adapter (niri, hyprland, sway, none, auto); detecting"
            );
            niri().or_else(hypr).or_else(sway)
        }
    }
}

/// How screens come back on after [`Action::PowerOffMonitors`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PowerOff {
    /// The compositor turns them on at the next input itself (niri).
    Compositor,
    /// The compositor keeps them off until told; kurashid tells it at the next input (`ext-idle-notify` resumed).
    WakeGuard,
}

/// Where screenshots come from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Screenshots {
    /// The compositor's own (niri: its UI, clipboard and `screenshot-path`).
    Compositor,
    /// `grim` (and `slurp` for a region, `wl-copy` for the clipboard), found on `PATH` or not.
    External { grim: bool, slurp: bool },
}

/// What an adapter offers beyond [`Capabilities`] (CONTRACT-CHANGE 170 proposes folding these into it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Features {
    /// Each output has its own workspace set (niri, Sway); Hyprland's are global, shown on one output each.
    pub per_output_workspaces: bool,
    pub keyboard_layouts: bool,
    pub power_off: PowerOff,
    pub screenshots: Screenshots,
}

impl Target {
    /// Start the adapter's event task. Must be called inside a tokio runtime.
    pub fn spawn(&self) -> AnyCompositor {
        match self.kind {
            Kind::Niri => AnyCompositor::Niri(NiriCompositor::spawn(self.path.clone())),
            Kind::Hyprland => {
                AnyCompositor::Hyprland(hyprland::HyprlandCompositor::spawn(self.path.clone()))
            }
            Kind::Sway => AnyCompositor::Sway(sway::SwayCompositor::spawn(self.path.clone())),
        }
    }

    /// One action on its own request connection(s), without an event stream.
    pub async fn act(&self, action: &Action) -> Result<()> {
        match self.kind {
            Kind::Niri => niri::act_at(&self.path, action).await,
            Kind::Hyprland => hyprland::act_at(&self.path, action).await,
            Kind::Sway => sway::act_at(&self.path, action).await,
        }
    }

    /// The focused output's name (the recorder's default output).
    pub async fn focused_output(&self) -> Result<Option<String>> {
        match self.kind {
            Kind::Niri => niri::focused_output_at(&self.path).await,
            Kind::Hyprland => hyprland::focused_output_at(&self.path).await,
            Kind::Sway => sway::focused_output_at(&self.path).await,
        }
    }

    /// The compositor's socket is there (not that it answers).
    pub fn reachable(&self) -> bool {
        match self.kind {
            Kind::Hyprland => self.path.join(hyprland::REQUEST_SOCKET).exists(),
            Kind::Niri | Kind::Sway => self.path.exists(),
        }
    }

    pub fn capabilities(&self) -> Capabilities {
        match self.kind {
            // NiriCompositor::capabilities() without a running adapter (pinned equal by a test).
            Kind::Niri => Capabilities {
                overview: true,
                workspace_names: true,
                ..Capabilities::default()
            },
            Kind::Hyprland => hyprland::CAPABILITIES,
            Kind::Sway => sway::CAPABILITIES,
        }
    }

    pub fn features(&self) -> Features {
        let external = || Screenshots::External {
            grim: on_path("grim").is_some(),
            slurp: on_path("slurp").is_some(),
        };
        match self.kind {
            Kind::Niri => Features {
                per_output_workspaces: true,
                keyboard_layouts: true,
                power_off: PowerOff::Compositor,
                screenshots: Screenshots::Compositor,
            },
            Kind::Hyprland => Features {
                per_output_workspaces: false,
                keyboard_layouts: true,
                power_off: PowerOff::WakeGuard,
                screenshots: external(),
            },
            Kind::Sway => Features {
                per_output_workspaces: true,
                keyboard_layouts: true,
                power_off: PowerOff::WakeGuard,
                screenshots: external(),
            },
        }
    }

    /// One line for `kurashi doctor`: the adapter, what it offers and what it lacks.
    pub fn describe(&self) -> String {
        let c = self.capabilities();
        let f = self.features();
        let mut has: Vec<String> = Vec::new();
        let mut lacks: Vec<&str> = Vec::new();
        let mut flag = |on: bool, name: &'static str, has: &mut Vec<String>| {
            if on {
                has.push(name.into());
            } else {
                lacks.push(name);
            }
        };
        flag(c.workspace_names, "workspace names", &mut has);
        flag(f.per_output_workspaces, "workspaces per output", &mut has);
        flag(f.keyboard_layouts, "keyboard layouts", &mut has);
        flag(c.overview, "overview", &mut has);
        flag(c.scroll_position, "scroll position", &mut has);
        flag(c.window_previews, "window previews", &mut has);
        flag(c.blur_hint, "blur hint", &mut has);
        has.push(match f.power_off {
            PowerOff::Compositor => "screens off".into(),
            PowerOff::WakeGuard => "screens off (kurashid wakes them at input)".into(),
        });
        match f.screenshots {
            Screenshots::Compositor => has.push("screenshots".into()),
            Screenshots::External { grim, slurp } => {
                let yn = |b: bool| if b { "found" } else { "missing" };
                has.push(format!(
                    "screenshots via grim ({}) / slurp ({})",
                    yn(grim),
                    yn(slurp)
                ));
            }
        }
        let mut line = format!("{}: {}", self.kind.name(), has.join(", "));
        if !lacks.is_empty() {
            line.push_str(&format!("; no {}", lacks.join(", ")));
        }
        line
    }
}

/// The chosen adapter. Each variant is a full adapter with its own event task.
pub enum AnyCompositor {
    Niri(NiriCompositor),
    Hyprland(hyprland::HyprlandCompositor),
    Sway(sway::SwayCompositor),
}

type BoxedEvents = Pin<Box<dyn Stream<Item = Event> + Send + 'static>>;

impl Compositor for AnyCompositor {
    async fn snapshot(&self) -> Result<CompositorState> {
        match self {
            AnyCompositor::Niri(c) => c.snapshot().await,
            AnyCompositor::Hyprland(c) => c.snapshot().await,
            AnyCompositor::Sway(c) => c.snapshot().await,
        }
    }

    fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        let s: BoxedEvents = match self {
            AnyCompositor::Niri(c) => Box::pin(c.events()),
            AnyCompositor::Hyprland(c) => Box::pin(c.events()),
            AnyCompositor::Sway(c) => Box::pin(c.events()),
        };
        s
    }

    async fn act(&self, action: Action) -> Result<()> {
        match self {
            AnyCompositor::Niri(c) => c.act(action).await,
            AnyCompositor::Hyprland(c) => c.act(action).await,
            AnyCompositor::Sway(c) => c.act(action).await,
        }
    }

    fn capabilities(&self) -> Capabilities {
        match self {
            AnyCompositor::Niri(c) => c.capabilities(),
            AnyCompositor::Hyprland(c) => c.capabilities(),
            AnyCompositor::Sway(c) => c.capabilities(),
        }
    }
}

// ---- shared by the Sway and Hyprland adapters ------------------------------------------------------------------

pub(crate) const BACKOFF_START: Duration = Duration::from_millis(250);
pub(crate) const BACKOFF_MAX: Duration = Duration::from_secs(4);
/// A request the compositor does not answer in this time counts as a lost connection.
pub(crate) const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

/// The state an adapter mirrors, its readiness and its subscribers. Events go out only once in sync, and while
/// the state lock is held, so a subscriber's snapshot is never older than the events still queued for it.
pub(crate) struct Mirror {
    state: Mutex<CompositorState>,
    ready: watch::Sender<bool>,
    tx: broadcast::Sender<Event>,
}

impl Mirror {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Mirror {
            state: Mutex::new(CompositorState::default()),
            ready: watch::channel(false).0,
            tx: broadcast::channel(256).0,
        })
    }

    /// The new projected state: events for what changed (none while not yet in sync), then ready.
    pub(crate) fn publish(&self, new: CompositorState) {
        let mut cur = self.state.lock().unwrap();
        if *self.ready.borrow() {
            for e in diff(&cur, &new) {
                let _ = self.tx.send(e);
            }
        }
        *cur = new;
        self.ready.send_replace(true);
    }

    /// The connection is gone: nothing held is known to be in effect any more.
    pub(crate) fn reset(&self) {
        *self.state.lock().unwrap() = CompositorState::default();
        self.ready.send_replace(false);
        let _ = self.tx.send(Event::Resync);
    }

    pub(crate) fn is_ready(&self) -> bool {
        *self.ready.borrow()
    }

    pub(crate) async fn snapshot(&self) -> Result<CompositorState> {
        let mut rx = self.ready.subscribe();
        rx.wait_for(|r| *r)
            .await
            .map_err(|_| Error::Unavailable("adapter stopped".into()))?;
        Ok(self.state.lock().unwrap().clone())
    }

    pub(crate) fn events(&self) -> impl Stream<Item = Event> + Send + Unpin + 'static {
        // A lagging subscriber missed events: the honest answer is Resync, not a silent gap.
        BroadcastStream::new(self.tx.subscribe()).map(|r| r.unwrap_or(Event::Resync))
    }
}

/// Run sessions forever with niri's backoff (250 ms doubling to 4 s; reset after a session that reached sync).
pub(crate) async fn reconnect_loop<F, Fut>(mirror: Arc<Mirror>, name: &'static str, mut session: F)
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<()>>,
{
    let mut backoff = BACKOFF_START;
    loop {
        if let Err(e) = session().await {
            tracing::warn!("{name} connection ended: {e}");
        }
        let synced = mirror.is_ready();
        mirror.reset();
        if synced {
            backoff = BACKOFF_START;
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

pub(crate) fn io_err(e: std::io::Error) -> Error {
    Error::Unavailable(e.to_string())
}

/// `name` as found on `PATH`.
pub(crate) fn on_path(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH")?
        .to_str()?
        .split(':')
        .map(|d| Path::new(d).join(name))
        .find(|p| p.is_file())
}

/// What an external screenshot takes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Shot {
    /// One output by name (`None`: all of them).
    Screen(Option<String>),
    /// A logical-coordinate rectangle (the focused window), `x,y wxh`.
    Rect(i32, i32, u32, u32),
    /// `slurp`'s selection.
    Region,
}

/// A screenshot by `grim` into `$XDG_PICTURES_DIR/Screenshots` (else `~/Pictures/Screenshots`), named as niri
/// names them, then onto the clipboard by `wl-copy` when it is installed. A region the user cancels is no error.
pub(crate) async fn external_screenshot(shot: Shot) -> Result<()> {
    use tokio::process::Command;
    let grim = on_path("grim").ok_or_else(|| Error::Unavailable("grim is not installed".into()))?;
    let geometry = match &shot {
        Shot::Region => {
            let slurp = on_path("slurp")
                .ok_or_else(|| Error::Unavailable("slurp is not installed".into()))?;
            let out = Command::new(slurp).output().await.map_err(io_err)?;
            if !out.status.success() {
                return Ok(()); // cancelled
            }
            Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
        }
        Shot::Rect(x, y, w, h) => Some(format!("{x},{y} {w}x{h}")),
        Shot::Screen(_) => None,
    };
    let dir = std::env::var_os("XDG_PICTURES_DIR")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join("Pictures")))
        .ok_or_else(|| Error::Unavailable("no pictures directory".into()))?
        .join("Screenshots");
    std::fs::create_dir_all(&dir).map_err(io_err)?;
    let file = dir.join(
        chrono::Local::now()
            .format("Screenshot from %Y-%m-%d %H-%M-%S.png")
            .to_string(),
    );
    let mut cmd = Command::new(grim);
    match (&shot, &geometry) {
        (Shot::Screen(Some(o)), _) => {
            cmd.arg("-o").arg(o);
        }
        (_, Some(g)) => {
            cmd.arg("-g").arg(g);
        }
        _ => {}
    }
    let status = cmd.arg(&file).status().await.map_err(io_err)?;
    if !status.success() {
        return Err(Error::Rejected(format!("grim exited with {status}")));
    }
    if let Some(copy) = on_path("wl-copy")
        && let Ok(f) = std::fs::File::open(&file)
    {
        // wl-copy forks to serve the clipboard; the parent returns once it has read the image.
        let _ = Command::new(copy)
            .args(["--type", "image/png"])
            .stdin(f)
            .status()
            .await;
    }
    tracing::info!(file = %file.display(), "screenshot saved");
    Ok(())
}

/// Screens off on a compositor that keeps them off until told (Sway `output * power off`, Hyprland `dpms off`),
/// and on again at the next input, as swayidle's `resume` and hypridle's `on-resume` do — but from kurashid's own
/// `ext-idle-notify` watcher: a 1 s notification proves the protocol works and the seat is idle, then `off`; its
/// `resumed` runs `on`. Without the protocol the screens are left on (they could not be woken).
pub(crate) async fn power_off_until_input<Off, On>(off: Off, on: On) -> Result<()>
where
    Off: Future<Output = Result<()>>,
    On: Future<Output = Result<()>> + Send + 'static,
{
    use crate::idle::{IdleEvent, IdleWatcher};
    let (watcher, mut rx) = IdleWatcher::spawn();
    watcher.arm(vec![1]);
    match tokio::time::timeout(Duration::from_secs(10), rx.recv()).await {
        Ok(Some(IdleEvent::Idled(_))) => {}
        Ok(Some(IdleEvent::Unavailable(why))) => {
            return Err(Error::Unavailable(format!(
                "no idle notifications ({why:?}): the screens could not be woken, so they stay on"
            )));
        }
        Err(_) => {
            return Err(Error::Rejected(
                "input kept coming: the screens stay on".into(),
            ));
        }
        Ok(_) => return Err(Error::Unavailable("idle watcher ended".into())),
    }
    off.await?;
    tokio::spawn(async move {
        let _watcher = watcher;
        while let Some(ev) = rx.recv().await {
            if matches!(ev, IdleEvent::Resumed(_) | IdleEvent::Unavailable(_)) {
                break;
            }
        }
        if let Err(e) = on.await {
            tracing::warn!(error = %e, "screens back on failed");
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<OsString> {
        let m: HashMap<String, OsString> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), OsString::from(v)))
            .collect();
        move |k| m.get(k).cloned()
    }

    #[test]
    fn detection_order_and_override() {
        let all = [
            ("NIRI_SOCKET", "/r/niri.sock"),
            ("HYPRLAND_INSTANCE_SIGNATURE", "abc"),
            ("XDG_RUNTIME_DIR", "/r"),
            ("SWAYSOCK", "/r/sway.sock"),
        ];
        let t = detect_with(env(&all)).unwrap();
        assert_eq!((t.kind, t.path), (Kind::Niri, "/r/niri.sock".into()));
        let t = detect_with(env(&all[1..])).unwrap();
        assert_eq!(t.kind, Kind::Hyprland);
        assert!(t.path.ends_with("abc"));
        let t = detect_with(env(&all[3..])).unwrap();
        assert_eq!((t.kind, t.path), (Kind::Sway, "/r/sway.sock".into()));
        assert_eq!(detect_with(env(&[])), None);
        // Empty counts as unset.
        assert_eq!(detect_with(env(&[("NIRI_SOCKET", "")])), None);

        let mut over = all.to_vec();
        over.push((OVERRIDE_ENV, "sway"));
        assert_eq!(detect_with(env(&over)).unwrap().kind, Kind::Sway);
        over.pop();
        over.push((OVERRIDE_ENV, "none"));
        assert_eq!(detect_with(env(&over)), None);
        // An override naming an adapter whose socket is not set gives none, not another one.
        assert_eq!(
            detect_with(env(&[("SWAYSOCK", "/s"), (OVERRIDE_ENV, "niri")])),
            None
        );
        assert_eq!(
            detect_with(env(&[("SWAYSOCK", "/s"), (OVERRIDE_ENV, "bogus")]))
                .unwrap()
                .kind,
            Kind::Sway
        );
    }

    #[test]
    fn describe_names_what_each_adapter_lacks() {
        let sway = Target {
            kind: Kind::Sway,
            path: "/x".into(),
        };
        let d = sway.describe();
        assert!(
            d.starts_with("sway: workspace names, workspaces per output"),
            "{d}"
        );
        assert!(d.contains("kurashid wakes them"), "{d}");
        assert!(d.contains("; no overview, scroll position"), "{d}");
        let hypr = Target {
            kind: Kind::Hyprland,
            path: "/x".into(),
        };
        assert!(hypr.describe().contains("no workspaces per output"));
        let niri = Target {
            kind: Kind::Niri,
            path: "/x".into(),
        };
        assert!(
            niri.describe()
                .contains("overview, screens off, screenshots")
        );
    }

    #[tokio::test]
    async fn target_capabilities_match_the_running_adapters() {
        let dir = tempfile::tempdir().unwrap();
        for kind in [Kind::Niri, Kind::Hyprland, Kind::Sway] {
            let t = Target {
                kind,
                path: dir.path().join("absent"),
            };
            assert!(!t.reachable());
            assert_eq!(t.spawn().capabilities(), t.capabilities(), "{kind:?}");
        }
    }

    #[tokio::test]
    async fn mirror_is_silent_until_synced_then_diffs() {
        let m = Mirror::new();
        let mut ev = m.events();
        let mut st = CompositorState {
            overview_open: true,
            ..Default::default()
        };
        m.publish(st.clone()); // first sync: no events, ready
        assert_eq!(m.snapshot().await.unwrap(), st);
        st.overview_open = false;
        m.publish(st.clone());
        m.publish(st.clone()); // unchanged: silent
        m.reset();
        assert_eq!(ev.next().await, Some(Event::Overview(false)));
        assert_eq!(ev.next().await, Some(Event::Resync));
        assert!(!m.is_ready());
    }
}
