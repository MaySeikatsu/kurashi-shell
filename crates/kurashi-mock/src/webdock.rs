//! The web dock's rules in the mock (MODS.md "Web dock", K38, K40): the mode state machine, the hover and focus
//! reports, the web pins the host keeps loaded, the host reports that edit `mod.webdock`, and the pin edits the
//! daemon makes as settings writes. Pure functions over the document: `state.rs` applies the merge patch that
//! `act` returns. In the product the daemon owns these rules (rule 1); the mock keeps them so the shell and the
//! host can be tested without kurashid.
//!
//! Timing: the mock has no timers and keeps no pointer state. Where the daemon waits (K40: a reveal after 250 ms,
//! 500 ms on a shared edge, a hide after 400 ms, the 24 px grace) the mock applies the change at once. It cannot
//! tell which parts the pointer is still inside, so it approximates: a part's leave hides a shown dock unless it is
//! pinned or engaged, and a part's enter reveals a hidden one. A move from one part to the next then ends where the
//! daemon ends (the card is shown again), though it passes through a hidden dock on the way.
//!
//! Replies: `webdock.add` answers `{pin}` in the daemon. `Outcome` carries only the document patch and the browser
//! URL, so the mock's reply is not carried yet (docs/CONTRACT-CHANGE.md, W20-webdock-daemon).

use std::path::PathBuf;

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
// The refusal keys are the daemon's (`crates/kurashi-mod-webdock/src/dock.rs`), so a shell test sees the same text.
const ERROR_ARGUMENT: &str = "webdock.error.argument";
const ERROR_UNKNOWN_PIN: &str = "webdock.error.unknown_pin";
const ERROR_NOT_A_SITE: &str = "webdock.error.not_a_site";
const ERROR_SIZE: &str = "webdock.error.size";
const ERROR_VIEW: &str = "webdock.error.view";
const ERROR_PERMISSION: &str = "webdock.error.permission";
const ERROR_URL: &str = "webdock.error.url";
const ERROR_ADDRESS: &str = "webdock.error.address";

/// What an action does: the merge patch for `mod.webdock` (none when nothing changes) and a URL the
/// default browser should open (`open_external`, `webdock.host.new_window`).
#[derive(Debug, Default, PartialEq)]
pub struct Outcome {
    pub ops: Option<Value>,
    pub external: Option<String>,
    /// The action's reply (`webdock.add` → `{pin}`, as the daemon answers; row 113).
    pub reply: Option<Value>,
}

impl Outcome {
    fn patch(ops: Value) -> Self {
        Outcome {
            ops: Some(ops),
            ..Outcome::default()
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

/// The document a fresh mock serves: hidden, no pins, the host ready (the mock starts no host), and the settings'
/// defaults as the daemon serves them (`pinned`, `engaged`, `hover`, `reserve`, `indicator`, `new_tabs`, `geometry`).
pub fn initial(profiles: &std::path::Path, icons: &std::path::Path) -> Value {
    json!({
        "available": true,
        "mode": "hidden",
        "size": "phone",
        "pinned": false,
        "engaged": false,
        "hover": true,
        "reserve": false,
        "indicator": true,
        "new_tabs": "dock",
        "edge": "right",
        "geometry": {"strip": 56, "width": 412, "large": 90, "grace": 24},
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
        "webdock.hide" => Ok(Outcome::patch(with_output(
            json!({"mode": "hidden", "engaged": false}),
            args,
        ))),
        "webdock.toggle" => Ok(toggle(doc, args)),
        "webdock.size" => size(doc, args),
        "webdock.hover" => hover(doc, args),
        "webdock.engage" => engage(doc, args),
        "webdock.select" => select(doc, args),
        "webdock.back" => Ok(back(doc)),
        "webdock.pin" => pin(doc, args),
        "webdock.add" => add(doc, args),
        "webdock.remove" => remove(doc, args),
        "webdock.move" => move_pin(doc, args),
        "webdock.retarget" => retarget(doc, args),
        "webdock.view" => view(doc, args),
        "webdock.open_external" => external(arg_str(args, "url")?),
        "webdock.host.loaded" => host_loaded(doc, args),
        "webdock.host.unloaded" => {
            update_pin(doc, pin_arg(args)?, |pin| pin["loaded"] = json!(false))
        }
        "webdock.host.audible" => {
            let on = arg_bool(args, "on")?;
            update_pin(doc, pin_arg(args)?, |pin| pin["audible"] = json!(on))
        }
        "webdock.host.blocked" => host_blocked(doc, args),
        "webdock.host.new_window" => {
            let pins = pins(doc);
            find_pin(&pins, pin_arg(args)?)?;
            external(arg_str(args, "url")?)
        }
        "webdock.host.crashed" => update_pin(doc, pin_arg(args)?, |pin| {
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
/// which holds at most `MAX_LOADED` web pins; an audible pin is never dropped from it. A view pin starts no host,
/// so `keep` does not change.
fn open(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let pins = pins(doc);
    let pin = find_pin(&pins, id)?;
    let mut ops = with_output(json!({"mode": "extended", "shown": id}), args);
    if is_web(pin) {
        ops["keep"] = json!(keep_with(doc, id));
    }
    Ok(Outcome::patch(ops))
}

/// `webdock.toggle`: from hidden, the shown pin's extended card, or the strip when nothing is shown, with the
/// keyboard in the dock (`engaged`); otherwise hidden. The shown pin is kept while hidden.
fn toggle(doc: &Value, args: &Value) -> Outcome {
    if doc["mode"] != "hidden" {
        return Outcome::patch(with_output(
            json!({"mode": "hidden", "engaged": false}),
            args,
        ));
    }
    match doc.get("shown").and_then(Value::as_str) {
        Some(shown) => {
            let mut ops = with_output(json!({"mode": "extended", "engaged": true}), args);
            if pin_is_web(doc, shown) {
                ops["keep"] = json!(keep_with(doc, shown));
            }
            Outcome::patch(ops)
        }
        None => Outcome::patch(with_output(
            json!({"mode": "compact", "engaged": true}),
            args,
        )),
    }
}

/// `webdock.size {size?}`: `phone` or `large`; without an argument it toggles.
fn size(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let size = match args.get("size").and_then(Value::as_str) {
        Some("phone") => "phone",
        Some("large") => "large",
        Some(_) => return Err(Fail::invalid(ERROR_SIZE)),
        None if doc["size"] == "large" => "phone",
        None => "large",
    };
    Ok(Outcome::patch(json!({"size": size})))
}

/// `webdock.hover {part, inside, output, shared?}` (K40), at once: a hidden dock reveals on an enter (the edge with
/// `hover` on; the daemon ignores a strip or card report there, the mock's approximation is in the module doc). A
/// shown dock ignores another output's reports; a part's leave hides it unless it is pinned or engaged.
fn hover(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let part = arg_str(args, "part")?;
    if !matches!(part, "edge" | "strip" | "card") {
        return Err(Fail::invalid(ERROR_ARGUMENT));
    }
    let inside = arg_bool(args, "inside")?;
    let output = arg_str(args, "output")?;
    if part == "edge" && doc["hover"] == false {
        return Ok(Outcome::default());
    }
    if doc["mode"] == "hidden" {
        return Ok(if inside {
            reveal(doc, Some(output))
        } else {
            Outcome::default()
        });
    }
    if doc["output"]
        .as_str()
        .is_some_and(|latched| latched != output)
    {
        return Ok(Outcome::default());
    }
    if inside {
        return Ok(match doc.get("output") {
            Some(_) => Outcome::default(),
            None => Outcome::patch(json!({"output": output})),
        });
    }
    if doc["pinned"] == true || doc["engaged"] == true {
        return Ok(Outcome::default());
    }
    Ok(Outcome::patch(json!({"mode": "hidden"})))
}

/// `webdock.engage {on}` (K40): a part took or lost keyboard focus. Losing it is a leave, and a focus that moves
/// into a hidden dock reveals it (the mock's approximation, as for `hover`).
fn engage(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let on = arg_bool(args, "on")?;
    if doc["mode"] == "hidden" {
        if !on {
            return Ok(Outcome::default());
        }
        let mut out = reveal(doc, None);
        if let Some(ops) = out.ops.as_mut() {
            ops["engaged"] = json!(true);
        }
        return Ok(out);
    }
    let mut ops = json!({"engaged": on});
    if !on && doc["pinned"] != true {
        ops["mode"] = json!("hidden");
    }
    Ok(Outcome::patch(ops))
}

/// `webdock.select {pin, output?}` (K40): a click on a pin shows it extended; a click on the shown pin's icon puts its
/// card away (compact, no `shown`; the pin stays loaded).
fn select(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let pins = pins(doc);
    let pin = find_pin(&pins, id)?;
    let mut ops = with_output(json!({}), args);
    if doc["mode"] == "extended" && doc["shown"] == id {
        ops["mode"] = json!("compact");
        ops["shown"] = Value::Null;
    } else {
        ops["mode"] = json!("extended");
        ops["shown"] = json!(id);
        if is_web(pin) {
            ops["keep"] = json!(keep_with(doc, id));
        }
    }
    Ok(Outcome::patch(ops))
}

/// `webdock.back {}` (K40): Escape on the dock's chrome. Extended goes to compact with no card; compact goes to
/// hidden unless the dock is pinned.
fn back(doc: &Value) -> Outcome {
    match doc["mode"].as_str() {
        Some("extended") => Outcome::patch(json!({"mode": "compact", "shown": null})),
        Some("compact") if doc["pinned"] != true => {
            Outcome::patch(json!({"mode": "hidden", "engaged": false}))
        }
        _ => Outcome::default(),
    }
}

/// `webdock.pin {on?}`: the `pinned` setting (a settings write in the daemon); without an argument it flips.
fn pin(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let on = match args.get("on") {
        None | Some(Value::Null) => None,
        Some(v) => Some(v.as_bool().ok_or_else(|| Fail::invalid(ERROR_ARGUMENT))?),
    };
    let current = doc["pinned"] == true;
    Ok(Outcome::patch(json!({"pinned": on.unwrap_or(!current)})))
}

/// `webdock.add {url, title?}` (K40): a web pin at the end of the list, its id a slug of the host, `-2`, `-3`… when
/// taken. The daemon's reply `{pin}` is not carried (see the module doc).
fn add(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let url = arg_str(args, "url")?;
    if !web_address(url) {
        return Err(Fail::invalid(ERROR_ADDRESS));
    }
    let mut pins = pins(doc);
    let taken: Vec<String> = pins
        .iter()
        .filter_map(|p| p["id"].as_str().map(str::to_string))
        .collect();
    let taken: Vec<&str> = taken.iter().map(String::as_str).collect();
    let id = unique_id(&slug_of(id_text(url)), &taken);
    let title = args
        .get("title")
        .and_then(Value::as_str)
        .filter(|t| !t.is_empty())
        .or_else(|| host_of(url))
        .map_or_else(|| id.clone(), str::to_string);
    pins.push(json!({
        "id": id,
        "kind": "web",
        "title": title,
        "target": url,
        "view": "mobile",
        "profile": id,
        "loaded": false,
    }));
    Ok(Outcome {
        reply: Some(json!({"pin": id})),
        ..Outcome::patch(json!({"pins": pins}))
    })
}

/// `webdock.remove {pin}` (K40): the pin's row goes; a card showing it closes, and the host stops keeping it.
fn remove(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let pins = pins(doc);
    find_pin(&pins, id)?;
    let rest: Vec<Value> = pins.into_iter().filter(|p| p["id"] != id).collect();
    let keep: Vec<String> = kept(doc).into_iter().filter(|k| k != id).collect();
    let mut ops = json!({"pins": rest, "keep": keep});
    if doc["shown"] == id {
        ops["shown"] = Value::Null;
        if doc["mode"] == "extended" {
            ops["mode"] = json!("compact");
        }
    }
    Ok(Outcome::patch(ops))
}

/// `webdock.move {pin, to}` (K40): the pin to index `to` (0-based), clamped to the list.
fn move_pin(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let to = args
        .get("to")
        .and_then(Value::as_i64)
        .ok_or_else(|| Fail::invalid(ERROR_ARGUMENT))?;
    let mut pins = pins(doc);
    let index = pins
        .iter()
        .position(|p| p["id"] == id)
        .ok_or_else(unknown_pin)?;
    let row = pins.remove(index);
    let at = usize::try_from(to.max(0))
        .unwrap_or(usize::MAX)
        .min(pins.len());
    pins.insert(at, row);
    Ok(Outcome::patch(json!({"pins": pins})))
}

/// `webdock.retarget {pin, url}` (K40): "replace the pin with this page". A web pin only; `https`, `http` or `file`.
fn retarget(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let url = arg_str(args, "url")?;
    let mut pins = pins(doc);
    if !is_web(find_pin(&pins, id)?) {
        return Err(Fail::invalid(ERROR_NOT_A_SITE));
    }
    if !web_address(url) {
        return Err(Fail::invalid(ERROR_ADDRESS));
    }
    for pin in pins.iter_mut().filter(|p| p["id"] == id) {
        pin["target"] = json!(url);
    }
    Ok(Outcome::patch(json!({"pins": pins})))
}

/// `webdock.view {pin, view}`: the profile's view, written to every pin that shares the profile
/// (QtWebEngine sets the user agent per profile, MODS.md "Web dock").
fn view(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let view = match args.get("view").and_then(Value::as_str) {
        Some(v @ ("mobile" | "desktop")) => v,
        _ => return Err(Fail::invalid(ERROR_VIEW)),
    };
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
        return Err(Fail::invalid(ERROR_PERMISSION));
    }
    update_pin(doc, pin_arg(args)?, |pin| {
        let mut blocked: Vec<Value> = pin["blocked"].as_array().cloned().unwrap_or_default();
        if !blocked.iter().any(|b| b.as_str() == Some(permission)) {
            blocked.push(json!(permission));
        }
        pin["blocked"] = json!(blocked);
    })
}

/// `webdock.host.loaded {pin, icon?}`: the page loaded; a crash or a blocked chip is over. An icon is taken when it is
/// a path (or `file://` URL) under `dirs.icons`; the daemon refuses any other with `webdock.error.icon` after it has
/// loaded the page, and the mock does the same without the reply.
fn host_loaded(doc: &Value, args: &Value) -> Result<Outcome, Fail> {
    let id = pin_arg(args)?;
    let icon = args
        .get("icon")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .and_then(|raw| icon_url(doc, raw));
    update_pin(doc, id, |pin| {
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
        return Err(Fail::invalid(ERROR_URL));
    }
    Ok(Outcome {
        external: Some(url.to_string()),
        ..Outcome::default()
    })
}

/// The reveal (K40): the strip, and the card of the shown pin (`reopen_last`, on by default in the mock).
fn reveal(doc: &Value, output: Option<&str>) -> Outcome {
    let mut ops = json!({"mode": "compact"});
    if let Some(output) = output {
        ops["output"] = json!(output);
    }
    if let Some(shown) = doc.get("shown").and_then(Value::as_str) {
        ops["mode"] = json!("extended");
        if pin_is_web(doc, shown) {
            ops["keep"] = json!(keep_with(doc, shown));
        }
    }
    Outcome::patch(ops)
}

/// The `keep` the host holds once `id` is shown (MODS.md "Lifecycle"): `id` first, then the most recent web pins up
/// to `MAX_LOADED`, then any audible pin beyond the cap.
fn keep_with(doc: &Value, id: &str) -> Vec<String> {
    let pins = pins(doc);
    let mut keep: Vec<String> = vec![id.to_string()];
    keep.extend(
        kept(doc)
            .into_iter()
            .filter(|k| k != id && find_pin(&pins, k).is_ok()),
    );
    let rest: Vec<String> = keep.split_off(keep.len().min(MAX_LOADED));
    keep.extend(
        rest.into_iter()
            .filter(|k| find_pin(&pins, k).is_ok_and(|p| p["audible"] == true)),
    );
    keep
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

fn pin_is_web(doc: &Value, id: &str) -> bool {
    find_pin(&pins(doc), id).is_ok_and(is_web)
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

/// A pin argument: a missing or empty `pin` is an unknown pin, as the daemon answers it.
fn pin_arg(args: &Value) -> Result<&str, Fail> {
    args.get("pin")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(unknown_pin)
}

fn arg_str<'a>(args: &'a Value, key: &str) -> Result<&'a str, Fail> {
    args.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| Fail::invalid(ERROR_ARGUMENT))
}

fn arg_bool(args: &Value, key: &str) -> Result<bool, Fail> {
    args.get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| Fail::invalid(ERROR_ARGUMENT))
}

/// A web pin's address: `https`, `http` or `file`, with something after the scheme (the daemon's rule).
fn web_address(url: &str) -> bool {
    ["https://", "http://", "file:"].iter().any(|scheme| {
        url.strip_prefix(scheme)
            .is_some_and(|rest| !rest.is_empty())
    })
}

/// The host of an `http` or `https` address: the authority without the user name and the port.
fn host_of(url: &str) -> Option<&str> {
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))?;
    let authority = rest.split(['/', '?', '#']).next()?;
    let host = authority.rsplit('@').next()?.split(':').next()?;
    (!host.is_empty()).then_some(host)
}

/// The text a pin's id is made of: the host of a web address, else a file's name without its extension.
fn id_text(url: &str) -> &str {
    match host_of(url) {
        Some(host) => host,
        None => url
            .rsplit('/')
            .find(|part| !part.is_empty())
            .map_or("", |name| {
                name.rsplit_once('.').map_or(name, |(stem, _)| stem)
            }),
    }
}

/// The daemon's slug rule for a pin id (`[a-z0-9-]`, 32 characters at most; `www.` dropped; `site` when empty).
fn slug_of(text: &str) -> String {
    let text = text.strip_prefix("www.").unwrap_or(text);
    let mut slug = String::new();
    for c in text.chars() {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let kept: String = slug.trim_matches('-').chars().take(32).collect();
    let kept = kept.trim_end_matches('-');
    if kept.is_empty() {
        "site".into()
    } else {
        kept.to_string()
    }
}

/// `base`, or `base-2`, `base-3`… for the first that no pin has.
fn unique_id(base: &str, taken: &[&str]) -> String {
    if !taken.contains(&base) {
        return base.into();
    }
    let mut n = 2;
    loop {
        let suffix = format!("-{n}");
        let stem: String = base.chars().take(32 - suffix.len()).collect();
        let candidate = format!("{}{suffix}", stem.trim_end_matches('-'));
        if !taken.contains(&candidate.as_str()) {
            return candidate;
        }
        n += 1;
    }
}

/// The icon URL a host reports, if it is a path or `file://` URL under `dirs.icons` with no `.` or `..` step.
fn icon_url(doc: &Value, icon: &str) -> Option<String> {
    let icons = doc["dirs"]["icons"].as_str()?;
    let path = icon.strip_prefix("file://").unwrap_or(icon);
    let under = path.starts_with('/')
        && path.starts_with(icons)
        && path[icons.len()..].starts_with('/')
        && !path.split('/').any(|step| step == ".." || step == ".");
    under.then(|| format!("file://{path}"))
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

    fn refusal_key(r: Result<Outcome, Fail>) -> String {
        match r {
            Err(f) => f.msg,
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
    fn the_start_document_has_the_fixture_keys() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../fixtures/ipc/server/snap_mod_webdock.json"
        ))
        .unwrap();
        let fixture = &fixture["data"];
        let d = doc();
        let keys = |v: &Value| {
            let mut k: Vec<String> = v
                .as_object()
                .map(|m| m.keys().cloned().collect())
                .unwrap_or_default();
            k.sort();
            k
        };
        for key in [
            "available",
            "pinned",
            "engaged",
            "hover",
            "reserve",
            "indicator",
            "new_tabs",
            "edge",
            "geometry",
            "keep",
            "pins",
            "host",
            "dirs",
            "mode",
            "size",
        ] {
            assert!(d.get(key).is_some(), "{key} is served");
            assert!(fixture.get(key).is_some(), "{key} is in the fixture");
        }
        assert_eq!(keys(&d["geometry"]), keys(&fixture["geometry"]));
        assert_eq!(d["geometry"]["grace"], 24);
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
        let f = act(&d, "webdock.open", &json!({})).unwrap_err();
        assert_eq!(
            f.msg, "webdock.error.unknown_pin",
            "a missing pin is unknown"
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
        assert_eq!(d["engaged"], true, "a toggle takes the keyboard");
        run(&mut d, "webdock.toggle", json!({})).unwrap();
        assert_eq!(d["mode"], "hidden");
        assert_eq!(d["engaged"], false);
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
            refusal_key(act(&d, "webdock.size", &json!({"size": "tiny"}))),
            "webdock.error.size"
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
            refusal_key(act(
                &d,
                "webdock.view",
                &json!({"pin": "weather", "view": "mobile"})
            )),
            "webdock.error.not_a_site"
        );
        let f = act(&d, "webdock.view", &json!({"pin": "zz", "view": "mobile"})).unwrap_err();
        assert_eq!(f.msg, "webdock.error.unknown_pin");
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.view",
                &json!({"pin": "a", "view": "tablet"})
            )),
            "webdock.error.view"
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
            refusal_key(act(
                &d,
                "webdock.open_external",
                &json!({"url": "file:///etc/passwd"})
            )),
            "webdock.error.url"
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
            refusal_key(act(
                &d,
                "webdock.host.blocked",
                &json!({"pin": "b", "permission": "smell"})
            )),
            "webdock.error.permission"
        );
        assert_eq!(
            refusal_key(act(&d, "webdock.host.loaded", &json!({"pin": "zz"}))),
            "webdock.error.unknown_pin"
        );
        // An icon outside the cache is not taken; the page still loads.
        run(
            &mut d,
            "webdock.host.loaded",
            json!({"pin": "b", "icon": "/etc/passwd"}),
        )
        .unwrap();
        assert_eq!(d["pins"][1]["loaded"], true);
        assert_eq!(d["pins"][1]["icon"], "file:///cache/icons/b.png");
        run(
            &mut d,
            "webdock.host.loaded",
            json!({"pin": "c", "icon": "/cache/icons/../../etc/x.png"}),
        )
        .unwrap();
        assert!(d["pins"][2].get("icon").is_none());
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

    #[test]
    fn a_hover_reveals_a_hidden_dock_at_once_and_a_leave_hides_a_shown_one() {
        let mut d = doc();
        run(&mut d, "webdock.open", json!({"pin": "b"})).unwrap();
        run(&mut d, "webdock.hide", json!({})).unwrap();
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "edge", "inside": true, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(
            d["mode"], "extended",
            "reopen last, as the daemon's default"
        );
        assert_eq!(d["output"], "DP-1");
        assert_eq!(d["keep"], json!(["b"]));

        // The card's leave hides the dock (nothing pins or engages it).
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "card", "inside": false, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "hidden");
        assert_eq!(d["shown"], "b", "hide keeps the shown pin");

        // An edge leave while hidden changes nothing; another output's reports are ignored while shown.
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "edge", "inside": false, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "hidden");
        run(&mut d, "webdock.collapse", json!({})).unwrap();
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "strip", "inside": false, "output": "DP-2"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "compact", "DP-2's leave is not this dock's");
    }

    #[test]
    fn a_pinned_or_engaged_dock_is_not_hidden_by_a_leave_and_a_hover_off_ignores_the_edge() {
        let mut d = doc();
        run(
            &mut d,
            "webdock.open",
            json!({"pin": "b", "output": "DP-1"}),
        )
        .unwrap();
        run(&mut d, "webdock.engage", json!({"on": true})).unwrap();
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "card", "inside": false, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "extended", "engaged holds it");
        run(&mut d, "webdock.engage", json!({"on": false})).unwrap();
        assert_eq!(d["mode"], "hidden", "losing focus is a leave");

        let mut d = doc();
        run(&mut d, "webdock.pin", json!({"on": true})).unwrap();
        assert_eq!(d["pinned"], true);
        run(&mut d, "webdock.open", json!({"pin": "b"})).unwrap();
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "card", "inside": false, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "extended", "pinned holds it");
        run(&mut d, "webdock.pin", json!({})).unwrap();
        assert_eq!(d["pinned"], false, "no argument flips the value in effect");

        let mut d = doc();
        d["hover"] = json!(false);
        run(
            &mut d,
            "webdock.hover",
            json!({"part": "edge", "inside": true, "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(d["mode"], "hidden", "hover off ignores the edge");
    }

    #[test]
    fn back_steps_down_and_a_pinned_compact_dock_stays_compact() {
        let mut d = doc();
        run(&mut d, "webdock.open", json!({"pin": "b"})).unwrap();
        run(&mut d, "webdock.back", json!({})).unwrap();
        assert_eq!(d["mode"], "compact");
        assert!(d.get("shown").is_none());
        run(&mut d, "webdock.back", json!({})).unwrap();
        assert_eq!(d["mode"], "hidden");
        run(&mut d, "webdock.back", json!({})).unwrap();
        assert_eq!(d["mode"], "hidden");

        run(&mut d, "webdock.pin", json!({"on": true})).unwrap();
        run(&mut d, "webdock.collapse", json!({})).unwrap();
        run(&mut d, "webdock.back", json!({})).unwrap();
        assert_eq!(d["mode"], "compact", "pinned: stays compact");
    }

    #[test]
    fn select_shows_a_pin_and_a_second_click_on_it_puts_its_card_away() {
        let mut d = doc();
        run(
            &mut d,
            "webdock.select",
            json!({"pin": "b", "output": "DP-1"}),
        )
        .unwrap();
        assert_eq!(
            (d["mode"].as_str(), d["shown"].as_str()),
            (Some("extended"), Some("b"))
        );
        assert_eq!(d["keep"], json!(["b"]));
        run(&mut d, "webdock.select", json!({"pin": "b"})).unwrap();
        assert_eq!(d["mode"], "compact");
        assert!(d.get("shown").is_none());
        assert_eq!(d["keep"], json!(["b"]), "the pin stays loaded");
        run(&mut d, "webdock.select", json!({"pin": "weather"})).unwrap();
        assert_eq!(d["mode"], "extended");
        assert_eq!(
            refusal_key(act(&d, "webdock.select", &json!({"pin": "zz"}))),
            "webdock.error.unknown_pin"
        );
    }

    #[test]
    fn add_remove_move_and_retarget_edit_the_pins_as_the_daemon_does() {
        let mut d = doc();
        let out = act(
            &d,
            "webdock.add",
            &json!({"url": "https://www.example.org/x"}),
        )
        .unwrap();
        assert_eq!(out.reply, Some(json!({"pin": "example-org"})));
        let ops = out.ops.unwrap();
        let pins = ops["pins"].as_array().unwrap();
        assert_eq!(pins.len(), 7);
        assert_eq!(pins[6]["id"], "example-org");
        assert_eq!(pins[6]["title"], "www.example.org");
        assert_eq!(pins[6]["kind"], "web");
        kurashi_ipc::merge_patch(&mut d, &ops);
        run(
            &mut d,
            "webdock.add",
            json!({"url": "https://example.org/y", "title": "Docs"}),
        )
        .unwrap();
        assert_eq!(d["pins"][7]["id"], "example-org-2", "the next free suffix");
        assert_eq!(d["pins"][7]["title"], "Docs");
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.add",
                &json!({"url": "javascript:alert(1)"})
            )),
            "webdock.error.address"
        );

        run(
            &mut d,
            "webdock.move",
            json!({"pin": "example-org", "to": 0}),
        )
        .unwrap();
        assert_eq!(d["pins"][0]["id"], "example-org");
        run(&mut d, "webdock.move", json!({"pin": "a", "to": 99})).unwrap();
        assert_eq!(
            d["pins"].as_array().unwrap().last().unwrap()["id"],
            "a",
            "clamped"
        );

        run(
            &mut d,
            "webdock.retarget",
            json!({"pin": "b", "url": "file:///home/u/n.html"}),
        )
        .unwrap();
        let b = d["pins"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["id"] == "b")
            .unwrap()
            .clone();
        assert_eq!(b["target"], "file:///home/u/n.html");
        assert_eq!(b["kind"], "web", "every other field stays");
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.retarget",
                &json!({"pin": "weather", "url": "https://x.example.org/"})
            )),
            "webdock.error.not_a_site"
        );
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.retarget",
                &json!({"pin": "b", "url": "javascript:alert(1)"})
            )),
            "webdock.error.address"
        );

        run(&mut d, "webdock.open", json!({"pin": "c"})).unwrap();
        run(&mut d, "webdock.remove", json!({"pin": "c"})).unwrap();
        assert!(d.get("shown").is_none(), "the card closes with its pin");
        assert_eq!(d["mode"], "compact");
        assert!(d["pins"].as_array().unwrap().iter().all(|p| p["id"] != "c"));
        assert_eq!(
            refusal_key(act(&d, "webdock.remove", &json!({"pin": "zz"}))),
            "webdock.error.unknown_pin"
        );
    }

    #[test]
    fn the_hover_engage_and_pin_arguments_are_checked() {
        let d = doc();
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.hover",
                &json!({"part": "nope", "inside": true, "output": "DP-1"})
            )),
            "webdock.error.argument"
        );
        assert_eq!(
            refusal_key(act(
                &d,
                "webdock.hover",
                &json!({"part": "edge", "inside": true})
            )),
            "webdock.error.argument"
        );
        assert_eq!(
            refusal_key(act(&d, "webdock.engage", &json!({"on": "yes"}))),
            "webdock.error.argument"
        );
        assert_eq!(
            refusal_key(act(&d, "webdock.pin", &json!({"on": "yes"}))),
            "webdock.error.argument"
        );
        assert_eq!(
            refusal_key(act(&d, "webdock.move", &json!({"pin": "a"}))),
            "webdock.error.argument"
        );
    }
}
