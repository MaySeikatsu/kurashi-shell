//! `svc.tray`: StatusNotifierItem tray, the KDE protocol every tray host speaks.
//!
//! `org.kde.StatusNotifierWatcher` is claimed with DoNotQueue. If we get it we are the watcher and
//! host ourselves. If someone else holds it we host theirs and never steal the name; when that
//! watcher goes away we try to take over. Items are tracked from signals only (NameOwnerChanged,
//! the item's `NewXxx` and `PropertiesChanged`, the foreign watcher's Registered/Unregistered), so
//! nothing polls (Ma: idle = silent). Dropping the [`ServiceHandle`] stops the task and releases
//! the names we hold.

mod item;
mod menu;

pub use kurashi_services::DocSink;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use futures_util::StreamExt;
use futures_util::stream::SelectAll;
use serde::Serialize;
use serde_json::{Value, json};
use tokio::sync::mpsc;
use tokio::task::{JoinHandle, JoinSet};
use zbus::message::{Header, Message, Type as MsgType};
use zbus::names::BusName;
use zbus::zvariant::{DynamicType, ObjectPath, Value as ZValue};
use zbus::{Connection, MatchRule, MessageStream};

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM_IFACE: &str = "org.kde.StatusNotifierItem";
const ITEM_PATH: &str = "/StatusNotifierItem";
const PROPS_IFACE: &str = "org.freedesktop.DBus.Properties";
/// Item and menu calls are best-effort. A stuck item must not wedge the tray or an intent.
const CALL_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Role {
    /// No watcher on the bus right now.
    Idle,
    /// We hold the watcher name and serve the interface.
    Owner,
    /// Another watcher holds the name; we track through it.
    Host,
}

struct Item {
    /// Registry key as watchers publish it: `<bus><path>`.
    id: String,
    /// Bus name as registered, well-known or unique. Kept to notice when it goes away.
    bus: String,
    /// Connection that owns the item now; its signals carry this as sender.
    unique: String,
    path: String,
    /// Last successful read. Items without one stay out of the document.
    view: Option<item::View>,
    /// A read is in flight. Signals arriving meanwhile only set `dirty`, so a noisy item costs
    /// one read at a time, not one per signal.
    busy: bool,
    dirty: bool,
}

struct State {
    role: Role,
    /// Name we hold as a host, or our unique name when the well-known one was taken.
    host: String,
    host_claimed: bool,
    /// Host mode: the watcher whose registry signals we trust.
    watcher: Option<String>,
    items: Vec<Item>,
    last_doc: Option<Value>,
}

struct Shared {
    conn: Connection,
    sink: Arc<dyn DocSink>,
    state: Mutex<State>,
    tx: mpsc::UnboundedSender<Msg>,
}

/// Work for the actor, from the watcher interface or from finished reads.
enum Msg {
    /// `RegisterStatusNotifierItem` from a client (owner mode).
    Register {
        service: String,
        sender: Option<String>,
    },
    /// A read finished. `None` means the item did not answer. The unique name pins the result to
    /// the owner it was read from, so it cannot land on a successor registered under the same id.
    Read {
        id: String,
        unique: String,
        view: Option<item::View>,
    },
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap()
    }

    /// Rebuild the document and hand it over if it changed. Called under the lock, so the sink
    /// sees documents in mutation order.
    fn publish(&self, st: &mut State) {
        let doc = doc(st);
        if st.last_doc.as_ref() != Some(&doc) {
            st.last_doc = Some(doc.clone());
            self.sink.set(doc);
        }
    }

    /// Unexport the watcher and release what we hold. Runs after `Drop`, so it is best-effort.
    async fn release(&self) {
        let (owner, host, claimed) = {
            let st = self.lock();
            (st.role == Role::Owner, st.host.clone(), st.host_claimed)
        };
        let _ = self
            .conn
            .object_server()
            .remove::<Watcher, _>(WATCHER_PATH)
            .await;
        if owner {
            let _ = self.conn.release_name(WATCHER).await;
        }
        if claimed {
            let _ = self.conn.release_name(host.as_str()).await;
        }
    }
}

fn doc(st: &State) -> Value {
    let items: Vec<Value> = st
        .items
        .iter()
        .filter_map(|i| {
            let v = i.view.as_ref()?;
            let mut o = json!({
                "id": i.id,
                "title": v.title,
                "icon_name": v.icon_name,
                "status": v.status,
                "has_menu": v.menu.is_some(),
            });
            let m = o.as_object_mut()?;
            if let Some(px) = &v.icon {
                m.insert(
                    "icon_pixmap".into(),
                    json!({"w": px.w, "h": px.h, "png_base64": px.png_base64}),
                );
            }
            if let Some(t) = &v.tooltip {
                m.insert("tooltip".into(), json!(t));
            }
            Some(o)
        })
        .collect();
    json!({"available": st.role != Role::Idle, "items": items})
}

/// The watcher interface. Served only while we own the name; the method just queues the work.
struct Watcher(Arc<Shared>);

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: String,
        #[zbus(header)] header: Header<'_>,
    ) {
        let sender = header.sender().map(|s| s.as_str().to_owned());
        let _ = self.0.tx.send(Msg::Register { service, sender });
    }

    /// We are a host ourselves, so a second host has nothing to track.
    fn register_status_notifier_host(&self, _service: String) {}

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.0.lock().items.iter().map(|i| i.id.clone()).collect()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property(emits_changed_signal = "const"))]
    fn protocol_version(&self) -> i32 {
        0
    }
}

/// Owns the event loop: one task, so every mutation happens in one order.
struct Actor {
    shared: Arc<Shared>,
    rx: mpsc::UnboundedReceiver<Msg>,
    tasks: JoinSet<()>,
}

impl Actor {
    async fn run(mut self, mut events: SelectAll<MessageStream>) {
        loop {
            tokio::select! {
                ev = events.next() => match ev {
                    Some(Ok(msg)) => self.on_signal(&msg).await,
                    Some(Err(e)) => tracing::debug!("tray: signal stream error: {e}"),
                    None => break,
                },
                msg = self.rx.recv() => match msg {
                    Some(msg) => self.on_msg(msg).await,
                    None => break,
                },
                Some(_) = self.tasks.join_next(), if !self.tasks.is_empty() => {}
            }
        }
    }

    /// Claim the watcher name, or host the one that already holds it.
    async fn establish(&mut self) {
        if self.try_own().await {
            return;
        }
        match name_owner(&self.shared.conn, WATCHER).await {
            Some(watcher) => self.become_host(watcher).await,
            None => {
                let mut st = self.shared.lock();
                st.role = Role::Idle;
                self.shared.publish(&mut st);
            }
        }
    }

    async fn try_own(&mut self) -> bool {
        let conn = self.shared.conn.clone();
        // Export before the name is visible, so an item that races in finds the object.
        if let Err(e) = conn
            .object_server()
            .at(WATCHER_PATH, Watcher(self.shared.clone()))
            .await
        {
            tracing::warn!(error = %e, "tray: cannot export the watcher");
            return false;
        }
        let flags = zbus::fdo::RequestNameFlags::DoNotQueue.into();
        match conn.request_name_with_flags(WATCHER, flags).await {
            Ok(
                zbus::fdo::RequestNameReply::PrimaryOwner
                | zbus::fdo::RequestNameReply::AlreadyOwner,
            ) => {
                {
                    let mut st = self.shared.lock();
                    st.role = Role::Owner;
                    st.watcher = None;
                    self.shared.publish(&mut st);
                }
                // We host our own watcher, so say so the way a real host would.
                let _ = conn
                    .emit_signal(
                        None::<&str>,
                        WATCHER_PATH,
                        WATCHER,
                        "StatusNotifierHostRegistered",
                        &(),
                    )
                    .await;
                true
            }
            other => {
                let _ = conn
                    .object_server()
                    .remove::<Watcher, _>(WATCHER_PATH)
                    .await;
                tracing::debug!(?other, "tray: watcher name held elsewhere; hosting it");
                false
            }
        }
    }

    /// Someone else holds the watcher: register as its host and adopt what it already tracks.
    async fn become_host(&mut self, watcher: String) {
        let conn = self.shared.conn.clone();
        let host = {
            let mut st = self.shared.lock();
            st.role = Role::Host;
            st.watcher = Some(watcher);
            self.shared.publish(&mut st);
            st.host.clone()
        };
        if let Err(e) = call_timed(
            &conn,
            WATCHER,
            WATCHER_PATH,
            WATCHER,
            "RegisterStatusNotifierHost",
            &(host,),
        )
        .await
        {
            tracing::debug!(error = %e, "tray: watcher refused the host registration");
        }
        // Signals for later registrations are already subscribed, so no change can slip between
        // this read and the subscription.
        let known = item::get_all(&conn, WATCHER, WATCHER_PATH, WATCHER)
            .await
            .and_then(|p| item::prop::<Vec<String>>(&p, "RegisteredStatusNotifierItems"))
            .unwrap_or_default();
        for id in known {
            self.track(&id, None, false).await;
        }
    }

    async fn on_msg(&mut self, msg: Msg) {
        match msg {
            Msg::Register { service, sender } => {
                self.track(&service, sender.as_deref(), true).await
            }
            Msg::Read { id, unique, view } => self.on_read(id, unique, view),
        }
    }

    /// Start tracking one item. `service` is what a client sent, or `<bus><path>` from a watcher.
    async fn track(&mut self, service: &str, sender: Option<&str>, announce: bool) {
        let Some((bus, path)) = split_service(service, sender) else {
            return;
        };
        if BusName::try_from(bus.as_str()).is_err() || ObjectPath::try_from(path.as_str()).is_err()
        {
            return;
        }
        let id = format!("{bus}{path}");
        // Signals come from the connection that owns the item, so resolve it once and match on it.
        let unique = if bus.starts_with(':') {
            bus.clone()
        } else {
            match name_owner(&self.shared.conn, &bus).await {
                Some(u) => u,
                None => return,
            }
        };
        let replaced = {
            let mut st = self.shared.lock();
            let stale = st.items.iter().position(|i| i.id == id);
            if stale.is_some_and(|p| st.items[p].unique == unique) {
                return;
            }
            // Same name under a new owner: the old entry goes, and its pending read is ignored
            // by `on_read` because the unique name no longer matches.
            let replaced = stale.map(|p| st.items.remove(p)).is_some();
            st.items.push(Item {
                id: id.clone(),
                bus,
                unique: unique.clone(),
                path: path.clone(),
                view: None,
                busy: true,
                dirty: false,
            });
            self.shared.publish(&mut st);
            replaced
        };
        self.read(id.clone(), unique, path);
        if announce {
            let mut changes = vec![];
            if replaced {
                changes.push(("StatusNotifierItemUnregistered", id.clone()));
            }
            changes.push(("StatusNotifierItemRegistered", id));
            self.announce(changes).await;
        }
    }

    fn read(&mut self, id: String, unique: String, path: String) {
        let (conn, tx) = (self.shared.conn.clone(), self.shared.tx.clone());
        self.tasks.spawn(async move {
            let view = item::read(&conn, &unique, &path).await;
            let _ = tx.send(Msg::Read { id, unique, view });
        });
    }

    fn on_read(&mut self, id: String, unique: String, view: Option<item::View>) {
        let mut st = self.shared.lock();
        let Some(i) = st
            .items
            .iter_mut()
            .find(|i| i.id == id && i.unique == unique)
        else {
            return;
        };
        if view.is_some() {
            i.view = view;
        }
        let again = if i.dirty {
            i.dirty = false;
            Some((i.unique.clone(), i.path.clone()))
        } else {
            i.busy = false;
            None
        };
        self.shared.publish(&mut st);
        drop(st);
        if let Some((unique, path)) = again {
            self.read(id, unique, path);
        }
    }

    async fn on_signal(&mut self, msg: &Message) {
        let h = msg.header();
        let member = h.member().map_or("", |m| m.as_str());
        let iface = h.interface().map_or("", |i| i.as_str());
        match (iface, member) {
            ("org.freedesktop.DBus", "NameOwnerChanged") => {
                if let Ok((name, old, new)) = msg.body().deserialize::<(String, String, String)>() {
                    self.on_owner_changed(&name, &old, &new).await;
                }
            }
            (WATCHER, "StatusNotifierItemRegistered" | "StatusNotifierItemUnregistered") => {
                let sender = h.sender().map(|s| s.as_str().to_owned());
                let trusted = {
                    let st = self.shared.lock();
                    st.role == Role::Host && st.watcher.as_deref() == sender.as_deref()
                };
                let Ok(id) = msg.body().deserialize::<String>() else {
                    return;
                };
                if !trusted {
                    return;
                }
                if member == "StatusNotifierItemRegistered" {
                    self.track(&id, None, false).await;
                } else {
                    self.remove_items(|i| i.id == id);
                }
            }
            (ITEM_IFACE, _) | (PROPS_IFACE, "PropertiesChanged") => {
                let sender = h.sender().map(|s| s.as_str().to_owned());
                let path = h.path().map(|p| p.as_str().to_owned());
                if let (Some(sender), Some(path)) = (sender, path) {
                    self.on_item_change(&sender, &path);
                }
            }
            _ => {}
        }
    }

    /// Any item signal means "re-read this item". Coalesced: one read in flight at a time.
    fn on_item_change(&mut self, unique: &str, path: &str) {
        let mut st = self.shared.lock();
        let Some(i) = st
            .items
            .iter_mut()
            .find(|i| i.unique == unique && i.path == path)
        else {
            return;
        };
        if i.busy {
            i.dirty = true;
            return;
        }
        i.busy = true;
        let (id, u, p) = (i.id.clone(), i.unique.clone(), i.path.clone());
        drop(st);
        self.read(id, u, p);
    }

    async fn on_owner_changed(&mut self, name: &str, old: &str, new: &str) {
        if name == WATCHER {
            let role = self.shared.lock().role;
            if role != Role::Owner {
                // The watcher went away or was replaced. What it tracked went with it.
                {
                    let mut st = self.shared.lock();
                    st.items.clear();
                    st.role = Role::Idle;
                    st.watcher = None;
                    self.shared.publish(&mut st);
                }
                self.establish().await;
            }
            return;
        }
        // The owner an item was registered under let go of its name, or its own connection closed.
        // Matching the old owner keeps a successor's re-registration alive when this event arrives
        // late; a release of some other name by the same connection does not touch the item.
        let gone = self.remove_items(|i| {
            (i.bus == name && i.unique == old) || (i.unique == name && new.is_empty())
        });
        self.announce(
            gone.into_iter()
                .map(|id| ("StatusNotifierItemUnregistered", id))
                .collect(),
        )
        .await;
    }

    /// Drop the items matching `gone` and publish. Returns their ids.
    fn remove_items(&self, gone: impl Fn(&Item) -> bool) -> Vec<String> {
        let mut st = self.shared.lock();
        let mut removed = vec![];
        st.items.retain(|i| {
            let drop_it = gone(i);
            if drop_it {
                removed.push(i.id.clone());
            }
            !drop_it
        });
        if !removed.is_empty() {
            self.shared.publish(&mut st);
        }
        removed
    }

    /// Owner only: tell listeners what changed in the registry, as signals and as the property.
    async fn announce(&self, changes: Vec<(&str, String)>) {
        if changes.is_empty() || self.shared.lock().role != Role::Owner {
            return;
        }
        let conn = &self.shared.conn;
        for (signal, id) in changes {
            let _ = conn
                .emit_signal(None::<&str>, WATCHER_PATH, WATCHER, signal, &(id,))
                .await;
        }
        let ids: Vec<String> = self
            .shared
            .lock()
            .items
            .iter()
            .map(|i| i.id.clone())
            .collect();
        let mut changed: HashMap<&str, ZValue<'_>> = HashMap::new();
        changed.insert("RegisteredStatusNotifierItems", ZValue::from(ids));
        let _ = conn
            .emit_signal(
                None::<&str>,
                WATCHER_PATH,
                PROPS_IFACE,
                "PropertiesChanged",
                &(WATCHER, changed, Vec::<&str>::new()),
            )
            .await;
    }
}

/// Stop: aborting the actor also aborts the reads it spawned (its `JoinSet` goes with it). Names
/// are released on the runtime, so this is best-effort and returns at once.
pub struct ServiceHandle {
    task: JoinHandle<()>,
    shared: Arc<Shared>,
}

impl Drop for ServiceHandle {
    fn drop(&mut self) {
        self.task.abort();
        if let Ok(rt) = tokio::runtime::Handle::try_current() {
            let shared = self.shared.clone();
            rt.spawn(async move { shared.release().await });
        }
    }
}

/// Intents from the frontend. Each targets one item by its `id`; an unknown id does nothing.
#[derive(Clone)]
pub struct Commands(Arc<Shared>);

impl Commands {
    pub async fn activate(&self, id: &str, x: i32, y: i32) -> zbus::Result<()> {
        self.item_call(id, "Activate", &(x, y)).await
    }

    pub async fn secondary_activate(&self, id: &str, x: i32, y: i32) -> zbus::Result<()> {
        self.item_call(id, "SecondaryActivate", &(x, y)).await
    }

    /// `orientation` is `"horizontal"` or `"vertical"`, spelled as the spec does.
    pub async fn scroll(&self, id: &str, delta: i32, orientation: &str) -> zbus::Result<()> {
        if !matches!(orientation, "horizontal" | "vertical") {
            return Err(zbus::Error::Failure(format!(
                "unknown scroll orientation {orientation:?}"
            )));
        }
        self.item_call(id, "Scroll", &(delta, orientation)).await
    }

    /// The item's menu as a tree of `{id, label?, separator?, enabled, icon_name?, toggle?,
    /// checked?, children?}`. An item without a menu gives an empty root, not an error.
    pub async fn menu(&self, id: &str) -> zbus::Result<Value> {
        let Some(target) = self.target(id) else {
            return Ok(menu::root(vec![]));
        };
        match target.menu {
            Some(path) => menu::fetch(&self.0.conn, &target.unique, &path).await,
            None => Ok(menu::root(vec![])),
        }
    }

    /// dbusmenu `clicked` for one entry of the item's menu.
    pub async fn menu_event(&self, id: &str, item_id: i32) -> zbus::Result<()> {
        let Some(Target {
            unique,
            menu: Some(path),
            ..
        }) = self.target(id)
        else {
            return Ok(());
        };
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_secs() as u32);
        call_timed(
            &self.0.conn,
            &unique,
            &path,
            menu::IFACE,
            "Event",
            &(item_id, "clicked", ZValue::from(0i32), timestamp),
        )
        .await?;
        Ok(())
    }

    async fn item_call<B>(&self, id: &str, method: &str, body: &B) -> zbus::Result<()>
    where
        B: Serialize + DynamicType,
    {
        let Some(target) = self.target(id) else {
            return Ok(());
        };
        call_timed(
            &self.0.conn,
            &target.unique,
            &target.path,
            ITEM_IFACE,
            method,
            body,
        )
        .await?;
        Ok(())
    }

    fn target(&self, id: &str) -> Option<Target> {
        self.0
            .lock()
            .items
            .iter()
            .find(|i| i.id == id)
            .map(|i| Target {
                unique: i.unique.clone(),
                path: i.path.clone(),
                menu: i.view.as_ref().and_then(|v| v.menu.clone()),
            })
    }
}

struct Target {
    unique: String,
    path: String,
    menu: Option<String>,
}

/// Start the tray on `conn`. Returns once the role is settled: the watcher is served (or hosted),
/// and the sink has the first document. Hold the handle for as long as the tray should run.
pub async fn start(conn: Connection, sink: Arc<dyn DocSink>) -> Result<(ServiceHandle, Commands)> {
    // Subscribe before anything else, so nothing that happens during the first reads is lost.
    let events = watch(&conn).await?;
    let (host, host_claimed) = claim_host(&conn).await;
    let (tx, rx) = mpsc::unbounded_channel();
    let shared = Arc::new(Shared {
        conn,
        sink,
        state: Mutex::new(State {
            role: Role::Idle,
            host,
            host_claimed,
            watcher: None,
            items: vec![],
            last_doc: None,
        }),
        tx,
    });
    let mut actor = Actor {
        shared: shared.clone(),
        rx,
        tasks: JoinSet::new(),
    };
    // Settle the role before returning, so a caller's first registration cannot beat the export.
    actor.establish().await;
    let task = tokio::spawn(actor.run(events));
    Ok((
        ServiceHandle {
            task,
            shared: shared.clone(),
        },
        Commands(shared),
    ))
}

async fn watch(conn: &Connection) -> Result<SelectAll<MessageStream>> {
    let rules = [
        MatchRule::builder()
            .msg_type(MsgType::Signal)
            .sender("org.freedesktop.DBus")?
            .interface("org.freedesktop.DBus")?
            .member("NameOwnerChanged")?
            .build(),
        MatchRule::builder()
            .msg_type(MsgType::Signal)
            .interface(ITEM_IFACE)?
            .build(),
        MatchRule::builder()
            .msg_type(MsgType::Signal)
            .interface(PROPS_IFACE)?
            .member("PropertiesChanged")?
            .arg(0, ITEM_IFACE)?
            .build(),
        MatchRule::builder()
            .msg_type(MsgType::Signal)
            .interface(WATCHER)?
            .build(),
    ];
    let mut all = SelectAll::new();
    for rule in rules {
        all.push(MessageStream::for_match_rule(rule, conn, None).await?);
    }
    Ok(all)
}

/// Host name for `RegisterStatusNotifierHost`: the conventional `org.kde.StatusNotifierHost-<pid>`
/// when free, else our unique name. Never queues behind someone else.
async fn claim_host(conn: &Connection) -> (String, bool) {
    let name = format!("org.kde.StatusNotifierHost-{}", std::process::id());
    let flags = zbus::fdo::RequestNameFlags::DoNotQueue.into();
    match conn.request_name_with_flags(name.as_str(), flags).await {
        Ok(
            zbus::fdo::RequestNameReply::PrimaryOwner | zbus::fdo::RequestNameReply::AlreadyOwner,
        ) => (name, true),
        _ => (
            conn.unique_name()
                .map(|u| u.to_string())
                .unwrap_or_default(),
            false,
        ),
    }
}

/// `RegisterStatusNotifierItem` takes a path (the item lives on the sender), a bus name (item at
/// `/StatusNotifierItem`), or the watcher's own `<bus><path>` form.
fn split_service(service: &str, sender: Option<&str>) -> Option<(String, String)> {
    if service.starts_with('/') {
        return Some((sender?.to_owned(), service.to_owned()));
    }
    match service.find('/') {
        Some(i) => Some((service[..i].to_owned(), service[i..].to_owned())),
        None => Some((service.to_owned(), ITEM_PATH.to_owned())),
    }
}

async fn name_owner(conn: &Connection, name: &str) -> Option<String> {
    let proxy = zbus::fdo::DBusProxy::new(conn).await.ok()?;
    let name = BusName::try_from(name).ok()?;
    proxy.get_name_owner(name).await.ok().map(|u| u.to_string())
}

/// A method call that a misbehaving peer cannot hold forever.
async fn call_timed<B>(
    conn: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
    method: &str,
    body: &B,
) -> zbus::Result<Message>
where
    B: Serialize + DynamicType,
{
    match tokio::time::timeout(
        CALL_TIMEOUT,
        conn.call_method(Some(dest), path, Some(iface), method, body),
    )
    .await
    {
        Ok(reply) => reply,
        Err(_) => Err(zbus::Error::Failure(format!(
            "{method} on {dest} timed out"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn service_forms_resolve_to_bus_and_path() {
        assert_eq!(
            split_service("/Menu", Some(":1.7")),
            Some((":1.7".into(), "/Menu".into()))
        );
        assert_eq!(split_service("/Menu", None), None);
        assert_eq!(
            split_service("org.x.App", None),
            Some(("org.x.App".into(), "/StatusNotifierItem".into()))
        );
        assert_eq!(
            split_service(":1.9/StatusNotifierItem", None),
            Some((":1.9".into(), "/StatusNotifierItem".into()))
        );
    }
}
