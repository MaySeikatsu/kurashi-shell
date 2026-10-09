//! `kurashi doctor` provider (card M7-doctor): a `query` of kind `doctor` that answers what works
//! and what does not, each degraded row naming a cause (`detail`) and a fix (`fix_key`) — Shōjiki.
//! Facts that need the outside world (sockets, buses, fontconfig) are probed once by the lead at
//! startup and handed in as [`DoctorFacts`]; everything else is read live from the daemon.

use std::sync::Arc;

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

/// Documents the daemon normally registers; unregistered ones are reported, not assumed.
const KNOWN_DOCS: &[&str] = &[
    crate::config::DOC,
    crate::config::SETTINGS_DOC,
    crate::workspaces::DOC,
    "svc.media",
    "svc.power",
    "svc.session",
    "svc.network",
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
pub fn register(daemon: &mut Daemon, facts: DoctorFacts) {
    let hub = daemon.hub.clone();
    let config = daemon.config.clone();
    let instance = daemon.instance.clone();
    let f: crate::QueryFn = Arc::new(move |_q| {
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
