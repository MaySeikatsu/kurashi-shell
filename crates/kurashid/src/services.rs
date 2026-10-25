//! D-Bus services (`kurashi-services`, `kurashi-tray`) as refcounted hub providers: the service —
//! its bus connection, match rules and task — exists only between the first subscribe and the last
//! unsubscribe (Ma, rule 5). While subscribed, a service that ends by itself (its bus went away, its
//! signal streams ended) is started again with backoff (C-services, review R.1 bus-loss finding).
//! I200: a bus that is not there at all is waited for (its socket appearing), not polled.

use std::future::Future;
use std::path::{Path, PathBuf};
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

    /// The socket file this bus listens on, as zbus finds the bus: `DBUS_SYSTEM_BUS_ADDRESS` /
    /// `DBUS_SESSION_BUS_ADDRESS`, else the stock place. `None` for an address without a socket file
    /// (abstract, tcp): there is nothing to watch for, and the supervisor backs off instead (I200).
    pub fn socket_path(self) -> Option<PathBuf> {
        let (var, stock) = match self {
            Bus::System => (
                "DBUS_SYSTEM_BUS_ADDRESS",
                Some(PathBuf::from("/var/run/dbus/system_bus_socket")),
            ),
            Bus::Session => (
                "DBUS_SESSION_BUS_ADDRESS",
                std::env::var_os("XDG_RUNTIME_DIR")
                    .filter(|d| !d.is_empty())
                    .map(|d| PathBuf::from(d).join("bus")),
            ),
        };
        match std::env::var(var) {
            Ok(address) if !address.is_empty() => unix_socket_path(&address),
            _ => stock,
        }
    }
}

/// The `path=` of the first `unix:` entry of a D-Bus address (`unix:path=/run/bus,guid=…;tcp:…`), unescaped.
fn unix_socket_path(address: &str) -> Option<PathBuf> {
    address.split(';').find_map(|entry| {
        let keys = entry.strip_prefix("unix:")?;
        let raw = keys.split(',').find_map(|kv| kv.strip_prefix("path="))?;
        let mut bytes = Vec::with_capacity(raw.len());
        let mut it = raw.bytes();
        while let Some(b) = it.next() {
            if b == b'%' {
                let hex = [it.next()?, it.next()?];
                bytes.push(u8::from_str_radix(std::str::from_utf8(&hex).ok()?, 16).ok()?);
            } else {
                bytes.push(b);
            }
        }
        use std::os::unix::ffi::OsStringExt;
        Some(PathBuf::from(std::ffi::OsString::from_vec(bytes)))
    })
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
/// I200: the cap while the bus itself cannot be reached and there is no socket file to wait for (an
/// abstract address, or a socket file nobody answers on): minutes apart, not a wakeup every 30 s.
const BUS_BACKOFF_MAX: Duration = Duration::from_secs(600);
/// The longest wait for an absent bus's socket before one more attempt, in case the watch missed it.
const BUS_WAIT_MAX: Duration = Duration::from_secs(1800);

struct Backoff(Duration);

impl Backoff {
    fn new() -> Self {
        Backoff(BACKOFF_MIN)
    }

    fn next_delay(&mut self) -> Duration {
        self.next_delay_up_to(BACKOFF_MAX)
    }

    fn next_delay_up_to(&mut self, cap: Duration) -> Duration {
        let delay = self.0.min(cap);
        self.0 = (delay * 2).min(cap);
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
    /// The bus's socket file: while it is absent, a failed connect waits for it to appear (I200).
    bus_socket: Option<PathBuf>,
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
        Self::with_connect(doc, bus.connect(), start).bus_socket_opt(bus.socket_path())
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
            bus_socket: None,
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

    /// The socket file the bus listens on (I200): a connect that fails while it is absent waits for
    /// it to appear instead of retrying. `new` sets the stock bus's; tests name their private bus's.
    pub fn bus_socket(self, path: impl Into<PathBuf>) -> Self {
        self.bus_socket_opt(Some(path.into()))
    }

    fn bus_socket_opt(mut self, path: Option<PathBuf>) -> Self {
        self.bus_socket = path;
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
            bus_socket: self.bus_socket.clone(),
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
    bus_socket: Option<PathBuf>,
    sink: Arc<dyn DocSink>,
    running: Arc<Mutex<Running<C>>>,
    generation: u64,
}

/// Why a start failed: the bus could not be reached, or the service could not start on it.
enum Failure {
    Bus(zbus::Error),
    Start(anyhow::Error),
}

impl<C, H> Supervision<C, H> {
    async fn attempt(&self) -> Result<(H, C), Failure> {
        let conn = (self.connect)().await.map_err(Failure::Bus)?;
        (self.start)(conn, self.sink.clone())
            .await
            .map_err(Failure::Start)
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
            // I200: no bus at all. A bus that starts creates its socket file, so wait for that (an inotify watch: no
            // wakeups) and try again at once. While the file is absent nothing else can help: the wait is long. A file
            // nobody answers on (a bus that died without removing it) is also retried on a backoff of minutes.
            Err(Failure::Bus(e)) => {
                if let Some(socket) = s.bus_socket.as_deref() {
                    let absent = !socket.exists();
                    let wait = if absent {
                        BUS_WAIT_MAX
                    } else {
                        backoff.next_delay_up_to(BUS_BACKOFF_MAX)
                    };
                    if !failing {
                        failing = true;
                        tracing::warn!(doc = s.doc, error = %e, socket = %socket.display(), ?wait, "no bus; waiting for its socket");
                    }
                    if socket_created(socket, wait).await {
                        backoff.reset();
                    }
                    continue;
                }
                let delay = backoff.next_delay_up_to(BUS_BACKOFF_MAX);
                if failing {
                    tracing::info!(doc = s.doc, error = %e, ?delay, "bus still unreachable; retrying");
                } else {
                    failing = true;
                    tracing::warn!(doc = s.doc, error = %e, ?delay, "bus unreachable; retrying");
                }
                delay
            }
            Err(Failure::Start(e)) => {
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

/// True once `socket` is created (it appears, or a file that was there is made anew), false after `max`. Watches the
/// deepest directory on its path that exists (non-recursive), woken only by a creation on the way to the socket; a
/// directory created on the way moves the watch down. Without a watch (inotify refused) it waits `max`.
async fn socket_created(socket: &Path, max: Duration) -> bool {
    use notify::{RecursiveMode, Watcher};
    let deadline = tokio::time::Instant::now() + max;
    let existed = socket.exists();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<PathBuf>();
    let mut watch: Option<(PathBuf, notify::RecommendedWatcher)> = None;
    loop {
        if !existed && socket.exists() {
            return true;
        }
        let dir = socket
            .ancestors()
            .skip(1)
            .find(|d| d.is_dir())
            .map(Path::to_path_buf);
        if let Some(dir) = dir.filter(|d| watch.as_ref().map(|(w, _)| w) != Some(d)) {
            let (target, tx) = (socket.to_path_buf(), tx.clone());
            let armed = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
                if let Ok(ev) = res
                    && ev.kind.is_create()
                {
                    for p in ev.paths.into_iter().filter(|p| target.starts_with(p)) {
                        let _ = tx.send(p);
                    }
                }
            })
            .and_then(|mut w| w.watch(&dir, RecursiveMode::NonRecursive).map(|()| w));
            match armed {
                // Checked again before waiting: the socket may have appeared while the watch was armed.
                Ok(w) => watch = Some((dir, w)),
                Err(e) => {
                    tracing::warn!(error = %e, dir = %dir.display(), "cannot watch for the bus socket");
                    tokio::time::sleep_until(deadline).await;
                    return false;
                }
            }
            continue;
        }
        tokio::select! {
            created = rx.recv() => {
                if created.as_deref() == Some(socket) {
                    return true;
                }
            }
            () = tokio::time::sleep_until(deadline) => return false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_socket_of_a_bus_address() {
        assert_eq!(
            unix_socket_path("unix:path=/run/user/1000/bus"),
            Some(PathBuf::from("/run/user/1000/bus"))
        );
        assert_eq!(
            unix_socket_path("tcp:host=x,port=1;unix:guid=ab,path=/tmp/a%20b"),
            Some(PathBuf::from("/tmp/a b"))
        );
        assert_eq!(unix_socket_path("unix:abstract=/tmp/dbus-x"), None);
        assert_eq!(unix_socket_path("tcp:host=localhost,port=1"), None);
    }

    #[test]
    fn an_unreachable_bus_backs_off_to_minutes() {
        let mut backoff = Backoff::new();
        let last = (0..20)
            .map(|_| backoff.next_delay_up_to(BUS_BACKOFF_MAX))
            .last();
        assert_eq!(last, Some(BUS_BACKOFF_MAX));
        assert_eq!(
            backoff.next_delay(),
            BACKOFF_MAX,
            "a service failure after it is capped at 30 s again"
        );
    }

    /// I200: the wait for an absent socket ends when it is created (inside a directory created meanwhile), the wait
    /// on a stale one when it is made anew, and either after its cap when nothing comes.
    #[tokio::test]
    async fn socket_created_follows_creation_and_ends_at_its_cap() {
        let dir = tempfile::tempdir().unwrap();
        let socket = dir.path().join("run/bus");
        let waiter = tokio::spawn({
            let socket = socket.clone();
            async move { socket_created(&socket, Duration::from_secs(30)).await }
        });
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!waiter.is_finished(), "nothing there yet");
        std::fs::create_dir(dir.path().join("run")).unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!waiter.is_finished(), "the directory is not the socket");
        let listener = std::os::unix::net::UnixListener::bind(&socket).unwrap();
        let created = tokio::time::timeout(Duration::from_secs(5), waiter)
            .await
            .expect("woken by the socket")
            .unwrap();
        assert!(created);

        // A stale file (its bus gone): only a new one ends the wait.
        drop(listener);
        let waiter = tokio::spawn({
            let socket = socket.clone();
            async move { socket_created(&socket, Duration::from_secs(30)).await }
        });
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!waiter.is_finished(), "the stale file is no news");
        std::fs::remove_file(&socket).unwrap();
        let _listener = std::os::unix::net::UnixListener::bind(&socket).unwrap();
        let created = tokio::time::timeout(Duration::from_secs(5), waiter)
            .await
            .expect("woken by the new socket")
            .unwrap();
        assert!(created);

        let started = std::time::Instant::now();
        assert!(!socket_created(&dir.path().join("never"), Duration::from_millis(300)).await);
        assert!(started.elapsed() >= Duration::from_millis(300));
    }

    #[test]
    fn backoff_doubles_up_to_the_cap_and_a_healthy_run_resets_it() {
        let mut backoff = Backoff::new();
        let ms: Vec<u128> = (0..9).map(|_| backoff.next_delay().as_millis()).collect();
        assert_eq!(ms, [250, 500, 1000, 2000, 4000, 8000, 16000, 30000, 30000]);
        backoff.reset();
        assert_eq!(backoff.next_delay(), BACKOFF_MIN);
    }
}
