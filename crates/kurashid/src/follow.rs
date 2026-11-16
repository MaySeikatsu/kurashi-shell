//! A mod's read-only feed of a document (K154 step 5, W91): `ModCtx::follow` → `Follow::watch` → here. The feed counts
//! as a subscriber of the document for as long as its receiver lives, so the document's service runs for a mod exactly
//! as it does for a view (Ma), and stops with the last of them.

use std::sync::Arc;

use kurashi_ipc::ServerMsg;
use kurashi_mod_api::unavailable;
use serde_json::Value;
use tokio::runtime::Handle;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::watch;

use crate::hub::Hub;

/// The data of `doc` now and after every change, until the receiver and its clones are dropped. A document that is not
/// there (its mod is off) reads `{"available": false}`; the feed takes it up when it is registered, and says
/// unavailable again when it goes.
pub fn feed(hub: Arc<Hub>, rt: &Handle, doc: &str) -> watch::Receiver<Value> {
    let name = doc.to_string();
    // Listening first: a change between the snapshot and the first `recv` is not lost.
    let mut events = hub.events();
    let mut registered = hub.registrations();
    let (mut subscribed, first) = match hub.subscribe(&name) {
        Ok((_, data)) => (true, data),
        Err(_) => (false, unavailable()),
    };
    let (tx, rx) = watch::channel(first);
    rt.spawn(async move {
        loop {
            let refresh = tokio::select! {
                () = tx.closed() => break,
                ev = events.recv() => match ev {
                    Ok(msg) => match &*msg {
                        ServerMsg::Snap { doc, .. } | ServerMsg::Patch { doc, .. } => *doc == name,
                        _ => false,
                    },
                    // Changes were dropped: read the document again.
                    Err(RecvError::Lagged(_)) => true,
                    Err(RecvError::Closed) => break,
                },
                r = registered.recv() => match r {
                    Ok(doc) => doc == name,
                    Err(RecvError::Lagged(_)) => true,
                    Err(RecvError::Closed) => break,
                },
            };
            if !refresh {
                continue;
            }
            if !subscribed {
                subscribed = hub.subscribe(&name).is_ok();
            }
            match hub.snapshot(&name) {
                Ok((_, data)) => {
                    tx.send_if_modified(|v| {
                        let changed = *v != data;
                        if changed {
                            *v = data;
                        }
                        changed
                    });
                }
                // Unregistered (its mod went off): the hub dropped the subscription with the document.
                Err(_) => {
                    subscribed = false;
                    tx.send_if_modified(|v| {
                        let changed = *v != unavailable();
                        if changed {
                            *v = unavailable();
                        }
                        changed
                    });
                }
            }
        }
        if subscribed {
            hub.unsubscribe(&name);
        }
    });
    rx
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::time::Duration;

    async fn settle() {
        tokio::time::sleep(Duration::from_millis(30)).await;
    }

    #[tokio::test]
    async fn the_feed_follows_the_document_and_counts_as_its_subscriber() {
        let hub = Hub::new();
        hub.register("svc.media", json!({"title": "a"}), None);
        let mut rx = feed(hub.clone(), &Handle::current(), "svc.media");
        assert_eq!(rx.borrow()["title"], "a");
        assert_eq!(hub.subscribers("svc.media"), 1);
        hub.set("svc.media", json!({"title": "b"}), None).unwrap();
        tokio::time::timeout(Duration::from_secs(2), rx.changed())
            .await
            .expect("a change")
            .unwrap();
        assert_eq!(rx.borrow()["title"], "b");
        drop(rx);
        settle().await;
        assert_eq!(
            hub.subscribers("svc.media"),
            0,
            "the last receiver ends the subscription"
        );
    }

    #[tokio::test]
    async fn a_document_that_is_not_there_reads_unavailable_until_it_is_registered() {
        let hub = Hub::new();
        let mut rx = feed(hub.clone(), &Handle::current(), "mod.terminal");
        assert_eq!(*rx.borrow(), unavailable());
        hub.register("mod.terminal", json!({"available": true}), None);
        tokio::time::timeout(Duration::from_secs(2), rx.changed())
            .await
            .expect("taken up")
            .unwrap();
        assert_eq!(rx.borrow()["available"], true);
        assert_eq!(hub.subscribers("mod.terminal"), 1);
        // Its mod goes off: unavailable again.
        hub.unregister("mod.terminal", json!({"available": false}));
        tokio::time::timeout(Duration::from_secs(2), rx.changed())
            .await
            .expect("gone")
            .unwrap();
        assert_eq!(*rx.borrow(), unavailable());
    }
}
