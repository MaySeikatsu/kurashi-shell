//! The web dock's rules in the mock (MODS.md "Web dock", K38): the mode state machine, the web pins
//! the host keeps loaded, and the host reports that edit `mod.webdock`. Pure functions over the
//! document: `state.rs` applies the merge patch that `act` returns. In the product the daemon owns
//! these rules (rule 1); the mock keeps them so the host can be tested without kurashid.

use std::path::PathBuf;

use kurashid::wiring::ARGS_INVALID;
use serde_json::{Value, json};

use crate::state::Fail;

/// Web pins the host keeps loaded at once (`max_loaded`, MODS.md "Web dock", its default).
const MAX_LOADED: usize = 4;
/// The `permission` a host reports (`webdock.host.blocked`); the header draws a chip for each.
pub const PERMISSIONS: [&str; 8] = [
    "camera",
    "microphone",
    "location",
    "notifications",
    "screen",
    "clipboard",
    "download",
    "other",
];
/// Set on a pin whose renderer stopped (`webdock.host.crashed`) until its next `loaded`.
pub const ERROR_CRASHED: &str = "webdock.error.crashed";
const ERROR_UNKNOWN_PIN: &str = "webdock.error.unknown_pin";
const ERROR_NOT_A_SITE: &str = "webdock.error.not_a_site";

/// What an action does: the merge patch for `mod.webdock` (none when nothing changes) and a URL the
/// default browser should open (`open_external`, `webdock.host.new_window`).
#[derive(Debug, Default, PartialEq)]
pub struct Outcome {
    pub ops: Option<Value>,
    pub external: Option<String>,
}

impl Outcome {
    fn patch(ops: Value) -> Self {
        Outcome {
            ops: Some(ops),
            external: None,
        }
    }
}

/// The `dirs` of `mod.webdock`: profiles under `$XDG_DATA_HOME`, favicons under `$XDG_CACHE_HOME`
/// (the daemon's `{data_dir}` and `{cache_dir}` for the mod, MODS.md "Host processes").
pub fn dir_paths() -> (PathBuf, PathBuf) {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    let base = |var: &str, rel: &str| {
        std::env::var_os(var)
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(rel))
    };
    (
        base("XDG_DATA_HOME", ".local/share").join("kurashi/webdock/profiles"),
        base("XDG_CACHE_HOME", ".cache").join("kurashi/webdock/icons"),
    )
}

/// The document a fresh mock serves: hidden, no pins, the host ready (the mock starts no host).
pub fn initial(profiles: &std::path::Path, icons: &std::path::Path) -> Value {
    json!({
        "available": true,
        "mode": "hidden",
        "size": "phone",
        "edge": "right",
        "geometry": {"strip": 56, "width": 412, "large": 90},
        "keep": [],
        "pins": [],
        "host": {"state": "ready"},
        "dirs": {
            "profiles": profiles.display().to_string(),
            "icons": icons.display().to_string(),
        },
    })
}

/// Applies one `webdock.*` action or host report to `doc` and says what to do outside the document.
pub fn act(doc: &Value, action: &str, args: &Value) -> Result<Outcome, Fail> {
    match action {
        "webdock.open" => open(doc, args),
        "webdock.collapse" => Ok(Outcome::patch(json!({"mode": "compact", "shown": null}))),
        "webdock.hide" => Ok(Outcome::patch(with_output(json!({"mode": "hidden"}), args))),
        "webdock.toggle" => Ok(toggle(doc, args)),
        "webdock.size" => size(doc, args),
        "webdock.view" => view(doc, args),
        "webdock.open_external" => external(arg_str(args, "url")?),
        "webdock.host.loaded" => host_loaded(doc, args),
        "webdock.host.unloaded" => update_pin(doc, arg_str(args, "pin")?, |pin| {
            pin["loaded"] = json!(false)
        }),
        "webdock.host.audible" => {
            let on = arg_bool(args, "on")?;
            update_pin(doc, arg_str(args, "pin")?, |pin| pin["audible"] = json!(on))
        }
        "webdock.host.blocked" => host_blocked(doc, args),
        "webdock.host.new_window" => {
            let pins = pins(doc);
            find_pin(&pins, arg_str(args, "pin")?)?;
            external(arg_str(args, "url")?)
        }
        "webdock.host.crashed" => update_pin(doc, arg_str(args, "pin")?, |pin| {
            pin["loaded"] = json!(false);
            pin["error"] = json!(ERROR_CRASHED);
        }),
        _ => Err(Fail {
            kind: "unknown_action",
            msg: format!("no action {action}"),
        }),
    }
}

/// `webdock.open {pin, output?}`: extended, showing the pin. A web pin moves to the front of `keep`,
/// which holds at most `MAX_LOADED` web pins; an audible pin is never dropped from it. A view pin
/// starts no host, so `keep` does not change.
fn open(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = arg_str(args, "pin")?;
    let pins = pins(doc);
    let pin = find_pin(&pins, id)?;
    let mut ops = with_output(json!({"mode": "extended", "shown": id}), args);
    if is_web(pin) {
        let mut keep: Vec<String> = vec![id.to_string()];
        keep.extend(
            kept(doc)
                .into_iter()
                .filter(|k| k.as_str() != id && find_pin(&pins, k).is_ok()),
        );
        let audible = |k: &String| find_pin(&pins, k).is_ok_and(|p| p["audible"] == true);
        let rest: Vec<String> = keep.split_off(keep.len().min(MAX_LOADED));
        keep.extend(rest.iter().filter(|k| audible(k)).cloned());
        ops["keep"] = json!(keep);
    }
    Ok(Outcome::patch(ops))
}

/// `webdock.toggle`: from hidden, the shown pin's extended card (or compact when nothing is shown);
/// otherwise hidden. The shown pin is kept while hidden.
fn toggle(doc: &Value, args: &Value) -> Outcome {
    let mode = if doc["mode"] != "hidden" {
        "hidden"
    } else if doc.get("shown").is_some() {
        "extended"
    } else {
        "compact"
    };
    Outcome::patch(with_output(json!({"mode": mode}), args))
}

/// `webdock.size {size?}`: `phone` or `large`; without an argument it toggles.
fn size(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let size = match args.get("size").and_then(Value::as_str) {
        Some("phone") => "phone",
        Some("large") => "large",
        Some(_) => return Err(Fail::invalid(ARGS_INVALID)),
        None if doc["size"] == "large" => "phone",
        None => "large",
    };
    Ok(Outcome::patch(json!({"size": size})))
}

/// `webdock.view {pin, view}`: the profile's view, written to every pin that shares the profile
/// (QtWebEngine sets the user agent per profile, MODS.md "Web dock").
fn view(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = arg_str(args, "pin")?;
    let view = arg_str(args, "view")?;
    if !matches!(view, "mobile" | "desktop") {
        return Err(Fail::invalid(ARGS_INVALID));
    }
    let mut pins = pins(doc);
    let profile = {
        let pin = find_pin(&pins, id)?;
        if !is_web(pin) {
            return Err(Fail::invalid(ERROR_NOT_A_SITE));
        }
        effective_profile(pin)
    };
    for pin in pins.iter_mut() {
        if is_web(pin) && effective_profile(pin) == profile {
            pin["view"] = json!(view);
        }
    }
    Ok(Outcome::patch(json!({"pins": pins})))
}

/// `webdock.host.blocked {pin, permission}`: the chip stays until the next `loaded`.
fn host_blocked(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let permission = arg_str(args, "permission")?;
    if !PERMISSIONS.contains(&permission) {
        return Err(Fail::invalid(ARGS_INVALID));
    }
    update_pin(doc, arg_str(args, "pin")?, |pin| {
        let mut blocked: Vec<Value> = pin["blocked"].as_array().cloned().unwrap_or_default();
        if !blocked.iter().any(|b| b.as_str() == Some(permission)) {
            blocked.push(json!(permission));
        }
        pin["blocked"] = json!(blocked);
    })
}

/// `webdock.host.loaded {pin, icon?}`: the page loaded; a crash or a blocked chip is over.
fn host_loaded(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let icon = args.get("icon").and_then(Value::as_str).map(str::to_string);
    update_pin(doc, arg_str(args, "pin")?, |pin| {
        pin["loaded"] = json!(true);
        if let Some(obj) = pin.as_object_mut() {
            obj.remove("error");
            obj.remove("blocked");
        }
        if let Some(icon) = &icon {
            pin["icon"] = json!(icon);
        }
    })
}

/// `open_external {url}` and `new_window`: http and https only, as `xdg-open` is asked (MODS.md).
fn external(url: &str) -> Result<Outcome, Fail> {
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err(Fail::invalid(ARGS_INVALID));
    }
    Ok(Outcome {
        ops: None,
        external: Some(url.to_string()),
    })
}

/// Changes one pin, found by id, and returns the whole `pins` array as the patch (arrays replace).
fn update_pin(doc: &Value, id: &str, change: impl FnOnce(&mut Value)) -> Result<Outcome, Fail> {
    let mut pins = pins(doc);
    let pin = pins
        .iter_mut()
        .find(|p| p["id"] == id)
        .ok_or_else(unknown_pin)?;
    change(pin);
    Ok(Outcome::patch(json!({"pins": pins})))
}

fn pins(doc: &Value) -> Vec<Value> {
    doc["pins"].as_array().cloned().unwrap_or_default()
}

/// The web pins in `keep`, most recently shown first.
fn kept(doc: &Value) -> Vec<String> {
    doc["keep"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn find_pin<'a>(pins: &'a [Value], id: &str) -> Result<&'a Value, Fail> {
    pins.iter().find(|p| p["id"] == id).ok_or_else(unknown_pin)
}

fn unknown_pin() -> Fail {
    Fail::invalid(ERROR_UNKNOWN_PIN)
}

fn is_web(pin: &Value) -> bool {
    pin["kind"] == "web"
}

/// A pin's profile: its own, or its id (the daemon's effective profile).
fn effective_profile(pin: &Value) -> String {
    pin["profile"]
        .as_str()
        .or(pin["id"].as_str())
        .unwrap_or_default()
        .to_string()
}

/// `output` from the arguments, when given, on the patch.
fn with_output(mut ops: Value, args: &Value) -> Value {
    if let Some(output) = args.get("output").and_then(Value::as_str) {
        ops["output"] = json!(output);
    }
    ops
}

fn arg_str<'a>(args: &'a Value, key: &str) -> Result<&'a str, Fail> {
    args.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

fn arg_bool(args: &Value, key: &str) -> Result<bool, Fail> {
    args.get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| Fail::invalid(ARGS_INVALID))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn web(id: &str) -> Value {
        json!({"id": id, "kind": "web", "title": id, "target": format!("file:///{id}.html")})
    }

    /// Five web pins (a, b, c, d, e), one view pin (weather), and the start document.
    fn doc() -> Value {
        let mut d = initial(
            std::path::Path::new("/data/profiles"),
            std::path::Path::new("/cache/icons"),
        );
        d["pins"] = json!([
            web("a"),
            web("b"),
            web("c"),
            web("d"),
            web("e"),
            {"id": "weather", "kind": "view", "title": "Weather", "target": "mod:weather:weather"},
        ]);
        d
    }

    /// Applies the outcome's patch the way state.rs does, and returns the new document.
    fn run(doc: &mut Value, action: &str, args: Value) -> Result<Outcome, Fail> {
        let out = act(doc, action, &args)?;
        if let Some(ops) = &out.ops {
            kurashi_ipc::merge_patch(doc, ops);
        }
        Ok(out)
    }

    fn refused(r: Result<Outcome, Fail>) -> &'static str {
        match r {
            Err(f) => f.kind,
            Ok(_) => panic!("expected a refusal"),
        }
    }

    #[test]
    fn the_start_document_is_hidden_with_no_pins_and_the_dirs_under_xdg() {
        let d = doc();
        assert_eq!(d["mode"], "hidden");
        assert_eq!(d["host"]["state"], "ready");
        assert_eq!(d["dirs"]["profiles"], "/data/profiles");
        assert_eq!(d["dirs"]["icons"], "/cache/icons");
        assert!(d.get("shown").is_none(), "no key for an absent value");
        let (profiles, icons) = dir_paths();
        assert!(profiles.ends_with("kurashi/webdock/profiles"));
        assert!(icons.ends_with("kurashi/webdock/icons"));
    }

    #[test]
    fn open_shows_the_pin_and_keeps_the_last_four_web_pins_most_recent_first() {
        let mut d = doc();
        for id in ["a", "b", "c", "d", "e"] {
            run(&mut d, "webdock.open", json!({"pin": id})).unwrap();
        }
        assert_eq!(d["mode"], "extended");
        assert_eq!(d["shown"], "e");
        assert_eq!(d["keep"], json!(["e", "d", "c", "b"]));
        // A view pin starts no host: it is shown, and `keep` does not change.
        run(&mut d, "webdock.open", json!({"pin": "weather"})).unwrap();
        assert_eq!(d["shown"], "weather");
        assert_eq!(d["keep"], json!(["e", "d", "c", "b"]));
    }

    #[test]
    fn an_audible_pin_is_never_dropped_from_keep() {
        let mut d = doc();
        d["pins"][0]["audible"] = json!(true); // a
        run(&mut d, "webdock.open", json!({"pin": "a"})).unwrap();
        for id in ["b", "c", "d", "e"] {
            run(&mut d, "webdock.open", json!({"pin": id})).unwrap();
        }
        let keep = d["keep"].as_array().unwrap();
        assert!(keep.contains(&json!("a")), "{keep:?}");
        assert!(keep.contains(&json!("e")));
    }

    #[test]
    fn open_takes_an_output_and_refuses_an_unknown_pin_with_its_key() {
        let mut d = doc();
        run(
            &mut d,
            "webdock.open",
            json!({"pin": "b", "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["output"], "DP-1");
        let f = act(&d, "webdock.open", &json!({"pin": "zz"})).unwrap_err();
        assert_eq!(
            (f.kind, f.msg.as_str()),
            ("invalid", "webdock.error.unknown_pin")
        );
    }

    #[test]
    fn collapse_clears_shown_and_hide_keeps_it() {
        let mut d = doc();
        run(&mut d, "webdock.open", json!({"pin": "b"})).unwrap();
        run(&mut d, "webdock.hide", json!({})).unwrap();
        assert_eq!(
            (d["mode"].as_str(), d["shown"].as_str()),
            (Some("hidden"), Some("b"))
        );
        run(&mut d, "webdock.collapse", json!({})).unwrap();
        assert_eq!(d["mode"], "compact");
        assert!(d.get("shown").is_none());
        assert_eq!(
            d["keep"],
            json!(["b"]),
            "collapse leaves the loaded pins loaded"
        );
    }

    #[test]
    fn toggle_reopens_the_shown_pin_from_hidden_or_goes_compact_and_back() {
        let mut d = doc();
        run(&mut d, "webdock.toggle", json!({})).unwrap();
        assert_eq!(d["mode"], "compact", "nothing shown yet");
        run(&mut d, "webdock.toggle", json!({})).unwrap();
        assert_eq!(d["mode"], "hidden");
        run(&mut d, "webdock.open", json!({"pin": "c"})).unwrap();
        run(&mut d, "webdock.toggle", json!({})).unwrap();
        assert_eq!(d["mode"], "hidden");
        run(&mut d, "webdock.toggle", json!({})).unwrap();
        assert_eq!(
            (d["mode"].as_str(), d["shown"].as_str()),
            (Some("extended"), Some("c"))
        );
    }

    #[test]
    fn size_sets_phone_or_large_toggles_without_an_argument_and_refuses_the_rest() {
        let mut d = doc();
        run(&mut d, "webdock.size", json!({"size": "large"})).unwrap();
        assert_eq!(d["size"], "large");
        run(&mut d, "webdock.size", json!({})).unwrap();
        assert_eq!(d["size"], "phone");
        assert_eq!(
            refused(act(&d, "webdock.size", &json!({"size": "tiny"}))),
            "invalid"
        );
    }

    #[test]
    fn view_writes_every_pin_that_shares_the_profile_and_refuses_views_and_unknown_pins() {
        let mut d = doc();
        d["pins"][0]["profile"] = json!("work"); // a
        d["pins"][1]["profile"] = json!("work"); // b
        run(
            &mut d,
            "webdock.view",
            json!({"pin": "b", "view": "desktop"}),
        )
        .unwrap();
        assert_eq!(d["pins"][0]["view"], "desktop", "a shares b's profile");
        assert_eq!(d["pins"][1]["view"], "desktop");
        assert!(d["pins"][2].get("view").is_none(), "c has its own profile");
        assert_eq!(
            refused(act(
                &d,
                "webdock.view",
                &json!({"pin": "weather", "view": "mobile"})
            )),
            "invalid"
        );
        let f = act(&d, "webdock.view", &json!({"pin": "zz", "view": "mobile"})).unwrap_err();
        assert_eq!(f.msg, "webdock.error.unknown_pin");
        assert_eq!(
            refused(act(
                &d,
                "webdock.view",
                &json!({"pin": "a", "view": "tablet"})
            )),
            "invalid"
        );
    }

    #[test]
    fn open_external_takes_http_and_https_only_and_changes_no_document() {
        let d = doc();
        let out = act(
            &d,
            "webdock.open_external",
            &json!({"url": "https://example.org/x"}),
        )
        .unwrap();
        assert_eq!(out.ops, None);
        assert_eq!(out.external.as_deref(), Some("https://example.org/x"));
        assert_eq!(
            refused(act(
                &d,
                "webdock.open_external",
                &json!({"url": "file:///etc/passwd"})
            )),
            "invalid"
        );
        assert_eq!(
            refused(act(
                &d,
                "webdock.open_external",
                &json!({"url": "javascript:alert(1)"})
            )),
            "invalid"
        );
    }

    #[test]
    fn host_reports_change_the_pin_the_way_the_host_describes_it() {
        let mut d = doc();
        run(
            &mut d,
            "webdock.host.blocked",
            json!({"pin": "b", "permission": "camera"}),
        )
        .unwrap();
        run(
            &mut d,
            "webdock.host.blocked",
            json!({"pin": "b", "permission": "camera"}),
        )
        .unwrap();
        assert_eq!(
            d["pins"][1]["blocked"],
            json!(["camera"]),
            "one chip per permission"
        );
        run(&mut d, "webdock.host.crashed", json!({"pin": "b"})).unwrap();
        assert_eq!(d["pins"][1]["error"], ERROR_CRASHED);
        assert_eq!(d["pins"][1]["loaded"], false);
        run(
            &mut d,
            "webdock.host.loaded",
            json!({"pin": "b", "icon": "file:///cache/icons/b.png"}),
        )
        .unwrap();
        assert_eq!(d["pins"][1]["loaded"], true);
        assert_eq!(d["pins"][1]["icon"], "file:///cache/icons/b.png");
        assert!(
            d["pins"][1].get("error").is_none(),
            "loaded ends the crash state"
        );
        assert!(
            d["pins"][1].get("blocked").is_none(),
            "and the blocked chips"
        );
        run(
            &mut d,
            "webdock.host.audible",
            json!({"pin": "b", "on": true}),
        )
        .unwrap();
        assert_eq!(d["pins"][1]["audible"], true);
        run(&mut d, "webdock.host.unloaded", json!({"pin": "b"})).unwrap();
        assert_eq!(d["pins"][1]["loaded"], false);
        assert_eq!(
            refused(act(
                &d,
                "webdock.host.blocked",
                &json!({"pin": "b", "permission": "smell"})
            )),
            "invalid"
        );
        assert_eq!(
            refused(act(&d, "webdock.host.loaded", &json!({"pin": "zz"}))),
            "invalid"
        );
    }

    #[test]
    fn new_window_goes_to_the_browser_and_an_unknown_action_is_refused() {
        let d = doc();
        let out = act(
            &d,
            "webdock.host.new_window",
            &json!({"pin": "a", "url": "https://example.org/"}),
        )
        .unwrap();
        assert_eq!(out.external.as_deref(), Some("https://example.org/"));
        assert_eq!(out.ops, None);
        let f = act(&d, "webdock.nope", &json!({})).unwrap_err();
        assert_eq!(f.kind, "unknown_action");
    }
}
