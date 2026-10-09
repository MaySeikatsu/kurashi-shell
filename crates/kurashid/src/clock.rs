//! `svc.clock` (PROTOCOL §8): `{hh, mm, date, weekday}`, patched exactly at minute boundaries and
//! only while someone subscribes — the timer is the provider (Ma). `weekday` is the short name in
//! the daemon's locale (i18n domain `clock`, keys `clock.weekday.1`..`7`, Monday = 1).

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use chrono::Datelike;

use serde_json::{Value, json};

use crate::hub::{Hub, Provider};

pub const DOC: &str = "svc.clock";

/// Short weekday names, Monday first. English unless the catalog has `clock.weekday.<n>`.
pub type Weekdays = Arc<[String; 7]>;

pub fn weekdays(catalog: &BTreeMap<String, String>) -> Weekdays {
    const EN: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    Arc::new(std::array::from_fn(|i| {
        catalog
            .get(&format!("clock.weekday.{}", i + 1))
            .cloned()
            .unwrap_or_else(|| EN[i].to_owned())
    }))
}

pub fn now_doc(names: &[String; 7]) -> Value {
    let now = chrono::Local::now();
    json!({
        "hh": now.format("%H").to_string(),
        "mm": now.format("%M").to_string(),
        "date": now.format("%Y-%m-%d").to_string(),
        "weekday": names[now.weekday().num_days_from_monday() as usize],
    })
}

pub struct ClockProvider {
    task: Mutex<Option<tokio::task::JoinHandle<()>>>,
    names: Weekdays,
}

impl ClockProvider {
    pub fn new(names: Weekdays) -> Self {
        ClockProvider {
            task: Mutex::new(None),
            names,
        }
    }
}

impl Provider for ClockProvider {
    fn start(&self, hub: Arc<Hub>) {
        let _ = hub.set(DOC, now_doc(&self.names), None);
        let names = self.names.clone();
        let task = tokio::spawn(async move {
            loop {
                let now = chrono::Local::now();
                let ms_into_minute = (now.timestamp_millis().rem_euclid(60_000)) as u64;
                // +5 ms so we land just after the boundary, never just before it.
                tokio::time::sleep(std::time::Duration::from_millis(
                    60_000 - ms_into_minute + 5,
                ))
                .await;
                let _ = hub.set(DOC, now_doc(&names), None);
            }
        });
        // A tick left running after the replacement would keep ticking with no subscriber.
        let old = self.task.lock().expect("clock lock").replace(task);
        if let Some(old) = old {
            old.abort();
        }
    }

    fn stop(&self) {
        if let Some(t) = self.task.lock().expect("clock lock").take() {
            t.abort();
        }
    }
}

pub fn register(hub: &Arc<Hub>, names: Weekdays) {
    hub.register(
        DOC,
        now_doc(&names),
        Some(Arc::new(ClockProvider::new(names))),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn restart_and_stop_leave_no_tick_task_behind() {
        let alive = || {
            tokio::runtime::Handle::current()
                .metrics()
                .num_alive_tasks()
        };
        let baseline = alive();
        let hub = Hub::new();
        let p = ClockProvider::new(weekdays(&BTreeMap::new()));
        p.start(hub.clone());
        // A second start replaces the first tick: the first must be aborted, not orphaned.
        p.start(hub.clone());
        p.stop();
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(alive(), baseline, "a tick task outlived stop");
    }

    #[test]
    fn weekday_names_come_from_the_catalog_with_english_fallback() {
        let mut cat = BTreeMap::new();
        cat.insert("clock.weekday.5".to_owned(), "金".to_owned());
        let names = weekdays(&cat);
        assert_eq!(names[4], "金");
        assert_eq!(names[0], "Mon");
    }

    #[test]
    fn shipped_catalogs_name_all_seven_days() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../i18n");
        for loc in ["en", "ja"] {
            let cat = crate::i18n::load_locale(&root, loc);
            for n in 1..=7 {
                assert!(
                    cat.contains_key(&format!("clock.weekday.{n}")),
                    "{loc} lacks day {n}"
                );
            }
        }
    }
}
