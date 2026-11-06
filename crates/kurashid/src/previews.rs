//! `svc.previews` (I284, I285, K92; `docs/ux/hover-previews.md`): last-seen stills for the bar's hover previews. While a window
//! list or workspaces module with previews on subscribes (Ma: otherwise nothing runs), an output is captured once it has
//! settled after a change of its workspace or focused window, and on the pointer's arrival at the bar (`preview.refresh`). The
//! workspace keeps the whole still; a window the still shows wholly keeps its crop (`kurashi_compositor::locate`). The
//! pictures are files in the runtime dir (tmpfs, the user's alone), gone with the window, the subscription or the session. Never
//! while locked, in the overview, or with a card, the launcher or a peek over the windows.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_compositor::any::Target;
use kurashi_compositor::capture::{Still, capture_output};
use kurashi_compositor::locate::{Grey, WindowGeom, locate};
use kurashi_compositor::{Compositor, CompositorState, Event};
use serde_json::{Value, json};
use tokio::sync::mpsc;
use tokio::time::Instant;
use tokio_stream::StreamExt;

use crate::actions::{ActionError, ActionRegistry};
use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.previews";
/// After a change, the time for the compositor's own animation to end: a still of a moving window is no use.
const SETTLE: Duration = Duration::from_millis(1200);
/// At most one round in this time, however quickly focus moves.
const MIN_GAP: Duration = Duration::from_millis(1500);
/// A compositor that does not answer.
const TIMEOUT: Duration = Duration::from_secs(3);
const WINDOW_MAX: (u32, u32) = (480, 300);
const WORKSPACE_MAX: (u32, u32) = (640, 360);

pub struct PreviewsProvider {
    target: Target,
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
    refresh: Arc<Mutex<Option<mpsc::UnboundedSender<Option<String>>>>>,
}

impl PreviewsProvider {
    pub fn new(target: Target) -> Arc<Self> {
        Arc::new(PreviewsProvider {
            target,
            task: Mutex::new(None),
            refresh: Arc::new(Mutex::new(None)),
        })
    }

    /// `preview.refresh {output?}`: the pointer reached the bar, so what is on screen now is worth keeping. Does nothing
    /// while no module subscribes; at most one round per `MIN_GAP`.
    pub fn register_actions(self: &Arc<Self>, actions: &mut ActionRegistry) {
        let refresh = self.refresh.clone();
        actions.register(
            "preview.refresh",
            "action.preview.refresh",
            move |args: Value| {
                let refresh = refresh.clone();
                async move {
                    let output = match args.get("output") {
                        None | Some(Value::Null) => None,
                        Some(Value::String(s)) => Some(s.clone()),
                        Some(_) => {
                            return Err(ActionError::Invalid(crate::wiring::ARGS_INVALID.into()));
                        }
                    };
                    if let Some(tx) = refresh.lock().expect("refresh lock").as_ref() {
                        let _ = tx.send(output);
                    }
                    Ok(None)
                }
            },
        );
    }
}

impl Provider for PreviewsProvider {
    fn start(&self, hub: Arc<Hub>) {
        let (tx, rx) = mpsc::unbounded_channel();
        *self.refresh.lock().expect("refresh lock") = Some(tx);
        let target = self.target.clone();
        let task = tokio::spawn(run(target, hub, rx));
        *self.task.lock().expect("task lock") = Some(task);
    }

    fn stop(&self) {
        *self.refresh.lock().expect("refresh lock") = None;
        if let Some(t) = self.task.lock().expect("task lock").take() {
            t.abort();
        }
        if let Some(d) = dir() {
            let _ = std::fs::remove_dir_all(d);
        }
    }
}

fn dir() -> Option<PathBuf> {
    Some(PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?).join("kurashi-previews"))
}

/// A picture: its file, its size and when it was taken (ms since the epoch: the frontend says how long ago).
#[derive(Clone, Debug, PartialEq)]
struct Pic {
    path: PathBuf,
    w: u32,
    h: u32,
    at: u64,
}
impl Pic {
    fn json(&self) -> Value {
        json!({"path": self.path.to_string_lossy(), "w": self.w, "h": self.h, "at": self.at})
    }
    fn remove(&self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

#[derive(Default)]
struct Pics {
    available: bool,
    windows: BTreeMap<u64, Pic>,
    workspaces: BTreeMap<u64, Pic>,
    /// Each workspace's windows, in niri's column order.
    order: BTreeMap<u64, Vec<u64>>,
    seq: u64,
}
impl Pics {
    fn document(&self) -> Value {
        let windows: serde_json::Map<String, Value> = self
            .windows
            .iter()
            .map(|(id, p)| (id.to_string(), p.json()))
            .collect();
        let ids: BTreeSet<u64> = self
            .workspaces
            .keys()
            .chain(self.order.keys())
            .copied()
            .collect();
        let workspaces: serde_json::Map<String, Value> = ids
            .into_iter()
            .map(|id| {
                let still = self.workspaces.get(&id).map_or(Value::Null, Pic::json);
                let order = self.order.get(&id).cloned().unwrap_or_default();
                (id.to_string(), json!({"still": still, "windows": order}))
            })
            .collect();
        json!({"available": self.available, "windows": windows, "workspaces": workspaces})
    }
    /// Drops what the compositor no longer has.
    fn prune(&mut self, state: &CompositorState) -> bool {
        let before = (self.windows.len(), self.workspaces.len());
        self.windows.retain(|id, p| {
            let keep = state.windows.iter().any(|w| w.id == *id);
            if !keep {
                p.remove();
            }
            keep
        });
        self.workspaces.retain(|id, p| {
            let keep = state.workspaces.iter().any(|w| w.id == *id);
            if !keep {
                p.remove();
            }
            keep
        });
        before != (self.windows.len(), self.workspaces.len())
    }
}

/// What makes an output worth a new still: its active workspace, its windows and the focus on it. A title is not (a
/// terminal's changes all the time).
fn keys(state: &CompositorState) -> BTreeMap<String, (u64, Option<u64>, Vec<u64>)> {
    let mut out = BTreeMap::new();
    for ws in state.workspaces.iter().filter(|w| w.active) {
        let Some(o) = ws.output.clone() else { continue };
        let on: Vec<_> = state
            .windows
            .iter()
            .filter(|w| w.workspace_id == Some(ws.id))
            .collect();
        let focused = on.iter().find(|w| w.focused).map(|w| w.id);
        out.insert(o, (ws.id, focused, on.iter().map(|w| w.id).collect()));
    }
    out
}

/// Whether something of the shell's own stands over the windows, or nothing should be kept now.
fn held(hub: &Hub, state: &CompositorState) -> bool {
    if state.overview_open {
        return true;
    }
    let doc = |name: &str| hub.snapshot(name).map(|(_, v)| v).unwrap_or(Value::Null);
    let ui = doc("runtime.ui");
    let open = ui["panel"].as_str().is_some_and(|p| !p.is_empty())
        || ui["launcher"] == true
        || ui.get("peek").is_some_and(|p| !p.is_null());
    open || doc(crate::lock::DOC)["locked"] == true
}

async fn run(target: Target, hub: Arc<Hub>, mut refresh: mpsc::UnboundedReceiver<Option<String>>) {
    let Some(dir) = dir() else { return };
    let _ = std::fs::remove_dir_all(&dir);
    if create_private(&dir).is_err() {
        return;
    }
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_default();
    let compositor = target.spawn();
    let mut events = compositor.events();
    let mut state = compositor.snapshot().await.unwrap_or_default();
    let mut pics = Pics {
        available: !display.is_empty(),
        ..Pics::default()
    };
    let _ = hub.set(DOC, pics.document(), None);
    let mut seen = keys(&state);
    let mut dirty: BTreeSet<String> = seen.keys().cloned().collect();
    let mut last = Instant::now() - MIN_GAP;
    let at = |wait: Duration, last: Instant| (Instant::now() + wait).max(last + MIN_GAP);
    let mut deadline = (!dirty.is_empty()).then(|| at(SETTLE, last));
    loop {
        // (no timer at all while nothing has changed: Ma)
        let sleep = async {
            match deadline {
                Some(d) => tokio::time::sleep_until(d).await,
                None => std::future::pending().await,
            }
        };
        tokio::select! {
            ev = events.next() => {
                let Some(ev) = ev else { return };
                match ev {
                    Event::Outputs(o) => state.outputs = o,
                    Event::Workspaces(w) => state.workspaces = w,
                    Event::Windows(w) => state.windows = w,
                    Event::Overview(o) => state.overview_open = o,
                    Event::Keyboard(_) => continue,
                    Event::Resync => {
                        if let Ok(s) = compositor.snapshot().await {
                            state = s;
                        }
                    }
                }
                if pics.prune(&state) {
                    let _ = hub.set(DOC, pics.document(), None);
                }
                let now = keys(&state);
                let mut changed = false;
                for (o, k) in &now {
                    if seen.get(o) != Some(k) {
                        dirty.insert(o.clone());
                        changed = true;
                    }
                }
                seen = now;
                if changed {
                    deadline = Some(at(SETTLE, last));
                }
            }
            asked = refresh.recv() => {
                let Some(asked) = asked else { return };
                match asked {
                    Some(o) => { dirty.insert(o); }
                    None => dirty.extend(seen.keys().cloned()),
                }
                if deadline.is_none() {
                    deadline = Some(at(Duration::ZERO, last));
                }
            }
            () = sleep => {
                deadline = None;
                last = Instant::now();
                if held(&hub, &state) {
                    dirty.clear();
                    continue;
                }
                let outs = std::mem::take(&mut dirty);
                round(&target, &hub, &state, &display, &dir, &outs, &mut pics).await;
            }
        }
    }
}

fn create_private(dir: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::DirBuilderExt;
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)
}

/// One still per output, and what it shows.
async fn round(
    target: &Target,
    hub: &Hub,
    state: &CompositorState,
    display: &str,
    dir: &Path,
    outs: &BTreeSet<String>,
    pics: &mut Pics,
) {
    let geoms = target.window_geoms().await.unwrap_or_default();
    pics.order = order_of(&geoms);
    for name in outs {
        let Some(out) = state.outputs.iter().find(|o| o.name == *name) else {
            continue;
        };
        let Some(ws) = state
            .workspaces
            .iter()
            .find(|w| w.active && w.output.as_deref() == Some(name.as_str()))
        else {
            continue;
        };
        let (d, n, tmp) = (display.to_owned(), name.clone(), dir.to_owned());
        let took = tokio::time::timeout(
            TIMEOUT,
            tokio::task::spawn_blocking(move || capture_output(&d, &n, &tmp)),
        )
        .await;
        let still = match took {
            Ok(Ok(Ok(s))) => s,
            other => {
                tracing::warn!(output = %name, result = ?other.map(|r| r.map(|c| c.map(|_| ()))), "no still");
                pics.available = false;
                continue;
            }
        };
        pics.available = true;
        // Pixels off the runtime: they are megabytes.
        let on: Vec<WindowGeom> = geoms
            .iter()
            .filter(|g| g.workspace == Some(ws.id))
            .cloned()
            .collect();
        let logical = (out.logical.2, out.logical.3);
        let (wsid, dir2, seq) = (ws.id, dir.to_owned(), pics.seq);
        pics.seq += 1;
        let done =
            tokio::task::spawn_blocking(move || cut(&still, logical, wsid, &on, &dir2, seq)).await;
        let Ok((whole, crops)) = done else { continue };
        if let Some(p) = whole
            && let Some(old) = pics.workspaces.insert(wsid, p)
        {
            old.remove();
        }
        if std::env::var_os("KURASHI_PREVIEW_LOG").is_some() {
            tracing::info!(workspace = wsid, windows = crops.len(), "preview round");
        }
        for (id, p) in crops {
            if let Some(old) = pics.windows.insert(id, p) {
                old.remove();
            }
        }
    }
    let _ = hub.set(DOC, pics.document(), None);
}

fn order_of(geoms: &[WindowGeom]) -> BTreeMap<u64, Vec<u64>> {
    let mut out: BTreeMap<u64, Vec<(usize, usize, u64)>> = BTreeMap::new();
    for g in geoms {
        let Some(ws) = g.workspace else { continue };
        let (c, r) = g.column.unwrap_or((usize::MAX, 0));
        out.entry(ws).or_default().push((c, r, g.id));
    }
    out.into_iter()
        .map(|(ws, mut v)| {
            v.sort_unstable();
            (ws, v.into_iter().map(|x| x.2).collect())
        })
        .collect()
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

/// The workspace's picture and the crops of the windows the still shows wholly.
fn cut(
    still: &Still,
    logical: (u32, u32),
    ws: u64,
    on: &[WindowGeom],
    dir: &Path,
    seq: u64,
) -> (Option<Pic>, Vec<(u64, Pic)>) {
    let at = now_ms();
    let Some(img) = image::RgbaImage::from_raw(still.width, still.height, still.rgbx.clone())
    else {
        return (None, Vec::new());
    };
    let whole = save(
        &img,
        (0, 0, still.width, still.height),
        WORKSPACE_MAX,
        &dir.join(format!("ws-{ws}-{seq}.png")),
        at,
    );
    let (lw, lh) = (logical.0.max(1), logical.1.max(1));
    let grey = Grey::from_rgbx(
        &still.rgbx,
        still.width as usize,
        still.height as usize,
        lw as usize,
        lh as usize,
    );
    let focused = on
        .iter()
        .find(|g| g.active)
        .and_then(|g| g.column)
        .map(|c| c.0);
    let scale = f64::from(still.width) / f64::from(lw);
    let mut crops = Vec::new();
    for (id, x, y) in locate(&grey, on, focused) {
        let Some(g) = on.iter().find(|g| g.id == id) else {
            continue;
        };
        let px = |v: f64| (v * scale).round().max(0.0) as u32;
        let (cx, cy) = (px(x), px(y));
        let cw = px(g.window.0).min(still.width.saturating_sub(cx));
        let ch = px(g.window.1).min(still.height.saturating_sub(cy));
        if cw < 8 || ch < 8 {
            continue;
        }
        if let Some(p) = save(
            &img,
            (cx, cy, cw, ch),
            WINDOW_MAX,
            &dir.join(format!("w-{id}-{seq}.png")),
            at,
        ) {
            crops.push((id, p));
        }
    }
    (whole, crops)
}

fn save(
    img: &image::RgbaImage,
    (x, y, w, h): (u32, u32, u32, u32),
    max: (u32, u32),
    path: &Path,
    at: u64,
) -> Option<Pic> {
    use image::ImageEncoder;
    let k = (f64::from(max.0) / f64::from(w))
        .min(f64::from(max.1) / f64::from(h))
        .min(1.0);
    let (tw, th) = (
        ((f64::from(w) * k) as u32).max(1),
        ((f64::from(h) * k) as u32).max(1),
    );
    let view = image::imageops::crop_imm(img, x, y, w, h).to_image();
    let small = image::imageops::thumbnail(&view, tw, th);
    let file = private_file(path).ok()?;
    let enc = image::codecs::png::PngEncoder::new_with_quality(
        std::io::BufWriter::new(file),
        image::codecs::png::CompressionType::Fast,
        image::codecs::png::FilterType::Sub,
    );
    enc.write_image(small.as_raw(), tw, th, image::ExtendedColorType::Rgba8)
        .ok()?;
    Some(Pic {
        path: path.to_owned(),
        w: tw,
        h: th,
        at,
    })
}

fn private_file(path: &Path) -> std::io::Result<std::fs::File> {
    use std::os::unix::fs::OpenOptionsExt;
    std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use kurashi_compositor::{Window, Workspace};

    fn win(id: u64, ws: u64, focused: bool, title: &str) -> Window {
        Window {
            id,
            app_id: Some("a".into()),
            title: Some(title.into()),
            workspace_id: Some(ws),
            focused,
            floating: false,
            urgent: false,
        }
    }
    fn space(id: u64, output: &str, active: bool) -> Workspace {
        Workspace {
            id,
            idx: 1,
            name: None,
            output: Some(output.into()),
            focused: active,
            active,
            occupied: true,
            urgent: false,
        }
    }

    /// A title changes all the time: it is no reason for a still. Focus, a new window and a workspace switch are.
    #[test]
    fn only_what_shows_is_a_reason_for_a_still() {
        let mut s = CompositorState {
            workspaces: vec![space(1, "A", true), space(2, "A", false)],
            windows: vec![win(10, 1, true, "one"), win(11, 1, false, "x")],
            ..Default::default()
        };
        let k0 = keys(&s);
        s.windows[0].title = Some("two".into());
        assert_eq!(keys(&s), k0);
        s.windows[0].focused = false;
        s.windows[1].focused = true;
        assert_ne!(keys(&s), k0);
        let k1 = keys(&s);
        s.windows.push(win(12, 1, false, "new"));
        assert_ne!(keys(&s), k1);
        let k2 = keys(&s);
        s.workspaces[0].active = false;
        s.workspaces[1].active = true;
        assert_ne!(keys(&s), k2);
    }

    #[test]
    fn the_column_order_is_niris_floating_last() {
        let g = |id, col: Option<(usize, usize)>| WindowGeom {
            id,
            workspace: Some(4),
            column: col,
            tile: (1.0, 1.0),
            window: (1.0, 1.0),
            offset_in_tile: (0.0, 0.0),
            floating_at: None,
            active: false,
        };
        let o = order_of(&[
            g(5, Some((2, 1))),
            g(6, None),
            g(7, Some((1, 2))),
            g(8, Some((1, 1))),
        ]);
        assert_eq!(o[&4], vec![8, 7, 5, 6]);
    }

    #[test]
    fn a_gone_window_loses_its_picture() {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("w.png");
        std::fs::write(&path, b"x").unwrap();
        let mut p = Pics::default();
        p.windows.insert(
            9,
            Pic {
                path: path.clone(),
                w: 1,
                h: 1,
                at: 0,
            },
        );
        assert!(p.prune(&CompositorState::default()));
        assert!(!path.exists());
        assert!(
            !p.document()["windows"]
                .as_object()
                .unwrap()
                .contains_key("9")
        );
    }

    #[test]
    fn the_document_says_what_it_has() {
        let mut p = Pics {
            available: true,
            ..Pics::default()
        };
        p.order.insert(3, vec![1, 2]);
        p.windows.insert(
            1,
            Pic {
                path: "/x/w.png".into(),
                w: 10,
                h: 5,
                at: 7,
            },
        );
        assert_eq!(
            p.document(),
            json!({"available": true,
                   "windows": {"1": {"path": "/x/w.png", "w": 10, "h": 5, "at": 7}},
                   "workspaces": {"3": {"still": null, "windows": [1, 2]}}})
        );
    }

    #[tokio::test]
    async fn refresh_without_a_subscriber_does_nothing() {
        let p = PreviewsProvider::new(Target {
            kind: kurashi_compositor::any::Kind::Niri,
            path: "/nonexistent".into(),
        });
        let mut actions = ActionRegistry::default();
        p.register_actions(&mut actions);
        actions
            .invoke("preview.refresh", Value::Null)
            .await
            .unwrap();
        assert!(
            actions
                .invoke("preview.refresh", json!({"output": 3}))
                .await
                .is_err()
        );
    }
}
