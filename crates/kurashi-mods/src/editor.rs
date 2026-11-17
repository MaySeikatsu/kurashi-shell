//! What the Mod Editor's messages are made of (W94, K154; PROTOCOL §6 "The Mod Editor's four"), in one place for the
//! daemon and the mock (rule 10): the points registry as the page's checklist reads it, the scaffold's spec from JSON,
//! the check's report as JSON, and a draft checked without staying on disk.

use std::path::Path;

use semver::Version;
use serde_json::{Value, json};

use crate::check::{self, Level, Report};
use crate::points::POINTS;
use crate::scaffold::{ScaffoldError, Spec, part_of};

/// The registry of extension points, each with the scaffold's part that makes it (absent where it has none).
pub fn points() -> Vec<Value> {
    POINTS
        .iter()
        .map(|p| {
            let mut v = serde_json::to_value(p).unwrap_or_default();
            if let Some(part) = part_of(p.id) {
                v["part"] = part.into();
            }
            v
        })
        .collect()
}

/// The check's report: `{id, passed, errors, notes, rules: [rule…], findings: [{rule, level, at, detail}]}`.
pub fn report(r: &Report) -> Value {
    json!({
        "id": r.id,
        "passed": r.passed(),
        "errors": r.count(Level::Error),
        "notes": r.count(Level::Warn),
        // Every rule the check holds a mod to, in the order a list shows them: the ones with no finding are met.
        "rules": check::RULES,
        "findings": r.findings.iter().map(|f| json!({
            "rule": f.rule, "level": f.level, "at": f.at, "detail": f.detail,
        })).collect::<Vec<_>>(),
    })
}

/// The scaffold's spec from an action's `spec` argument; `None` when it is not an object.
pub fn spec(v: &Value) -> Option<Spec> {
    if !v.is_object() {
        return None;
    }
    let text = |k: &str| v[k].as_str().unwrap_or_default().to_owned();
    let list = |k: &str| -> Vec<String> {
        v[k].as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default()
    };
    Some(Spec {
        id: text("id"),
        name: text("name"),
        icon: text("icon"),
        description: text("description"),
        with: list("with"),
        uses: list("uses"),
        host: v["host"].as_str().map(str::to_owned),
        skips: v["skips"]
            .as_object()
            .into_iter()
            .flatten()
            .filter_map(|(k, why)| Some((k.clone(), why.as_str()?.to_owned())))
            .collect(),
    })
}

/// A scaffold error's key (`mods.new.error.*`), and whether it is the folder that could not be written (`unavailable`
/// rather than `invalid`).
pub fn error_key(e: &ScaffoldError) -> (String, bool) {
    // I604: a refusal that names what it is about keeps the name after its key (`mods.new.error.skip_empty: desk`), so
    // the page can mark that field; every other detail (a path, an id) stays out of the message.
    if let ScaffoldError::SkipEmpty(_) = e {
        return (e.to_string(), false);
    }
    let key = e
        .to_string()
        .split(':')
        .next()
        .unwrap_or_default()
        .to_owned();
    (key, matches!(e, ScaffoldError::Write(_)))
}

/// A draft's report and files: written into `scratch` (a folder of the caller's that does not exist yet), checked and
/// removed — nothing of it stays.
pub fn check_draft(s: &Spec, scratch: &Path, daemon: &Version) -> Result<Value, ScaffoldError> {
    let files = s.files()?;
    let checked = s.write(scratch).map(|dir| check::check_dir(&dir, daemon));
    let _ = std::fs::remove_dir_all(scratch);
    let mut data = report(&checked?);
    data["files"] = files
        .iter()
        .map(|(path, text)| json!({"path": path.to_string_lossy(), "text": text}))
        .collect();
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_draft_is_checked_and_nothing_of_it_stays() {
        let tmp = tempfile::tempdir().unwrap();
        let scratch = tmp.path().join("draft");
        let s = spec(&json!({
            "id": "tea", "name": "Tea", "icon": "emoji_food_beverage", "description": "A cup.",
            "with": ["widget", "panel"], "uses": [],
        }))
        .unwrap();
        let v = Version::parse(env!("CARGO_PKG_VERSION")).unwrap();
        let d = check_draft(&s, &scratch, &v).unwrap();
        assert_eq!(d["passed"], true, "{d}");
        assert!(
            d["files"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["path"] == "mod.toml")
        );
        assert!(!scratch.exists());
        assert!(spec(&json!("tea")).is_none());
        let bad = Spec {
            id: "Tea!".into(),
            ..s
        };
        let e = check_draft(&bad, &scratch, &v).unwrap_err();
        assert_eq!(
            error_key(&e),
            ("mods.new.error.id_invalid".to_string(), false)
        );
        assert_eq!(points().len(), POINTS.len());
        // The author's own reason is written; one given empty is refused, naming the variant.
        let own = spec(&json!({
            "id": "tea", "name": "Tea", "icon": "emoji_food_beverage", "with": ["widget"],
            "skips": {"desk": "it has nothing to say at rest", "peek": "  "},
        }))
        .unwrap();
        let e = check_draft(&own, &scratch, &v).unwrap_err();
        assert!(
            error_key(&e).0.starts_with("mods.new.error.skip_empty: "),
            "the refusal names the variant (I604): {}",
            error_key(&e).0
        );
        let own = Spec {
            skips: [(
                "desk".to_string(),
                "it has nothing to say at rest".to_string(),
            )]
            .into(),
            ..own
        };
        let d = check_draft(&own, &scratch, &v).unwrap();
        let manifest = d["files"][0]["text"].as_str().unwrap();
        assert!(
            manifest.contains("desk = \"it has nothing to say at rest\""),
            "{manifest}"
        );
        assert_eq!(d["rules"].as_array().unwrap().len(), check::RULES.len());
    }
}
