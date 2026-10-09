//! `org.freedesktop.Notifications` server (spec 1.2) as a library, plus the `svc.notifications`
//! document. The daemon owns notification state; the frontend renders toasts + the center from it.
//!
//! Ma (idle = silent): no ticking. One task sleeps until the earliest toast deadline and is
//! re-armed (via `Notify`) only when a mutation changes the deadline set.

mod image;
mod markup;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use serde_json::{Value as Json, json};
use tokio::sync::Notify;
use tokio::time::Instant;
use zbus::Connection;
use zbus::zvariant::Value;

pub use kurashi_services::DocSink;

const PATH: &str = "/org/freedesktop/Notifications";
const IFACE: &str = "org.freedesktop.Notifications";

/// Reasons from the spec's `NotificationClosed` signal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloseReason {
    Expired = 1,
    Dismissed = 2,
    Closed = 3,
    Undefined = 4,
}

#[derive(Clone, Debug)]
pub struct NotifyConfig {
    /// Request `org.freedesktop.Notifications`. Off in tests and when another daemon owns it.
    pub claim_name: bool,
    /// Max stored notifications (oldest dropped first).
    pub history_max: usize,
    /// Do-not-disturb at startup: non-critical notifications are stored but never toast.
    pub dnd: bool,
    /// Default toast time per urgency when the client sends -1; 0 = never expires.
    pub timeout_low_ms: u32,
    pub timeout_normal_ms: u32,
    pub timeout_critical_ms: u32,
    /// Where decoded image hints are cached as PNG.
    pub cache_dir: PathBuf,
}

impl NotifyConfig {
    pub fn new(cache_dir: PathBuf) -> Self {
        Self {
            claim_name: true,
            history_max: 200,
            dnd: false,
            timeout_low_ms: 3000,
            timeout_normal_ms: 5000,
            timeout_critical_ms: 0,
            cache_dir,
        }
    }
}

struct Item {
    id: u32,
    app_name: String,
    app_icon: String,
    summary: String,
    body: String,
    actions: Vec<(String, String)>,
    urgency: u8,
    category: Option<String>,
    desktop_entry: Option<String>,
    image: Option<String>,
    time_ms: u64,
    read: bool,
    showing: bool,
    resident: bool,
    transient: bool,
    deadline: Option<Instant>,
    expires_at_ms: Option<u64>,
}

struct State {
    next_id: u32,
    dnd: bool,
    /// Newest first.
    items: Vec<Item>,
    last_doc: Option<Json>,
}

struct Core {
    conn: Connection,
    cfg: NotifyConfig,
    sink: Arc<dyn DocSink>,
    wake: Notify,
    state: Mutex<State>,
}

/// A signal to emit after the state lock is released.
enum Sig {
    Closed(u32, CloseReason),
    Action(u32, String),
    Replied(u32, String),
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

impl Core {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap()
    }

    /// Rebuild the document and hand it to the sink if it changed. Called with the lock held so
    /// the sink sees documents in mutation order.
    fn publish(&self, st: &mut State) {
        let doc = doc(st);
        if st.last_doc.as_ref() != Some(&doc) {
            st.last_doc = Some(doc.clone());
            self.sink.set(doc);
        }
        self.wake.notify_one();
    }

    async fn emit(&self, sigs: Vec<Sig>) {
        for s in sigs {
            let r = match s {
                Sig::Closed(id, why) => {
                    self.conn
                        .emit_signal(
                            None::<&str>,
                            PATH,
                            IFACE,
                            "NotificationClosed",
                            &(id, why as u32),
                        )
                        .await
                }
                Sig::Action(id, key) => {
                    self.conn
                        .emit_signal(None::<&str>, PATH, IFACE, "ActionInvoked", &(id, key))
                        .await
                }
                Sig::Replied(id, text) => {
                    self.conn
                        .emit_signal(
                            None::<&str>,
                            PATH,
                            IFACE,
                            "NotificationReplied",
                            &(id, text),
                        )
                        .await
                }
            };
            if let Err(e) = r {
                tracing::debug!("notification signal failed: {e}");
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: &str,
        actions: Vec<String>,
        hints: &HashMap<String, Value<'_>>,
        expire_timeout: i32,
    ) -> (u32, Vec<Sig>) {
        let hint_str = |k: &str| match hints.get(k) {
            Some(Value::Str(s)) => Some(s.to_string()),
            _ => None,
        };
        let hint_bool = |k: &str| matches!(hints.get(k), Some(Value::Bool(true)));
        let urgency = match hints.get("urgency") {
            Some(Value::U8(u)) => (*u).min(2),
            _ => 1,
        };
        let image = ["image-data", "image_data", "icon_data"]
            .iter()
            .find_map(|k| hints.get(*k))
            .and_then(image::RawImage::from_value)
            .and_then(|i| i.cache(&self.cfg.cache_dir))
            .map(|p| p.to_string_lossy().into_owned())
            .or_else(|| {
                let p = hint_str("image-path").or_else(|| hint_str("image_path"))?;
                let p = p.strip_prefix("file://").unwrap_or(&p).to_owned();
                p.starts_with('/').then_some(p)
            });
        let actions = actions
            .chunks_exact(2)
            .map(|c| (c[0].clone(), c[1].clone()))
            .collect();
        let transient = hint_bool("transient");

        let mut st = self.lock();
        let show = urgency == 2 || !st.dnd;
        let timeout_ms = match expire_timeout {
            0 => 0,
            t if t > 0 => t as u32,
            _ => match urgency {
                0 => self.cfg.timeout_low_ms,
                1 => self.cfg.timeout_normal_ms,
                _ => self.cfg.timeout_critical_ms,
            },
        };
        let now = Instant::now();
        let deadline =
            (show && timeout_ms > 0).then(|| now + Duration::from_millis(timeout_ms.into()));
        let t = now_ms();
        let existing = st.items.iter().position(|i| i.id == replaces_id);
        let id = if existing.is_some() {
            replaces_id
        } else {
            loop {
                st.next_id = st.next_id.checked_add(1).unwrap_or(1);
                if !st.items.iter().any(|i| i.id == st.next_id) {
                    break st.next_id;
                }
            }
        };
        let item = Item {
            id,
            app_name,
            app_icon,
            summary,
            body: markup::sanitize(body),
            actions,
            urgency,
            category: hint_str("category"),
            desktop_entry: hint_str("desktop-entry"),
            image,
            time_ms: t,
            read: false,
            showing: show,
            resident: hint_bool("resident"),
            transient,
            deadline,
            expires_at_ms: deadline.map(|_| t + u64::from(timeout_ms)),
        };
        if let Some(p) = existing {
            st.items.remove(p);
        }
        // Transient + suppressed by DND: never shown, so never stored.
        if !(transient && !show) {
            st.items.insert(0, item);
        }
        let mut sigs = vec![];
        while st.items.len() > self.cfg.history_max.max(1) {
            let old = st.items.pop().unwrap();
            if old.showing {
                sigs.push(Sig::Closed(old.id, CloseReason::Undefined));
            }
        }
        self.publish(&mut st);
        (id, sigs)
    }

    /// Remove `id` entirely (toast and history).
    fn close(&self, id: u32, why: CloseReason) -> Vec<Sig> {
        let mut st = self.lock();
        let Some(p) = st.items.iter().position(|i| i.id == id) else {
            return vec![];
        };
        st.items.remove(p);
        self.publish(&mut st);
        vec![Sig::Closed(id, why)]
    }

    /// After an action/reply: resident items only hide their toast, others close (reason 2).
    fn after_interaction(&self, id: u32) -> Vec<Sig> {
        let mut st = self.lock();
        let Some(i) = st.items.iter_mut().find(|i| i.id == id) else {
            return vec![];
        };
        if i.resident {
            i.showing = false;
            i.deadline = None;
            i.read = true;
            self.publish(&mut st);
            return vec![];
        }
        drop(st);
        self.close(id, CloseReason::Dismissed)
    }

    fn expire_due(&self) -> Vec<Sig> {
        let mut st = self.lock();
        let now = Instant::now();
        let mut sigs = vec![];
        let mut gone = vec![];
        for i in st.items.iter_mut() {
            if i.showing && i.deadline.is_some_and(|d| d <= now) {
                i.showing = false;
                i.deadline = None;
                sigs.push(Sig::Closed(i.id, CloseReason::Expired));
                if i.transient {
                    gone.push(i.id);
                }
            }
        }
        if !sigs.is_empty() {
            st.items.retain(|i| !gone.contains(&i.id));
            self.publish(&mut st);
        }
        sigs
    }

    fn next_deadline(&self) -> Option<Instant> {
        self.lock()
            .items
            .iter()
            .filter(|i| i.showing)
            .filter_map(|i| i.deadline)
            .min()
    }
}

fn doc(st: &State) -> Json {
    let items: Vec<Json> = st
        .items
        .iter()
        .map(|i| {
            let mut o = json!({
                "id": i.id,
                "app_name": i.app_name,
                "app_icon": i.app_icon,
                "summary": i.summary,
                "body": i.body,
                "actions": i.actions.iter().map(|(k, l)| json!({"key": k, "label": l})).collect::<Vec<_>>(),
                "urgency": urgency_name(i.urgency),
                "time": i.time_ms,
                "read": i.read,
                "resident": i.resident,
                "transient": i.transient,
            });
            // Documents never contain null (PROTOCOL §3): absent stays absent.
            let m = o.as_object_mut().unwrap();
            if let Some(v) = &i.category {
                m.insert("category".into(), json!(v));
            }
            if let Some(v) = &i.desktop_entry {
                m.insert("desktop_entry".into(), json!(v));
            }
            if let Some(v) = &i.image {
                m.insert("image".into(), json!(v));
            }
            if let (Some(v), true) = (i.expires_at_ms, i.showing) {
                m.insert("expires_at".into(), json!(v));
            }
            o
        })
        .collect();
    json!({
        "dnd": st.dnd,
        "unread": st.items.iter().filter(|i| !i.read).count(),
        "toasts": st.items.iter().filter(|i| i.showing).map(|i| i.id).collect::<Vec<_>>(),
        "items": items,
    })
}

struct Iface(Arc<Core>);

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Iface {
    fn get_capabilities(&self) -> Vec<String> {
        [
            "body",
            "body-markup",
            "actions",
            "icon-static",
            "persistence",
            "inline-reply",
        ]
        .map(String::from)
        .to_vec()
    }

    #[allow(clippy::too_many_arguments)]
    async fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: HashMap<String, Value<'_>>,
        expire_timeout: i32,
    ) -> u32 {
        let (id, sigs) = self.0.notify(
            app_name,
            replaces_id,
            app_icon,
            summary,
            &body,
            actions,
            &hints,
            expire_timeout,
        );
        self.0.emit(sigs).await;
        id
    }

    async fn close_notification(&self, id: u32) {
        let sigs = self.0.close(id, CloseReason::Closed);
        self.0.emit(sigs).await;
    }

    fn get_server_information(&self) -> (String, String, String, String) {
        (
            "kurashi".into(),
            "kurashi-shell".into(),
            env!("CARGO_PKG_VERSION").into(),
            "1.2".into(),
        )
    }
}

/// User-side operations, driven by frontend intents.
#[derive(Clone)]
pub struct Commands(Arc<Core>);

impl Commands {
    pub async fn invoke_action(&self, id: u32, key: &str) {
        let known = self
            .0
            .lock()
            .items
            .iter()
            .any(|i| i.id == id && i.actions.iter().any(|(k, _)| k == key));
        if !known {
            return;
        }
        let mut sigs = vec![Sig::Action(id, key.to_owned())];
        sigs.extend(self.0.after_interaction(id));
        self.0.emit(sigs).await;
    }

    pub async fn reply(&self, id: u32, text: &str) {
        if !self.0.lock().items.iter().any(|i| i.id == id) {
            return;
        }
        let mut sigs = vec![Sig::Replied(id, text.to_owned())];
        sigs.extend(self.0.after_interaction(id));
        self.0.emit(sigs).await;
    }

    pub async fn dismiss(&self, id: u32) {
        let sigs = self.0.close(id, CloseReason::Dismissed);
        self.0.emit(sigs).await;
    }

    pub async fn dismiss_all(&self) {
        let ids: Vec<u32> = self.0.lock().items.iter().map(|i| i.id).collect();
        let mut sigs = vec![];
        for id in ids {
            sigs.extend(self.0.close(id, CloseReason::Dismissed));
        }
        self.0.emit(sigs).await;
    }

    pub fn mark_read(&self, id: u32) {
        let mut st = self.0.lock();
        if let Some(i) = st.items.iter_mut().find(|i| i.id == id) {
            i.read = true;
            self.0.publish(&mut st);
        }
    }

    pub fn mark_all_read(&self) {
        let mut st = self.0.lock();
        st.items.iter_mut().for_each(|i| i.read = true);
        self.0.publish(&mut st);
    }

    /// Affects only notifications arriving afterwards; toasts already showing run out normally.
    pub fn set_dnd(&self, on: bool) {
        let mut st = self.0.lock();
        st.dnd = on;
        self.0.publish(&mut st);
    }
}

/// Drop = stop: aborts the expiry timer, unexports the interface and releases the name.
pub struct NotifyHandle {
    timer: tokio::task::JoinHandle<()>,
    core: Arc<Core>,
}

impl Drop for NotifyHandle {
    fn drop(&mut self) {
        self.timer.abort();
        let core = self.core.clone();
        if let Ok(rt) = tokio::runtime::Handle::try_current() {
            rt.spawn(async move {
                let _ = core.conn.object_server().remove::<Iface, _>(PATH).await;
                if core.cfg.claim_name {
                    let _ = core.conn.release_name(IFACE).await;
                }
            });
        }
    }
}

pub struct Server;

impl Server {
    /// Export the interface on `conn` and (if `cfg.claim_name`) request the well-known name.
    /// The sink receives the initial (empty) document immediately.
    pub async fn serve(
        conn: Connection,
        sink: Arc<dyn DocSink>,
        cfg: NotifyConfig,
    ) -> Result<(NotifyHandle, Commands)> {
        let claim = cfg.claim_name;
        let core = Arc::new(Core {
            conn: conn.clone(),
            sink,
            wake: Notify::new(),
            state: Mutex::new(State {
                next_id: 0,
                dnd: cfg.dnd,
                items: vec![],
                last_doc: None,
            }),
            cfg,
        });
        {
            let mut st = core.lock();
            core.publish(&mut st);
        }
        conn.object_server().at(PATH, Iface(core.clone())).await?;
        if claim {
            conn.request_name(IFACE).await?;
        }
        let c = core.clone();
        let timer = tokio::spawn(async move {
            loop {
                match c.next_deadline() {
                    Some(d) => {
                        tokio::select! {
                            () = tokio::time::sleep_until(d) => {
                                let sigs = c.expire_due();
                                c.emit(sigs).await;
                            }
                            () = c.wake.notified() => {}
                        }
                    }
                    None => c.wake.notified().await,
                }
            }
        });
        Ok((
            NotifyHandle {
                timer,
                core: core.clone(),
            },
            Commands(core),
        ))
    }
}

fn urgency_name(u: u8) -> &'static str {
    ["low", "normal", "critical"][usize::from(u.min(2))]
}
