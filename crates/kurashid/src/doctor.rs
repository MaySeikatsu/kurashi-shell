//! `kurashi doctor` provider (card M7-doctor): a `query` of kind `doctor` that answers what works
//! and what does not, each degraded row naming a cause (`detail`) and a fix (`fix_key`) — Shōjiki.
//! Facts that need the outside world (sockets, buses, fontconfig) are probed once by the lead at
//! startup and handed in as [`DoctorFacts`]; everything else is read live from the daemon.

use std::sync::{Arc, Mutex};

use kurashi_ipc::PROTOCOL_VERSION;
use serde_json::{Value, json};

use crate::Daemon;

/// Startup probes. `None` = not probed / not applicable (row reports `n/a`).
#[derive(Debug, Clone, Default)]
pub struct DoctorFacts {
    pub compositor_socket: Option<bool>,
    pub session_bus: Option<bool>,
    pub system_bus: Option<bool>,
    /// Did we win the `org.freedesktop.Notifications` name?
    pub notification_name_owned: Option<bool>,
    pub fc_list_worked: Option<bool>,
    pub data_dir_found: Option<bool>,
}

/// Facts shared between the doctor query and the tasks that learn them asynchronously (the
/// notification task connects to the session bus, the session actions to the system bus): they
/// report what they actually saw, the query never guesses (Shōjiki).
#[derive(Clone, Default)]
pub struct SharedFacts(Arc<Mutex<DoctorFacts>>);

impl SharedFacts {
    pub fn update(&self, f: impl FnOnce(&mut DoctorFacts)) {
        f(&mut self.0.lock().expect("doctor facts lock"));
    }

    pub fn get(&self) -> DoctorFacts {
        self.0.lock().expect("doctor facts lock").clone()
    }
}

impl From<DoctorFacts> for SharedFacts {
    fn from(f: DoctorFacts) -> Self {
        Self(Arc::new(Mutex::new(f)))
    }
}

/// Documents the daemon normally registers; unregistered ones are reported, not assumed.
const KNOWN_DOCS: &[&str] = &[
    crate::config::DOC,
    crate::config::SETTINGS_DOC,
    crate::workspaces::DOC,
    "svc.media",
    "svc.power",
    "svc.session",
    "svc.network",
    "svc.notifications",
    "theme",
    "i18n",
    "mods",
    "runtime.ui",
    "runtime.island.main",
    "svc.clock",
    "svc.audio",
    "runtime.lock",
];

/// Row id `bus_session` + status `n/a` → summary key `doctor.bus_session.na` (TOML-friendly).
fn row(id: &str, status: &str, detail: impl Into<String>, fix: bool) -> Value {
    let mut r = json!({
        "id": id,
        "status": status,
        "summary_key": format!("doctor.{id}.{}", status.replace('/', "")),
        "detail": detail.into(),
    });
    if fix {
        r["fix_key"] = json!(format!("doctor.{id}.fix"));
    }
    r
}

/// `ok` when true, otherwise `bad` (`warn` or `fail`); `n/a` when unprobed.
fn probe(id: &str, fact: Option<bool>, bad: &str, what: &str) -> Value {
    match fact {
        Some(true) => row(id, "ok", what, false),
        Some(false) => row(id, bad, what, true),
        None => row(id, "n/a", what, false),
    }
}

/// Adds the `doctor` query provider. Call after `daemon.config` is set.
pub fn register(daemon: &mut Daemon, facts: impl Into<SharedFacts>) {
    let facts: SharedFacts = facts.into();
    let hub = daemon.hub.clone();
    let config = daemon.config.clone();
    let instance = daemon.instance.clone();
    let f: crate::QueryFn = Arc::new(move |_q| {
        let facts = facts.get();
        let mut rows = vec![
            row("protocol", "ok", format!("v{PROTOCOL_VERSION}"), false),
            row("instance", "ok", instance.clone(), false),
            probe(
                "compositor",
                facts.compositor_socket,
                "fail",
                "compositor socket",
            ),
            probe("bus_session", facts.session_bus, "fail", "session bus"),
            probe("bus_system", facts.system_bus, "warn", "system bus"),
            probe(
                "notifications",
                facts.notification_name_owned,
                "warn",
                "org.freedesktop.Notifications",
            ),
            probe("fonts", facts.fc_list_worked, "warn", "fc-list"),
            probe("data_dir", facts.data_dir_found, "fail", "data directory"),
        ];
        rows.push(match &config {
            None => row("config", "n/a", "no config store", false),
            Some(c) => {
                let diags = c.diagnostics();
                if diags.is_empty() {
                    row("config", "ok", "0 diagnostics", false)
                } else {
                    let list = diags
                        .iter()
                        .map(|d| {
                            format!("{}: {} ({})", d.file.display(), d.key, d.reason.i18n_key())
                        })
                        .collect::<Vec<_>>()
                        .join("; ");
                    row(
                        "config",
                        "warn",
                        format!("{} diagnostics: {list}", diags.len()),
                        true,
                    )
                }
            }
        });
        let present: Vec<&str> = KNOWN_DOCS
            .iter()
            .copied()
            .filter(|d| hub.snapshot(d).is_ok())
            .collect();
        let missing: Vec<&str> = KNOWN_DOCS
            .iter()
            .copied()
            .filter(|d| !present.contains(d))
            .collect();
        rows.push(if missing.is_empty() {
            row("docs", "ok", format!("{} registered", present.len()), false)
        } else {
            row(
                "docs",
                "warn",
                format!("missing: {}", missing.join(", ")),
                true,
            )
        });
        let subs = present
            .iter()
            .map(|d| format!("{d}={}", hub.subscribers(d)))
            .collect::<Vec<_>>()
            .join(" ");
        rows.push(row("subscribers", "ok", subs, false));
        rows
    });
    daemon.queries.insert("doctor".into(), f);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ActionRegistry, Hub, Intents};

    fn status(rows: &[Value], id: &str) -> String {
        rows.iter().find(|r| r["id"] == id).unwrap()["status"]
            .as_str()
            .unwrap()
            .into()
    }

    #[test]
    fn async_facts_flip_from_na_when_tasks_report() {
        let mut d = Daemon::new(Hub::new(), ActionRegistry::default(), Intents::default());
        let facts = SharedFacts::default();
        register(&mut d, facts.clone());
        let q = d.queries.get("doctor").unwrap().clone();
        let rows = q("");
        assert_eq!(status(&rows, "bus_session"), "n/a");
        assert_eq!(status(&rows, "bus_system"), "n/a");
        assert_eq!(status(&rows, "notifications"), "n/a");

        facts.update(|f| {
            f.session_bus = Some(true);
            f.system_bus = Some(false);
            f.notification_name_owned = Some(false);
        });
        let rows = q("");
        assert_eq!(status(&rows, "bus_session"), "ok");
        assert_eq!(status(&rows, "bus_system"), "warn");
        assert_eq!(status(&rows, "notifications"), "warn");
    }
}
