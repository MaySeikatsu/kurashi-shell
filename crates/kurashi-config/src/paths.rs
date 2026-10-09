use std::path::{Path, PathBuf};

/// Where the engine reads and writes (ARCHITECTURE §9). Tests use [`Paths::rooted`] so nothing
/// ever touches the real `~/.config`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    /// `~/.config/kurashi`
    pub config_dir: PathBuf,
    /// `~/.local/state/kurashi`
    pub state_dir: PathBuf,
}

impl Paths {
    /// XDG locations via `dirs`; `None` only when no home directory can be determined.
    pub fn from_xdg() -> Option<Self> {
        let config = dirs::config_dir()?;
        let state =
            dirs::state_dir().or_else(|| dirs::home_dir().map(|h| h.join(".local/state")))?;
        Some(Self {
            config_dir: config.join("kurashi"),
            state_dir: state.join("kurashi"),
        })
    }

    /// Everything below `root` (`root/config`, `root/state`).
    pub fn rooted(root: &Path) -> Self {
        Self {
            config_dir: root.join("config"),
            state_dir: root.join("state"),
        }
    }

    pub fn user_file(&self) -> PathBuf {
        self.config_dir.join("config.toml")
    }

    /// Written by Home-Manager (K15); read-only for us.
    pub fn managed_file(&self) -> PathBuf {
        self.config_dir.join("managed.toml")
    }

    pub fn user_profiles_dir(&self) -> PathBuf {
        self.config_dir.join("profiles")
    }

    /// Which profile supplied which entry of the `profile:<name>` layer.
    pub fn profile_state_file(&self) -> PathBuf {
        self.state_dir.join("profile-layer.toml")
    }
}
