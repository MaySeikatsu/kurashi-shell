//! The Mod Editor's four on the mock (W94, K154; PROTOCOL §6): the page is built on `just mock` against the same
//! generator and ruleset as the daemon (`kurashi_mods::editor`), so its files and its live check are the real ones.
//! Nothing is written: `mod.new` answers as the daemon would and the mock's `mods` document stays as it is.

use kurashi_mods::editor;
use serde_json::{Value, json};

use crate::state::Fail;

/// The ids the mock treats as taken (its `mods` document's).
const TAKEN: &[&str] = &[
    "timer",
    "weather",
    "sysmon",
    "wallpaper",
    "webdock",
    "hello",
];

fn version() -> semver::Version {
    semver::Version::parse(env!("CARGO_PKG_VERSION")).expect("crate version")
}

fn refusal(e: &kurashi_mods::scaffold::ScaffoldError) -> Fail {
    match editor::error_key(e) {
        (key, true) => Fail::unavailable(key),
        (key, false) => Fail::invalid(key),
    }
}

fn draft(spec: &Value) -> Result<Value, Fail> {
    let s = editor::spec(spec).ok_or_else(|| Fail::invalid("error.args.invalid"))?;
    if TAKEN.contains(&s.id.as_str()) {
        return Err(Fail::invalid("mods.new.error.id_taken"));
    }
    static DRAFTS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let scratch = std::env::temp_dir().join(format!(
        "kurashi-mock-draft-{}-{}",
        std::process::id(),
        DRAFTS.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    editor::check_draft(&s, &scratch, &version()).map_err(|e| refusal(&e))
}

/// `query points`.
pub fn points() -> Vec<Value> {
    editor::points()
}

/// `mod.check`, `mod.new`, `mod.rescan`; `None` for any other action.
pub fn act(action: &str, args: &Value) -> Option<Result<Option<Value>, Fail>> {
    Some(match action {
        "mod.check" if args["id"].is_string() => Ok(Some(json!({
            "id": args["id"], "passed": true, "errors": 0, "notes": 0, "findings": [],
        }))),
        "mod.check" => draft(&args["spec"]).map(Some),
        "mod.new" => draft(&args["spec"]).map(|mut d| {
            let id = d["id"].as_str().unwrap_or_default().to_owned();
            if let Some(o) = d.as_object_mut() {
                o.remove("files");
            }
            Some(json!({ "path": format!("/home/you/.local/share/kurashi/mods/{id}"), "check": d }))
        }),
        "mod.rescan" => Ok(None),
        _ => return None,
    })
}
