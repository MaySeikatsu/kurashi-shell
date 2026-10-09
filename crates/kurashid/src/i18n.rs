//! The `i18n` document (PROTOCOL §5, K17): flat `key → text` for the active locale with an
//! English fallback, merged from `i18n/<locale>/<domain>.toml`. Frontends never read the files.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

pub const FALLBACK: &str = "en";

/// Where `i18n/`, `palettes/` and the frontend live: `$KURASHI_DATA_DIR`, the install prefix
/// baked in at build time (nix sets it), then the source tree for `cargo run`.
pub fn data_dir() -> PathBuf {
    if let Some(d) = std::env::var_os("KURASHI_DATA_DIR") {
        return d.into();
    }
    if let Some(d) = option_env!("KURASHI_DATA_DIR") {
        return d.into();
    }
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// `ja_JP.UTF-8` → `ja`; empty, `C` and `POSIX` → the fallback.
pub fn locale_from_env() -> String {
    let raw = ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty())
        .unwrap_or_default();
    let lang = raw.split(['_', '.', '@']).next().unwrap_or("");
    if lang.is_empty() || lang == "C" || lang == "POSIX" {
        FALLBACK.into()
    } else {
        lang.to_ascii_lowercase()
    }
}

/// All strings of one locale; later domains win on duplicate keys (sorted file order).
pub fn load_locale(root: &Path, locale: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let Ok(dir) = std::fs::read_dir(root.join(locale)) else {
        return out;
    };
    let mut files: Vec<_> = dir
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "toml"))
        .collect();
    files.sort();
    for path in files {
        let parsed = std::fs::read_to_string(&path)
            .map_err(|e| e.to_string())
            .and_then(|t| t.parse::<toml::Table>().map_err(|e| e.to_string()));
        match parsed {
            Ok(table) => flatten("", &table, &mut out),
            Err(e) => tracing::warn!(file = %path.display(), error = %e, "skipping i18n file"),
        }
    }
    out
}

fn flatten(prefix: &str, table: &toml::Table, out: &mut BTreeMap<String, String>) {
    for (k, v) in table {
        let key = if prefix.is_empty() {
            k.clone()
        } else {
            format!("{prefix}.{k}")
        };
        match v {
            toml::Value::String(s) => {
                out.insert(key, s.clone());
            }
            toml::Value::Table(t) => flatten(&key, t, out),
            _ => tracing::warn!(%key, "i18n values must be strings"),
        }
    }
}

/// Document value: the locale's strings over the fallback's, so a missing translation shows
/// English instead of a raw key.
pub fn document(root: &Path, locale: &str) -> Value {
    let mut strings = load_locale(root, FALLBACK);
    if locale != FALLBACK {
        strings.extend(load_locale(root, locale));
    }
    json!({"locale": locale, "fallback": FALLBACK, "strings": strings})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_overrides_fallback_and_nested_tables_flatten() {
        let dir = std::env::temp_dir().join(format!("kurashi-i18n-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("en")).unwrap();
        std::fs::create_dir_all(dir.join("ja")).unwrap();
        std::fs::write(
            dir.join("en/a.toml"),
            "\"x.hello\" = \"Hello\"\n[x]\nbye = \"Bye\"\n",
        )
        .unwrap();
        std::fs::write(dir.join("ja/a.toml"), "\"x.hello\" = \"こんにちは\"\n").unwrap();
        let doc = document(&dir, "ja");
        assert_eq!(doc["strings"]["x.hello"], "こんにちは");
        assert_eq!(doc["strings"]["x.bye"], "Bye", "falls back to en");
        assert_eq!(doc["locale"], "ja");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn shipped_frontend_strings_exist_in_every_locale() {
        let root = data_dir().join("i18n");
        let en = load_locale(&root, "en");
        let ja = load_locale(&root, "ja");
        assert!(!en.is_empty());
        let missing: Vec<_> = en.keys().filter(|k| !ja.contains_key(*k)).collect();
        assert!(missing.is_empty(), "ja lacks {missing:?}");
    }
}
