//! K47 daily-driver documents in the mock (parity with kurashid's `svc.idle`, `svc.nightlight`, `svc.keyboard`,
//! `svc.recorder`): the shapes of PROTOCOL's rows and their actions answered in memory. Nothing runs (no wlsunset, no
//! recorder, no compositor); the screenshot actions are accepted and logged.

use serde_json::{Value, json};

use crate::state::Fail;

pub const IDLE: &str = "svc.idle";
pub const NIGHT: &str = "svc.nightlight";
pub const KEYBOARD: &str = "svc.keyboard";
pub const RECORDER: &str = "svc.recorder";

/// The four documents as an idle session shows them: two layouts, nothing inhibited, night light off, not recording.
pub fn docs() -> Vec<(&'static str, Value)> {
    vec![
        (
            IDLE,
            json!({"enabled": true, "stage": "active", "caffeine": false, "inhibited": false, "inhibitors": []}),
        ),
        (
            NIGHT,
            json!({"available": true, "enabled": false, "active": false, "temperature": 4000, "schedule": "manual"}),
        ),
        (
            KEYBOARD,
            json!({"layouts": [{"name": "English (US)", "short": "us"}, {"name": "Japanese", "short": "jp"}], "current": 0}),
        ),
        (
            RECORDER,
            json!({"available": true, "backend": "wf-recorder", "recording": false}),
        ),
    ]
}

/// Whether the action is one of these.
pub fn handles(action: &str) -> bool {
    [
        "idle.",
        "nightlight.",
        "keyboard.",
        "recorder.",
        "screenshot.",
    ]
    .iter()
    .any(|p| action.starts_with(p))
}

/// The optional `on` of a toggle; without it the opposite of `current`.
fn on_arg(args: &Value, current: bool) -> Result<bool, Fail> {
    match args.get("on") {
        None | Some(Value::Null) => Ok(!current),
        Some(v) => v
            .as_bool()
            .ok_or_else(|| Fail::invalid("error.args.invalid")),
    }
}

/// The action against the current documents: the `(document, merge patch)` pairs it changes.
pub fn act(
    doc: impl Fn(&str) -> Value,
    action: &str,
    args: &Value,
    now_ms: i64,
) -> Result<Vec<(&'static str, Value)>, Fail> {
    Ok(match action {
        "idle.caffeine" => {
            let on = on_arg(args, doc(IDLE)["caffeine"] == true)?;
            vec![(IDLE, json!({"caffeine": on, "inhibited": on}))]
        }
        // The mock's lock is a no-op (see runtime.lock in state.rs).
        "idle.lock_now" => Vec::new(),
        "nightlight.toggle" => {
            let on = on_arg(args, doc(NIGHT)["enabled"] == true)?;
            vec![(NIGHT, json!({"enabled": on, "active": on}))]
        }
        "keyboard.next" => {
            let d = doc(KEYBOARD);
            let n = d["layouts"].as_array().map_or(0, Vec::len) as u64;
            if n == 0 {
                return Ok(Vec::new());
            }
            let cur = d["current"].as_u64().unwrap_or(0);
            vec![(KEYBOARD, json!({"current": (cur + 1) % n}))]
        }
        "keyboard.set" => {
            let d = doc(KEYBOARD);
            let n = d["layouts"].as_array().map_or(0, Vec::len) as u64;
            let i = args["index"]
                .as_u64()
                .ok_or_else(|| Fail::invalid("error.args.invalid"))?;
            if i >= n {
                return Err(Fail::invalid("error.keyboard.no_such_layout"));
            }
            vec![(KEYBOARD, json!({"current": i}))]
        }
        "recorder.start" | "recorder.stop" | "recorder.toggle" => {
            let recording = doc(RECORDER)["recording"] == true;
            let start = match action {
                "recorder.start" if recording => return Err(Fail::invalid("error.recorder.busy")),
                "recorder.stop" if !recording => {
                    return Err(Fail::invalid("error.recorder.not_recording"));
                }
                "recorder.start" => true,
                "recorder.stop" => false,
                _ => !recording,
            };
            if start {
                vec![(
                    RECORDER,
                    json!({"recording": true, "since_ms": now_ms,
                           "file": "/home/mock/Videos/kurashi-2026-10-21_10-00-00.mp4"}),
                )]
            } else {
                vec![(RECORDER, json!({"recording": false, "since_ms": null}))]
            }
        }
        "screenshot.screen" | "screenshot.window" | "screenshot.region" => {
            tracing::info!(action, "screenshot: logged in the mock");
            Vec::new()
        }
        _ => {
            return Err(Fail {
                kind: "unknown_action",
                msg: format!("no action {action}"),
            });
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn get(name: &str) -> Value {
        docs().into_iter().find(|(n, _)| *n == name).unwrap().1
    }

    #[test]
    fn toggles_and_layouts() {
        let p = act(get, "idle.caffeine", &json!({}), 0).unwrap();
        assert_eq!(
            p,
            vec![(IDLE, json!({"caffeine": true, "inhibited": true}))]
        );
        let p = act(get, "keyboard.next", &json!({}), 0).unwrap();
        assert_eq!(p, vec![(KEYBOARD, json!({"current": 1}))]);
        assert!(act(get, "keyboard.set", &json!({"index": 5}), 0).is_err());
        let p = act(get, "recorder.toggle", &json!({}), 7).unwrap();
        assert_eq!(p[0].1["recording"], true);
        assert!(
            act(get, "recorder.stop", &json!({}), 0).is_err(),
            "not recording"
        );
        assert!(handles("screenshot.region") && !handles("audio.mute"));
    }
}
