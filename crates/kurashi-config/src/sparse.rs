//! Sparse TOML files: flatten to `(key, output) → value`, surgical writes that keep the user's
//! comments and order, and the schema migration chain.

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use serde_json::Value as Json;
use toml_edit::{DocumentMut, InlineTable, Item, Table, TableLike, Value};

use crate::convert::item_to_json;
use crate::{Diagnostic, DiagnosticReason, SchemaView, Slot};

pub(crate) const VERSION_KEY: &str = "schema_version";
pub(crate) const OUTPUTS_KEY: &str = "outputs";

/// One step of the `schema_version` chain. Runs on the parsed document so renames can move
/// items together with their comments.
#[derive(Clone, Copy)]
pub struct Migration {
    pub from: u32,
    pub to: u32,
    pub apply: fn(&mut DocumentMut) -> Result<(), String>,
}

impl std::fmt::Debug for Migration {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Migration({} -> {})", self.from, self.to)
    }
}

pub(crate) struct Flat {
    pub entries: BTreeMap<Slot, Json>,
    pub diagnostics: Vec<Diagnostic>,
}

struct Cx<'a> {
    schema: &'a dyn SchemaView,
    known: &'a HashSet<String>,
    file: &'a Path,
    out: Flat,
}

impl Cx<'_> {
    fn diag(&mut self, key: String, reason: DiagnosticReason) {
        self.out.diagnostics.push(Diagnostic {
            file: self.file.to_path_buf(),
            key,
            reason,
        });
    }
}

fn display_key(output: Option<&str>, key: &str) -> String {
    match output {
        Some(o) => format!("{OUTPUTS_KEY}.{o}.{key}"),
        None => key.to_string(),
    }
}

/// Flattens a document using the schema to decide where a key ends (a known key's value may
/// itself be a table). `skip` lists reserved top-level names (`schema_version`, `_managed`).
pub(crate) fn flatten(
    root: &dyn TableLike,
    schema: &dyn SchemaView,
    known: &HashSet<String>,
    file: &Path,
    skip: &[&str],
) -> Flat {
    let mut cx = Cx {
        schema,
        known,
        file,
        out: Flat {
            entries: BTreeMap::new(),
            diagnostics: Vec::new(),
        },
    };
    for (k, item) in root.iter() {
        if skip.contains(&k) {
            continue;
        }
        if k == OUTPUTS_KEY {
            let Some(outputs) = item.as_table_like() else {
                cx.diag(k.into(), DiagnosticReason::UnknownKey);
                continue;
            };
            for (o, sub) in outputs.iter() {
                let Some(sub) = sub.as_table_like() else {
                    cx.diag(format!("{OUTPUTS_KEY}.{o}"), DiagnosticReason::UnknownKey);
                    continue;
                };
                for (k2, i2) in sub.iter() {
                    walk(i2, &mut vec![k2.to_string()], Some(o), &mut cx);
                }
            }
            continue;
        }
        walk(item, &mut vec![k.to_string()], None, &mut cx);
    }
    cx.out
}

fn walk(item: &Item, path: &mut Vec<String>, output: Option<&str>, cx: &mut Cx<'_>) {
    let key = path.join(".");
    if cx.known.contains(&key) {
        if output.is_some() && !cx.schema.per_output(&key) {
            cx.diag(display_key(output, &key), DiagnosticReason::NotPerOutput);
            return;
        }
        let Some(json) = item_to_json(item) else {
            let message = "unsupported value".into();
            cx.diag(
                display_key(output, &key),
                DiagnosticReason::Invalid { message },
            );
            return;
        };
        match cx.schema.validate(&key, &json) {
            Ok(()) => {
                cx.out
                    .entries
                    .insert((key, output.map(str::to_string)), json);
            }
            Err(message) => {
                cx.diag(
                    display_key(output, &key),
                    DiagnosticReason::Invalid { message },
                );
            }
        }
    } else if let Some(t) = item.as_table_like() {
        for (k, i) in t.iter() {
            path.push(k.to_string());
            walk(i, path, output, cx);
            path.pop();
        }
    } else {
        cx.diag(display_key(output, &key), DiagnosticReason::UnknownKey);
    }
}

/// Path segments of a slot inside a file.
pub(crate) fn segments(slot: &Slot) -> Vec<String> {
    let mut segs = Vec::new();
    if let Some(o) = &slot.1 {
        segs.push(OUTPUTS_KEY.to_string());
        segs.push(o.clone());
    }
    segs.extend(slot.0.split('.').map(str::to_string));
    segs
}

/// Sets a leaf, creating missing tables (implicit, so no empty `[bar]` headers appear). An
/// existing value keeps its decor (trailing comment, spacing).
pub(crate) fn set_path(t: &mut dyn TableLike, inline: bool, segs: &[String], mut v: Value) {
    let (head, rest) = segs.split_first().expect("non-empty path");
    if rest.is_empty() {
        if let Some(Item::Value(old)) = t.get_mut(head) {
            *v.decor_mut() = old.decor().clone();
            *old = v;
        } else {
            t.insert(head, Item::Value(v));
        }
        return;
    }
    if !t.get(head).is_some_and(Item::is_table_like) {
        let item = if inline {
            Item::Value(Value::InlineTable(InlineTable::new()))
        } else {
            let mut nt = Table::new();
            nt.set_implicit(true);
            nt.set_dotted(t.is_dotted());
            Item::Table(nt)
        };
        t.insert(head, item);
    }
    match t.get_mut(head) {
        Some(Item::Table(child)) => set_path(child, false, rest, v),
        Some(Item::Value(Value::InlineTable(child))) => set_path(child, true, rest, v),
        _ => unreachable!("just ensured a table"),
    }
}

/// Removes a leaf and every table that became empty because of it.
pub(crate) fn remove_path(t: &mut dyn TableLike, segs: &[String]) -> bool {
    let (head, rest) = segs.split_first().expect("non-empty path");
    if rest.is_empty() {
        return t.remove(head).is_some();
    }
    let removed = match t.get_mut(head) {
        Some(Item::Table(c)) => remove_path(c, rest),
        Some(Item::Value(Value::InlineTable(c))) => remove_path(c, rest),
        _ => false,
    };
    if removed {
        match t.get_mut(head) {
            Some(i) if i.as_table_like().is_some_and(|c| c.is_empty()) => {
                t.remove(head);
            }
            // Only sub-tables left: drop the now-empty `[header]` line.
            Some(Item::Table(c)) if c.iter().all(|(_, i)| i.is_table()) => c.set_implicit(true),
            _ => {}
        }
    }
    removed
}

pub(crate) fn file_version(doc: &DocumentMut) -> u32 {
    // A file without `schema_version` predates versioning: it is version 1.
    doc.get(VERSION_KEY)
        .and_then(Item::as_integer)
        .and_then(|v| u32::try_from(v).ok())
        .unwrap_or(1)
}

pub(crate) fn set_version(doc: &mut DocumentMut, v: u32) {
    set_path(
        doc.as_table_mut(),
        false,
        &[VERSION_KEY.to_string()],
        Value::from(i64::from(v)),
    );
}

pub(crate) struct LoadedDoc {
    /// `None` when the file could not be read or parsed: never overwrite it then.
    pub doc: Option<DocumentMut>,
    pub diagnostics: Vec<Diagnostic>,
}

fn diag(file: &Path, reason: DiagnosticReason) -> Diagnostic {
    Diagnostic {
        file: file.to_path_buf(),
        key: String::new(),
        reason,
    }
}

/// Reads and (if older than `target`) migrates a file. Migration is all-or-nothing; with
/// `persist`, the original bytes go to `<file>.bak-v<N>` before the migrated file is written.
pub(crate) fn read_doc(
    path: &Path,
    target: u32,
    migrations: &[Migration],
    persist: bool,
) -> LoadedDoc {
    let mut diagnostics = Vec::new();
    let text = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return LoadedDoc {
                doc: Some(DocumentMut::new()),
                diagnostics,
            };
        }
        Err(e) => {
            let message = e.to_string();
            diagnostics.push(diag(path, DiagnosticReason::Io { message }));
            return LoadedDoc {
                doc: None,
                diagnostics,
            };
        }
    };
    let mut doc = match text.parse::<DocumentMut>() {
        Ok(d) => d,
        Err(e) => {
            let message = e.to_string();
            diagnostics.push(diag(path, DiagnosticReason::Parse { message }));
            return LoadedDoc {
                doc: None,
                diagnostics,
            };
        }
    };
    let found = file_version(&doc);
    if found > target {
        let reason = DiagnosticReason::NewerSchema {
            found,
            supported: target,
        };
        diagnostics.push(diag(path, reason));
    } else if found < target {
        match migrate(&doc, found, target, migrations) {
            Ok(migrated) => {
                if persist {
                    let backup = backup_path(path, found);
                    let res = std::fs::write(&backup, &text)
                        .and_then(|()| atomic_write(path, &migrated.to_string()));
                    if let Err(e) = res {
                        let message = e.to_string();
                        diagnostics.push(diag(path, DiagnosticReason::Io { message }));
                    }
                }
                doc = migrated;
            }
            Err(reason) => diagnostics.push(diag(path, reason)),
        }
    }
    LoadedDoc {
        doc: Some(doc),
        diagnostics,
    }
}

fn migrate(
    doc: &DocumentMut,
    from: u32,
    target: u32,
    migrations: &[Migration],
) -> Result<DocumentMut, DiagnosticReason> {
    let mut work = doc.clone();
    let mut cur = from;
    while cur < target {
        let m = migrations
            .iter()
            .find(|m| m.from == cur && m.to > cur)
            .ok_or(DiagnosticReason::MigrationMissing { from: cur })?;
        (m.apply)(&mut work).map_err(|message| DiagnosticReason::MigrationFailed {
            from: m.from,
            to: m.to,
            message,
        })?;
        cur = m.to;
    }
    set_version(&mut work, cur);
    Ok(work)
}

pub(crate) fn backup_path(path: &Path, version: u32) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".bak-v{version}"));
    path.with_file_name(name)
}

/// Write-to-temp + rename so a crash never leaves a half-written config.
pub(crate) fn atomic_write(path: &Path, contents: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut tmp = path.file_name().unwrap_or_default().to_os_string();
    tmp.push(".tmp");
    let tmp = path.with_file_name(tmp);
    std::fs::write(&tmp, contents)?;
    std::fs::rename(&tmp, path)
}
