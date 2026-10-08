//! Shared vocabulary for every Kurashi crate: document names, revisions and the
//! provenance-carrying value type (K5).

use serde::{Deserialize, Serialize};

/// Monotonic revision of a state document. Gaps trigger a resync (PROTOCOL §3).
pub type Rev = u64;

/// Where an effective value came from, lowest to highest precedence (K5).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind", content = "name")]
pub enum Source {
    Default,
    /// Declared via Nix / Home-Manager (`managed.toml`, K15).
    Nix,
    Theme(String),
    Profile(String),
    User,
    Forced(String),
}

/// An effective value plus everything the UI needs to be honest about it (Shōjiki).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Provenanced {
    pub value: serde_json::Value,
    pub source: Source,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub forced_by: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// Default socket location: `$KURASHI_SOCKET` or `$XDG_RUNTIME_DIR/kurashi/ipc.sock`.
pub fn default_socket_path() -> std::path::PathBuf {
    if let Some(p) = std::env::var_os("KURASHI_SOCKET") {
        return p.into();
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into());
    std::path::Path::new(&runtime)
        .join("kurashi")
        .join("ipc.sock")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn source_serializes_tagged() {
        let s = serde_json::to_string(&Source::Profile("kanso".into())).unwrap();
        assert_eq!(s, r#"{"kind":"profile","name":"kanso"}"#);
        let d = serde_json::to_string(&Source::Default).unwrap();
        assert_eq!(d, r#"{"kind":"default"}"#);
    }
}
