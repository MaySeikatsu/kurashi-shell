//! Traits the derive implements, plus the leaf value types config structs may use.

use serde_json::Value;

use crate::meta::{Choice, KeyMeta, Ty};
use crate::records::{FieldType, RecordField, RecordSpec};

/// A single config value type (one key). Implemented for primitives, `String`, `Vec<String>`,
/// [`Color`], [`FontFamilies`], [`ActionId`], and by `#[derive(KurashiSchema)]` on unit enums.
pub trait KurashiLeaf {
    fn ty() -> Ty;
    fn to_value(&self) -> Value;
    fn choices() -> Vec<Choice> {
        Vec::new()
    }
    /// Implicit bounds of the Rust type, validated even without `range`.
    fn type_bounds() -> Option<(Value, Value)> {
        None
    }
    /// The rows' fields of a [`Ty::Records`] key (K38) — a core key's, as a mod's manifest declares its own.
    fn record() -> Option<RecordSpec> {
        None
    }
}

/// A table of keys. Implemented by `#[derive(KurashiSchema)]` on structs with named fields.
pub trait KurashiNode {
    /// Append this subtree's keys (in declaration order) under `prefix` (`""` at the root).
    fn collect(prefix: &str, ctx: &Ctx, out: &mut Vec<KeyMeta>);
    /// The typed value with every field at its schema default.
    fn schema_default() -> Self
    where
        Self: Sized;
}

/// Settings placement inherited down the tree (container attrs override, fields override those).
#[derive(Debug, Clone, Default)]
pub struct Ctx {
    pub page: Option<String>,
    pub section: Option<String>,
}

impl Ctx {
    pub fn with(&self, page: Option<&str>, section: Option<&str>) -> Ctx {
        Ctx {
            page: page.map(str::to_owned).or_else(|| self.page.clone()),
            section: section.map(str::to_owned).or_else(|| self.section.clone()),
        }
    }
}

/// `#rrggbb` / `#rrggbbaa` colour (settings control: color picker).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Color(pub String);

impl Color {
    pub fn new(hex: &str) -> Self {
        Self(hex.to_owned())
    }
}

/// Font family fallback chain (settings control: font picker).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FontFamilies(pub Vec<String>);

impl FontFamilies {
    pub fn of(families: &[&str]) -> Self {
        Self(strings(families))
    }
}

/// Action id bound to an input slot; empty = unbound.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionId(pub String);

impl ActionId {
    pub fn new(id: &str) -> Self {
        Self(id.to_owned())
    }
}

/// A motion curve's text (K83; settings control: the curve editor); `""` = the motion profile's.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MotionCurve(pub String);

impl MotionCurve {
    /// `""`: the profile's curve.
    pub fn profile() -> Self {
        Self(String::new())
    }
}

/// `default = strings(&["a", "b"])` for `Vec<String>` fields.
pub fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| (*s).to_owned()).collect()
}

impl KurashiLeaf for bool {
    fn ty() -> Ty {
        Ty::Bool
    }
    fn to_value(&self) -> Value {
        Value::Bool(*self)
    }
}

macro_rules! int_leaf {
    ($($t:ty),*) => {$(
        impl KurashiLeaf for $t {
            fn ty() -> Ty { Ty::Int }
            fn to_value(&self) -> Value { Value::from(*self) }
            fn type_bounds() -> Option<(Value, Value)> {
                Some((Value::from(<$t>::MIN), Value::from(<$t>::MAX)))
            }
        }
    )*};
}
int_leaf!(u8, u16, u32, u64, i8, i16, i32, i64);

macro_rules! float_leaf {
    ($($t:ty),*) => {$(
        impl KurashiLeaf for $t {
            fn ty() -> Ty { Ty::Float }
            fn to_value(&self) -> Value { Value::from(*self) }
        }
    )*};
}
float_leaf!(f32, f64);

impl KurashiLeaf for String {
    fn ty() -> Ty {
        Ty::String
    }
    fn to_value(&self) -> Value {
        Value::String(self.clone())
    }
}

impl KurashiLeaf for Vec<String> {
    fn ty() -> Ty {
        Ty::StringList
    }
    fn to_value(&self) -> Value {
        Value::from(self.clone())
    }
}

/// Session 30 (I502, `docs/ux/groups.md`): the named groups of bar modules and sidebar sections — `[[layout.groups]]`
/// rows `{id, name, members, accordion}`, `members` the ids in order, comma-separated. A zone's or a sidebar's list names a
/// group as `group:<id>`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ModuleGroups(pub Vec<Value>);

impl KurashiLeaf for ModuleGroups {
    fn ty() -> Ty {
        Ty::Records
    }
    fn to_value(&self) -> Value {
        Value::from(self.0.clone())
    }
    fn record() -> Option<RecordSpec> {
        let field =
            |key: &str, ty: FieldType, required: bool, default: Option<Value>| RecordField {
                key: key.to_owned(),
                ty,
                required,
                default,
                label: Some(format!("config.layout.groups.field.{key}")),
                pattern: (key == "id").then(|| "slug".to_owned()),
                schemes: Vec::new(),
                choices: Vec::new(),
                range: None,
            };
        Some(RecordSpec {
            fields: vec![
                field("id", FieldType::String, true, None),
                field("name", FieldType::String, false, Some(Value::from(""))),
                field("members", FieldType::String, false, Some(Value::from(""))),
                field(
                    "accordion",
                    FieldType::Bool,
                    false,
                    Some(Value::Bool(false)),
                ),
            ],
            unique: Some("id".to_owned()),
            item_label: Some("name".to_owned()),
        })
    }
}

impl KurashiLeaf for Color {
    fn ty() -> Ty {
        Ty::Color
    }
    fn to_value(&self) -> Value {
        Value::String(self.0.clone())
    }
}

impl KurashiLeaf for FontFamilies {
    fn ty() -> Ty {
        Ty::Font
    }
    fn to_value(&self) -> Value {
        Value::from(self.0.clone())
    }
}

impl KurashiLeaf for MotionCurve {
    fn ty() -> Ty {
        Ty::Curve
    }
    fn to_value(&self) -> Value {
        Value::String(self.0.clone())
    }
}

impl KurashiLeaf for ActionId {
    fn ty() -> Ty {
        Ty::Action
    }
    fn to_value(&self) -> Value {
        Value::String(self.0.clone())
    }
}
