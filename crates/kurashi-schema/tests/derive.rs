//! A test tree that uses every `#[kurashi(...)]` attribute, plus validation behaviour.

use kurashi_schema::{
    ActionId, CmpOp, Color, Coupling, KurashiNode, KurashiSchema, Registry, Ty, ValidationError,
    control_kind,
};
use serde_json::json;

#[derive(Debug, Clone, Copy, PartialEq, KurashiSchema)]
#[kurashi(i18n = "look")]
enum Style {
    /// Plain and simple
    Plain,
    #[kurashi(rename = "fancy-pants")]
    Fancy,
}

#[derive(Debug, PartialEq, KurashiSchema)]
#[kurashi(page = "test", section = "basics")]
struct Root {
    /// Enabled
    #[kurashi(default = true, restart)]
    enabled: bool,
    /// Size
    /// How big it is.
    /// Second help line.
    #[kurashi(default = 10, range = 0..=20, step = 5, unit = "px", per_output, advanced,
              requires = "enabled == true")]
    size: u32,
    /// Ratio
    #[kurashi(default = 0.5, range = 0.0..=1.0, label = "custom.ratio", help = "custom.ratio_help",
              section = "extra", since = 2)]
    ratio: f64,
    /// Style
    #[kurashi(default = Style::Plain, capability = "blur", overridden_by = "child.lock => plain",
              hidden)]
    style: Style,
    /// Mode
    #[kurashi(default = "a".to_owned(), choices = ["a", "b_c"], page = "other")]
    mode: String,
    /// Accent
    #[kurashi(default = Color::new("#d7c4a1"))]
    accent: Color,
    /// Bound action
    #[kurashi(default = ActionId::new(""), requires = "style != fancy-pants")]
    action: ActionId,
    #[kurashi(nested, section = "child_section")]
    child: Child,
}

#[derive(Debug, PartialEq, KurashiSchema)]
#[kurashi(input_slots(left = "child.open", scroll_down = "child.next"))]
struct Child {
    /// Lock
    #[kurashi(default = false)]
    lock: bool,
    /// Count
    #[kurashi(default = -3)]
    count: i8,
}

fn reg() -> Registry {
    Registry::build::<Root>(2).expect("consistent")
}

#[test]
fn keys_in_declaration_order() {
    let r = reg();
    let keys: Vec<&str> = r.keys().collect();
    let mut expected = vec![
        "enabled",
        "size",
        "ratio",
        "style",
        "mode",
        "accent",
        "action",
        "child.lock",
        "child.count",
    ];
    let slots = [
        "left",
        "right",
        "middle",
        "hover",
        "scroll_up",
        "scroll_down",
        "shift_scroll_up",
        "shift_scroll_down",
    ];
    let slot_keys: Vec<String> = slots.iter().map(|s| format!("child.input.{s}")).collect();
    expected.extend(slot_keys.iter().map(String::as_str));
    assert_eq!(keys, expected);
}

#[test]
fn every_attribute_lands_in_meta() {
    let r = reg();
    let enabled = r.get("enabled").unwrap();
    assert!(enabled.flags.restart);
    assert_eq!(enabled.text.label, "Enabled");
    assert_eq!(enabled.help, None);
    assert_eq!(
        (enabled.page.as_str(), enabled.section.as_str()),
        ("test", "basics")
    );

    let size = r.get("size").unwrap();
    assert_eq!(size.ty, Ty::Int);
    assert_eq!(size.default, json!(10));
    assert_eq!(size.constraints.min, Some(json!(0)));
    assert_eq!(size.constraints.max, Some(json!(20)));
    assert_eq!(size.constraints.step, Some(json!(5)));
    assert_eq!(size.constraints.unit.as_deref(), Some("px"));
    assert!(size.flags.per_output && size.flags.advanced);
    assert_eq!(size.label, "config.size.label");
    assert_eq!(size.help.as_deref(), Some("config.size.help"));
    assert_eq!(
        size.text.help.as_deref(),
        Some("How big it is. Second help line.")
    );
    assert_eq!(
        size.couplings,
        vec![Coupling::Requires {
            key: "enabled".into(),
            op: CmpOp::Eq,
            value: json!(true)
        }]
    );
    assert_eq!(control_kind(size), "slider");

    let ratio = r.get("ratio").unwrap();
    assert_eq!(ratio.label, "custom.ratio");
    assert_eq!(ratio.help.as_deref(), Some("custom.ratio_help"));
    assert_eq!(ratio.section, "extra");
    assert_eq!(ratio.since, 2);
    assert_eq!(ratio.default, json!(0.5));

    let style = r.get("style").unwrap();
    assert_eq!(style.ty, Ty::Choice);
    assert!(style.flags.hidden);
    let choices: Vec<(&str, &str, &str)> = style
        .constraints
        .choices
        .iter()
        .map(|c| (c.value.as_str(), c.label.as_str(), c.text.as_str()))
        .collect();
    assert_eq!(
        choices,
        vec![
            ("plain", "config.choice.look.plain", "Plain and simple"),
            (
                "fancy-pants",
                "config.choice.look.fancy-pants",
                "Fancy pants"
            ),
        ]
    );
    assert_eq!(
        style.couplings,
        vec![
            Coupling::Capability {
                name: "blur".into()
            },
            Coupling::OverriddenBy {
                key: "child.lock".into(),
                forces: Some(json!("plain"))
            },
        ]
    );

    let mode = r.get("mode").unwrap();
    assert_eq!(mode.ty, Ty::String);
    assert_eq!(mode.page, "other");
    assert_eq!(control_kind(mode), "select");
    assert_eq!(mode.constraints.choices[1].label, "config.mode.choice.b_c");

    assert_eq!(control_kind(r.get("accent").unwrap()), "color");
    let action = r.get("action").unwrap();
    assert_eq!(
        action.couplings,
        vec![Coupling::Requires {
            key: "style".into(),
            op: CmpOp::Ne,
            value: json!("fancy-pants")
        }]
    );

    let count = r.get("child.count").unwrap();
    assert_eq!(count.section, "child_section");
    assert_eq!(count.default, json!(-3));

    let left = r.get("child.input.left").unwrap();
    assert_eq!(
        (left.ty, left.default.clone()),
        (Ty::Action, json!("child.open"))
    );
    assert_eq!(control_kind(left), "action_binding");
    assert_eq!(r.get("child.input.hover").unwrap().default, json!(""));
    assert_eq!(left.section, "child_section");
}

#[test]
fn schema_default_matches_registry() {
    let d = Root::schema_default();
    assert_eq!(d.size, 10);
    assert_eq!(d.style, Style::Plain);
    assert_eq!(
        kurashi_schema::KurashiLeaf::to_value(&Style::Fancy),
        json!("fancy-pants")
    );
    assert_eq!(d.child.count, -3);
    assert_eq!(reg().defaults()["child.count"], json!(-3));
}

#[test]
fn validation_rejects_with_typed_errors() {
    let r = reg();
    assert!(r.validate("size", &json!(15)).is_ok());
    assert!(r.validate("style", &json!("fancy-pants")).is_ok());

    let e = r.validate("size", &json!(25)).unwrap_err();
    assert_eq!(
        e,
        ValidationError::OutOfRange {
            key: "size".into(),
            min: json!(0),
            max: json!(20),
            got: json!(25)
        }
    );
    assert_eq!(e.i18n_key(), "error.config.out_of_range");

    let e = r.validate("size", &json!("big")).unwrap_err();
    assert!(matches!(
        e,
        ValidationError::WrongType {
            expected: Ty::Int,
            ..
        }
    ));
    assert_eq!(e.i18n_key(), "error.config.wrong_type");

    let e = r.validate("style", &json!("fancy")).unwrap_err();
    assert!(matches!(&e, ValidationError::UnknownChoice { got, .. } if got == "fancy"));
    assert_eq!(e.i18n_key(), "error.config.unknown_choice");

    let e = r.validate("mode", &json!("z")).unwrap_err();
    assert_eq!(e.i18n_key(), "error.config.unknown_choice");

    assert_eq!(
        r.validate("size", &json!(7)).unwrap_err().i18n_key(),
        "error.config.off_step"
    );
    assert_eq!(
        r.validate("child.count", &json!(200))
            .unwrap_err()
            .i18n_key(),
        "error.config.out_of_range"
    );
    assert_eq!(
        r.validate("accent", &json!("red")).unwrap_err().i18n_key(),
        "error.config.invalid_color"
    );
    assert_eq!(
        r.validate("nope", &json!(1)).unwrap_err().i18n_key(),
        "error.config.unknown_key"
    );

    // Serializes with a code tag for `rejected` replies.
    let wire = serde_json::to_value(r.validate("enabled", &json!(1)).unwrap_err()).unwrap();
    assert_eq!(wire["code"], "wrong_type");
    assert_eq!(wire["key"], "enabled");
}

#[test]
fn since_newer_than_version_is_rejected() {
    let errs = Registry::build::<Root>(1).unwrap_err();
    assert!(
        errs.iter()
            .any(|e| matches!(e, kurashi_schema::SchemaError::SinceTooNew { .. }))
    );
}

#[test]
fn coupling_evaluation() {
    let r = reg();
    let style = r.get("style").unwrap();
    let values = |k: &str| (k == "child.lock").then_some(json!(true));
    let blocked = style.blocked_by(&values, &|_| true);
    assert_eq!(blocked.len(), 1);
    assert_eq!(blocked[0].reason_key(), "settings.inert.overridden_by");
    let free = style.blocked_by(&|_| Some(json!(false)), &|_| false);
    assert!(matches!(free[..], [Coupling::Capability { .. }]));
}
