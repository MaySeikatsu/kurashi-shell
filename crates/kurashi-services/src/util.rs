use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use futures_util::stream::SelectAll;
use futures_util::{Stream, StreamExt};
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

/// Runs `refresh` for every bus event and emits what it returns. The stream ending, or an `Err`
/// item, ends the loop: zbus sends the `Err` when the socket dies and ends the stream right after
/// it, so nothing past that point asks the bus anything.
pub(crate) async fn follow<T, S, F, Fut>(
    service: &'static str,
    em: &Emitter,
    mut events: S,
    unavailable: Value,
    mut refresh: F,
) where
    S: Stream<Item = zbus::Result<T>> + Unpin,
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Value>,
{
    while let Some(Ok(item)) = events.next().await {
        em.emit(refresh(item).await);
    }
    ended(service, em, unavailable);
}

/// Nothing refreshes the document once its event stream is over, so it says `unavailable` instead
/// of keeping its last value (rule 2). Logged once; the service task ends right after this.
pub(crate) fn ended(service: &'static str, em: &Emitter, unavailable: Value) {
    tracing::warn!(
        service,
        "D-Bus signal stream ended; document is now unavailable"
    );
    em.emit(unavailable);
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

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use futures_util::stream;
    use serde_json::json;

    use super::*;

    #[derive(Default)]
    struct Docs(Mutex<Vec<Value>>);

    impl DocSink for Docs {
        fn set(&self, doc: Value) {
            self.0.lock().unwrap().push(doc);
        }
    }

    #[tokio::test]
    async fn stream_end_marks_unavailable_after_the_last_refresh() {
        let docs = Arc::new(Docs::default());
        let em = Emitter::new(docs.clone());
        let events = stream::iter(vec![Ok::<i32, zbus::Error>(1), Ok(2)]);
        follow(
            "test",
            &em,
            events,
            json!({"gone": true}),
            |n: i32| async move { json!({"n": n}) },
        )
        .await;
        assert_eq!(
            *docs.0.lock().unwrap(),
            vec![json!({"n": 1}), json!({"n": 2}), json!({"gone": true})]
        );
    }

    #[tokio::test]
    async fn error_item_ends_the_stream_without_asking_the_bus() {
        // zbus sends an Err when the socket dies and ends the stream right after it: no call on
        // that dead connection, and nothing after the Err is read.
        let docs = Arc::new(Docs::default());
        let em = Emitter::new(docs.clone());
        let asked = Arc::new(AtomicBool::new(false));
        let events = stream::iter(vec![
            Err(zbus::Error::Failure("socket closed".into())),
            Ok(1),
        ]);
        follow("test", &em, events, json!({"gone": true}), |_: i32| {
            let asked = asked.clone();
            async move {
                asked.store(true, Ordering::SeqCst);
                json!({"refreshed": true})
            }
        })
        .await;
        assert!(
            !asked.load(Ordering::SeqCst),
            "refreshed after the socket failed"
        );
        assert_eq!(*docs.0.lock().unwrap(), vec![json!({"gone": true})]);
    }
}
