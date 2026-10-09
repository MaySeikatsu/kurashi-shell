//! The mock's documents and action dispatch (PROTOCOL §3–§6). Pure state: no sockets, no clock,
//! so the daemon's rules (panel exclusivity, which session calls need `confirm`) are unit-tested
//! here, and `tests/wire.rs` checks the same through the socket.

use std::collections::HashMap;

use kurashi_core::Rev;
use kurashi_ipc::{ServerMsg, merge_patch};
use kurashid::wiring::CONFIRM_REQUIRED;
use serde_json::{Value, json};
use tokio::sync::broadcast;

use crate::documents;

/// The fake backlight starts at half scale (`svc.brightness` 0.5).
const BRIGHTNESS_START: u32 = documents::BRIGHTNESS_MAX / 2;
/// Default `brightness.up/down` step, a fraction of full scale (the OSD card's default).
const BRIGHTNESS_STEP: f64 = 0.05;

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
}

pub struct State {
    pub docs: HashMap<String, Doc>,
    pub outputs: Vec<String>,
    pub tx: broadcast::Sender<ServerMsg>,
}

impl State {
    pub fn new(outputs: &[String]) -> Self {
        let seed = [
            ("theme", documents::theme()),
            (
                "i18n",
                kurashid::i18n::document(
                    &kurashid::i18n::data_dir().join("i18n"),
                    &kurashid::i18n::locale_from_env(),
                ),
            ),
            ("svc.clock", documents::clock()),
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
        }
    }

    pub fn data(&self, doc: &str) -> &Value {
        &self.docs[doc].data
    }

    /// Merge-patch a document and broadcast it under the next revision. A patch that changes
    /// nothing is dropped, so an idle mock stays silent (Ma).
    fn patch(&mut self, doc: &str, ops: Value, origin: Option<String>) {
        self.apply(doc, ops, origin, false);
    }

    /// `force` is for the mock control messages: an explicit request to emit (`mock.tick` advances
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
            "session.suspend" | "session.reboot" | "session.poweroff" | "session.logout" => {
                if args["confirm"].as_bool() != Some(true) {
                    return Err(Fail::invalid(CONFIRM_REQUIRED));
                }
                tracing::info!(%action, "session action: no-op in the mock");
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

    /// Mock control (`mock.face`): the island switches face, as an event would make it.
    pub fn mock_face(&mut self, face: &str) {
        self.apply(
            "runtime.island.main",
            json!({"face": face, "reason": "event"}),
            None,
            true,
        );
    }

    pub fn mock_tick(&mut self) {
        self.apply("svc.clock", documents::clock(), None, true);
    }

    pub fn mock_workspace(&mut self, idx: u32) {
        let ws = documents::workspaces(&self.outputs, idx);
        self.apply("svc.workspaces", ws, None, true);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> State {
        State::new(&["HEADLESS-1".to_owned()])
    }

    fn none() -> Value {
        Value::Null
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
}
