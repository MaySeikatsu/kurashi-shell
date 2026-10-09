//! `svc.tray` on private dbus-daemons (C-services, review R.1 bus-loss finding): a bus that dies
//! takes the document unavailable, a bus listening at the same address again brings it back without
//! re-subscribing, a first connect that fails is retried, and nothing retries after the last
//! unsubscribe.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use kurashid::hub::Hub;
use kurashid::services::{ConnectFn, ServiceProvider};
use serde_json::{Value, json};

const TRAY_DOC: &str = "svc.tray";
const UNTIL: Duration = Duration::from_secs(10);
/// The restart budget the card asks for: the document is back within this long.
const RECOVERY: Duration = Duration::from_secs(5);

fn idle() -> Value {
    json!({"available": false, "items": []})
}

/// A fresh directory for one test's bus, removed when the test ends. Declared before the buses so
/// it outlives them.
struct Scratch(PathBuf);

impl Scratch {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("kurashid-svc-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Scratch(dir)
    }

    fn addr(&self) -> String {
        format!("unix:path={}", self.0.join("bus").display())
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// A session-type dbus-daemon on the scratch address. Dropping it kills only this child.
struct PrivateBus {
    child: Option<Child>,
}

impl PrivateBus {
    /// Starts a daemon and returns once it has printed the address, i.e. once it accepts clients.
    fn start(scratch: &Scratch) -> Self {
        let socket = scratch.0.join("bus");
        // A killed daemon leaves its socket file behind; the next one must not trip over it.
        let _ = std::fs::remove_file(&socket);
        let conf = scratch.0.join("bus.conf");
        std::fs::write(
            &conf,
            format!(
                r#"<busconfig><type>session</type>
<listen>unix:path={}</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"#,
                socket.display()
            ),
        )
        .unwrap();
        let mut child = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", conf.display()))
            .args(["--nofork", "--print-address"])
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon (run inside nix develop)");
        let mut printed = String::new();
        BufReader::new(child.stdout.as_mut().unwrap())
            .read_line(&mut printed)
            .unwrap();
        let bus = Self { child: Some(child) };
        // The printed address carries a `,guid=` suffix; the socket path is what must match.
        assert!(
            printed.trim().starts_with(&scratch.addr()),
            "the daemon listens where the test expects: {printed}"
        );
        bus
    }

    /// Kills this daemon and waits until it is gone.
    fn kill(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for PrivateBus {
    fn drop(&mut self) {
        self.kill();
    }
}

/// Opens `addr` on every call and counts the calls: a reconnect shows up as another attempt.
fn counting_bus(addr: String, attempts: Arc<AtomicUsize>) -> ConnectFn {
    Arc::new(move || {
        let (addr, attempts) = (addr.clone(), attempts.clone());
        Box::pin(async move {
            attempts.fetch_add(1, Ordering::SeqCst);
            zbus::connection::Builder::address(addr.as_str())?
                .build()
                .await
        })
    })
}

fn tray_provider(
    connect: ConnectFn,
) -> Arc<ServiceProvider<kurashi_tray::Commands, kurashi_tray::ServiceHandle>> {
    Arc::new(
        ServiceProvider::with_connect(TRAY_DOC, connect, kurashi_tray::start).unavailable(idle()),
    )
}

fn available(hub: &Hub) -> bool {
    hub.snapshot(TRAY_DOC).unwrap().1["available"] == true
}

/// Polls `cond` until it holds; fails the test when `within` runs out first.
async fn until(what: &str, within: Duration, mut cond: impl FnMut() -> bool) {
    let deadline = Instant::now() + within;
    while !cond() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

#[tokio::test]
async fn tray_reconnects_after_a_bus_restart_and_stops_on_unsubscribe() {
    let scratch = Scratch::new("reconnect");
    let mut bus = PrivateBus::start(&scratch);
    let attempts = Arc::new(AtomicUsize::new(0));
    let provider = tray_provider(counting_bus(scratch.addr(), attempts.clone()));
    let hub = Hub::new();
    hub.register(TRAY_DOC, idle(), Some(provider.clone()));

    hub.subscribe(TRAY_DOC).unwrap();
    until("the tray to be available", UNTIL, || available(&hub)).await;
    assert_eq!(
        attempts.load(Ordering::SeqCst),
        1,
        "one start for one subscriber"
    );

    // The bus dies: the tray's task ends, the provider marks the document unavailable and stops
    // answering commands while it waits to start the tray again.
    bus.kill();
    until("the tray to be unavailable", UNTIL, || !available(&hub)).await;
    assert!(
        provider.commands().is_none(),
        "no commands while the tray is down"
    );

    // A bus at the same address again: the provider reconnects without a new subscribe.
    bus = PrivateBus::start(&scratch);
    until("the tray to come back", RECOVERY, || available(&hub)).await;
    assert!(
        attempts.load(Ordering::SeqCst) > 1,
        "the restart reconnected"
    );
    assert!(provider.commands().is_some());

    // The last unsubscribe takes the supervisor with the service.
    hub.unsubscribe(TRAY_DOC);
    assert!(
        !provider.is_supervised(),
        "no supervisor after the last unsubscribe"
    );
    assert!(provider.commands().is_none());

    // Another bus death with nobody subscribed: no retry may run.
    let after_unsubscribe = attempts.load(Ordering::SeqCst);
    bus.kill();
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(
        attempts.load(Ordering::SeqCst),
        after_unsubscribe,
        "a retry ran after the last unsubscribe"
    );
}

#[tokio::test]
async fn first_connect_is_retried_until_the_bus_is_up() {
    let scratch = Scratch::new("first-connect");
    let attempts = Arc::new(AtomicUsize::new(0));
    let provider = tray_provider(counting_bus(scratch.addr(), attempts.clone()));
    let hub = Hub::new();
    hub.register(TRAY_DOC, idle(), Some(provider.clone()));

    // No bus yet: the first attempt fails and a retry follows, without any new subscribe.
    hub.subscribe(TRAY_DOC).unwrap();
    until("a retry after the failed connect", RECOVERY, || {
        attempts.load(Ordering::SeqCst) >= 2
    })
    .await;
    assert!(!available(&hub));

    let mut bus = PrivateBus::start(&scratch);
    until("the tray to come up", RECOVERY, || available(&hub)).await;

    hub.unsubscribe(TRAY_DOC);
    bus.kill();
}

#[tokio::test]
async fn unsubscribe_cancels_a_pending_retry() {
    let scratch = Scratch::new("cancel-retry");
    let attempts = Arc::new(AtomicUsize::new(0));
    let provider = tray_provider(counting_bus(scratch.addr(), attempts.clone()));
    let hub = Hub::new();
    hub.register(TRAY_DOC, idle(), Some(provider.clone()));

    // No bus: the provider waits between attempts. Unsubscribe while a retry is pending.
    hub.subscribe(TRAY_DOC).unwrap();
    until("a retry to be pending", RECOVERY, || {
        attempts.load(Ordering::SeqCst) >= 2
    })
    .await;
    hub.unsubscribe(TRAY_DOC);
    assert!(
        !provider.is_supervised(),
        "no supervisor after the last unsubscribe"
    );
    let at_unsubscribe = attempts.load(Ordering::SeqCst);

    // A bus appears: nothing may connect to it on the provider's behalf.
    let _bus = PrivateBus::start(&scratch);
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_eq!(
        attempts.load(Ordering::SeqCst),
        at_unsubscribe,
        "a retry ran after the last unsubscribe"
    );
    assert!(!available(&hub));
}
