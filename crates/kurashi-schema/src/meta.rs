//! Per-key metadata produced by `#[derive(KurashiSchema)]` and stored in the [`Registry`].
//!
//! [`Registry`]: crate::Registry

use serde::Serialize;
use serde_json::Value;

/// Value type of a key. Everything in memory is `serde_json::Value`; TOML only at file
/// boundaries (M1-config), so every type here must be representable in TOML (no null).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Ty {
    Bool,
    Int,
    Float,
    String,
    /// One of a closed set of strings (unit enums, or `choices = [...]` on a `String`).
    Choice,
    StringList,
    /// `#rrggbb` or `#rrggbbaa`.
    Color,
    /// Font family fallback chain, first installed wins (DESIGN-SYSTEM §3 typography).
    Font,
    /// Action id for an input slot; `""` means unbound (ARCHITECTURE §6).
    Action,
}

impl Ty {
    pub fn name(self) -> &'static str {
        match self {
            Ty::Bool => "bool",
            Ty::Int => "int",
            Ty::Float => "float",
            Ty::String => "string",
            Ty::Choice => "choice",
            Ty::StringList => "string_list",
            Ty::Color => "color",
            Ty::Font => "font",
            Ty::Action => "action",
        }
    }
}

impl std::fmt::Display for Ty {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name())
    }
}

/// One allowed value of a [`Ty::Choice`] key.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Choice {
    pub value: String,
    /// i18n key of the display label.
    pub label: String,
    /// English source text (from the variant's doc comment).
    #[serde(skip)]
    pub text: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Constraints {
    /// Inclusive range from `range = a..=b`.
    pub min: Option<Value>,
    pub max: Option<Value>,
    pub step: Option<Value>,
    pub unit: Option<String>,
    pub choices: Vec<Choice>,
    /// Implicit bounds of the Rust type (e.g. `0..=255` for `u8`); validated but not shown.
    pub type_bounds: Option<(Value, Value)>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Flags {
    /// May be overridden per output (`[outputs."DP-1".bar]`).
    pub per_output: bool,
    /// Change takes effect only after restarting the shell.
    pub restart: bool,
    /// Shown only in the settings' advanced view.
    pub advanced: bool,
    /// Not shown in settings at all (still valid config, still in docs/example).
    pub hidden: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CmpOp {
    Eq,
    Ne,
}

impl CmpOp {
    pub fn symbol(self) -> &'static str {
        match self {
            CmpOp::Eq => "==",
            CmpOp::Ne => "!=",
        }
    }
}

/// Why a key can be inert. Schema data, evaluated in the daemon (ARCHITECTURE §3) so renderers
/// never grow `&&` chains; the settings UI uses it to explain the inert state (Shōjiki).
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Coupling {
    /// Active only while `key op value` holds.
    Requires {
        key: String,
        op: CmpOp,
        value: Value,
    },
    /// Needs a compositor capability (e.g. `blur`); forced off when it is missing.
    Capability { name: String },
    /// While the bool `key` is true this key is forced (to `forces`, if given), e.g. a11y modes.
    OverriddenBy {
        key: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        forces: Option<Value>,
    },
}

impl Coupling {
    /// i18n key of the sentence that explains this coupling in the UI.
    pub fn reason_key(&self) -> &'static str {
        match self {
            Coupling::Requires { .. } => "settings.inert.requires",
            Coupling::Capability { .. } => "settings.inert.capability",
            Coupling::OverriddenBy { .. } => "settings.inert.overridden_by",
        }
    }

    /// Is this coupling currently making the key inert? `value_of` returns effective values,
    /// `has_capability` asks the compositor adapter.
    pub fn blocks(
        &self,
        value_of: &dyn Fn(&str) -> Option<Value>,
        has_capability: &dyn Fn(&str) -> bool,
    ) -> bool {
        match self {
            Coupling::Requires { key, op, value } => {
                let holds = value_of(key).as_ref() == Some(value);
                match op {
                    CmpOp::Eq => !holds,
                    CmpOp::Ne => holds,
                }
            }
            Coupling::Capability { name } => !has_capability(name),
            Coupling::OverriddenBy { key, .. } => value_of(key) == Some(Value::Bool(true)),
        }
    }
}

/// English source text of a key, taken from its doc comment (first line = label, rest = help).
/// The i18n catalog for `en` is generated from it ([`crate::i18n_en`]).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Text {
    pub label: String,
    pub help: Option<String>,
}

/// Everything known about one flat dotted key (`bar.height`, `theme.material.blur`).
#[derive(Debug, Clone, PartialEq)]
pub struct KeyMeta {
    pub key: String,
    pub ty: Ty,
    pub default: Value,
    pub constraints: Constraints,
    /// i18n key of the label (default `config.<key>.label`).
    pub label: String,
    /// i18n key of the help text (default `config.<key>.help` when the doc has help text).
    pub help: Option<String>,
    pub page: String,
    pub section: String,
    pub flags: Flags,
    pub couplings: Vec<Coupling>,
    /// Schema version that introduced the key.
    pub since: u32,
    pub text: Text,
}

impl KeyMeta {
    /// A key with no constraints, flags or couplings; label/help keys derived from `key`.
    pub fn new(key: impl Into<String>, ty: Ty, default: Value) -> Self {
        let key = key.into();
        let page = key.split('.').next().unwrap_or_default().to_owned();
        Self {
            label: format!("config.{key}.label"),
            help: None,
            page,
            section: "general".into(),
            ty,
            default,
            constraints: Constraints::default(),
            flags: Flags::default(),
            couplings: Vec::new(),
            since: 1,
            text: Text::default(),
            key,
        }
    }

    /// Couplings currently making this key inert (empty = active).
    pub fn blocked_by(
        &self,
        value_of: &dyn Fn(&str) -> Option<Value>,
        has_capability: &dyn Fn(&str) -> bool,
    ) -> Vec<&Coupling> {
        self.couplings
            .iter()
            .filter(|c| c.blocks(value_of, has_capability))
            .collect()
    }
}
