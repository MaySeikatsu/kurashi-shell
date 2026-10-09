//! One schema (rule 3): config types are plain Rust structs annotated with `#[kurashi(...)]`;
//! from them come defaults, validation, settings metadata, `config.example.toml`, docs and the
//! `en` i18n catalog. Layering/resolution lives in `kurashi-config`, not here.
//!
//! # `#[derive(KurashiSchema)]`
//!
//! On a **struct** with named fields it implements [`KurashiNode`] (a table of keys); on a
//! **unit enum** it implements [`KurashiLeaf`] with string choices (`snake_case` variant names).
//!
//! Every leaf field needs a doc comment: the first line is the English label, the rest the
//! English help. i18n keys default to `config.<key>.label` / `config.<key>.help`.
//!
//! Field attributes:
//! - `default = <expr>` — required on leaves; typed (`16` for `u32`, `16.0` for `f64`).
//! - `range = a..=b`, `step = <expr>` — numeric fields only, typed like `default`.
//! - `unit = "px"` — display unit.
//! - `choices = ["a", "b"]` — closed set for a `String` field (enums get choices automatically).
//! - `label = "<i18n key>"`, `help = "<i18n key>"` — override the derived i18n keys.
//! - `page = "…"`, `section = "…"` — settings placement (also on structs; inherited downwards;
//!   fallback page = first key segment, section = `general`).
//! - `per_output` — may be overridden per output.
//! - `requires = "<key> == <value>"` / `"<key> != <value>"` — inert unless it holds; the value
//!   is JSON, or a bare word meaning a string (`!= solid`). Repeatable.
//! - `capability = "<name>"` — inert/forced off when the compositor lacks it. Repeatable.
//! - `overridden_by = "<bool key>"` or `"<bool key> => <value>"` — forced (to `value`) while
//!   that key is true, e.g. a11y modes. Repeatable.
//! - `restart`, `advanced`, `hidden` — flags (hidden: valid config, not shown in settings).
//! - `since = <n>` — schema version that introduced the key (default 1).
//! - `nested` — the field is itself a `KurashiSchema` struct (a sub-table).
//!
//! Container attributes: `page`, `section`, and on components
//! `input_slots(left = "<action>", scroll_up = "…", …)` which emits
//! `<component>.input.<slot>` keys for all universal slots (unlisted ones unbound, `""`).
//! Enum attributes: `i18n = "<id>"` (choice keys `config.choice.<id>.<value>`, default the
//! snake_case enum name); on variants `rename = "<value>"`.

extern crate self as kurashi_schema;

mod error;
mod generate;
mod leaf;
mod meta;
mod registry;
pub mod v1;

#[doc(hidden)]
pub mod __private;

pub use error::{SchemaError, ValidationError};
pub use generate::{control_kind, docs_markdown, example_toml, i18n_en, settings_meta, toml_value};
pub use kurashi_schema_derive::KurashiSchema;
pub use leaf::{ActionId, Color, Ctx, FontFamilies, KurashiLeaf, KurashiNode, strings};
pub use meta::{Choice, CmpOp, Constraints, Coupling, Flags, KeyMeta, Text, Ty};
pub use registry::{Registry, validate_value};

/// Current config schema version (written as `schema_version` in `config.toml`).
pub const SCHEMA_VERSION: u32 = v1::VERSION;
