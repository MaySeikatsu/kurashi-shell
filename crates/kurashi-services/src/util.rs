use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use futures_util::stream::SelectAll;
use serde_json::Value;
use zbus::message::Type as MsgType;
use zbus::zvariant::OwnedValue;
use zbus::{Connection, MatchRule, MessageStream};

/// Receives the full document value on every change. The hub diffs; we never send patches.
pub trait DocSink: Send + Sync + 'static {
    fn set(&self, doc: Value);
}

/// Drop = stop: aborts the service task (which drops its signal streams and match rules).
#[derive(Default)]
pub struct ServiceHandle {
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl ServiceHandle {
    pub(crate) fn new(task: tokio::task::JoinHandle<()>) -> Self {
        Self { tasks: vec![task] }
    }
    /// A handle with nothing running (read-on-demand services).
    pub(crate) fn inert() -> Self {
        Self::default()
    }
}

impl Drop for ServiceHandle {
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
    }
}

/// Sink wrapper that skips documents identical to the previous one, so noisy signals
/// (e.g. wifi strength jitter, unrelated PropertiesChanged) do not wake the hub.
pub(crate) struct Emitter {
    sink: Arc<dyn DocSink>,
    last: Mutex<Option<Value>>,
}

impl Emitter {
    pub(crate) fn new(sink: Arc<dyn DocSink>) -> Arc<Self> {
        Arc::new(Self {
            sink,
            last: Mutex::new(None),
        })
    }
    pub(crate) fn emit(&self, doc: Value) {
        let mut last = self.last.lock().unwrap();
        if last.as_ref() == Some(&doc) {
            return;
        }
        *last = Some(doc.clone());
        drop(last);
        self.sink.set(doc);
    }
}

pub(crate) type Events = SelectAll<MessageStream>;

/// Register all rules *before* the initial read so no change can slip between the two.
pub(crate) async fn watch(conn: &Connection, rules: Vec<MatchRule<'static>>) -> Result<Events> {
    let mut all = SelectAll::new();
    for r in rules {
        all.push(MessageStream::for_match_rule(r, conn, None).await?);
    }
    Ok(all)
}

pub(crate) fn props_changed(path_ns: &'static str) -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path_namespace(path_ns)?
        .build())
}

pub(crate) fn name_owner_changed(ns: &'static str) -> Result<MatchRule<'static>> {
    Ok(MatchRule::builder()
        .msg_type(MsgType::Signal)
        .sender("org.freedesktop.DBus")?
        .interface("org.freedesktop.DBus")?
        .member("NameOwnerChanged")?
        .arg0ns(ns)?
        .build())
}

pub(crate) async fn name_has_owner(conn: &Connection, name: &str) -> bool {
    let Ok(proxy) = zbus::fdo::DBusProxy::new(conn).await else {
        return false;
    };
    let Ok(n) = zbus::names::BusName::try_from(name) else {
        return false;
    };
    proxy.name_has_owner(n).await.unwrap_or(false)
}

pub(crate) type Props = HashMap<String, OwnedValue>;

pub(crate) async fn get_all(
    conn: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
) -> Option<Props> {
    let proxy = zbus::fdo::PropertiesProxy::builder(conn)
        .destination(dest.to_owned())
        .ok()?
        .path(path.to_owned())
        .ok()?
        .build()
        .await
        .ok()?;
    let iface = zbus::names::InterfaceName::try_from(iface.to_owned()).ok()?;
    proxy.get_all(iface).await.ok()
}

pub(crate) fn prop<T: TryFrom<OwnedValue>>(p: &Props, key: &str) -> Option<T> {
    p.get(key)?.try_clone().ok()?.try_into().ok()
}

/// Plain method call with no reply body; used by all command APIs.
pub(crate) async fn call<B>(
    conn: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
    method: &str,
    body: &B,
) -> zbus::Result<zbus::Message>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
{
    conn.call_method(Some(dest), path, Some(iface), method, body)
        .await
}
