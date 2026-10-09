//! Hub lifecycle and update atomicity under concurrent callers (PROTOCOL §3, Ma rule 5):
//! a provider's running state must agree with the subscriber count (review finding 2), and two
//! updates must not overwrite each other (review finding 8).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};

use kurashid::{Hub, Provider};
use serde_json::json;

/// A provider whose `stop` stays open until the test releases it, so another caller can race it.
struct GatedStop {
    entered: AtomicBool,
    running: AtomicBool,
    release: Mutex<mpsc::Receiver<()>>,
}

impl Provider for GatedStop {
    fn start(&self, _hub: Arc<Hub>) {
        self.running.store(true, Ordering::SeqCst);
    }

    fn stop(&self) {
        self.entered.store(true, Ordering::SeqCst);
        let _ = self.release.lock().expect("gate lock").recv();
        self.running.store(false, Ordering::SeqCst);
    }
}

#[test]
fn subscribe_racing_a_stop_leaves_the_provider_running() {
    let (release_tx, release_rx) = mpsc::channel();
    let gate = Arc::new(GatedStop {
        entered: AtomicBool::new(false),
        running: AtomicBool::new(false),
        release: Mutex::new(release_rx),
    });
    let hub = Hub::new();
    hub.register("svc.gate", json!({}), Some(gate.clone()));
    hub.subscribe("svc.gate").unwrap();

    // 1 -> 0: the stop blocks inside the provider.
    let last_out = {
        let hub = hub.clone();
        thread::spawn(move || hub.unsubscribe("svc.gate"))
    };
    let deadline = Instant::now() + Duration::from_secs(5);
    while !gate.entered.load(Ordering::SeqCst) {
        assert!(Instant::now() < deadline, "stop never started");
        thread::sleep(Duration::from_millis(1));
    }

    // 0 -> 1 while that stop is still running.
    let first_in = {
        let hub = hub.clone();
        thread::spawn(move || hub.subscribe("svc.gate").map(|_| ()))
    };
    thread::sleep(Duration::from_millis(50));
    release_tx.send(()).unwrap();
    last_out.join().unwrap();
    first_in.join().unwrap().unwrap();

    assert_eq!(hub.subscribers("svc.gate"), 1);
    assert!(
        gate.running.load(Ordering::SeqCst),
        "a subscriber is attached but the provider was stopped"
    );
}

#[test]
fn concurrent_updates_to_different_keys_are_both_kept() {
    let hub = Hub::new();
    hub.register("svc.kv", json!({}), None);
    let (entered_tx, entered_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel::<()>();

    let first = {
        let hub = hub.clone();
        thread::spawn(move || {
            hub.update("svc.kv", None, move |d| {
                // Parked mid-update: a second writer must not start from the old document.
                entered_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                d["a"] = json!(1);
            })
            .unwrap();
        })
    };
    entered_rx
        .recv_timeout(Duration::from_secs(5))
        .expect("first update never ran");

    let second = {
        let hub = hub.clone();
        thread::spawn(move || hub.update("svc.kv", None, |d| d["b"] = json!(2)).unwrap())
    };
    thread::sleep(Duration::from_millis(50));
    release_tx.send(()).unwrap();
    first.join().unwrap();
    second.join().unwrap();

    assert_eq!(
        hub.snapshot("svc.kv").unwrap().1,
        json!({"a": 1, "b": 2}),
        "one update overwrote the other"
    );
}
