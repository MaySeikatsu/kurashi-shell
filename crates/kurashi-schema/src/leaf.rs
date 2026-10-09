//! Traits the derive implements, plus the leaf value types config structs may use.

use serde_json::Value;

use crate::meta::{Choice, KeyMeta, Ty};

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

impl KurashiLeaf for ActionId {
    fn ty() -> Ty {
        Ty::Action
    }
    fn to_value(&self) -> Value {
        Value::String(self.0.clone())
    }
}
