//! Support code for the derive's expansion. Not a public API.

use serde_json::Value;

use crate::leaf::{ActionId, Ctx, KurashiLeaf};
use crate::meta::{CmpOp, Coupling, KeyMeta, Text, Ty};

pub use crate::meta::Choice;
pub use serde_json::Value as JsonValue;

/// Universal input slots every placeable component declares (ARCHITECTURE §6), with the English
/// label and help used for the generated `<component>.input.<slot>` keys.
pub const INPUT_SLOTS: &[(&str, &str)] = &[
    ("left", "Left click"),
    ("right", "Right click"),
    ("middle", "Middle click"),
    ("hover", "Hover"),
    ("scroll_up", "Scroll up"),
    ("scroll_down", "Scroll down"),
    ("shift_scroll_up", "Shift + scroll up"),
    ("shift_scroll_down", "Shift + scroll down"),
];

pub fn join(prefix: &str, name: &str) -> String {
    if prefix.is_empty() {
        name.to_owned()
    } else {
        format!("{prefix}.{name}")
    }
}

pub fn value<T: KurashiLeaf>(v: &T) -> Value {
    v.to_value()
}

pub fn leaf<T: KurashiLeaf>(
    prefix: &str,
    name: &str,
    ctx: &Ctx,
    default: &T,
    label: &str,
    help: Option<&str>,
) -> KeyMeta {
    let mut m = KeyMeta::new(join(prefix, name), T::ty(), default.to_value());
    if let Some(page) = &ctx.page {
        m.page.clone_from(page);
    }
    if let Some(section) = &ctx.section {
        m.section.clone_from(section);
    }
    m.constraints.choices = T::choices();
    m.constraints.type_bounds = T::type_bounds();
    m.help = help.map(|_| format!("config.{}.help", m.key));
    m.text = Text {
        label: label.to_owned(),
        help: help.map(str::to_owned),
    };
    m
}

/// `choices = [...]` on a `String` field.
pub fn string_choices(key: &str, values: &[(&str, &str)]) -> Vec<Choice> {
    values
        .iter()
        .map(|(v, text)| Choice {
            value: (*v).to_owned(),
            label: format!("config.{key}.choice.{v}"),
            text: (*text).to_owned(),
        })
        .collect()
}

/// The derive validated the JSON at compile time.
pub fn json(src: &str) -> Value {
    serde_json::from_str(src).expect("validated by kurashi-schema-derive")
}

pub fn requires(key: &str, ne: bool, value: &str) -> Coupling {
    Coupling::Requires {
        key: key.to_owned(),
        op: if ne { CmpOp::Ne } else { CmpOp::Eq },
        value: json(value),
    }
}

pub fn capability(name: &str) -> Coupling {
    Coupling::Capability {
        name: name.to_owned(),
    }
}

pub fn overridden_by(key: &str, forces: Option<&str>) -> Coupling {
    Coupling::OverriddenBy {
        key: key.to_owned(),
        forces: forces.map(json),
    }
}

/// Emit `<prefix>.input.<slot>` for every universal slot; `defaults` maps slot → action id,
/// unspecified slots are unbound (`""` — TOML has no null).
pub fn input_slots(prefix: &str, ctx: &Ctx, defaults: &[(&str, &str)], out: &mut Vec<KeyMeta>) {
    let prefix = join(prefix, "input");
    for (slot, label) in INPUT_SLOTS {
        let action = defaults
            .iter()
            .find(|(s, _)| s == slot)
            .map_or("", |(_, a)| a);
        let mut m = leaf(&prefix, slot, ctx, &ActionId::new(action), label, None);
        debug_assert_eq!(m.ty, Ty::Action);
        // Slot labels are the same for every component: one i18n key per slot.
        m.label = format!("config.input.{slot}");
        m.flags.advanced = true;
        out.push(m);
    }
}

#[diagnostic::on_unimplemented(
    message = "`range`/`step` need a numeric field type, `{Self}` is not numeric"
)]
pub trait Numeric {}
macro_rules! numeric {
    ($($t:ty),*) => {$( impl Numeric for $t {} )*};
}
numeric!(u8, u16, u32, u64, i8, i16, i32, i64, f32, f64);

#[diagnostic::on_unimplemented(message = "`choices` needs a `String` field, not `{Self}`")]
pub trait Textual {}
impl Textual for String {}

#[diagnostic::on_unimplemented(
    message = "`choices_from` needs a `String` or `Vec<String>` field, not `{Self}`"
)]
pub trait ChoiceSource {}
impl ChoiceSource for String {}
impl ChoiceSource for Vec<String> {}

pub fn assert_numeric<T: Numeric>() {}
pub fn assert_textual<T: Textual>() {}
pub fn assert_choice_source<T: ChoiceSource>() {}
