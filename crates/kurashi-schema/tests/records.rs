//! The `records` type (K38, MODS.md "Records"): one checker for every row, normalisation to every
//! declared field, each problem named by its path, and the description the Settings editor reads.

use kurashi_schema::{
    FieldType, KeyMeta, RecordField, RecordProblem, RecordSpec, Registry, Ty, ValidationError,
    check_record_field, settings_meta, validate_value,
};
use serde_json::{Value, json};

fn field(key: &str, ty: FieldType) -> RecordField {
    RecordField {
        key: key.into(),
        ty,
        required: false,
        default: None,
        label: None,
        pattern: None,
        schemes: vec![],
        choices: vec![],
        range: None,
    }
}

/// The web dock's pins in miniature: a slug id, a url target, an enum view, a bool and an int.
fn spec() -> RecordSpec {
    let id = RecordField {
        required: true,
        pattern: Some("slug".into()),
        ..field("id", FieldType::String)
    };
    let target = RecordField {
        required: true,
        schemes: vec!["https".into(), "mod".into()],
        ..field("target", FieldType::Url)
    };
    let view = RecordField {
        choices: vec!["default".into(), "mobile".into()],
        default: Some(json!("default")),
        ..field("view", FieldType::Enum)
    };
    let keep = RecordField {
        default: Some(json!(false)),
        ..field("keep", FieldType::Bool)
    };
    let size = RecordField {
        range: Some((1, 9)),
        default: Some(json!(3)),
        ..field("size", FieldType::Int)
    };
    RecordSpec {
        fields: vec![id, target, view, keep, size],
        unique: Some("id".into()),
        item_label: Some("target".into()),
    }
}

const KEY: &str = "mods.webdock.pins";

fn problems(rows: &Value) -> Vec<ValidationError> {
    spec().check(KEY, rows).err().unwrap_or_default()
}

fn record(key: &str, problem: RecordProblem) -> ValidationError {
    ValidationError::Record {
        key: key.into(),
        problem,
    }
}

#[test]
fn absent_optional_fields_take_their_defaults_and_every_field_is_present() {
    let out = spec()
        .check(KEY, &json!([{"id": "a", "target": "https://x"}]))
        .unwrap();
    assert_eq!(
        out,
        json!([{"id": "a", "target": "https://x", "view": "default", "keep": false, "size": 3}])
    );
    // An empty list is a valid value (the usual default).
    assert_eq!(spec().check(KEY, &json!([])).unwrap(), json!([]));
}

#[test]
fn every_wrong_field_is_named_by_its_row_and_field() {
    let cases = [
        (
            json!([{"id": "a", "target": "https://x", "color": "red"}]),
            record("mods.webdock.pins[0].color", RecordProblem::UnknownField),
        ),
        (
            json!([{"id": "a"}]),
            record("mods.webdock.pins[0].target", RecordProblem::MissingField),
        ),
        (
            json!([{"id": "", "target": "https://x"}]),
            record("mods.webdock.pins[0].id", RecordProblem::MissingField),
        ),
        (
            json!([{"id": "Bad Id", "target": "https://x"}]),
            record("mods.webdock.pins[0].id", RecordProblem::Slug),
        ),
        (
            json!([{"id": "a".repeat(33), "target": "https://x"}]),
            record("mods.webdock.pins[0].id", RecordProblem::Slug),
        ),
        (
            json!([{"id": "a", "target": "example.com"}]),
            record("mods.webdock.pins[0].target", RecordProblem::UrlInvalid),
        ),
        (
            json!([{"id": "a", "target": "ftp://x"}]),
            record(
                "mods.webdock.pins[0].target",
                RecordProblem::Scheme {
                    allowed: vec!["https".into(), "mod".into()],
                },
            ),
        ),
        (
            json!([{"id": "a", "target": "https://x", "view": "tv"}]),
            record(
                "mods.webdock.pins[0].view",
                RecordProblem::Choice {
                    choices: vec!["default".into(), "mobile".into()],
                },
            ),
        ),
        (
            json!([{"id": "a", "target": "https://x", "keep": "yes"}]),
            record(
                "mods.webdock.pins[0].keep",
                RecordProblem::WrongType {
                    expected: FieldType::Bool,
                },
            ),
        ),
        (
            json!([{"id": "a", "target": "https://x", "size": 10}]),
            record(
                "mods.webdock.pins[0].size",
                RecordProblem::OutOfRange { min: 1, max: 9 },
            ),
        ),
        (
            json!([{"id": "a", "target": "https://x", "size": 2.5}]),
            record(
                "mods.webdock.pins[0].size",
                RecordProblem::WrongType {
                    expected: FieldType::Int,
                },
            ),
        ),
        (
            json!([1]),
            record("mods.webdock.pins[0]", RecordProblem::NotARecord),
        ),
        (
            json!([{"id": "a", "target": "https://x"}, {"id": "a", "target": "https://y"}]),
            record("mods.webdock.pins[1].id", RecordProblem::Duplicate),
        ),
        (
            json!("not a list"),
            ValidationError::WrongType {
                key: KEY.into(),
                expected: Ty::Records,
                got: json!("not a list"),
            },
        ),
    ];
    for (rows, expected) in cases {
        assert_eq!(problems(&rows), vec![expected], "for {rows}");
    }
}

#[test]
fn a_bad_value_reports_every_problem_not_just_the_first() {
    let rows = json!([
        {"id": "Bad Id", "target": "example.com", "color": "red"},
        {"id": "b", "target": "https://x", "size": 0}
    ]);
    let errs = problems(&rows);
    let mut keys: Vec<&str> = errs.iter().map(ValidationError::key).collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        [
            "mods.webdock.pins[0].color",
            "mods.webdock.pins[0].id",
            "mods.webdock.pins[0].target",
            "mods.webdock.pins[1].size",
        ]
    );
}

#[test]
fn unique_compares_the_normalised_values() {
    // Two rows that differ only in a defaulted field still share the unique id.
    let rows = json!([
        {"id": "a", "target": "https://x"},
        {"id": "a", "target": "https://y", "view": "mobile"}
    ]);
    assert_eq!(
        problems(&rows),
        vec![record("mods.webdock.pins[1].id", RecordProblem::Duplicate)]
    );
}

#[test]
fn validate_value_is_the_one_validator_for_a_records_key() {
    let mut m = KeyMeta::new(KEY, Ty::Records, json!([]));
    m.constraints.record = Some(spec());
    assert!(validate_value(&m, &json!([{"id": "a", "target": "https://x"}])).is_ok());
    assert_eq!(
        validate_value(&m, &json!([{"id": "a", "target": "example.com"}])),
        Err(record(
            "mods.webdock.pins[0].target",
            RecordProblem::UrlInvalid
        ))
    );
    // A records key without its fields accepts only the empty list.
    let bare = KeyMeta::new(KEY, Ty::Records, json!([]));
    assert!(validate_value(&bare, &json!([])).is_ok());
    assert!(validate_value(&bare, &json!([{"id": "a"}])).is_err());
}

#[test]
fn each_field_type_checks_its_own_values() {
    let slug = RecordField {
        pattern: Some("slug".into()),
        ..field("s", FieldType::String)
    };
    assert_eq!(check_record_field(&slug, &json!("ok-1")), None);
    assert_eq!(
        check_record_field(&slug, &json!("OK")),
        Some(RecordProblem::Slug)
    );
    let url = RecordField {
        schemes: vec!["file".into()],
        ..field("u", FieldType::Url)
    };
    assert_eq!(check_record_field(&url, &json!("file:///tmp/x.html")), None);
    assert_eq!(
        check_record_field(&url, &json!("file:")),
        Some(RecordProblem::UrlInvalid)
    );
    assert_eq!(
        check_record_field(&url, &json!("file:/tmp/x")),
        None,
        "an absolute path after one slash is still absolute"
    );
    assert_eq!(
        check_record_field(&url, &json!(3)),
        Some(RecordProblem::WrongType {
            expected: FieldType::Url
        })
    );
}

#[test]
fn the_label_field_is_the_declared_one_or_the_first_string() {
    let mut s = spec();
    assert_eq!(s.label_field().unwrap().key, "target");
    s.item_label = None;
    assert_eq!(s.label_field().unwrap().key, "id", "the first string field");
}

#[test]
fn settings_meta_describes_the_records_editor() {
    let mut m = KeyMeta::new(KEY, Ty::Records, json!([]));
    m.constraints.record = Some(spec());
    m.page = "mods.webdock".into();
    let reg = Registry::from_keys(1, vec![m]).expect("one valid key");
    let doc = settings_meta(&reg);
    let row = &doc["pages"][0]["sections"][0]["rows"][0];
    assert_eq!(row["control"], "records");
    assert_eq!(row["type"], "records");
    assert_eq!(row["default"], json!([]));
    assert_eq!(row["record"]["unique"], "id");
    assert_eq!(row["record"]["item_label"], "target");
    let fields = row["record"]["fields"].as_array().unwrap();
    assert_eq!(fields.len(), 5);
    assert_eq!(fields[1]["type"], "url");
    assert_eq!(fields[1]["schemes"], json!(["https", "mod"]));
    assert_eq!(fields[2]["default"], "default");
    assert_eq!(fields[2]["choices"][1]["value"], "mobile");
    assert_eq!(
        fields[2]["choices"][1]["label"],
        "mods.webdock.pins.view.mobile"
    );
    assert_eq!(fields[4]["range"], json!([1, 9]));
}
