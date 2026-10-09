//! D-Bus services (`kurashi-services`, `kurashi-tray`) as refcounted hub providers: the service —
//! its bus connection, match rules and task — exists only between the first subscribe and the last
//! unsubscribe (Ma, rule 5). While subscribed, a service that ends by itself (its bus went away, its
//! signal streams ended) is started again with backoff (C-services, review R.1 bus-loss finding).

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use kurashi_services::{DocSink, ServiceHandle};
use serde_json::Value;
use tokio::task::JoinHandle;
use zbus::Connection;

use crate::hub::{Hub, Provider};

/// Opens the bus a service runs on. Called each time the service starts, never at daemon startup.
/// Injected so tests run on a private dbus-daemon (CONTRACT-CHANGE #15).
pub type ConnectFn =
    Arc<dyn Fn() -> Pin<Box<dyn Future<Output = zbus::Result<Connection>> + Send>> + Send + Sync>;

/// The two stock buses.
#[derive(Clone, Copy, Debug)]
pub enum Bus {
    Session,
    System,
}

impl Bus {
    /// Opens this bus each time a service starts, never at daemon startup.
    pub fn connect(self) -> ConnectFn {
        match self {
            Bus::Session => Arc::new(|| Box::pin(Connection::session())),
            Bus::System => Arc::new(|| Box::pin(Connection::system())),
        }
    }
}

/// What a provider needs from a running service: whether its task ended by itself. Dropping the
/// handle stops the service, so a provider holds it exactly as long as the service runs.
pub trait ServiceTask: Send + 'static {
    /// Resolves once the task has ended by itself; pending while it runs.
    fn finished(&mut self) -> impl Future<Output = ()> + Send;
}

// Named differently from the inherent `ended`, so the call below cannot resolve back to this impl.
impl ServiceTask for ServiceHandle {
    fn finished(&mut self) -> impl Future<Output = ()> + Send {
        ServiceHandle::ended(self)
    }
}

impl ServiceTask for kurashi_tray::ServiceHandle {
    fn finished(&mut self) -> impl Future<Output = ()> + Send {
        kurashi_tray::ServiceHandle::ended(self)
    }
}

/// Restart delays while subscribed: 250 ms, doubling up to 30 s. A run that lasted a healthy minute
/// starts the sequence again.
const BACKOFF_MIN: Duration = Duration::from_millis(250);
const BACKOFF_MAX: Duration = Duration::from_secs(30);
const HEALTHY_RUN: Duration = Duration::from_secs(60);

struct Backoff(Duration);

impl Backoff {
    fn new() -> Self {
        Backoff(BACKOFF_MIN)
    }

    fn next_delay(&mut self) -> Duration {
        let delay = self.0;
        self.0 = (delay * 2).min(BACKOFF_MAX);
        delay
    }

    fn reset(&mut self) {
        self.0 = BACKOFF_MIN;
    }
}

type StartFut<H, C> = Pin<Box<dyn Future<Output = anyhow::Result<(H, C)>> + Send>>;
type StartFn<H, C> = Arc<dyn Fn(Connection, Arc<dyn DocSink>) -> StartFut<H, C> + Send + Sync>;
type Observer = Arc<dyn Fn(&Value) + Send + Sync>;

struct Running<C> {
    /// Bumped on every start and stop. A supervisor whose generation is stale was stopped, and it
    /// publishes nothing more.
    generation: u64,
    /// Runs the service and any pending retry. `stop` aborts it, which drops the handle.
    supervisor: Option<JoinHandle<()>>,
    commands: Option<C>,
}

/// A service as a hub provider. `H` is the handle that keeps the service alive: the stock services
/// return `kurashi_services::ServiceHandle`, the tray its own.
pub struct ServiceProvider<C, H = ServiceHandle> {
    doc: &'static str,
    connect: ConnectFn,
    start: StartFn<H, C>,
    observer: Option<Observer>,
    /// Shown when the running service ends by itself. Needed only by a task that does not mark its
    /// own outage (`util::ended` does); rule 2 says the document must not keep a stale value.
    unavailable: Option<Value>,
    running: Arc<Mutex<Running<C>>>,
}

struct HubSink {
    hub: Arc<Hub>,
    doc: &'static str,
    observer: Option<Observer>,
}

impl DocSink for HubSink {
    fn set(&self, doc: Value) {
        if let Some(o) = &self.observer {
            o(&doc);
        }
        let _ = self.hub.set(self.doc, doc, None);
    }
}

impl<C: Clone + Send + 'static, H: ServiceTask> ServiceProvider<C, H> {
    /// A service on one of the stock buses.
    pub fn new<F, Fut>(doc: &'static str, bus: Bus, start: F) -> Self
    where
        F: Fn(Connection, Arc<dyn DocSink>) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = anyhow::Result<(H, C)>> + Send + 'static,
    {
        Self::with_connect(doc, bus.connect(), start)
    }

    /// A service on a bus the caller opens (tests run it on a private dbus-daemon).
    pub fn with_connect<F, Fut>(doc: &'static str, connect: ConnectFn, start: F) -> Self
    where
        F: Fn(Connection, Arc<dyn DocSink>) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = anyhow::Result<(H, C)>> + Send + 'static,
    {
        ServiceProvider {
            doc,
            connect,
            start: Arc::new(move |conn, sink| Box::pin(start(conn, sink))),
            observer: None,
            unavailable: None,
            running: Arc::new(Mutex::new(Running {
                generation: 0,
                supervisor: None,
                commands: None,
            })),
        }
    }

    /// Called with every new document before it reaches the hub (e.g. media → island signal).
    pub fn observe(mut self, f: impl Fn(&Value) + Send + Sync + 'static) -> Self {
        self.observer = Some(Arc::new(f));
        self
    }

    /// The document shown when the running service ends by itself (see `unavailable`).
    pub fn unavailable(mut self, doc: Value) -> Self {
        self.unavailable = Some(doc);
        self
    }

    /// Commands of the running service; `None` while nobody subscribes or a retry is pending.
    pub fn commands(&self) -> Option<C> {
        self.running.lock().expect("svc lock").commands.clone()
    }

    /// Whether a supervisor is attached: from the first subscribe to the last unsubscribe.
    pub fn is_supervised(&self) -> bool {
        self.running.lock().expect("svc lock").supervisor.is_some()
    }
}

impl<C: Clone + Send + 'static, H: ServiceTask> Provider for ServiceProvider<C, H> {
    fn start(&self, hub: Arc<Hub>) {
        let generation = {
            let mut r = self.running.lock().expect("svc lock");
            r.generation += 1;
            r.generation
        };
        let supervision = Supervision {
            doc: self.doc,
            connect: self.connect.clone(),
            start: self.start.clone(),
            unavailable: self.unavailable.clone(),
            sink: Arc::new(HubSink {
                hub,
                doc: self.doc,
                observer: self.observer.clone(),
            }),
            running: self.running.clone(),
            generation,
        };
        let task = tokio::spawn(supervise(supervision));
        let previous = self
            .running
            .lock()
            .expect("svc lock")
            .supervisor
            .replace(task);
        if let Some(previous) = previous {
            previous.abort();
        }
    }

    fn stop(&self) {
        let (supervisor, commands) = {
            let mut r = self.running.lock().expect("svc lock");
            r.generation += 1;
            (r.supervisor.take(), r.commands.take())
        };
        // Outside the lock: dropping the commands and aborting the supervisor (which drops the
        // service) may release bus names.
        drop(commands);
        if let Some(supervisor) = supervisor {
            supervisor.abort();
        }
    }
}

/// One subscription's supervisor: the service it runs and the state it publishes into.
struct Supervision<C, H> {
    doc: &'static str,
    connect: ConnectFn,
    start: StartFn<H, C>,
    unavailable: Option<Value>,
    sink: Arc<dyn DocSink>,
    running: Arc<Mutex<Running<C>>>,
    generation: u64,
}

impl<C, H> Supervision<C, H> {
    async fn attempt(&self) -> anyhow::Result<(H, C)> {
        let conn = (self.connect)().await?;
        (self.start)(conn, self.sink.clone()).await
    }

    /// Publishes the commands of the running service. False once this supervisor was stopped; the
    /// caller then drops what it holds.
    fn publish(&self, commands: Option<C>) -> bool {
        let previous = {
            let mut r = self.running.lock().expect("svc lock");
            if r.generation != self.generation {
                return false;
            }
            std::mem::replace(&mut r.commands, commands)
        };
        drop(previous);
        true
    }
}

/// Keeps the service running while subscribed: start it, wait until it ends by itself, then start
/// it again after a delay. Aborting this task (stop) drops the service and any pending retry.
async fn supervise<C, H>(s: Supervision<C, H>)
where
    C: Clone + Send + 'static,
    H: ServiceTask,
{
    let mut backoff = Backoff::new();
    // The first failure of an outage is a warning; each retry after it is logged at info.
    let mut failing = false;
    loop {
        let delay = match s.attempt().await {
            Ok((mut handle, commands)) => {
                failing = false;
                if !s.publish(Some(commands)) {
                    return;
                }
                let up = Instant::now();
                handle.finished().await;
                drop(handle);
                if !s.publish(None) {
                    return;
                }
                if up.elapsed() >= HEALTHY_RUN {
                    backoff.reset();
                }
                if let Some(doc) = &s.unavailable {
                    s.sink.set(doc.clone());
                }
                let delay = backoff.next_delay();
                tracing::info!(doc = s.doc, delay = ?delay, "service ended; starting it again");
                delay
            }
            Err(e) => {
                let delay = backoff.next_delay();
                if failing {
                    tracing::info!(doc = s.doc, error = %e, ?delay, "still not running; retrying");
                } else {
                    failing = true;
                    tracing::warn!(doc = s.doc, error = %e, ?delay, "failed to start; retrying");
                }
                delay
            }
        };
        tokio::time::sleep(delay).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_doubles_up_to_the_cap_and_a_healthy_run_resets_it() {
        let mut backoff = Backoff::new();
        let ms: Vec<u128> = (0..9).map(|_| backoff.next_delay().as_millis()).collect();
        assert_eq!(ms, [250, 500, 1000, 2000, 4000, 8000, 16000, 30000, 30000]);
        backoff.reset();
        assert_eq!(backoff.next_delay(), BACKOFF_MIN);
    }
}
