//! IPC protocol v1 (docs/PROTOCOL.md). One JSON object per line (NDJSON, K4); the `t`
//! field carries the message type. Frozen at the end of M1 (K17): shape changes need a
//! DECISIONS entry, a fixture update and a PROTOCOL.md update.

use kurashi_core::{Provenanced, Rev, Source};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWrite, AsyncWriteExt, BufReader};

pub const PROTOCOL_VERSION: u32 = 1;
/// Lines above this size are rejected (PROTOCOL §1).
pub const MAX_LINE: usize = 4 * 1024 * 1024;

/// Client → server.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum ClientMsg {
    Hello {
        v: u32,
        client: String,
        #[serde(default)]
        caps: Vec<String>,
    },
    Sub {
        id: String,
        doc: String,
    },
    Unsub {
        doc: String,
    },
    Resync {
        doc: String,
    },
    Intent {
        key: String,
        value: Value,
        #[serde(default)]
        origin: Option<String>,
        #[serde(default)]
        coalesce: bool,
    },
    #[serde(rename = "cfg.get")]
    CfgGet {
        id: String,
        key: String,
        /// Resolve for one output (per-output keys); absent = global.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
    #[serde(rename = "cfg.explain")]
    CfgExplain {
        id: String,
        key: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
    /// One atomic, undoable transaction (ARCHITECTURE §3). `dry_run` answers with `preview`.
    Apply {
        id: String,
        ops: Vec<ApplyOp>,
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        dry_run: bool,
    },
    Undo {
        id: String,
    },
    Redo {
        id: String,
    },
    Act {
        id: String,
        action: String,
        #[serde(default)]
        args: Value,
    },
    Query {
        id: String,
        kind: String,
        q: String,
    },
    Ping,
    /// Test/bench control messages understood only by `kurashi-mock`.
    #[serde(rename = "mock.tick")]
    MockTick,
    #[serde(rename = "mock.face")]
    MockFace {
        face: String,
    },
    #[serde(rename = "mock.workspace")]
    MockWorkspace {
        idx: u32,
    },
}

/// Server → client.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum ServerMsg {
    Welcome {
        v: u32,
        server: String,
        #[serde(default)]
        caps: Vec<String>,
        /// Changes every daemon start: a client that reconnects and sees a new instance
        /// re-subscribes everything instead of trusting its cached revisions.
        #[serde(default, skip_serializing_if = "String::is_empty")]
        instance: String,
    },
    Goodbye {
        reason: String,
        supported: Vec<u32>,
    },
    /// Full document. `id` echoes `sub`/`resync`; absent when the server pushes a fresh
    /// snapshot on its own (backing service restarted, compositor resync) — replace state.
    Snap {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        doc: String,
        rev: Rev,
        data: Value,
    },
    /// JSON merge-patch (RFC 7396) relative to `rev - 1`.
    Patch {
        doc: String,
        rev: Rev,
        ops: Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        origin: Option<String>,
    },
    #[serde(rename = "cfg.val")]
    CfgVal {
        id: String,
        key: String,
        v: Provenanced,
    },
    /// `cfg.explain` answer: every layer that has the key, lowest precedence first; the last
    /// `active` entry is the effective value.
    #[serde(rename = "cfg.why")]
    CfgWhy {
        id: String,
        key: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
        layers: Vec<LayerValue>,
    },
    /// `apply`/`undo`/`redo` committed; `undo` is the transaction id.
    Applied {
        id: String,
        rev: Rev,
        undo: String,
    },
    /// `apply` with `dry_run`: effective changes the transaction would cause.
    Preview {
        id: String,
        diff: Vec<DiffEntry>,
    },
    Rejected {
        id: String,
        errors: Vec<OpError>,
    },
    Done {
        id: String,
        /// Optional action result (e.g. `profile.preview` diff).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        data: Option<Value>,
    },
    Results {
        id: String,
        items: Vec<Value>,
    },
    Err {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        kind: String,
        msg: String,
    },
    Pong,
    Bye {
        reason: String,
    },
}

/// One operation of an `apply` transaction:
/// `{"set":"bar.main.edge","value":"left"}` or `{"reset":"theme.motion","output":"DP-1"}`.
/// `reset` of a section prefix removes every user key below it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ApplyOp {
    Set {
        set: String,
        value: Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
    Reset {
        reset: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
}

/// One provenance layer in a `cfg.why` answer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LayerValue {
    pub source: Source,
    pub value: Value,
    /// True for the layer that wins.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub active: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// Effective-value change of one key (profile previews, dry runs). `before`/`after` are absent
/// when no layer (not even the schema) has a value on that side.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiffEntry {
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<Provenanced>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub after: Option<Provenanced>,
}

/// Why one op of a transaction was rejected. `code` is an i18n key (rule 8).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OpError {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    pub code: String,
    pub msg: String,
}

#[derive(Debug, thiserror::Error)]
pub enum CodecError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("line exceeds {MAX_LINE} bytes")]
    TooLong,
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
}

/// Serialize one message as a single NDJSON line.
pub fn encode<T: Serialize>(msg: &T) -> Result<String, CodecError> {
    let mut s = serde_json::to_string(msg)?;
    s.push('\n');
    Ok(s)
}

pub async fn write_msg<W: AsyncWrite + Unpin, T: Serialize>(
    w: &mut W,
    msg: &T,
) -> Result<(), CodecError> {
    w.write_all(encode(msg)?.as_bytes()).await?;
    w.flush().await?;
    Ok(())
}

/// Line reader with the protocol's size limit. Returns `Ok(None)` at EOF.
pub struct LineReader<R> {
    inner: BufReader<R>,
    buf: String,
}

impl<R: tokio::io::AsyncRead + Unpin> LineReader<R> {
    pub fn new(r: R) -> Self {
        Self {
            inner: BufReader::new(r),
            buf: String::new(),
        }
    }

    pub async fn next_value<T: for<'de> Deserialize<'de>>(
        &mut self,
    ) -> Result<Option<T>, CodecError> {
        loop {
            self.buf.clear();
            let n = self.inner.read_line(&mut self.buf).await?;
            if n == 0 {
                return Ok(None);
            }
            if n > MAX_LINE {
                return Err(CodecError::TooLong);
            }
            let line = self.buf.trim();
            if line.is_empty() {
                continue;
            }
            return Ok(Some(serde_json::from_str(line)?));
        }
    }
}

/// RFC 7396 JSON merge-patch, used by clients and the mock to apply `patch` messages.
pub fn merge_patch(target: &mut Value, patch: &Value) {
    match patch {
        Value::Object(p) => {
            if !target.is_object() {
                *target = Value::Object(Default::default());
            }
            let t = target.as_object_mut().expect("object");
            for (k, v) in p {
                if v.is_null() {
                    t.remove(k);
                } else {
                    merge_patch(t.entry(k.clone()).or_insert(Value::Null), v);
                }
            }
        }
        other => *target = other.clone(),
    }
}

/// The merge-patch that turns `old` into `new` (inverse of [`merge_patch`]); `None` if equal.
/// Removed object members become `null`, so stale optional fields (e.g. a `forced_by` that no
/// longer applies) never survive a patch. Documents therefore must not contain `null` values —
/// absence is the only "empty" (PROTOCOL §3).
pub fn diff_patch(old: &Value, new: &Value) -> Option<Value> {
    match (old, new) {
        (Value::Object(o), Value::Object(n)) => {
            let mut out = serde_json::Map::new();
            for k in o.keys() {
                if !n.contains_key(k) {
                    out.insert(k.clone(), Value::Null);
                }
            }
            for (k, nv) in n {
                match o.get(k) {
                    Some(ov) => {
                        if let Some(p) = diff_patch(ov, nv) {
                            out.insert(k.clone(), p);
                        }
                    }
                    None => {
                        out.insert(k.clone(), nv.clone());
                    }
                }
            }
            (!out.is_empty()).then_some(Value::Object(out))
        }
        _ if old == new => None,
        // Replacing a non-object by an object must not merge into it.
        (_, Value::Object(_)) => Some(new.clone()),
        _ => Some(new.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Golden fixtures: every file in fixtures/ipc/client must parse as ClientMsg and
    /// re-serialize to the same JSON value; same for fixtures/ipc/server.
    #[test]
    fn fixtures_round_trip() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/ipc");
        let mut checked = 0;
        for (dir, is_client) in [("client", true), ("server", false)] {
            for entry in std::fs::read_dir(root.join(dir)).expect("fixture dir") {
                let path = entry.unwrap().path();
                let text = std::fs::read_to_string(&path).unwrap();
                let original: Value = serde_json::from_str(&text).unwrap();
                let again = if is_client {
                    serde_json::to_value(
                        serde_json::from_value::<ClientMsg>(original.clone()).unwrap(),
                    )
                    .unwrap()
                } else {
                    serde_json::to_value(
                        serde_json::from_value::<ServerMsg>(original.clone()).unwrap(),
                    )
                    .unwrap()
                };
                assert_eq!(original, again, "fixture {} changed shape", path.display());
                checked += 1;
            }
        }
        assert!(checked >= 8, "expected fixtures, found {checked}");
    }

    #[test]
    fn merge_patch_rfc7396() {
        let mut doc = json!({"a": 1, "b": {"c": 2, "d": 3}});
        merge_patch(&mut doc, &json!({"a": null, "b": {"c": 5}, "e": [1]}));
        assert_eq!(doc, json!({"b": {"c": 5, "d": 3}, "e": [1]}));
    }

    #[test]
    fn diff_patch_removes_stale_fields() {
        let old = json!({"k": {"value": 1, "source": {"kind": "forced", "name": "a11y"}, "forced_by": "a11y"}});
        let new = json!({"k": {"value": 2, "source": {"kind": "user"}}});
        let p = diff_patch(&old, &new).unwrap();
        let mut d = old.clone();
        merge_patch(&mut d, &p);
        assert_eq!(d, new);
        assert_eq!(diff_patch(&new, &new), None);
    }

    fn arb_json() -> impl proptest::strategy::Strategy<Value = Value> {
        use proptest::prelude::*;
        // No nulls: documents never contain them (see diff_patch).
        let leaf = prop_oneof![
            any::<bool>().prop_map(Value::from),
            (-50i64..50).prop_map(Value::from),
            "[a-c]{0,2}".prop_map(Value::from),
        ];
        leaf.prop_recursive(3, 24, 4, |inner| {
            prop_oneof![
                proptest::collection::vec(inner.clone(), 0..3).prop_map(Value::from),
                proptest::collection::btree_map("[a-d]", inner, 0..4)
                    .prop_map(|m| Value::Object(m.into_iter().collect())),
            ]
        })
    }

    proptest::proptest! {
        #[test]
        fn diff_then_merge_reaches_new(old in arb_json(), new in arb_json()) {
            let mut d = old.clone();
            if let Some(p) = diff_patch(&old, &new) {
                merge_patch(&mut d, &p);
            }
            proptest::prop_assert_eq!(d, new);
        }
    }

    #[test]
    fn encode_is_single_line() {
        let s = encode(&ServerMsg::Err {
            id: None,
            kind: "x".into(),
            msg: "line\nbreak".into(),
        })
        .unwrap();
        assert_eq!(s.matches('\n').count(), 1, "framing must stay one line");
    }
}
