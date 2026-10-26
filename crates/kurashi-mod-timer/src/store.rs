//! The timer state file (`$XDG_STATE_HOME/kurashi/timer.json`, else `~/.local/state/kurashi/timer.json`, as the weather and
//! wallpaper mods resolve their state): the timers survive a daemon restart. Written atomically (a temporary file, then a
//! rename). A file that does not parse is set aside as `timer.json.bad` and the mod starts empty, with a log line, so one
//! broken file never stops timers from working.

use std::io;
use std::path::{Path, PathBuf};

use crate::model::State;

pub const FILE: &str = "timer.json";

/// The state file the daemon uses.
pub fn default_path() -> PathBuf {
    let base = std::env::var_os("XDG_STATE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    base.join("kurashi").join(FILE)
}

/// The saved state, or an empty one when there is no file yet (or it cannot be used).
pub fn load(path: &Path) -> State {
    match std::fs::read(path) {
        Ok(bytes) => match serde_json::from_slice::<State>(&bytes) {
            Ok(state) => state,
            Err(e) => {
                tracing::warn!(file = %path.display(), error = %e, "timer state does not parse; set aside");
                let _ = std::fs::rename(path, path.with_extension("json.bad"));
                State::default()
            }
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => State::default(),
        Err(e) => {
            tracing::warn!(file = %path.display(), error = %e, "timer state cannot be read");
            State::default()
        }
    }
}

/// Writes the state: a temporary file in the same folder, then a rename over the old one.
pub fn save(path: &Path, state: &State) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let text = serde_json::to_vec(state).map_err(io::Error::other)?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{MINUTE_MS, State};

    #[test]
    fn a_saved_state_loads_back_and_a_missing_one_is_empty() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("kurashi").join(FILE);
        assert_eq!(load(&path), State::default(), "no file yet");
        let mut state = State::default();
        state.start_countdown(1_000, 5 * MINUTE_MS, "tea");
        save(&path, &state).unwrap();
        assert!(
            !path.with_extension("json.tmp").exists(),
            "the temporary file is renamed away"
        );
        assert_eq!(load(&path), state);
    }

    #[test]
    fn a_file_that_does_not_parse_is_set_aside_and_the_mod_starts_empty() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(FILE);
        std::fs::write(&path, b"{ not json").unwrap();
        assert_eq!(load(&path), State::default());
        assert!(!path.exists());
        assert!(path.with_extension("json.bad").exists());
    }

    #[test]
    fn the_default_path_follows_xdg_state_home() {
        // Only the shape: the environment of a test run is not ours to set.
        let p = default_path();
        assert!(p.ends_with("kurashi/timer.json"), "{}", p.display());
    }
}
