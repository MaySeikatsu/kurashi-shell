//! Document hub: named state documents with monotonic revisions (PROTOCOL §3), patch
//! broadcast, and refcounted backing providers (Ma, rule 5).
//!
//! Lock order: a document's `lifecycle` before `docs`. Providers run with `lifecycle` held, so their
//! `start`/`stop` may `set`/`update` any document but must not subscribe or unsubscribe that same one.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use kurashi_core::Rev;
use kurashi_ipc::{ServerMsg, diff_patch};
use serde_json::Value;
use tokio::sync::broadcast;

/// Backs a document with a live source (a service, the compositor, …). Started when the first
/// client subscribes, stopped when the last one leaves — nothing runs for unwatched state.
pub trait Provider: Send + Sync {
    fn start(&self, hub: Arc<Hub>);
    fn stop(&self);
}

struct Doc {
    rev: Rev,
    data: Value,
    provider: Option<Arc<dyn Provider>>,
    subs: usize,
    /// Serialises subscriber-count changes with the provider's start and stop. Otherwise a stop
    /// (1 -> 0) and a start (0 -> 1) can interleave and leave the provider off with a subscriber
    /// attached (review finding 2). Kept apart from `docs` because providers call back into the hub.
    lifecycle: Arc<Mutex<()>>,
}

pub struct Hub {
    docs: Mutex<HashMap<String, Doc>>,
    /// Last revision of each document removed at runtime (`unregister`), taken again by a
    /// re-registration: clients that still hold the old revisions must not see them restart.
    /// Taken while `docs` is held, never the other way round.
    retired: Mutex<HashMap<String, Rev>>,
    tx: broadcast::Sender<Arc<ServerMsg>>,
    /// Lets `subscribe` hand providers an owning handle without callers passing one around.
    me: std::sync::Weak<Hub>,
}

#[derive(Debug, thiserror::Error, PartialEq)]
#[error("no document {0}")]
pub struct UnknownDoc(pub String);

impl Hub {
    pub fn new() -> Arc<Self> {
        let (tx, _) = broadcast::channel(1024);
        Arc::new_cyclic(|me| Hub {
            docs: Mutex::new(HashMap::new()),
            retired: Mutex::new(HashMap::new()),
            tx,
            me: me.clone(),
        })
    }

    /// Patches and pushed snapshots for every document; connections filter by subscription.
    pub fn events(&self) -> broadcast::Receiver<Arc<ServerMsg>> {
        self.tx.subscribe()
    }

    pub fn register(&self, name: &str, initial: Value, provider: Option<Arc<dyn Provider>>) {
        let mut docs = self.docs.lock().expect("hub lock");
        let rev = self
            .retired
            .lock()
            .expect("hub lock")
            .remove(name)
            .map_or(1, |last| last + 1);
        docs.insert(
            name.to_string(),
            Doc {
                rev,
                data: initial,
                provider,
                subs: 0,
                lifecycle: Arc::default(),
            },
        );
    }

    /// Removes a document at runtime (K26: a disabled mod's documents). Its provider stops first if
    /// it is running; subscribers get `last` as a snapshot (a disabled mod's `{available:false}`).
    /// Afterwards subscribing answers `unknown_doc`, and a re-registration goes on with the next
    /// revision. A connection still subscribed keeps that subscription in its own set: its later
    /// unsubscribe finds no document and does nothing. False when there was no such document.
    pub fn unregister(&self, name: &str, last: Value) -> bool {
        let Ok(lifecycle) = self.lifecycle_of(name) else {
            return false;
        };
        let _turn = lifecycle.lock().expect("lifecycle lock");
        let running = {
            let docs = self.docs.lock().expect("hub lock");
            match docs.get(name) {
                Some(d) if d.subs > 0 => d.provider.clone(),
                _ => None,
            }
        };
        // Outside `docs`: the provider may publish into the hub while it stops.
        if let Some(p) = running {
            p.stop();
        }
        let mut docs = self.docs.lock().expect("hub lock");
        let Some(d) = docs.remove(name) else {
            return false;
        };
        let rev = d.rev + 1;
        self.retired
            .lock()
            .expect("hub lock")
            .insert(name.to_string(), rev);
        // Sent while `docs` is held: a publish of the stopped provider can no longer land after it.
        let _ = self.tx.send(Arc::new(ServerMsg::Snap {
            id: None,
            doc: name.into(),
            rev,
            data: last,
        }));
        true
    }

    /// Current `(rev, data)` without subscribing.
    pub fn snapshot(&self, name: &str) -> Result<(Rev, Value), UnknownDoc> {
        let docs = self.docs.lock().expect("hub lock");
        let d = docs.get(name).ok_or_else(|| UnknownDoc(name.into()))?;
        Ok((d.rev, d.data.clone()))
    }

    /// Replace a document's data; broadcasts the merge-patch diff (nothing if unchanged).
    pub fn set(&self, name: &str, new: Value, origin: Option<String>) -> Result<(), UnknownDoc> {
        let mut docs = self.docs.lock().expect("hub lock");
        let d = docs.get_mut(name).ok_or_else(|| UnknownDoc(name.into()))?;
        self.commit(name, d, new, origin);
        Ok(())
    }

    /// Mutate a document in place; the resulting change is broadcast as one patch. The closure runs
    /// under the hub lock, so no other write lands between the read and the write (review finding 8).
    /// Keep it short, and don't call back into the hub from it.
    pub fn update(
        &self,
        name: &str,
        origin: Option<String>,
        f: impl FnOnce(&mut Value),
    ) -> Result<(), UnknownDoc> {
        let mut docs = self.docs.lock().expect("hub lock");
        let d = docs.get_mut(name).ok_or_else(|| UnknownDoc(name.into()))?;
        let mut new = d.data.clone();
        f(&mut new);
        self.commit(name, d, new, origin);
        Ok(())
    }

    /// Store `new` as the document's data and broadcast the merge-patch from the old data.
    fn commit(&self, name: &str, d: &mut Doc, new: Value, origin: Option<String>) {
        let Some(ops) = diff_patch(&d.data, &new) else {
            return;
        };
        d.data = new;
        d.rev += 1;
        let _ = self.tx.send(Arc::new(ServerMsg::Patch {
            doc: name.into(),
            rev: d.rev,
            ops,
            origin,
        }));
    }

    /// Rebuild a document from scratch (provider restart, compositor resync): clients get a
    /// `snap` without `id` and replace their state (PROTOCOL §3).
    pub fn push_snapshot(&self, name: &str, data: Value) -> Result<(), UnknownDoc> {
        let mut docs = self.docs.lock().expect("hub lock");
        let d = docs.get_mut(name).ok_or_else(|| UnknownDoc(name.into()))?;
        d.data = data;
        d.rev += 1;
        let _ = self.tx.send(Arc::new(ServerMsg::Snap {
            id: None,
            doc: name.into(),
            rev: d.rev,
            data: d.data.clone(),
        }));
        Ok(())
    }

    /// Count a subscriber; the first one starts the provider. Returns the snapshot to send.
    pub fn subscribe(&self, name: &str) -> Result<(Rev, Value), UnknownDoc> {
        let lifecycle = self.lifecycle_of(name)?;
        let _turn = lifecycle.lock().expect("lifecycle lock");
        let start = {
            let mut docs = self.docs.lock().expect("hub lock");
            let d = docs.get_mut(name).ok_or_else(|| UnknownDoc(name.into()))?;
            d.subs += 1;
            (d.subs == 1).then(|| d.provider.clone()).flatten()
        };
        // Outside `docs`: providers usually call back into `set` right away.
        if let (Some(p), Some(hub)) = (start, self.me.upgrade()) {
            p.start(hub);
        }
        self.snapshot(name)
    }

    /// Drop a subscriber; the last one stops the provider.
    pub fn unsubscribe(&self, name: &str) {
        let Ok(lifecycle) = self.lifecycle_of(name) else {
            return;
        };
        let _turn = lifecycle.lock().expect("lifecycle lock");
        let stop = {
            let mut docs = self.docs.lock().expect("hub lock");
            let Some(d) = docs.get_mut(name) else { return };
            if d.subs == 0 {
                return;
            }
            d.subs -= 1;
            (d.subs == 0).then(|| d.provider.clone()).flatten()
        };
        if let Some(p) = stop {
            p.stop();
        }
    }

    pub fn subscribers(&self, name: &str) -> usize {
        self.docs
            .lock()
            .expect("hub lock")
            .get(name)
            .map_or(0, |d| d.subs)
    }

    /// The document's lifecycle lock, cloned out so it can be taken without holding `docs`.
    fn lifecycle_of(&self, name: &str) -> Result<Arc<Mutex<()>>, UnknownDoc> {
        self.docs
            .lock()
            .expect("hub lock")
            .get(name)
            .map(|d| d.lifecycle.clone())
            .ok_or_else(|| UnknownDoc(name.into()))
    }
}
