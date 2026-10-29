//! The strings the daemon itself says: a notification's title, body and buttons (the frontend translates its own copy from
//! the `i18n` document). The catalogue is the mod's `i18n/<locale>/mod-timer.toml`, found the way kurashid finds its own
//! (`crates/kurashid/src/i18n.rs`): `$KURASHI_DATA_DIR` (set by the package's wrappers), then the source tree.
//! The locale comes from LC_ALL, LC_MESSAGES or LANG; a string the locale lacks is English.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub const FILE: &str = "mod-timer.toml";
const FALLBACK: &str = "en";

#[derive(Clone, Debug, Default)]
pub struct Texts(BTreeMap<String, String>);

impl Texts {
    /// The catalogue for `locale` over the English one. A missing file is an empty catalogue: keys then show as themselves.
    pub fn load(i18n_root: &Path, locale: &str) -> Self {
        let mut strings = read(i18n_root, FALLBACK);
        if locale != FALLBACK {
            strings.extend(read(i18n_root, locale));
        }
        Texts(strings)
    }

    /// The catalogue the daemon uses, for the locale in the environment.
    pub fn from_env() -> Self {
        Self::load(&i18n_root(), &locale_from_env())
    }

    /// `key` with each `{name}` replaced by its value; the key itself when there is no text for it.
    pub fn t(&self, key: &str, args: &[(&str, &str)]) -> String {
        let Some(text) = self.0.get(key) else {
            return key.to_owned();
        };
        args.iter().fold(text.clone(), |text, (name, value)| {
            text.replace(&format!("{{{name}}}"), value)
        })
    }
}

fn read(root: &Path, locale: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let path = root.join(locale).join(FILE);
    let Ok(text) = std::fs::read_to_string(&path) else {
        return out;
    };
    match text.parse::<toml::Table>() {
        Ok(table) => {
            for (key, value) in table {
                if let toml::Value::String(s) = value {
                    out.insert(key, s);
                }
            }
        }
        Err(e) => tracing::warn!(file = %path.display(), error = %e, "skipping mod i18n file"),
    }
    out
}

/// The i18n root: `<data dir>/i18n`, where the data dir is `$KURASHI_DATA_DIR`, else the source tree (`cargo run` and
/// the tests).
pub fn i18n_root() -> PathBuf {
    let data = std::env::var_os("KURASHI_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("../.."));
    data.join("i18n")
}

/// `ja_JP.UTF-8` → `ja`; empty, `C` and `POSIX` → English.
pub fn locale_from_env() -> String {
    let raw = ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|k| std::env::var(k).ok())
        .find(|v| !v.is_empty())
        .unwrap_or_default();
    let lang = raw.split(['_', '.', '@']).next().unwrap_or("");
    if lang.is_empty() || lang == "C" || lang == "POSIX" {
        FALLBACK.to_owned()
    } else {
        lang.to_ascii_lowercase()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_locale_overrides_english_and_placeholders_fill_in() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("en")).unwrap();
        std::fs::create_dir_all(dir.path().join("ja")).unwrap();
        std::fs::write(
            dir.path().join("en").join(FILE),
            "\"mod-timer.end.at\" = \"Ended at {time}\"\n\"mod-timer.end.up\" = \"Time is up\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.path().join("ja").join(FILE),
            "\"mod-timer.end.at\" = \"{time}に終了\"\n",
        )
        .unwrap();
        let ja = Texts::load(dir.path(), "ja");
        assert_eq!(
            ja.t("mod-timer.end.at", &[("time", "14:25")]),
            "14:25に終了"
        );
        assert_eq!(
            ja.t("mod-timer.end.up", &[]),
            "Time is up",
            "a missing ja string is English"
        );
        assert_eq!(
            ja.t("mod-timer.unknown", &[]),
            "mod-timer.unknown",
            "a missing key shows as itself"
        );
    }

    #[test]
    fn the_locale_is_read_from_the_environment_like_kurashid_reads_it() {
        // The shape only: the test run's own environment decides the value.
        let l = locale_from_env();
        assert!(!l.is_empty() && !l.contains('_') && !l.contains('.'), "{l}");
    }
}
