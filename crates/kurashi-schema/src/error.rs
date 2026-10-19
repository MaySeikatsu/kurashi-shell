//! Typed errors. Every [`ValidationError`] carries an i18n key; `Display` is the English
//! developer message (logs, tests), the UI renders `i18n_key()` with the serialized fields.

use serde::Serialize;
use serde_json::Value;

use crate::meta::Ty;
use crate::records::RecordProblem;

/// A value was rejected for a key. Serializes as `{"code": "...", "key": ..., ...}` so it can
/// travel in a `rejected` reply unchanged.
#[derive(Debug, Clone, PartialEq, thiserror::Error, Serialize)]
#[serde(tag = "code", rename_all = "snake_case")]
pub enum ValidationError {
    #[error("unknown config key `{key}`")]
    UnknownKey { key: String },
    #[error("`{key}` expects a value of type {expected}, got {got}")]
    WrongType {
        key: String,
        expected: Ty,
        got: Value,
    },
    #[error("`{key}` must be within {min}..={max}, got {got}")]
    OutOfRange {
        key: String,
        min: Value,
        max: Value,
        got: Value,
    },
    #[error("`{key}` must be a multiple of {step} (from {base}), got {got}")]
    OffStep {
        key: String,
        step: Value,
        base: Value,
        got: Value,
    },
    #[error("`{key}` must be one of {choices:?}, got {got:?}")]
    UnknownChoice {
        key: String,
        got: String,
        choices: Vec<String>,
    },
    #[error("`{key}` must be a #rrggbb or #rrggbbaa colour, got {got:?}")]
    InvalidColor { key: String, got: String },
    #[error("`{key}` must be an action id like `island.expand` (or empty), got {got:?}")]
    InvalidAction { key: String, got: String },
    #[error("`{key}` must not be empty")]
    EmptyList { key: String },
    /// A row or field of a `records` value is wrong (K38, MODS.md "Records"). `key` is the path
    /// `mods.<id>.<key>[<n>].<field>` (`…[<n>]` for a row that is not a table), so a rejection names
    /// the field it is about.
    #[error("`{key}` {problem}")]
    Record { key: String, problem: RecordProblem },
}

impl ValidationError {
    /// Every variant with its i18n key and English template, in one place (feeds `i18n_en`).
    pub const CATALOG: &[(&str, &str)] = &[
        (
            "error.config.record_not_a_record",
            "“{key}” must be a table of fields.",
        ),
        (
            "error.config.record_unknown_field",
            "“{key}” is not a field of this list.",
        ),
        ("error.config.record_missing_field", "“{key}” is required."),
        (
            "error.config.record_wrong_type",
            "“{key}” has the wrong type.",
        ),
        (
            "error.config.record_slug",
            "“{key}” must be a slug: a-z, 0-9 and hyphens, 1 to 32 characters.",
        ),
        (
            "error.config.record_url",
            "“{key}” must be an absolute URL.",
        ),
        (
            "error.config.record_scheme",
            "“{key}” uses a scheme that is not allowed here.",
        ),
        (
            "error.config.record_choice",
            "“{key}” must be one of the choices.",
        ),
        (
            "error.config.record_out_of_range",
            "“{key}” is outside the allowed range.",
        ),
        (
            "error.config.record_duplicate",
            "“{key}” repeats another row’s value.",
        ),
        ("error.config.unknown_key", "Unknown setting “{key}”."),
        (
            "error.config.wrong_type",
            "“{key}” expects a value of type {expected}.",
        ),
        (
            "error.config.out_of_range",
            "“{key}” must be between {min} and {max}.",
        ),
        (
            "error.config.off_step",
            "“{key}” must change in steps of {step}.",
        ),
        (
            "error.config.unknown_choice",
            "“{key}” must be one of: {choices}.",
        ),
        (
            "error.config.invalid_color",
            "“{key}” must be a colour like #d7c4a1.",
        ),
        (
            "error.config.invalid_action",
            "“{key}” must be an action id like island.expand.",
        ),
        ("error.config.empty_list", "“{key}” must not be empty."),
    ];

    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::UnknownKey { .. } => "error.config.unknown_key",
            Self::WrongType { .. } => "error.config.wrong_type",
            Self::OutOfRange { .. } => "error.config.out_of_range",
            Self::OffStep { .. } => "error.config.off_step",
            Self::UnknownChoice { .. } => "error.config.unknown_choice",
            Self::InvalidColor { .. } => "error.config.invalid_color",
            Self::InvalidAction { .. } => "error.config.invalid_action",
            Self::EmptyList { .. } => "error.config.empty_list",
            Self::Record { problem, .. } => problem.i18n_key(),
        }
    }

    pub fn key(&self) -> &str {
        match self {
            Self::UnknownKey { key }
            | Self::WrongType { key, .. }
            | Self::OutOfRange { key, .. }
            | Self::OffStep { key, .. }
            | Self::UnknownChoice { key, .. }
            | Self::InvalidColor { key, .. }
            | Self::InvalidAction { key, .. }
            | Self::EmptyList { key }
            | Self::Record { key, .. } => key,
        }
    }
}

/// The schema itself is inconsistent (a bug in the config structs, caught by `Registry::build`
/// and the v1 test — never a user error).
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum SchemaError {
    #[error("key `{0}` is declared twice")]
    DuplicateKey(String),
    #[error("key `{0}` is both a value and a table (unrepresentable in TOML)")]
    KeyIsTable(String),
    #[error("default of `{key}` is invalid: {error}")]
    InvalidDefault { key: String, error: ValidationError },
    #[error("`{key}` couples to unknown key `{target}`")]
    DanglingCoupling { key: String, target: String },
    #[error("`{key}` couples to `{target}` with an invalid value: {error}")]
    CouplingValue {
        key: String,
        target: String,
        error: ValidationError,
    },
    #[error("`{key}` is overridden by `{target}`, which is not a bool")]
    OverrideNotBool { key: String, target: String },
    #[error("`{key}` has since = {since}, newer than schema version {version}")]
    SinceTooNew {
        key: String,
        since: u32,
        version: u32,
    },
}
