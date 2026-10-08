//! IPC protocol v1 (docs/PROTOCOL.md). One JSON object per line (NDJSON, K4); the `t`
//! field carries the message type. Draft until the M1 contract freeze.

use kurashi_core::{Provenanced, Rev};
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
    },
    #[serde(rename = "cfg.explain")]
    CfgExplain {
        id: String,
        key: String,
    },
    Apply {
        id: String,
        ops: Vec<Value>,
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
    },
    Goodbye {
        reason: String,
        supported: Vec<u32>,
    },
    Snap {
        id: String,
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
    Applied {
        id: String,
        rev: Rev,
        undo: String,
    },
    Rejected {
        id: String,
        errors: Vec<String>,
    },
    Done {
        id: String,
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
