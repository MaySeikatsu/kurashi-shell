//! The mod's settings as the supervisor uses them (`mods.wallpaper.*`, K22). The defaults here are
//! the manifest's (`mods/wallpaper/mod.toml`); the daemon always supplies every key, the defaults only
//! cover a missing one.

use std::path::PathBuf;

use kurashi_mod_api::Settings;
#[cfg(test)]
use kurashi_mod_api::Values;
use serde_json::Value;
#[cfg(test)]
use serde_json::json;

pub const DEFAULT_BACKEND: &str = "awww";
pub const DEFAULT_FOLDERS: &str = "~/Pictures/Wallpapers";
pub const FITS: &[&str] = &["crop", "fit", "stretch", "no"];
pub const ANCHORS: &[&str] = &[
    "center",
    "top",
    "bottom",
    "left",
    "right",
    "top-left",
    "top-right",
    "bottom-left",
    "bottom-right",
];
pub const TRANSITIONS: &[&str] = &["none", "fade", "wipe", "wave", "grow", "random"];

/// What the supervisor reads from the settings each time they change.
#[derive(Clone, Debug, PartialEq)]
pub struct Config {
    /// The `backend` value as stored; a value that is not a known backend is reported as such.
    pub backend: String,
    /// `folders`, a path list (I54), unexpanded. An old `:`-joined string is read as its parts.
    pub folders: Vec<String>,
    pub fit: String,
    pub crop_anchor: String,
    pub transition: String,
    pub duration: f64,
    pub angle: i64,
    /// Minutes between rotations; 0 = rotation off.
    pub rotate_min: u32,
    /// `rotate_order`: `shuffle` (true) or `alphabetical` (false).
    pub shuffle: bool,
    /// `rotate_per_output`: each output rotates on its own due time, else all outputs together.
    pub per_output: bool,
    /// `restore`: re-apply the stored images when the backend (re)starts.
    pub restore: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            backend: DEFAULT_BACKEND.into(),
            folders: vec![DEFAULT_FOLDERS.into()],
            fit: "crop".into(),
            crop_anchor: "center".into(),
            transition: "fade".into(),
            duration: 1.0,
            angle: 45,
            rotate_min: 0,
            shuffle: false,
            per_output: false,
            restore: true,
        }
    }
}

impl Config {
    /// The values in effect now.
    pub fn read(settings: &Settings) -> Self {
        let d = Self::default();
        let text = |key: &str, default: &str| {
            settings
                .get(key)
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_else(|| default.to_string())
        };
        let choice = |key: &str, allowed: &[&str], default: &str| {
            let v = text(key, default);
            if allowed.contains(&v.as_str()) {
                v
            } else {
                default.to_string()
            }
        };
        Self {
            backend: text("backend", &d.backend),
            folders: folders(settings.get("folders").as_ref()).unwrap_or(d.folders),
            fit: choice("fit", FITS, &d.fit),
            crop_anchor: choice("crop_anchor", ANCHORS, &d.crop_anchor),
            transition: choice("transition", TRANSITIONS, &d.transition),
            duration: settings
                .get("transition_duration")
                .and_then(|v| v.as_f64())
                .filter(|v| (0.1..=10.0).contains(v))
                .unwrap_or(d.duration),
            angle: settings
                .get("transition_angle")
                .and_then(|v| v.as_i64())
                .filter(|v| (0..=360).contains(v))
                .unwrap_or(d.angle),
            rotate_min: settings
                .get("rotate")
                .and_then(|v| v.as_i64())
                .and_then(|v| u32::try_from(v).ok())
                .filter(|v| *v <= 1440)
                .unwrap_or(0),
            shuffle: text("rotate_order", "alphabetical") == "shuffle",
            per_output: settings
                .get("rotate_per_output")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            restore: settings
                .get("restore")
                .and_then(|v| v.as_bool())
                .unwrap_or(true),
        }
    }

    /// `folders` with `~` expanded, empty entries dropped.
    pub fn roots(&self) -> Vec<PathBuf> {
        let home = std::env::var_os("HOME").map(PathBuf::from);
        self.folders
            .iter()
            .map(|f| f.trim())
            .filter(|f| !f.is_empty())
            .map(|f| expand_home(f, home.as_deref()))
            .collect()
    }

    /// The rotation order as the settings name it.
    pub fn order_name(&self) -> &'static str {
        if self.shuffle {
            "shuffle"
        } else {
            "alphabetical"
        }
    }

    /// The settings in effect as a plain map (tests and the manifest-default check).
    #[cfg(test)]
    pub fn to_json(&self) -> Value {
        json!({
            "backend": self.backend, "folders": self.folders, "fit": self.fit,
            "crop_anchor": self.crop_anchor, "transition": self.transition,
            "transition_duration": self.duration, "transition_angle": self.angle,
            "rotate": self.rotate_min, "rotate_order": self.order_name(),
            "rotate_per_output": self.per_output, "restore": self.restore,
        })
    }
}

/// The manifest defaults as the daemon would supply them (`Values`), for tests that build a
/// `Settings` by hand.
#[cfg(test)]
pub fn default_values() -> Values {
    let d = Config::default();
    let mut v = Values::new();
    for (k, val) in d.to_json().as_object().into_iter().flatten() {
        v.insert(k.clone(), val.clone());
    }
    v
}

/// `folders` as stored: a list of paths (I54), or the `:`-joined string it was before manifests had
/// free lists (the daemon reads that as the list too; a mod run against an older daemon may not).
fn folders(v: Option<&Value>) -> Option<Vec<String>> {
    match v? {
        Value::Array(items) => Some(
            items
                .iter()
                .filter_map(|i| i.as_str().map(str::to_string))
                .collect(),
        ),
        Value::String(joined) => Some(
            joined
                .split(':')
                .map(str::trim)
                .filter(|f| !f.is_empty())
                .map(str::to_string)
                .collect(),
        ),
        _ => None,
    }
}

fn expand_home(path: &str, home: Option<&std::path::Path>) -> PathBuf {
    match (path.strip_prefix("~/"), home) {
        (Some(rest), Some(home)) => home.join(rest),
        _ if path == "~" => home
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(path)),
        _ => PathBuf::from(path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::watch;

    fn settings(values: Values) -> Settings {
        let (_, rx) = watch::channel(values);
        Settings::new(rx)
    }

    #[test]
    fn defaults_read_back_as_the_manifest_declares_them() {
        let c = Config::read(&settings(default_values()));
        assert_eq!(c, Config::default());
        assert!(c.restore && !c.per_output && !c.shuffle);
    }

    #[test]
    fn a_value_outside_its_choices_falls_back_to_the_default() {
        let mut v = default_values();
        v.insert("fit".into(), json!("span"));
        v.insert("rotate".into(), json!(9999));
        let c = Config::read(&settings(v));
        assert_eq!(c.fit, "crop");
        assert_eq!(c.rotate_min, 0, "above the 1440 limit is off");
    }

    #[test]
    fn folders_split_at_colons_and_expand_home() {
        let mut v = default_values();
        v.insert("folders".into(), json!("/a/b: ~/Pics ::/c"));
        let c = Config::read(&settings(v));
        assert_eq!(c.folders, ["/a/b", "~/Pics", "/c"], "the old colon string");
        let mut v = default_values();
        v.insert("folders".into(), json!(["/a/b", "~/Pics", " ", "/c"]));
        let c = Config::read(&settings(v));
        let home = std::path::Path::new("/home/u");
        assert_eq!(
            expand_home("~/Pics", Some(home)),
            PathBuf::from("/home/u/Pics")
        );
        assert_eq!(expand_home("/x", Some(home)), PathBuf::from("/x"));
        let roots = c.roots();
        assert_eq!(roots.len(), 3, "the empty entry is dropped");
        assert_eq!(roots[1].file_name().unwrap(), "Pics");
    }
}
