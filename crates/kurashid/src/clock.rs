//! `svc.clock` (PROTOCOL §8): `{hh, mm, date, weekday}`, patched exactly at minute boundaries and
//! only while someone subscribes — the timer is the provider (Ma).

use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.clock";

pub fn now_doc() -> Value {
    let now = chrono::Local::now();
    json!({
        "hh": now.format("%H").to_string(),
        "mm": now.format("%M").to_string(),
        "date": now.format("%Y-%m-%d").to_string(),
        "weekday": now.format("%a").to_string(),
    })
}

#[derive(Default)]
pub struct ClockProvider {
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl Provider for ClockProvider {
    fn start(&self, hub: Arc<Hub>) {
        let _ = hub.set(DOC, now_doc(), None);
        let task = tokio::spawn(async move {
            loop {
                let now = chrono::Local::now();
                let ms_into_minute = (now.timestamp_millis().rem_euclid(60_000)) as u64;
                // +5 ms so we land just after the boundary, never just before it.
                tokio::time::sleep(std::time::Duration::from_millis(
                    60_000 - ms_into_minute + 5,
                ))
                .await;
                let _ = hub.set(DOC, now_doc(), None);
            }
        });
        *self.task.lock().expect("clock lock") = Some(task);
    }

    fn stop(&self) {
        if let Some(t) = self.task.lock().expect("clock lock").take() {
            t.abort();
        }
    }
}

pub fn register(hub: &Arc<Hub>) {
    hub.register(DOC, now_doc(), Some(Arc::new(ClockProvider::default())));
}
