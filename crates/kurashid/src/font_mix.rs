//! The font mix in effect (I176, K93; `docs/ux/fonts.md`): from `theme.typography.mix.*` to a generated font in the cache, published as
//! the tokens `font.mix.file`, `font.mix.family`, `font.mix.state` and `font.mix.missing`. A file already made is used at once;
//! otherwise it is built off the runtime and the theme republished when it is there (Ma: built once per set of fonts, nothing at rest).
//! `font.mix.preview {fonts}` builds one for Settings' comparison without changing the config.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};

use kurashi_theme::font_mix::{self, MAX_FONTS};
use serde_json::{Map, Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;

/// The preset's fonts, in order: the first gives the metrics. `count` takes the first so many (2: the plainest; 3: the shipped default).
pub const HANDWRITING: [&str; 4] = ["Kalam", "Patrick Hand", "Handlee", "Gochi Hand"];

static AGAIN: OnceLock<Arc<dyn Fn() + Send + Sync>> = OnceLock::new();
static BUILDING: Mutex<BTreeSet<String>> = Mutex::new(BTreeSet::new());

/// What to call when a font has been built.
pub fn on_ready(again: Arc<dyn Fn() + Send + Sync>) {
    let _ = AGAIN.set(again);
}

fn cache_dir() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    Some(base.join("kurashi/fonts"))
}

/// A family as fontconfig has it: its file and face. `None` when fontconfig would only substitute another.
fn locate(family: &str) -> Option<(PathBuf, u32)> {
    let out = Command::new("fc-match")
        .arg("--format=%{file}\n%{index}\n%{family}\n")
        .arg(format!("{family}:style=Regular"))
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout).into_owned();
    let mut lines = text.lines();
    let (file, index, names) = (lines.next()?, lines.next()?, lines.next()?);
    names
        .split(',')
        .any(|n| n.trim().eq_ignore_ascii_case(family))
        .then(|| {
            // (the upper bits name a variable font's instance; the default outlines serve)
            let face = index.parse::<u32>().unwrap_or(0) & 0xffff;
            (PathBuf::from(file), face)
        })
}

/// FNV-1a: a name for a set of fonts, stable across runs (a std hasher is not).
fn fnv(text: &str) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325_u64;
    for b in text.bytes() {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    h
}

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub sources: Vec<(PathBuf, u32)>,
    pub missing: Vec<String>,
    pub hash: String,
}
impl Plan {
    pub fn family(&self) -> String {
        format!("Kurashi Mix {}", self.hash)
    }
    fn file(&self, dir: &Path) -> PathBuf {
        dir.join(format!("mix-{}.ttf", self.hash))
    }
}

/// What a list of families comes to here. The files' times are in the name, so an updated font makes a new mix.
pub fn plan(families: &[String]) -> Plan {
    let mut sources = Vec::new();
    let mut missing = Vec::new();
    let mut key = String::from("v1\n");
    for f in families.iter().take(MAX_FONTS) {
        match locate(f) {
            Some((path, face)) => {
                let stamp = std::fs::metadata(&path)
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map_or(0, |d| d.as_secs());
                key.push_str(&format!("{}|{face}|{stamp}\n", path.display()));
                sources.push((path, face));
            }
            None => missing.push(f.clone()),
        }
    }
    Plan {
        sources,
        missing,
        hash: format!("{:016x}", fnv(&key)),
    }
}

/// The families the config asks for, or nothing with the mix off.
pub fn wanted(store: &ConfigStore) -> Option<Vec<String>> {
    let text = |key: &str| {
        store
            .get(key, None)
            .and_then(|p| p.value.as_str().map(String::from))
            .unwrap_or_default()
    };
    let count = store
        .get("theme.typography.mix.count", None)
        .and_then(|p| p.value.as_u64())
        .map_or(3, |c| c as usize);
    let list: Vec<String> = match text("theme.typography.mix.preset").as_str() {
        "handwriting" => HANDWRITING.iter().map(|s| (*s).to_owned()).collect(),
        "custom" => store
            .get("theme.typography.mix.fonts", None)
            .and_then(|p| p.value.as_array().cloned())
            .unwrap_or_default()
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect(),
        _ => return None,
    };
    Some(list.into_iter().take(count.clamp(2, MAX_FONTS)).collect())
}

/// Builds `plan` into `dir`; the file appears whole (written beside it, then renamed).
fn build(plan: &Plan, dir: &Path) -> Result<PathBuf, String> {
    let file = plan.file(dir);
    if file.is_file() {
        return Ok(file);
    }
    let bytes: Vec<Vec<u8>> = plan
        .sources
        .iter()
        .map(|(p, _)| std::fs::read(p).map_err(|e| format!("{}: {e}", p.display())))
        .collect::<Result<_, _>>()?;
    let inputs: Vec<(&[u8], u32)> = bytes
        .iter()
        .zip(&plan.sources)
        .map(|(b, (_, face))| (b.as_slice(), *face))
        .collect();
    let out = font_mix::build(&inputs, &plan.family()).map_err(|e| e.to_string())?;
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let tmp = dir.join(format!("mix-{}.tmp", plan.hash));
    std::fs::write(&tmp, out).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &file).map_err(|e| e.to_string())?;
    Ok(file)
}

/// `font.mix.*` into a theme document's tokens. Never blocks: a font not built yet is `building`, and the theme is republished.
pub fn apply(store: &ConfigStore, tokens: &mut Map<String, Value>) {
    let mut set = |file: &str, family: &str, state: &str, missing: &[String]| {
        tokens.insert("font.mix.file".into(), json!(file));
        tokens.insert("font.mix.family".into(), json!(family));
        tokens.insert("font.mix.state".into(), json!(state));
        tokens.insert("font.mix.missing".into(), json!(missing));
    };
    let Some(families) = wanted(store) else {
        set("", "", "off", &[]);
        return;
    };
    let plan = plan(&families);
    if plan.sources.len() < 2 {
        set("", "", "too_few", &plan.missing);
        return;
    }
    let Some(dir) = cache_dir() else {
        set("", "", "failed", &plan.missing);
        return;
    };
    let file = plan.file(&dir);
    if file.is_file() {
        set(&file.to_string_lossy(), &plan.family(), "on", &plan.missing);
        return;
    }
    set("", "", "building", &plan.missing);
    spawn(plan);
}

fn spawn(plan: Plan) {
    if !BUILDING
        .lock()
        .expect("building lock")
        .insert(plan.hash.clone())
    {
        return;
    }
    let Ok(rt) = tokio::runtime::Handle::try_current() else {
        BUILDING.lock().expect("building lock").remove(&plan.hash);
        return;
    };
    rt.spawn_blocking(move || {
        if let Some(dir) = cache_dir() {
            if let Err(e) = build(&plan, &dir) {
                tracing::warn!(error = %e, "font mix not built");
            } else {
                forget_others(&dir, &plan);
            }
        }
        BUILDING.lock().expect("building lock").remove(&plan.hash);
        if let Some(f) = AGAIN.get() {
            f();
        }
    });
}

/// Mixes pile up as fonts are tried: only the last few stay (Settings' comparison keeps a handful).
fn forget_others(dir: &Path, keep: &Plan) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = rd
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("mix-"))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    files.sort();
    let extra = files.len().saturating_sub(16);
    for (_, p) in files.into_iter().take(extra) {
        if p != keep.file(dir) {
            let _ = std::fs::remove_file(p);
        }
    }
}

/// `font.mix.preview {fonts:[…]}`: a mix of these fonts, built if need be, nothing else changed: `{file, family, missing}`. With one font,
/// that font's name alone.
pub fn register_actions(actions: &mut ActionRegistry) {
    actions.register("font.mix.preview", "action.font.mix.preview", |args: Value| async move {
        let families: Vec<String> = args
            .get("fonts")
            .and_then(Value::as_array)
            .ok_or_else(|| ActionError::Invalid(crate::wiring::ARGS_INVALID.into()))?
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect();
        let done = tokio::task::spawn_blocking(move || {
            let plan = plan(&families);
            if plan.sources.len() < 2 {
                return Ok::<_, String>(json!({"file": "", "family": "", "missing": plan.missing}));
            }
            let dir = cache_dir().ok_or("no cache dir")?;
            let file = build(&plan, &dir)?;
            forget_others(&dir, &plan);
            Ok(json!({"file": file.to_string_lossy(), "family": plan.family(), "missing": plan.missing}))
        })
        .await
        .map_err(|e| ActionError::Unavailable(e.to_string()))?;
        done.map(Some).map_err(ActionError::Unavailable)
    });
}

/// The installed families, for the fonts row's offers (`fonts.installed`). `fc-list` costs a process, and the offers are read often:
/// it runs again only when a font folder of the user's changed, so a font dropped in (or made by a mod, I415) is offered without a restart.
pub fn installed() -> Vec<String> {
    static SEEN: Mutex<Option<(Vec<u64>, Vec<String>)>> = Mutex::new(None);
    let stamp = font_folders_stamp();
    let mut seen = SEEN.lock().expect("fonts lock");
    if let Some((s, names)) = seen.as_ref()
        && *s == stamp
    {
        return names.clone();
    }
    let names = list_families();
    *seen = Some((stamp, names.clone()));
    names
}

fn font_folders_stamp() -> Vec<u64> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let data = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|h| h.join(".local/share")));
    [
        data.map(|d| d.join("fonts")),
        home.map(|h| h.join(".fonts")),
    ]
    .into_iter()
    .flatten()
    .map(|d| {
        std::fs::metadata(d)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_secs())
    })
    .collect()
}

fn list_families() -> Vec<String> {
    let Ok(out) = Command::new("fc-list")
        .args(["--format=%{family[0]}\n"])
        .output()
    else {
        return Vec::new();
    };
    let mut names: Vec<String> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| l.trim().to_owned())
        .filter(|l| !l.is_empty() && !l.starts_with("Kurashi Mix"))
        .collect();
    names.sort_by_key(|n| n.to_lowercase());
    names.dedup();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_is_stable_across_runs() {
        assert_eq!(fnv("Kalam"), fnv("Kalam"));
        assert_ne!(fnv("Kalam"), fnv("Handlee"));
        // (a fixed value: a changed hash would orphan every cached font)
        assert_eq!(fnv("a"), 0xaf63_dc4c_8601_ec8c);
    }

    #[test]
    fn a_family_that_is_not_there_is_missing_not_substituted() {
        let p = plan(&["No Such Font Kurashi".to_owned()]);
        assert_eq!(p.missing, vec!["No Such Font Kurashi"]);
        assert!(p.sources.is_empty());
    }

    #[test]
    fn the_plan_names_the_family_and_file_by_its_hash() {
        let p = Plan {
            sources: vec![],
            missing: vec![],
            hash: "abc".into(),
        };
        assert_eq!(p.family(), "Kurashi Mix abc");
        assert_eq!(p.file(Path::new("/c")), PathBuf::from("/c/mix-abc.ttf"));
    }
}
