//! What a mod's host program serves (K155, W93; PROTOCOL §2 "Host programs"): the meeting point of the action registry
//! (an invocation of the mod's action) and the server (the host's scoped connection that took the action with `serve`).
//! One entry per mod id, made when the mod is enabled ([`super::program::ProgramMod`]) and found by the server when the
//! host connects.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use kurashi_ipc::ServerMsg;
use kurashi_mod_api::ActionError;
use serde_json::Value;
use tokio::sync::{Notify, oneshot};

/// The reasons a host mod's documents and actions answer with while its program is away (i18n keys).
pub const STARTING: &str = "mods.host.starting";
pub const NOT_RUNNING: &str = "mods.host.not_running";
pub const TIMEOUT: &str = "mods.host.timeout";
pub const TOO_LARGE: &str = "mods.host.too_large";

/// A document a host publishes is at most this large as JSON.
pub const PUB_MAX: usize = 256 * 1024;
/// How long an invocation waits for the host's answer.
pub const CALL_WAIT: Duration = Duration::from_secs(10);
/// How long an invocation that starts the program (`start = "action"`) waits for its `serve`.
pub const SERVE_WAIT: Duration = Duration::from_secs(5);

type Answer = Result<Option<Value>, ActionError>;
type Push = Arc<dyn Fn(ServerMsg) + Send + Sync>;

/// The connection that serves, and the calls it has not answered.
struct Conn {
    id: u64,
    push: Push,
    actions: BTreeSet<String>,
    pending: HashMap<String, oneshot::Sender<Answer>>,
    next: u64,
}

#[derive(Default)]
struct State {
    /// The documents (`mod.<name>`) and actions the manifest provides: the most a host may publish and take.
    docs: BTreeSet<String>,
    actions: BTreeSet<String>,
    conn: Option<Conn>,
}

/// One mod's served state.
#[derive(Default)]
pub struct Served {
    state: Mutex<State>,
    /// A `serve` arrived (an invocation that started the program waits for it).
    served: Notify,
}

fn table() -> &'static Mutex<BTreeMap<String, Arc<Served>>> {
    static TABLE: OnceLock<Mutex<BTreeMap<String, Arc<Served>>>> = OnceLock::new();
    TABLE.get_or_init(Default::default)
}

/// The served state of mod `mod_id` (made on first use: the mod's enable and its host's connection both ask).
pub fn of(mod_id: &str) -> Arc<Served> {
    table()
        .lock()
        .expect("served lock")
        .entry(mod_id.to_string())
        .or_default()
        .clone()
}

impl Served {
    /// What the manifest provides, set at enable; an empty set at disable.
    pub fn provides(&self, docs: BTreeSet<String>, actions: BTreeSet<String>) {
        let mut s = self.state.lock().expect("served lock");
        s.docs = docs;
        s.actions = actions;
    }

    /// The documents the manifest provides (for the server: back to unavailable when the host goes).
    pub fn docs(&self) -> Vec<String> {
        self.state
            .lock()
            .expect("served lock")
            .docs
            .iter()
            .cloned()
            .collect()
    }

    /// Whether a host of this mod may publish `doc`.
    pub fn may_pub(&self, doc: &str) -> bool {
        self.state.lock().expect("served lock").docs.contains(doc)
    }

    /// Connection `conn` takes `actions`: all of them, or none — the first one the manifest does not provide is the
    /// error. A second `serve` (of this or a newer connection) replaces the first; its unanswered calls fail.
    pub fn serve(&self, conn: u64, push: Push, actions: Vec<String>) -> Result<(), String> {
        let mut s = self.state.lock().expect("served lock");
        if let Some(bad) = actions.iter().find(|a| !s.actions.contains(*a)) {
            return Err(bad.clone());
        }
        if let Some(old) = s.conn.take() {
            fail(old.pending);
        }
        s.conn = Some(Conn {
            id: conn,
            push,
            actions: actions.into_iter().collect(),
            pending: HashMap::new(),
            next: 0,
        });
        drop(s);
        self.served.notify_waiters();
        Ok(())
    }

    /// The host's answer to call `id`; one that is late or unknown is dropped.
    pub fn answer(&self, conn: u64, id: &str, answer: Answer) {
        let waiting = {
            let mut s = self.state.lock().expect("served lock");
            match s.conn.as_mut() {
                Some(c) if c.id == conn => c.pending.remove(id),
                _ => None,
            }
        };
        if let Some(tx) = waiting {
            let _ = tx.send(answer);
        }
    }

    /// Connection `conn` closed: its calls fail, and nothing is served until the host connects again.
    pub fn closed(&self, conn: u64) {
        let mut s = self.state.lock().expect("served lock");
        if s.conn.as_ref().is_some_and(|c| c.id == conn) {
            if let Some(old) = s.conn.take() {
                fail(old.pending);
            }
        }
    }

    /// Whether a connected host serves `action` now.
    pub fn serves(&self, action: &str) -> bool {
        self.state
            .lock()
            .expect("served lock")
            .conn
            .as_ref()
            .is_some_and(|c| c.actions.contains(action))
    }

    /// Waits up to `wait` for a host to serve `action` (the program was just started for it).
    pub async fn until_served(&self, action: &str, wait: Duration) -> bool {
        let deadline = tokio::time::Instant::now() + wait;
        loop {
            let notified = self.served.notified();
            if self.serves(action) {
                return true;
            }
            if tokio::time::timeout_at(deadline, notified).await.is_err() {
                return self.serves(action);
            }
        }
    }

    /// Invokes `action` on the host that serves it: `unavailable` with [`NOT_RUNNING`] when none does, with
    /// [`TIMEOUT`] when the host does not answer within [`CALL_WAIT`].
    pub async fn call(&self, action: &str, args: Value) -> Answer {
        let (rx, push, msg, id, conn) = {
            let mut s = self.state.lock().expect("served lock");
            let Some(c) = s.conn.as_mut().filter(|c| c.actions.contains(action)) else {
                return Err(ActionError::Unavailable(NOT_RUNNING.into()));
            };
            c.next += 1;
            let id = format!("c{}", c.next);
            let (tx, rx) = oneshot::channel();
            c.pending.insert(id.clone(), tx);
            let msg = ServerMsg::Call {
                id: id.clone(),
                action: action.to_string(),
                args,
            };
            (rx, c.push.clone(), msg, id, c.id)
        };
        push(msg);
        match tokio::time::timeout(CALL_WAIT, rx).await {
            Ok(Ok(answer)) => answer,
            // The connection went away with the call unanswered.
            Ok(Err(_)) => Err(ActionError::Unavailable(NOT_RUNNING.into())),
            Err(_) => {
                // A late answer finds nothing to resolve.
                let mut s = self.state.lock().expect("served lock");
                if let Some(c) = s.conn.as_mut().filter(|c| c.id == conn) {
                    c.pending.remove(&id);
                }
                Err(ActionError::Unavailable(TIMEOUT.into()))
            }
        }
    }
}

fn fail(pending: HashMap<String, oneshot::Sender<Answer>>) {
    for (_, tx) in pending {
        let _ = tx.send(Err(ActionError::Unavailable(NOT_RUNNING.into())));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn served(actions: &[&str]) -> Arc<Served> {
        let s = Arc::new(Served::default());
        s.provides(
            ["mod.tea".to_string()].into(),
            actions.iter().map(|a| (*a).to_string()).collect(),
        );
        s
    }

    /// A host's end: what the daemon pushed to it.
    fn sink() -> (Push, Arc<Mutex<Vec<ServerMsg>>>) {
        let got = Arc::new(Mutex::new(Vec::new()));
        let g = got.clone();
        (Arc::new(move |m| g.lock().unwrap().push(m)), got)
    }

    #[tokio::test]
    async fn a_call_reaches_the_host_that_serves_and_takes_its_answer() {
        let s = served(&["tea.start", "tea.stop"]);
        let (push, got) = sink();
        s.serve(1, push, vec!["tea.start".into()]).unwrap();
        assert!(s.serves("tea.start") && !s.serves("tea.stop"));
        let call = {
            let s = s.clone();
            tokio::spawn(async move { s.call("tea.start", json!({"minutes": 3})).await })
        };
        // The host sees the call with the daemon's id and answers it.
        let id = loop {
            if let Some(ServerMsg::Call { id, action, args }) = got.lock().unwrap().first().cloned()
            {
                assert_eq!(
                    (action.as_str(), &args),
                    ("tea.start", &json!({"minutes": 3}))
                );
                break id;
            }
            tokio::task::yield_now().await;
        };
        assert_eq!(id, "c1");
        s.answer(1, &id, Ok(Some(json!({"ends_at": 5}))));
        assert_eq!(call.await.unwrap(), Ok(Some(json!({"ends_at": 5}))));
        // An action nobody serves, and one served by nobody connected.
        assert_eq!(
            s.call("tea.stop", json!({})).await,
            Err(ActionError::Unavailable(NOT_RUNNING.into()))
        );
    }

    #[test]
    fn a_host_takes_only_what_the_manifest_provides_and_all_or_nothing() {
        let s = served(&["tea.start"]);
        let (push, _) = sink();
        assert_eq!(
            s.serve(1, push.clone(), vec!["tea.start".into(), "cfg.set".into()]),
            Err("cfg.set".into())
        );
        assert!(!s.serves("tea.start"), "none is taken");
        assert!(s.may_pub("mod.tea") && !s.may_pub("mod.other") && !s.may_pub("svc.media"));
        s.serve(1, push, vec!["tea.start".into()]).unwrap();
        assert!(s.serves("tea.start"));
    }

    #[tokio::test]
    async fn a_connection_that_closes_fails_its_calls() {
        let s = served(&["tea.start"]);
        let (push, got) = sink();
        s.serve(7, push, vec!["tea.start".into()]).unwrap();
        let call = {
            let s = s.clone();
            tokio::spawn(async move { s.call("tea.start", json!({})).await })
        };
        while got.lock().unwrap().is_empty() {
            tokio::task::yield_now().await;
        }
        // Another connection's close changes nothing; the serving one's fails the call.
        s.closed(3);
        assert!(s.serves("tea.start"));
        s.closed(7);
        assert_eq!(
            call.await.unwrap(),
            Err(ActionError::Unavailable(NOT_RUNNING.into()))
        );
        assert!(!s.serves("tea.start"));
    }

    #[tokio::test]
    async fn an_invocation_waits_for_a_program_that_was_just_started() {
        let s = served(&["tea.start"]);
        assert!(!s.until_served("tea.start", Duration::from_millis(20)).await);
        let waiter = {
            let s = s.clone();
            tokio::spawn(async move { s.until_served("tea.start", Duration::from_secs(2)).await })
        };
        tokio::task::yield_now().await;
        let (push, _) = sink();
        s.serve(1, push, vec!["tea.start".into()]).unwrap();
        assert!(waiter.await.unwrap());
    }
}
