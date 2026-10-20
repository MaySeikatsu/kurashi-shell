//! The actions (`tasks.*`, K46). Each one reads the file right before it writes (so an edit made elsewhere since the
//! last publish is never lost), changes only its own line, and writes atomically; then the service publishes. A refusal
//! is an i18n key: a bad argument is `Invalid`, a file that cannot be used now is `Unavailable`.

use kurashi_mod_api::{ActionError, Settings};
use serde_json::{Value, json};

use crate::markdown::{self, File};
use crate::service::{Config, Shared};
use crate::store::{self, Read};

pub const ERR_TEXT: &str = "mod-tasks.error.text";
pub const ERR_ID: &str = "mod-tasks.error.id";
pub const ERR_GONE: &str = "mod-tasks.error.gone";
pub const ERR_WRITE: &str = "mod-tasks.error.write";
pub const ERR_READ_ONLY: &str = "mod-tasks.error.read_only";
pub const ERR_NOTE_LARGE: &str = "mod-tasks.error.too_large";

fn invalid(key: &str) -> ActionError {
    ActionError::Invalid(key.into())
}

fn unavailable(key: &str) -> ActionError {
    ActionError::Unavailable(key.into())
}

fn id_arg(args: &Value) -> Result<String, ActionError> {
    args["id"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| invalid(ERR_ID))
}

fn text_arg(args: &Value) -> Result<String, ActionError> {
    markdown::clean_text(args["text"].as_str().unwrap_or("")).ok_or_else(|| invalid(ERR_TEXT))
}

/// Read the checklist now, let `change` edit it, write it back. `create`: a missing file starts empty (the add);
/// otherwise a missing file means the item is gone.
fn with_file(
    s: &Shared,
    settings: &Settings,
    create: bool,
    change: impl FnOnce(&mut File) -> Result<Value, ActionError>,
) -> Result<Option<Value>, ActionError> {
    let cfg = Config::read(settings, &s.paths);
    let reply = {
        let _guard = s.write_lock();
        let mut file = match store::read(&cfg.file) {
            Read::Missing if create => File::parse(""),
            Read::Missing => return Err(unavailable(ERR_GONE)),
            Read::Failed(key) => return Err(unavailable(key)),
            Read::Text(_, true) => return Err(unavailable(ERR_READ_ONLY)),
            Read::Text(text, false) => File::parse(&text),
        };
        let before = file.render();
        let reply = change(&mut file)?;
        let after = file.render();
        if after != before {
            store::write_atomic(&cfg.file, &after).map_err(|_| unavailable(ERR_WRITE))?;
        }
        reply
    };
    s.wake.notify_one();
    Ok((!reply.is_null()).then_some(reply))
}

/// `tasks.add {text}`: `- [ ] text` under the last section; the file and its folder are made when missing.
pub fn add(s: &Shared, settings: &Settings, args: &Value) -> Result<Option<Value>, ActionError> {
    let text = text_arg(args)?;
    with_file(s, settings, true, |f| Ok(json!({"id": f.add(&text)})))
}

/// `tasks.toggle {id}`: ticks (with today's `✅` date) or unticks.
pub fn toggle(s: &Shared, settings: &Settings, args: &Value) -> Result<Option<Value>, ActionError> {
    let id = id_arg(args)?;
    let today = (s.today)();
    with_file(s, settings, false, |f| {
        let done = f.toggle(&id, &today).ok_or_else(|| unavailable(ERR_GONE))?;
        Ok(json!({"id": id, "done": done}))
    })
}

/// `tasks.edit {id, text}`: the new text, the markers kept. Answers the item's new id.
pub fn edit(s: &Shared, settings: &Settings, args: &Value) -> Result<Option<Value>, ActionError> {
    let id = id_arg(args)?;
    let text = text_arg(args)?;
    with_file(s, settings, false, |f| {
        let new = f.edit(&id, &text).ok_or_else(|| unavailable(ERR_GONE))?;
        Ok(json!({"id": new}))
    })
}

/// `tasks.remove {id}`.
pub fn remove(s: &Shared, settings: &Settings, args: &Value) -> Result<Option<Value>, ActionError> {
    let id = id_arg(args)?;
    with_file(s, settings, false, |f| {
        if f.remove(&id) {
            Ok(Value::Null)
        } else {
            Err(unavailable(ERR_GONE))
        }
    })
}

/// `tasks.clear_done {}`: removes every done item (also those older than today). Answers how many.
pub fn clear_done(s: &Shared, settings: &Settings) -> Result<Option<Value>, ActionError> {
    with_file(s, settings, false, |f| {
        Ok(json!({"removed": f.clear_done()}))
    })
}

/// `tasks.notes.set {text}`: the whole note. A file that uses CRLF keeps it; an empty note on a missing file makes none.
pub fn notes_set(
    s: &Shared,
    settings: &Settings,
    args: &Value,
) -> Result<Option<Value>, ActionError> {
    let Some(text) = args["text"].as_str() else {
        return Err(invalid(ERR_TEXT));
    };
    if text.len() as u64 > store::MAX_BYTES {
        return Err(invalid(ERR_NOTE_LARGE));
    }
    let cfg = Config::read(settings, &s.paths);
    {
        let _guard = s.write_lock();
        let crlf = match store::read(&cfg.notes) {
            Read::Missing if text.is_empty() => return Ok(None),
            Read::Missing => false,
            Read::Failed(key) => return Err(unavailable(key)),
            Read::Text(_, true) => return Err(unavailable(ERR_READ_ONLY)),
            Read::Text(old, false) => {
                if old.replace("\r\n", "\n") == text.replace("\r\n", "\n") {
                    return Ok(None);
                }
                old.contains("\r\n")
            }
        };
        let lf = text.replace("\r\n", "\n");
        let out = if crlf { lf.replace('\n', "\r\n") } else { lf };
        store::write_atomic(&cfg.notes, &out).map_err(|_| unavailable(ERR_WRITE))?;
    }
    s.wake.notify_one();
    Ok(None)
}
