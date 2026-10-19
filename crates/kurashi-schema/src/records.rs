//! The `records` setting type (K38, MODS.md "Records"): a list of tables whose fields a mod's
//! manifest declares. One set of rules serves the manifest's default (`kurashi-mods`) and every
//! value ([`crate::validate_value`]): [`RecordSpec::check`] normalises a value (absent optional
//! fields take their defaults) or names every problem by path, `<key>[<n>].<field>`.

use std::fmt;

use serde::Serialize;
use serde_json::{Map, Value};

use crate::error::ValidationError;
use crate::meta::Ty;

/// Type of one field (`type = "…"` in the manifest).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum FieldType {
    String,
    Url,
    Enum,
    Bool,
    Int,
}

impl FieldType {
    /// The manifest's spelling of the type.
    pub fn name(self) -> &'static str {
        match self {
            FieldType::String => "string",
            FieldType::Url => "url",
            FieldType::Enum => "enum",
            FieldType::Bool => "bool",
            FieldType::Int => "int",
        }
    }
}

/// One `[[setting.field]]` of a records setting, as the manifest declared it.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RecordField {
    pub key: String,
    #[serde(rename = "type")]
    pub ty: FieldType,
    pub required: bool,
    /// What a row without the field takes. Absent only for a required field (the row must set it).
    pub default: Option<Value>,
    /// i18n key (or plain text) of the field's name in the editor.
    pub label: Option<String>,
    /// `pattern = "slug"` (strings): `[a-z0-9-]`, 1 to 32 characters.
    pub pattern: Option<String>,
    /// `schemes = [...]` (urls): the scheme an absolute url must have.
    pub schemes: Vec<String>,
    /// `choices = [...]` (enums): the values the field takes.
    pub choices: Vec<String>,
    /// `range = [min, max]` (ints), inclusive.
    pub range: Option<(i64, i64)>,
}

/// The fields of a records setting, its `unique` field and the field a row is named by.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct RecordSpec {
    pub fields: Vec<RecordField>,
    /// `unique = "<field>"`: no two rows share its value (compared after the defaults are filled).
    pub unique: Option<String>,
    /// `item_label = "<field>"`; without one, the first string field names a row.
    pub item_label: Option<String>,
}

/// What is wrong with one row or field. The English text is the developer message; the UI shows
/// [`RecordProblem::i18n_key`] (`error.config.record_*`).
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordProblem {
    /// The row is not a table.
    NotARecord,
    /// A field the manifest does not declare.
    UnknownField,
    /// A required field is absent (or an empty string).
    MissingField,
    /// The value is not of the field's type.
    WrongType { expected: FieldType },
    /// Not a slug (`pattern = "slug"`).
    Slug,
    /// Not an absolute URL.
    UrlInvalid,
    /// An absolute URL, but its scheme is not one of the field's `schemes`.
    Scheme { allowed: Vec<String> },
    /// Not one of the enum's `choices`.
    Choice { choices: Vec<String> },
    /// Outside the int's `range`.
    OutOfRange { min: i64, max: i64 },
    /// Repeats the `unique` value of another row.
    Duplicate,
}

impl RecordProblem {
    /// The i18n key of the message (`error.config.record_*`, CATALOG in `error.rs`).
    pub fn i18n_key(&self) -> &'static str {
        match self {
            Self::NotARecord => "error.config.record_not_a_record",
            Self::UnknownField => "error.config.record_unknown_field",
            Self::MissingField => "error.config.record_missing_field",
            Self::WrongType { .. } => "error.config.record_wrong_type",
            Self::Slug => "error.config.record_slug",
            Self::UrlInvalid => "error.config.record_url",
            Self::Scheme { .. } => "error.config.record_scheme",
            Self::Choice { .. } => "error.config.record_choice",
            Self::OutOfRange { .. } => "error.config.record_out_of_range",
            Self::Duplicate => "error.config.record_duplicate",
        }
    }
}

impl fmt::Display for RecordProblem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotARecord => f.write_str("must be a table of fields"),
            Self::UnknownField => f.write_str("is not a field of this list"),
            Self::MissingField => f.write_str("is required"),
            Self::WrongType { expected } => write!(f, "must be {}", expected_text(*expected)),
            Self::Slug => f.write_str("must be a slug: a-z, 0-9 and hyphens, 1 to 32 characters"),
            Self::UrlInvalid => f.write_str("must be an absolute URL"),
            Self::Scheme { allowed } => {
                write!(f, "must use one of the schemes {}", allowed.join(", "))
            }
            Self::Choice { choices } => write!(f, "must be one of {}", choices.join(", ")),
            Self::OutOfRange { min, max } => write!(f, "must be between {min} and {max}"),
            Self::Duplicate => f.write_str("repeats the value of another row"),
        }
    }
}

fn expected_text(t: FieldType) -> &'static str {
    match t {
        FieldType::String => "text",
        FieldType::Url => "a URL",
        FieldType::Enum => "one of the choices",
        FieldType::Bool => "true or false",
        FieldType::Int => "a whole number",
    }
}

/// `[a-z0-9-]`, 1 to 32 characters.
fn is_slug(s: &str) -> bool {
    (1..=32).contains(&s.len())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// The scheme of an absolute URL (`https` in `https://…`, `mod` in `mod:webdock:pins`), or `None`
/// when `s` has no lowercase scheme or nothing after it, or contains whitespace or control characters.
fn absolute_scheme(s: &str) -> Option<&str> {
    let (scheme, rest) = s.split_once(':')?;
    let first = scheme.bytes().next()?;
    let ok_scheme = first.is_ascii_lowercase()
        && scheme
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"+.-".contains(&b));
    let ok_rest = !rest.is_empty() && rest.chars().all(|c| !c.is_whitespace() && !c.is_control());
    (ok_scheme && ok_rest).then_some(scheme)
}

/// Whether `v` is an acceptable value of `f`, or what is wrong with it. Used for every row's
/// field and for the defaults the manifest declares.
pub fn check_record_field(f: &RecordField, v: &Value) -> Option<RecordProblem> {
    let wrong = || Some(RecordProblem::WrongType { expected: f.ty });
    match f.ty {
        FieldType::String => {
            let Some(s) = v.as_str() else { return wrong() };
            (f.pattern.as_deref() == Some("slug") && !is_slug(s)).then_some(RecordProblem::Slug)
        }
        FieldType::Url => {
            let Some(s) = v.as_str() else { return wrong() };
            match absolute_scheme(s) {
                None => Some(RecordProblem::UrlInvalid),
                Some(scheme) if !f.schemes.iter().any(|a| a == scheme) => {
                    Some(RecordProblem::Scheme {
                        allowed: f.schemes.clone(),
                    })
                }
                Some(_) => None,
            }
        }
        FieldType::Enum => {
            let Some(s) = v.as_str() else { return wrong() };
            (!f.choices.iter().any(|c| c == s)).then(|| RecordProblem::Choice {
                choices: f.choices.clone(),
            })
        }
        FieldType::Bool => (!v.is_boolean()).then_some(RecordProblem::WrongType {
            expected: FieldType::Bool,
        }),
        FieldType::Int => {
            let Some(n) = v.as_i64() else { return wrong() };
            match f.range {
                Some((min, max)) if n < min || n > max => {
                    Some(RecordProblem::OutOfRange { min, max })
                }
                _ => None,
            }
        }
    }
}

impl RecordSpec {
    /// The field a row is named by: `item_label` when declared, else the first string field, else
    /// the first field. `None` only for a spec without fields (refused by the manifest).
    pub fn label_field(&self) -> Option<&RecordField> {
        match &self.item_label {
            Some(name) => self.fields.iter().find(|f| &f.key == name),
            None => self
                .fields
                .iter()
                .find(|f| f.ty == FieldType::String)
                .or_else(|| self.fields.first()),
        }
    }

    /// Normalises `rows` for `key` (the setting's `mods.<id>.<key>`, or any prefix the caller names):
    /// every row an object of the declared fields, absent optional fields filled from their defaults,
    /// `unique` values distinct. Returns the normalised array, or every problem, each named by its
    /// path (`key[n]` for a row, `key[n].field` for a field).
    pub fn check(&self, key: &str, rows: &Value) -> Result<Value, Vec<ValidationError>> {
        let Some(items) = rows.as_array() else {
            return Err(vec![ValidationError::WrongType {
                key: key.into(),
                expected: Ty::Records,
                got: rows.clone(),
            }]);
        };
        let mut errs = Vec::new();
        let mut normal: Vec<(usize, Map<String, Value>)> = Vec::with_capacity(items.len());
        let problem = |path: String, p: RecordProblem| ValidationError::Record {
            key: path,
            problem: p,
        };
        for (n, row) in items.iter().enumerate() {
            let at = |field: &str| format!("{key}[{n}].{field}");
            let Some(obj) = row.as_object() else {
                errs.push(problem(format!("{key}[{n}]"), RecordProblem::NotARecord));
                continue;
            };
            for name in obj.keys() {
                if !self.fields.iter().any(|f| &f.key == name) {
                    errs.push(problem(at(name), RecordProblem::UnknownField));
                }
            }
            let mut row_out = Map::new();
            for f in &self.fields {
                let given = obj
                    .get(&f.key)
                    .filter(|v| !(f.required && v.as_str() == Some("")));
                match given {
                    Some(v) => match check_record_field(f, v) {
                        Some(p) => errs.push(problem(at(&f.key), p)),
                        None => {
                            row_out.insert(f.key.clone(), v.clone());
                        }
                    },
                    None if f.required => {
                        errs.push(problem(at(&f.key), RecordProblem::MissingField))
                    }
                    None => {
                        if let Some(d) = &f.default {
                            row_out.insert(f.key.clone(), d.clone());
                        }
                    }
                }
            }
            normal.push((n, row_out));
        }
        if let Some(unique) = &self.unique {
            let mut seen: Vec<&Value> = Vec::new();
            for (n, row) in &normal {
                let Some(v) = row.get(unique) else { continue };
                if seen.contains(&v) {
                    errs.push(problem(
                        format!("{key}[{n}].{unique}"),
                        RecordProblem::Duplicate,
                    ));
                } else {
                    seen.push(v);
                }
            }
        }
        if !errs.is_empty() {
            return Err(errs);
        }
        Ok(Value::Array(
            normal
                .into_iter()
                .map(|(_, row)| Value::Object(row))
                .collect(),
        ))
    }
}
