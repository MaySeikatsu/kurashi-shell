//! The mock's documents and action dispatch (PROTOCOL §3–§6). Pure state: no sockets and no
//! timers (the minute ticker lives in main.rs), so the daemon's rules (panel exclusivity, which
//! session calls need `confirm`, what a notification action closes) are unit-tested here, and
//! `tests/wire.rs` checks the same through the socket.

use std::collections::HashMap;
use std::hash::{BuildHasher, Hasher};

use chrono::NaiveTime;
use kurashi_core::Rev;
use kurashi_ipc::{ServerMsg, merge_patch};
use kurashid::wiring::CONFIRM_REQUIRED;
use serde_json::{Value, json};
use tokio::sync::broadcast;

use crate::documents::{self, Note};

/// The fake backlight starts at half scale (`svc.brightness` 0.5).
const BRIGHTNESS_START: u32 = documents::BRIGHTNESS_MAX / 2;
/// Default `brightness.up/down` step, a fraction of full scale (the OSD card's default).
const BRIGHTNESS_STEP: f64 = 0.05;
/// Rows per launcher query, as kurashid's launcher provider answers (`query(q, 30)`).
const QUERY_LIMIT: usize = 30;

pub struct Doc {
    pub rev: Rev,
    pub data: Value,
}

/// A failed action or intent: `kind` is the PROTOCOL §7 error kind, `msg` the text the UI keys on
/// (the confirm step keys on `session.confirm_required`).
#[derive(Debug, PartialEq)]
pub struct Fail {
    pub kind: &'static str,
    pub msg: String,
}

impl Fail {
    fn invalid(msg: impl Into<String>) -> Self {
        Fail {
            kind: "invalid",
            msg: msg.into(),
        }
    }

    fn unavailable(msg: impl Into<String>) -> Self {
        Fail {
            kind: "unavailable",
            msg: msg.into(),
        }
    }
}

pub struct State {
    pub docs: HashMap<String, Doc>,
    pub outputs: Vec<String>,
    pub tx: broadcast::Sender<ServerMsg>,
    /// Changes every mock start (PROTOCOL §2), so a client that reconnects sees a new instance.
    pub instance: String,
    /// `--fixed-time`: the time every clock reads, for the life of the process.
    fixed_time: Option<NaiveTime>,
    /// Newest first; `svc.notifications` is rebuilt from these after every change.
    notes: Vec<Note>,
    next_note_id: u32,
    dnd: bool,
}

impl State {
    pub fn new(outputs: &[String], fixed_time: Option<NaiveTime>) -> Self {
        let notes = documents::seed_notes(documents::now(fixed_time).timestamp_millis());
        let next_note_id = notes.iter().map(|n| n.id + 1).max().unwrap_or(1);
        let seed = [
            ("theme", documents::theme()),
            (
                "i18n",
                kurashid::i18n::document(
                    &kurashid::i18n::data_dir().join("i18n"),
                    &kurashid::i18n::locale_from_env(),
                ),
            ),
            ("svc.clock", documents::clock(documents::now(fixed_time))),
            ("svc.notifications", documents::notes_doc(&notes, false)),
            ("svc.workspaces", documents::workspaces(outputs, 1)),
            ("svc.audio", json!({"volume": 0.5, "muted": false})),
            (
                "svc.media",
                json!({"title": "夜に駆ける", "artist": "YOASOBI", "playing": true}),
            ),
            ("svc.brightness", documents::brightness(BRIGHTNESS_START)),
            (
                "runtime.island.main",
                json!({"face": "clock", "faces": ["clock", "media"], "reason": "default", "pinned": false}),
            ),
            (
                "runtime.ui",
                json!({"popup": false, "panel": "", "launcher": false}),
            ),
            // Unlocked and never changes: `session.lock` is a no-op here, so there is no unlock
            // path for the lock surface to wait on.
            (
                "runtime.lock",
                json!({"locked": false, "busy": false, "failures": 0}),
            ),
            (
                "bindings",
                documents::bindings(kurashi_schema::v1::registry()),
            ),
            (
                "mods.probe",
                json!({"widgets": [{
                    "id": "hello",
                    "ui": {"type": "row", "children": [
                        {"type": "icon", "name": "leaf"},
                        {"type": "text", "bind": "text"}
                    ]},
                    "state": {"text": "こんにちは"}
                }]}),
            ),
        ];
        let (tx, _) = broadcast::channel(256);
        State {
            docs: seed
                .into_iter()
                .map(|(name, data)| (name.to_string(), Doc { rev: 1, data }))
                .collect(),
            outputs: outputs.to_vec(),
            tx,
            instance: new_instance_id(),
            fixed_time,
            notes,
            next_note_id,
            dnd: false,
        }
    }

    pub fn data(&self, doc: &str) -> &Value {
        &self.docs[doc].data
    }

    /// Whether the minute ticker should run. Never under `--fixed-time`.
    pub fn clock_ticks(&self) -> bool {
        self.fixed_time.is_none()
    }

    /// Merge-patch a document and broadcast it under the next revision. A patch that changes
    /// nothing is dropped, so an idle mock stays silent (Ma).
    fn patch(&mut self, doc: &str, ops: Value, origin: Option<String>) {
        self.apply(doc, ops, origin, false);
    }

    /// `force` is for the mock control messages: an explicit request to emit (`mock.tick` re-emits
    /// the clock, PROTOCOL §8), so it is never deduplicated.
    fn apply(&mut self, doc: &str, ops: Value, origin: Option<String>, force: bool) {
        let d = self.docs.get_mut(doc).expect("known doc");
        let mut next = d.data.clone();
        merge_patch(&mut next, &ops);
        if next == d.data && !force {
            return;
        }
        d.data = next;
        d.rev += 1;
        let _ = self.tx.send(ServerMsg::Patch {
            doc: doc.into(),
            rev: d.rev,
            ops,
            origin,
        });
    }

    /// Intents: fire-and-forget, coalesced by the client. `audio.volume` is the probe's only one.
    pub fn intent(&mut self, key: &str, value: &Value, origin: Option<String>) -> Result<(), Fail> {
        match key {
            "audio.volume" => {
                let volume = value.as_f64().unwrap_or(0.5).clamp(0.0, 1.0);
                self.patch("svc.audio", json!({"volume": volume}), origin);
                Ok(())
            }
            _ => Err(Fail::invalid(format!("unknown intent {key}"))),
        }
    }

    /// Actions with the daemon's semantics. `Ok` carries `done.data`; nothing here returns data
    /// itself, but `input.dispatch` passes its bound action's result on.
    pub fn act(&mut self, action: &str, args: &Value) -> Result<Option<Value>, Fail> {
        match action {
            "island.next" | "island.prev" => {
                let next = if self.data("runtime.island.main")["face"] == "clock" {
                    "media"
                } else {
                    "clock"
                };
                self.patch(
                    "runtime.island.main",
                    json!({"face": next, "reason": "user"}),
                    None,
                );
            }
            "island.pin" => {
                let pinned = !self.data("runtime.island.main")["pinned"]
                    .as_bool()
                    .unwrap_or(false);
                self.patch("runtime.island.main", json!({"pinned": pinned}), None);
            }
            "island.expand" | "probe.popup.toggle" => self.toggle_panel("island"),
            "notifications.center" => self.toggle_panel("notifications"),
            "session.menu" => self.toggle_panel("session"),
            "launcher.toggle" => {
                let open = self.data("runtime.ui")["launcher"]
                    .as_bool()
                    .unwrap_or(false);
                self.patch("runtime.ui", json!({"launcher": !open}), None);
            }
            "ui.close" => self.patch(
                "runtime.ui",
                json!({"popup": false, "panel": "", "launcher": false}),
                None,
            ),
            "audio.mute.toggle" => {
                let muted = !self.data("svc.audio")["muted"].as_bool().unwrap_or(false);
                self.patch("svc.audio", json!({"muted": muted}), None);
            }
            "brightness.up" => self.brightness_step(args, 1),
            "brightness.down" => self.brightness_step(args, -1),
            // Needs no confirmation (wiring.rs `session.lock`, M5-ui-session); a no-op here.
            "session.lock" => tracing::info!("session.lock: no-op in the mock"),
            // Without a confirm the daemon refuses; with one it acts, and the mock does nothing.
            "session.suspend" | "session.reboot" | "session.poweroff" | "session.logout" => {
                if args["confirm"].as_bool() != Some(true) {
                    return Err(Fail::invalid(CONFIRM_REQUIRED));
                }
                tracing::info!(%action, "session action: no-op in the mock");
            }
            // kurashi-notify's commands. No id means all, for dismiss and mark_read.
            "notify.dismiss" => {
                match note_id(args) {
                    Some(id) => self.notes.retain(|n| n.id != id),
                    None => self.notes.clear(),
                }
                self.publish_notes();
            }
            "notify.invoke" => {
                let id = note_id(args).ok_or_else(|| Fail::invalid("notify.invoke needs id"))?;
                let key = args["key"].as_str().unwrap_or("default");
                // An unknown id or key is a silent no-op, as kurashi-notify's `invoke_action`.
                let known = self
                    .notes
                    .iter()
                    .any(|n| n.id == id && n.actions.iter().any(|(k, _)| k == key));
                if known {
                    self.after_interaction(id);
                }
            }
            "notify.mark_read" => {
                let id = note_id(args);
                for n in self
                    .notes
                    .iter_mut()
                    .filter(|n| id.is_none_or(|id| n.id == id))
                {
                    n.read = true;
                }
                self.publish_notes();
            }
            "notify.dnd" => {
                self.dnd = args["on"].as_bool().unwrap_or(true);
                self.publish_notes();
            }
            "mock.notify" => return self.mock_notify(args),
            // Logged, never spawned: the mock has no processes to start, and it answers no pid.
            "launcher.launch" => {
                let id = args["id"]
                    .as_str()
                    .ok_or_else(|| Fail::invalid("launcher.launch needs id"))?;
                if !documents::APPS.iter().any(|app| app.0 == id) {
                    return Err(Fail::unavailable(format!("no app {id}")));
                }
                tracing::info!(%id, "launcher.launch: not spawned in the mock");
            }
            "input.dispatch" => return self.dispatch(args),
            _ => {
                return Err(Fail {
                    kind: "unknown_action",
                    msg: format!("no action {action}"),
                });
            }
        }
        Ok(None)
    }

    /// `query {kind, q}` (PROTOCOL §6). Only `launcher` is served; any other kind is refused the
    /// way kurashid refuses a kind with no provider.
    pub fn query(&self, kind: &str, q: &str) -> Result<Vec<Value>, Fail> {
        match kind {
            "launcher" => Ok(launcher_rows(q)),
            _ => Err(Fail::invalid(format!("no query provider {kind}"))),
        }
    }

    /// Panels are exclusive: opening one switches away from another, and opening the open one
    /// closes it. `popup` mirrors "a panel is open" for the probe-era frontend.
    fn toggle_panel(&mut self, name: &str) {
        let open = self.data("runtime.ui")["panel"] == name;
        let panel = if open { "" } else { name };
        self.patch("runtime.ui", json!({"panel": panel, "popup": !open}), None);
    }

    /// `brightness.up/down {step?}`: `step` is a fraction of full scale, clamped to the device.
    fn brightness_step(&mut self, args: &Value, dir: i64) {
        let step = args["step"]
            .as_f64()
            .unwrap_or(BRIGHTNESS_STEP)
            .clamp(0.0, 1.0);
        let delta = (step * f64::from(documents::BRIGHTNESS_MAX)).round() as i64 * dir;
        let cur = self.data("svc.brightness")["value"].as_i64().unwrap_or(0);
        let value = (cur + delta).clamp(0, i64::from(documents::BRIGHTNESS_MAX));
        let value = u32::try_from(value).unwrap_or(0);
        self.patch("svc.brightness", documents::brightness(value), None);
    }

    /// `input.dispatch {component, slot, args?}`: runs the slot's bound action with `args.args`.
    /// An unbound slot is a no-op, not an error: the UI may send every click.
    fn dispatch(&mut self, args: &Value) -> Result<Option<Value>, Fail> {
        let field = |k: &str| {
            args[k]
                .as_str()
                .ok_or_else(|| Fail::invalid(format!("input.dispatch needs {k}")))
        };
        let (component, slot) = (field("component")?, field("slot")?);
        let bound = self.data("bindings")[component][slot]["action"]
            .as_str()
            .filter(|a| !a.is_empty())
            .map(str::to_owned);
        match bound {
            Some(action) => self.act(&action, &args["args"]),
            None => Ok(None),
        }
    }

    /// `mock.notify {summary, body?, app_name?, urgency?, actions?}` adds a notification the way
    /// kurashi-notify's `Notify` does: newest first, a toast unless DND is on (critical always
    /// shows). Returns `{id}`. Stands in for a `kurashi mock notify` subcommand.
    fn mock_notify(&mut self, args: &Value) -> Result<Option<Value>, Fail> {
        let summary = args["summary"]
            .as_str()
            .ok_or_else(|| Fail::invalid("mock.notify needs summary"))?;
        let urgency = match args["urgency"].as_str().unwrap_or("normal") {
            u @ ("low" | "normal" | "critical") => u,
            other => return Err(Fail::invalid(format!("unknown urgency {other}"))),
        };
        let mut actions = Vec::new();
        for a in args["actions"].as_array().into_iter().flatten() {
            match (a["key"].as_str(), a["label"].as_str()) {
                (Some(key), Some(label)) => actions.push((key.to_owned(), label.to_owned())),
                _ => return Err(Fail::invalid("mock.notify actions need key and label")),
            }
        }
        let id = self.next_note_id;
        self.next_note_id += 1;
        let mut note = Note::new(
            id,
            args["app_name"].as_str().unwrap_or("kurashi-mock"),
            summary,
            args["body"].as_str().unwrap_or(""),
            urgency,
            documents::now(self.fixed_time).timestamp_millis(),
        );
        note.actions = actions;
        note.showing = urgency == "critical" || !self.dnd;
        self.notes.insert(0, note);
        self.publish_notes();
        Ok(Some(json!({"id": id})))
    }

    /// After a notification action (kurashi-notify's `after_interaction`): a resident note only
    /// hides its toast, anything else is removed.
    fn after_interaction(&mut self, id: u32) {
        if let Some(i) = self.notes.iter().position(|n| n.id == id) {
            if self.notes[i].resident {
                self.notes[i].showing = false;
                self.notes[i].read = true;
            } else {
                self.notes.remove(i);
            }
            self.publish_notes();
        }
    }

    /// Rebuilds `svc.notifications` from the list. The patch is the whole document (arrays replace
    /// under merge-patch), and `apply` drops it when nothing changed.
    fn publish_notes(&mut self) {
        let doc = documents::notes_doc(&self.notes, self.dnd);
        self.patch("svc.notifications", doc, None);
    }

    /// Mock control (`mock.face`): the island switches face, as an event would make it.
    pub fn mock_face(&mut self, face: &str) {
        self.apply(
            "runtime.island.main",
            json!({"face": face, "reason": "event"}),
            None,
            true,
        );
    }

    /// Mock control (`mock.tick`): re-emits the clock. Under `--fixed-time` that is the same
    /// document again, since the time does not move.
    pub fn mock_tick(&mut self) {
        let clock = documents::clock(documents::now(self.fixed_time));
        self.apply("svc.clock", clock, None, true);
    }

    pub fn mock_workspace(&mut self, idx: u32) {
        let ws = documents::workspaces(&self.outputs, idx);
        self.apply("svc.workspaces", ws, None, true);
    }
}

/// `args.id` as a notification id; absent or out of range is `None`.
fn note_id(args: &Value) -> Option<u32> {
    args["id"].as_u64().and_then(|id| u32::try_from(id).ok())
}

/// Launcher rows for `q`, in kurashi-launcher's `QueryResult` shape with `kind` always `app`. A
/// case-insensitive substring match over name, generic name and desktop id; name-prefix matches
/// rank first. An empty query lists the index.
fn launcher_rows(q: &str) -> Vec<Value> {
    let q = q.trim().to_lowercase();
    let mut hits: Vec<(f64, Value)> = documents::APPS
        .iter()
        .filter_map(|&(id, name, generic, icon)| {
            let name_l = name.to_lowercase();
            let score = if q.is_empty() {
                0.5
            } else if name_l.starts_with(&q) {
                1.0
            } else if name_l.contains(&q) {
                0.8
            } else if generic.to_lowercase().contains(&q) || id.to_lowercase().contains(&q) {
                0.5
            } else {
                return None;
            };
            let row = json!({
                "id": id,
                "name": name,
                "generic": generic,
                "icon": icon,
                "kind": "app",
                "score": score,
            });
            Some((score, row))
        })
        .collect();
    hits.sort_by(|a, b| b.0.total_cmp(&a.0));
    hits.into_iter()
        .take(QUERY_LIMIT)
        .map(|(_, row)| row)
        .collect()
}

/// A fresh id per mock process (PROTOCOL §2). `RandomState` is seeded from the OS once per
/// process, so the id is random without a dependency; the pid and the seed counter keep two
/// instances in one process apart.
fn new_instance_id() -> String {
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u32(std::process::id());
    format!("{:016x}", h.finish())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> State {
        State::new(&["HEADLESS-1".to_owned()], None)
    }

    fn none() -> Value {
        Value::Null
    }

    /// The ids in `svc.notifications.items`, in list order.
    fn ids(st: &State) -> Vec<u64> {
        st.data("svc.notifications")["items"]
            .as_array()
            .expect("items")
            .iter()
            .map(|i| i["id"].as_u64().expect("id"))
            .collect()
    }

    #[test]
    fn runtime_ui_panels_are_exclusive_and_popup_mirrors_them() {
        let mut st = state();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false})
        );
        st.act("island.expand", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "island", "launcher": false})
        );
        // A second panel switches; it does not stack.
        st.act("notifications.center", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "notifications", "launcher": false})
        );
        // The open panel's own toggle closes it.
        st.act("notifications.center", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false})
        );
        // The probe alias is the island panel; the session menu is its own panel.
        st.act("probe.popup.toggle", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "island");
        st.act("session.menu", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "session");
        assert_eq!(st.data("runtime.ui")["popup"], true);
    }

    #[test]
    fn launcher_toggles_on_its_own_and_ui_close_resets_everything() {
        let mut st = state();
        st.act("island.expand", &none()).unwrap();
        st.act("launcher.toggle", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": true, "panel": "island", "launcher": true})
        );
        st.act("launcher.toggle", &none()).unwrap();
        assert_eq!(st.data("runtime.ui")["launcher"], false);
        st.act("launcher.toggle", &none()).unwrap();
        st.act("ui.close", &none()).unwrap();
        assert_eq!(
            st.data("runtime.ui"),
            &json!({"popup": false, "panel": "", "launcher": false})
        );
    }

    #[test]
    fn closing_what_is_already_closed_emits_nothing() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.act("ui.close", &none()).unwrap();
        assert!(rx.try_recv().is_err(), "no change, no patch (Ma)");
        st.act("island.expand", &none()).unwrap();
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
    }

    #[test]
    fn bindings_are_the_island_defaults_from_the_schema() {
        let st = state();
        let b = st.data("bindings");
        for (slot, action) in [
            ("left", "island.expand"),
            ("right", "island.pin"),
            ("scroll_up", "island.prev"),
            ("scroll_down", "island.next"),
        ] {
            assert_eq!(
                b["island.main"][slot],
                json!({"action": action, "source": {"kind": "default"}}),
                "{slot}"
            );
        }
        assert!(
            b["island.main"].get("middle").is_none(),
            "unbound slots are absent, not null"
        );
    }

    #[test]
    fn input_dispatch_runs_the_bound_action_and_ignores_unbound_slots() {
        let mut st = state();
        let d = |slot: &str| json!({"component": "island.main", "slot": slot});
        st.act("input.dispatch", &d("left")).unwrap();
        assert_eq!(st.data("runtime.ui")["panel"], "island");

        let mut rx = st.tx.subscribe();
        assert_eq!(st.act("input.dispatch", &d("middle")), Ok(None));
        assert!(rx.try_recv().is_err(), "unbound slot changes nothing");

        st.act("input.dispatch", &d("scroll_down")).unwrap();
        assert_eq!(st.data("runtime.island.main")["face"], "media");

        assert_eq!(
            st.act("input.dispatch", &json!({})),
            Err(Fail::invalid("input.dispatch needs component"))
        );
        assert_eq!(
            st.act("input.dispatch", &json!({"component": "island.main"})),
            Err(Fail::invalid("input.dispatch needs slot"))
        );
    }

    #[test]
    fn brightness_starts_at_half_and_steps_within_the_device_range() {
        let mut st = state();
        assert_eq!(st.data("svc.brightness"), &documents::brightness(500));
        assert_eq!(st.data("svc.brightness")["percent"], 50.0);

        // Default step is 5 %.
        st.act("brightness.up", &none()).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 550);
        assert_eq!(st.data("svc.brightness")["percent"], 55.0);

        st.act("brightness.down", &json!({"step": 0.5})).unwrap();
        assert_eq!(st.data("svc.brightness")["percent"], 5.0);

        st.act("brightness.down", &json!({"step": 1.0})).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 0);
        let mut rx = st.tx.subscribe();
        st.act("brightness.down", &none()).unwrap();
        assert!(rx.try_recv().is_err(), "clamped at 0: no change, no patch");

        st.act("brightness.up", &json!({"step": 2.0})).unwrap();
        assert_eq!(st.data("svc.brightness")["percent"], 100.0);
        st.act("brightness.up", &none()).unwrap();
        assert_eq!(st.data("svc.brightness")["value"], 1000);
    }

    #[test]
    fn session_lock_is_free_and_destructive_calls_need_confirm() {
        let mut st = state();
        assert_eq!(CONFIRM_REQUIRED, "session.confirm_required");
        let mut rx = st.tx.subscribe();
        st.act("session.lock", &none()).unwrap();
        for action in [
            "session.suspend",
            "session.reboot",
            "session.poweroff",
            "session.logout",
        ] {
            let unconfirmed = Fail {
                kind: "invalid",
                msg: "session.confirm_required".into(),
            };
            assert_eq!(st.act(action, &none()), Err(unconfirmed), "{action}");
            assert_eq!(
                st.act(action, &json!({"confirm": false})),
                Err(Fail {
                    kind: "invalid",
                    msg: "session.confirm_required".into()
                }),
                "{action} with confirm:false"
            );
            st.act(action, &json!({"confirm": true})).unwrap();
        }
        assert!(rx.try_recv().is_err(), "session calls are no-ops here");
    }

    #[test]
    fn unknown_actions_and_intents_are_refused_with_their_kind() {
        let mut st = state();
        assert_eq!(
            st.act("no.such", &none()),
            Err(Fail {
                kind: "unknown_action",
                msg: "no action no.such".into()
            })
        );
        assert_eq!(
            st.intent("no.such", &none(), None),
            Err(Fail::invalid("unknown intent no.such"))
        );
    }

    #[test]
    fn mock_face_accepts_transient_faces_such_as_brightness() {
        let mut st = state();
        st.mock_face("brightness");
        assert_eq!(st.data("runtime.island.main")["face"], "brightness");
        assert_eq!(st.data("runtime.island.main")["reason"], "event");
    }

    #[test]
    fn mock_controls_emit_even_when_nothing_changes() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.mock_tick();
        st.mock_tick();
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(rx.try_recv().is_err());

        st.mock_face("media");
        st.mock_face("media");
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert!(matches!(rx.try_recv(), Ok(ServerMsg::Patch { .. })));
        assert_eq!(
            st.docs["runtime.island.main"].rev, 3,
            "1 + two forced patches"
        );
    }

    #[test]
    fn seeded_notifications_are_history_only_with_a_critical_and_an_actionable_one() {
        let st = state();
        let n = st.data("svc.notifications");
        assert_eq!(n["dnd"], false);
        assert_eq!(n["toasts"], json!([]), "nothing shows at idle (Ma)");
        assert_eq!(n["unread"], 2, "one of the three is already read");
        let items = n["items"].as_array().expect("items");
        assert_eq!(items.len(), 3);
        assert!(items.iter().any(|i| i["urgency"] == "critical"));
        let actionable = items
            .iter()
            .find(|i| !i["actions"].as_array().expect("actions").is_empty())
            .expect("one note with actions");
        assert_eq!(
            actionable["actions"][0],
            json!({"key": "open", "label": "Open"})
        );
        for item in items {
            for field in [
                "id",
                "app_name",
                "app_icon",
                "summary",
                "body",
                "actions",
                "urgency",
                "time",
                "read",
                "resident",
                "transient",
            ] {
                assert!(item.get(field).is_some(), "{field} is present");
            }
            assert!(item.get("expires_at").is_none(), "absent, never null");
        }
    }

    #[test]
    fn dismiss_removes_one_note_or_all_and_an_unknown_id_changes_nothing() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        st.act("notify.dismiss", &json!({"id": 999})).unwrap();
        assert!(rx.try_recv().is_err(), "unknown id: no change, no patch");

        st.act("notify.dismiss", &json!({"id": 2})).unwrap();
        assert_eq!(ids(&st), vec![1, 3]);
        st.act("notify.dismiss", &none()).unwrap();
        assert_eq!(ids(&st), Vec::<u64>::new());
        assert_eq!(st.data("svc.notifications")["unread"], 0);
    }

    #[test]
    fn invoke_runs_a_known_action_and_closes_the_note_unless_it_is_resident() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        // An unknown key or id, or no key when the note has no default action, changes nothing.
        st.act("notify.invoke", &json!({"id": 2, "key": "nope"}))
            .unwrap();
        st.act("notify.invoke", &json!({"id": 999, "key": "open"}))
            .unwrap();
        st.act("notify.invoke", &json!({"id": 2})).unwrap();
        assert!(rx.try_recv().is_err());
        assert_eq!(ids(&st), vec![1, 2, 3]);

        st.act("notify.invoke", &json!({"id": 2, "key": "open"}))
            .unwrap();
        assert_eq!(ids(&st), vec![1, 3], "a known action closes the note");

        // A resident note only hides its toast and counts as read.
        st.notes[0].resident = true;
        st.notes[0].showing = true;
        st.notes[0].actions = vec![("open".into(), "Open".into())];
        st.publish_notes();
        st.act("notify.invoke", &json!({"id": 1, "key": "open"}))
            .unwrap();
        assert_eq!(ids(&st), vec![1, 3], "resident: still in the list");
        assert_eq!(st.data("svc.notifications")["toasts"], json!([]));
        assert_eq!(st.data("svc.notifications")["unread"], 0);

        assert_eq!(
            st.act("notify.invoke", &none()),
            Err(Fail::invalid("notify.invoke needs id"))
        );
    }

    #[test]
    fn mark_read_marks_one_note_or_all() {
        let mut st = state();
        st.act("notify.mark_read", &json!({"id": 1})).unwrap();
        assert_eq!(st.data("svc.notifications")["unread"], 1);
        st.act("notify.mark_read", &none()).unwrap();
        assert_eq!(st.data("svc.notifications")["unread"], 0);
    }

    #[test]
    fn dnd_keeps_normal_notifications_out_of_toasts_but_not_critical_ones() {
        let mut st = state();
        st.act("notify.dnd", &json!({"on": true})).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], true);

        st.act("mock.notify", &json!({"summary": "quiet"})).unwrap();
        assert_eq!(
            st.data("svc.notifications")["toasts"],
            json!([]),
            "DND: a normal note is history only"
        );
        st.act(
            "mock.notify",
            &json!({"summary": "alarm", "urgency": "critical"}),
        )
        .unwrap();
        assert_eq!(
            st.data("svc.notifications")["toasts"],
            json!([5]),
            "critical shows under DND"
        );

        // `on` defaults to true, as the daemon's does, and turning DND off changes the flag only.
        st.act("notify.dnd", &none()).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], true);
        st.act("notify.dnd", &json!({"on": false})).unwrap();
        assert_eq!(st.data("svc.notifications")["dnd"], false);
    }

    #[test]
    fn mock_notify_adds_a_toast_on_top_and_returns_its_id() {
        let mut st = state();
        let done = st
            .act(
                "mock.notify",
                &json!({
                    "summary": "Build finished",
                    "body": "ok",
                    "app_name": "cargo",
                    "actions": [{"key": "open", "label": "Open log"}]
                }),
            )
            .unwrap();
        assert_eq!(done, Some(json!({"id": 4})));
        assert_eq!(ids(&st), vec![4, 1, 2, 3], "newest first");

        let n = &st.data("svc.notifications")["items"][0];
        assert_eq!(n["app_name"], "cargo");
        assert_eq!(n["urgency"], "normal");
        assert_eq!(n["actions"], json!([{"key": "open", "label": "Open log"}]));
        assert_eq!(st.data("svc.notifications")["toasts"], json!([4]));
        assert_eq!(st.data("svc.notifications")["unread"], 3);

        // Refused input allocates no id.
        assert_eq!(
            st.act("mock.notify", &json!({})),
            Err(Fail::invalid("mock.notify needs summary"))
        );
        assert_eq!(
            st.act("mock.notify", &json!({"summary": "x", "urgency": "loud"})),
            Err(Fail::invalid("unknown urgency loud"))
        );
        assert_eq!(
            st.act(
                "mock.notify",
                &json!({"summary": "x", "actions": [{"key": "open"}]})
            ),
            Err(Fail::invalid("mock.notify actions need key and label"))
        );
        let next = st.act("mock.notify", &json!({"summary": "y"})).unwrap();
        assert_eq!(next, Some(json!({"id": 5})));
    }

    #[test]
    fn launcher_query_matches_by_substring_and_other_kinds_are_refused() {
        let st = state();
        let rows = st.query("launcher", "fire").unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"], "firefox.desktop");
        assert_eq!(rows[0]["kind"], "app");
        assert_eq!(rows[0]["icon"], "firefox");

        assert_eq!(
            st.query("launcher", "").unwrap().len(),
            documents::APPS.len(),
            "an empty query lists the index"
        );
        // The generic name and the desktop id match too, and case does not matter.
        assert!(
            st.query("launcher", "TERMINAL")
                .unwrap()
                .iter()
                .any(|r| r["id"] == "foot.desktop")
        );
        assert!(
            st.query("launcher", "calc")
                .unwrap()
                .iter()
                .any(|r| r["name"] == "Calculator")
        );
        assert!(st.query("launcher", "zzz").unwrap().is_empty());
        assert_eq!(
            st.query("notifications", "x"),
            Err(Fail::invalid("no query provider notifications"))
        );
    }

    #[test]
    fn launcher_launch_needs_a_known_app_and_changes_no_document() {
        let mut st = state();
        let mut rx = st.tx.subscribe();
        assert_eq!(
            st.act("launcher.launch", &none()),
            Err(Fail::invalid("launcher.launch needs id"))
        );
        assert_eq!(
            st.act("launcher.launch", &json!({"id": "nope.desktop"})),
            Err(Fail::unavailable("no app nope.desktop"))
        );
        assert_eq!(
            st.act("launcher.launch", &json!({"id": "foot.desktop"})),
            Ok(None)
        );
        assert!(rx.try_recv().is_err(), "a launch emits nothing");
    }

    #[test]
    fn fixed_time_pins_the_clock_and_mock_tick_only_re_emits_it() {
        let fixed = NaiveTime::from_hms_opt(14, 7, 0).expect("time");
        let mut st = State::new(&["HEADLESS-1".to_owned()], Some(fixed));
        assert!(!st.clock_ticks(), "no minute ticker under --fixed-time");
        assert_eq!(
            st.data("svc.clock"),
            &json!({"hh": "14", "mm": "07", "date": "2026-10-09", "weekday": "Fri"})
        );

        // An explicit mock.tick still emits (PROTOCOL §8), with the same time.
        let mut rx = st.tx.subscribe();
        st.mock_tick();
        assert!(matches!(
            rx.try_recv(),
            Ok(ServerMsg::Patch { ref doc, .. }) if doc == "svc.clock"
        ));
        assert_eq!(st.data("svc.clock")["mm"], "07");
        assert!(state().clock_ticks(), "a live mock ticks");
    }

    #[test]
    fn each_mock_process_gets_its_own_instance_id() {
        let (a, b) = (state(), state());
        assert!(!a.instance.is_empty());
        assert_ne!(a.instance, b.instance);
    }
}
