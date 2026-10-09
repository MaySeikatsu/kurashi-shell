//! The mod's own state file (`$XDG_STATE_HOME/kurashi/wallpaper.json`): the image last applied to
//! each output, the image applied to every output, the favourite looks and the rotation pause. The
//! backend remembers nothing the mod relies on (`--no-cache`), so this file is the truth for what is
//! restored. Writes go through a temporary file and a rename; a file that does not parse is moved
//! aside (`.bad`) and the mod starts empty, reporting it, rather than guessing.

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

pub const FILE: &str = "wallpaper.json";

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct OutputState {
    pub path: String,
}

/// A favourite look (★): the image, and the theme it was saved with. `scheme` is `dark` or `light`
/// and `variant` the palette the look uses (`wallpaper`, the image's own colours, or a bundled
/// palette name); the picker applies both with the image. The mod stores them as the user saw them.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Favourite {
    #[serde(alias = "path")]
    pub image: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scheme: Option<String>,
    #[serde(default, alias = "palette", skip_serializing_if = "Option::is_none")]
    pub variant: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Persisted {
    #[serde(default)]
    pub version: u32,
    /// The image last applied to every output at once.
    #[serde(default)]
    pub all: Option<String>,
    /// The image last applied to one output, by output name. Kept for outputs that are unplugged.
    #[serde(default)]
    pub outputs: BTreeMap<String, OutputState>,
    #[serde(default)]
    pub favourites: Vec<Favourite>,
    /// Rotation paused by the user (`wallpaper.rotation.pause`); the interval stays in Settings.
    #[serde(default)]
    pub paused: bool,
    /// The picture the theme follows (`wallpaper.set` with `theme: true`): the shell's palette is
    /// extracted from it when the theme source is `wallpaper`. Kept apart from the outputs, so a
    /// "wallpaper only" change leaves the theme where it was.
    #[serde(default)]
    pub theme_image: Option<String>,
}

/// What loading found: the state, and whether a broken file was set aside.
pub struct Loaded {
    pub state: Persisted,
    pub set_aside: bool,
}

pub fn load(path: &Path) -> Loaded {
    match std::fs::read_to_string(path) {
        Ok(text) => match serde_json::from_str::<Persisted>(&text) {
            Ok(state) => Loaded {
                state,
                set_aside: false,
            },
            Err(e) => {
                tracing::warn!(file = %path.display(), error = %e, "wallpaper state does not parse; set aside");
                let _ = std::fs::rename(path, path.with_extension("json.bad"));
                Loaded {
                    state: Persisted::default(),
                    set_aside: true,
                }
            }
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => Loaded {
            state: Persisted::default(),
            set_aside: false,
        },
        Err(e) => {
            tracing::warn!(file = %path.display(), error = %e, "wallpaper state unreadable");
            Loaded {
                state: Persisted::default(),
                set_aside: false,
            }
        }
    }
}

pub fn save(path: &Path, state: &Persisted) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("json.tmp");
    let mut text = serde_json::to_string_pretty(&Persisted {
        version: 1,
        ..state.clone()
    })
    .map_err(io::Error::other)?;
    text.push('\n');
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("kurashi-wp-state-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_saved_state_loads_back_unchanged() {
        let dir = scratch("roundtrip");
        let path = dir.join(FILE);
        let mut state = Persisted {
            all: Some("/w/a.png".into()),
            paused: true,
            ..Persisted::default()
        };
        state.outputs.insert(
            "DP-1".into(),
            OutputState {
                path: "/w/b.png".into(),
            },
        );
        state.favourites.push(Favourite {
            image: "/w/b.png".into(),
            scheme: Some("dark".into()),
            variant: Some("wallpaper".into()),
        });
        state.theme_image = Some("/w/a.png".into());
        save(&path, &state).unwrap();
        let loaded = load(&path);
        assert!(!loaded.set_aside);
        assert_eq!(loaded.state.all, state.all);
        assert_eq!(loaded.state.outputs, state.outputs);
        assert_eq!(loaded.state.favourites, state.favourites);
        assert_eq!(loaded.state.theme_image, state.theme_image);
        assert!(loaded.state.paused);
        assert!(
            !dir.join("wallpaper.json.tmp").exists(),
            "the rename consumed the temp file"
        );
    }

    #[test]
    fn a_favourite_saved_with_the_old_field_names_still_loads() {
        // The first picker wrote `path` and `palette`; the look keeps its picture and palette.
        let old: Persisted =
            serde_json::from_str(r#"{"favourites":[{"path":"/w/x.png","palette":"kanso"}]}"#)
                .unwrap();
        assert_eq!(
            old.favourites,
            [Favourite {
                image: "/w/x.png".into(),
                scheme: None,
                variant: Some("kanso".into()),
            }]
        );
    }

    #[test]
    fn a_missing_file_is_an_empty_state_and_a_broken_one_is_set_aside() {
        let dir = scratch("broken");
        let path = dir.join(FILE);
        assert_eq!(load(&path).state, Persisted::default());
        std::fs::write(&path, "{not json").unwrap();
        let loaded = load(&path);
        assert!(loaded.set_aside);
        assert_eq!(loaded.state, Persisted::default());
        assert!(dir.join("wallpaper.json.bad").exists());
        assert!(!path.exists());
    }
}
