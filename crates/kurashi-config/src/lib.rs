//! Config engine: turns sparse layers into effective values with honest provenance (K5, K15),
//! applies atomic transactions with undo/redo, loads profiles section-wise as one transaction
//! (K7) and edits the user's TOML without destroying their formatting.
//!
//! Layers, lowest to highest precedence:
//! `default → nix → theme:<recipe> → profile:<name> → user → forced:<reason>`.
//! Inside a layer an output-specific entry beats the global one; across layers, layer order
//! always wins (a user *global* value beats a profile *per-output* value).
//!
//! The crate is schema-agnostic: it consumes [`SchemaView`]; the daemon adapts the real schema.
//!
//! ## File format (`config.toml`, profiles, `managed.toml`)
//! ```toml
//! schema_version = 1          # missing = 1; older files are migrated (backup .bak-v<N>)
//!
//! [bar.main]
//! edge = "top"                # key "bar.main.edge"
//!
//! [outputs."DP-1".bar]
//! height = 40                 # key "bar.height", only for output DP-1 (key must be per-output)
//! ```
//! Unknown or invalid keys never fail the file: they are skipped, left untouched on disk and
//! reported as [`Diagnostic`]s (Shōjiki).

mod convert;
mod engine;
mod paths;
mod sparse;

#[cfg(any(test, feature = "testing"))]
pub mod testing;

#[cfg(test)]
mod tests;

use serde::{Deserialize, Serialize};

pub use engine::{Config, Options};
pub use kurashi_core::{Provenanced, Rev, Source};
pub use paths::Paths;
pub use sparse::Migration;
pub use toml_edit::DocumentMut;

/// What the engine needs from the schema (K6). The lead adapts `kurashi-schema` to this.
pub trait SchemaView {
    fn version(&self) -> u32;
    fn default(&self, key: &str) -> Option<serde_json::Value>;
    /// `Err` carries an i18n key or message describing why the value is invalid.
    fn validate(&self, key: &str, v: &serde_json::Value) -> Result<(), String>;
    fn per_output(&self, key: &str) -> bool;
    fn keys(&self) -> Vec<String>;
}

/// `(key, output)`; `None` is the global (all-outputs) slot.
pub type Slot = (String, Option<String>);

/// One mutation inside an [`Config::apply`] batch. Both target the `user` layer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "op")]
pub enum Op {
    Set {
        key: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
        value: serde_json::Value,
    },
    /// Removes the user value. `key` may be a section prefix (`theme.motion`) which resets every
    /// user key below it (for that output only, or global only when `output` is `None`).
    Reset {
        key: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
}

impl Op {
    pub fn set(key: &str, value: serde_json::Value) -> Self {
        Op::Set {
            key: key.into(),
            output: None,
            value,
        }
    }
    pub fn set_on(key: &str, output: &str, value: serde_json::Value) -> Self {
        Op::Set {
            key: key.into(),
            output: Some(output.into()),
            value,
        }
    }
    pub fn reset(key: &str) -> Self {
        Op::Reset {
            key: key.into(),
            output: None,
        }
    }
}

/// Result of a committed transaction (apply, undo, redo, profile load).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Applied {
    pub rev: Rev,
    /// `tx-<n>`; `None` when the batch changed no layer entry (nothing recorded to undo).
    pub tx_id: Option<String>,
    /// Slots whose effective value or provenance changed — what the daemon patches.
    /// A global slot `(key, None)` implies every output that follows the global value;
    /// `(key, Some(o))` is listed only where `o` deviates from the global value.
    pub changed: Vec<Slot>,
}

/// Why a batch was rejected. The whole batch is rejected; nothing changes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum OpError {
    #[error("op {index}: unknown key {key}")]
    UnknownKey { index: usize, key: String },
    #[error("op {index}: {key} has no per-output values")]
    NotPerOutput {
        index: usize,
        key: String,
        output: String,
    },
    #[error("op {index}: invalid value for {key}: {message}")]
    Invalid {
        index: usize,
        key: String,
        message: String,
    },
    #[error("cannot persist: {message}")]
    Persist { message: String },
}

/// One layer's contribution to a key, for `cfg.why` ([`Config::explain`]).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LayerValue {
    pub source: Source,
    /// `Some` when this is the output-specific entry of the layer.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    pub value: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub forced_by: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// A value pinned by the `forced:<name>` layer, e.g. `forced:capability` or `forced:nix`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Forced {
    pub value: serde_json::Value,
    pub forced_by: Option<String>,
    /// i18n key explaining why the control is inert.
    pub reason: Option<String>,
}

/// Effective before/after of one slot. `None` = no value at all (unknown to every layer).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiffEntry {
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    pub before: Option<Provenanced>,
    pub after: Option<Provenanced>,
}

/// Effective-value diff (profile preview, external edit, layer swaps) plus file diagnostics.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Diff {
    /// Revision after the change (unchanged for a preview).
    pub rev: Rev,
    pub entries: Vec<DiffEntry>,
    pub diagnostics: Vec<Diagnostic>,
}

impl Diff {
    pub fn changed(&self) -> Vec<Slot> {
        self.entries
            .iter()
            .map(|e| (e.key.clone(), e.output.clone()))
            .collect()
    }
}

/// An entry a profile operation did not carry out, with the i18n key of why (PROTOCOL §6):
/// `not_applied` (a forced layer holds its key) or `left_out` (an export keeps it on this machine).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Skipped {
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    pub reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub forced_by: Option<String>,
}

/// What loading a profile would do: the effective changes, and the entries a forced layer holds back.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProfileReview {
    pub diff: Diff,
    pub not_applied: Vec<Skipped>,
}

/// A profile load: one undoable transaction, the file's diagnostics and what a forced layer holds back.
#[derive(Debug, Clone, PartialEq)]
pub struct ProfileLoaded {
    pub applied: Applied,
    pub diagnostics: Vec<Diagnostic>,
    pub not_applied: Vec<Skipped>,
}

/// A profile written by [`Config::export_profile`], and the entries it left out.
#[derive(Debug, Clone, PartialEq)]
pub struct Exported {
    pub path: std::path::PathBuf,
    pub left_out: Vec<Skipped>,
}

/// Export leaves out a value for one output: it names that machine's output.
pub const REASON_EXPORT_PER_OUTPUT: &str = "config.export.per_output";
/// Export leaves out a value that names a file or folder: it names that machine's place.
pub const REASON_EXPORT_PATH: &str = "config.export.path";
/// Reason of a held entry whose forced layer gave none.
pub const REASON_FORCED: &str = "config.error.forced";

/// A problem in a file that was skipped instead of failing the whole load (Shōjiki).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Diagnostic {
    pub file: std::path::PathBuf,
    /// Dotted path as written in the file (`outputs.DP-1.bar.height`); empty for file-level.
    pub key: String,
    pub reason: DiagnosticReason,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum DiagnosticReason {
    /// Syntax error: the file is ignored and never overwritten until fixed.
    Parse {
        message: String,
    },
    Io {
        message: String,
    },
    UnknownKey,
    NotPerOutput,
    /// Value TOML can carry but the schema rejects (message from [`SchemaView::validate`]).
    Invalid {
        message: String,
    },
    /// File written by a newer Kurashi; loaded best-effort.
    NewerSchema {
        found: u32,
        supported: u32,
    },
    MigrationMissing {
        from: u32,
    },
    MigrationFailed {
        from: u32,
        to: u32,
        message: String,
    },
}

impl DiagnosticReason {
    /// i18n key for the frontend (`i18n/*/config.toml`).
    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::Parse { .. } => "config.diag.parse",
            Self::Io { .. } => "config.diag.io",
            Self::UnknownKey => "config.diag.unknown_key",
            Self::NotPerOutput => "config.diag.not_per_output",
            Self::Invalid { .. } => "config.diag.invalid",
            Self::NewerSchema { .. } => "config.diag.newer_schema",
            Self::MigrationMissing { .. } => "config.diag.migration_missing",
            Self::MigrationFailed { .. } => "config.diag.migration_failed",
        }
    }
}

/// Engine-level failure (I/O, unknown profile, refused write).
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("io error on {path}: {source}")]
    Io {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    #[error("profile not found: {0}")]
    ProfileNotFound(String),
    #[error("invalid profile name: {0}")]
    InvalidProfileName(String),
    /// The file has a syntax/IO error; acting on it would silently drop the user's intent.
    #[error("unreadable file: {0:?}")]
    Unreadable(Vec<Diagnostic>),
    #[error("{0}")]
    Refused(String),
}

/// i18n key used as `reason` for `managed.toml` values when `_managed.enforce = true` (K15).
pub const REASON_NIX_ENFORCED: &str = "config.forced.nix_enforced";
/// `forced:<name>` used for enforced Home-Manager settings.
pub const FORCED_NIX: &str = "nix";
