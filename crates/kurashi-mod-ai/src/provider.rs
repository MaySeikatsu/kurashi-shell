//! The three wire formats (shellseikatsu `Services/LlmService.qml`: `_buildBody`, `_endpointAndHeaders`, `_parseLine`;
//! ii `services/ai/OpenAiApiStrategy.qml`: reasoning deltas):
//! - `ollama`: `POST {base}/api/chat`, NDJSON lines `{"message": {"content", "thinking"?}, "done"}`; models from
//!   `GET {base}/api/tags`. Local and keyless.
//! - `openai` (and every OpenAI-compatible server: llama.cpp, vLLM, LM Studio, OpenRouter, Mistral…): `POST
//!   {base}/chat/completions`, SSE `data: {"choices": [{"delta": {"content", "reasoning_content"?}}]}` and `data:
//!   [DONE]`; models from `GET {base}/models`. `Authorization: Bearer <key>` when a key is set.
//! - `anthropic`: `POST {base}/v1/messages`, SSE events (`content_block_delta` with `text_delta` or `thinking_delta`,
//!   `message_stop`, `error`); models from `GET {base}/v1/models`. `x-api-key` and `anthropic-version`.

use serde_json::{Value, json};

use crate::http::{Header, HttpError, Request};
use crate::key::{ApiKey, KeySource};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Ollama,
    OpenAi,
    Anthropic,
}

impl Format {
    pub fn id(self) -> &'static str {
        match self {
            Self::Ollama => "ollama",
            Self::OpenAi => "openai",
            Self::Anthropic => "anthropic",
        }
    }

    pub fn from_id(s: &str) -> Self {
        match s {
            "openai" => Self::OpenAi,
            "anthropic" => Self::Anthropic,
            _ => Self::Ollama,
        }
    }
}

pub const DEFAULT_OLLAMA: &str = "http://127.0.0.1:11434";
pub const DEFAULT_OPENAI: &str = "https://api.openai.com/v1";
pub const DEFAULT_ANTHROPIC: &str = "https://api.anthropic.com";
pub const ANTHROPIC_VERSION: &str = "2023-06-01";

/// The provider the settings choose, resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub format: Format,
    /// Without a trailing slash.
    pub base: String,
    /// The model the settings name; empty: Ollama's first installed one, else "choose one".
    pub model: String,
    pub key: KeySource,
    pub max_tokens: u32,
    pub system: String,
}

/// A settings reader: the value of `mods.ai.<key>` in effect.
pub trait Get {
    fn str(&self, key: &str) -> Option<String>;
    fn int(&self, key: &str) -> Option<i64>;
}

impl Get for kurashi_mod_api::Settings {
    fn str(&self, key: &str) -> Option<String> {
        self.get(key).and_then(|v| v.as_str().map(str::to_string))
    }
    fn int(&self, key: &str) -> Option<i64> {
        self.get(key).and_then(|v| v.as_i64())
    }
}

impl Provider {
    pub fn from_settings(s: &dyn Get) -> Self {
        let format = Format::from_id(&s.str("provider").unwrap_or_default());
        let id = format.id();
        let text = |k: &str| {
            s.str(&format!("{id}_{k}"))
                .unwrap_or_default()
                .trim()
                .to_string()
        };
        let default_base = match format {
            Format::Ollama => DEFAULT_OLLAMA,
            Format::OpenAi => DEFAULT_OPENAI,
            Format::Anthropic => DEFAULT_ANTHROPIC,
        };
        let base = Some(text("url"))
            .filter(|u| !u.is_empty())
            .unwrap_or_else(|| default_base.into())
            .trim_end_matches('/')
            .to_string();
        let key = match format {
            Format::Ollama => KeySource::new("", ""),
            _ => KeySource::new(&text("key_env"), &text("key_secret")),
        };
        Self {
            format,
            base,
            model: text("model"),
            key,
            max_tokens: s.int("max_tokens").unwrap_or(4096).clamp(1, 1_000_000) as u32,
            system: s
                .str("system_prompt")
                .unwrap_or_default()
                .trim()
                .to_string(),
        }
    }

    /// The server runs on this computer (no message leaves it).
    pub fn local(&self) -> bool {
        let rest = self
            .base
            .split_once("://")
            .map(|(_, r)| r)
            .unwrap_or(&self.base);
        let host = rest.split(['/', '?']).next().unwrap_or("");
        let host = host.rsplit_once('@').map(|(_, h)| h).unwrap_or(host);
        let name = if host.starts_with('[') {
            host.split(']').next().unwrap_or("").trim_start_matches('[')
        } else {
            host.split(':').next().unwrap_or("")
        };
        name == "localhost"
            || name.starts_with("127.")
            || name == "::1"
            || name.ends_with(".localhost")
    }

    fn auth(&self, req: Request, key: Option<&ApiKey>) -> Request {
        match (self.format, key) {
            (Format::Anthropic, Some(k)) => req
                .header(
                    "x-api-key",
                    Header::Secret {
                        prefix: "",
                        key: k.clone(),
                    },
                )
                .header("anthropic-version", Header::Plain(ANTHROPIC_VERSION.into())),
            (Format::Anthropic, None) => {
                req.header("anthropic-version", Header::Plain(ANTHROPIC_VERSION.into()))
            }
            (Format::OpenAi, Some(k)) => req.header(
                "authorization",
                Header::Secret {
                    prefix: "Bearer ",
                    key: k.clone(),
                },
            ),
            _ => req,
        }
    }

    /// The model list's request.
    pub fn models_request(&self, key: Option<&ApiKey>) -> Request {
        let url = match self.format {
            Format::Ollama => format!("{}/api/tags", self.base),
            Format::OpenAi => format!("{}/models", self.base),
            Format::Anthropic => format!("{}/v1/models?limit=100", self.base),
        };
        self.auth(Request::get(url), key)
    }

    /// The streamed chat request: `history` is `(role, text)` with roles `user` and `assistant`.
    pub fn chat_request(
        &self,
        model: &str,
        history: &[(String, String)],
        key: Option<&ApiKey>,
    ) -> Request {
        let messages: Vec<Value> = history
            .iter()
            .map(|(role, content)| json!({"role": role, "content": content}))
            .collect();
        let with_system = |mut m: Vec<Value>| {
            if !self.system.is_empty() {
                m.insert(0, json!({"role": "system", "content": self.system}));
            }
            m
        };
        let (url, body) = match self.format {
            Format::Ollama => (
                format!("{}/api/chat", self.base),
                json!({"model": model, "messages": with_system(messages), "stream": true}),
            ),
            Format::OpenAi => (
                format!("{}/chat/completions", self.base),
                json!({"model": model, "messages": with_system(messages), "stream": true}),
            ),
            Format::Anthropic => {
                let mut b = json!({
                    "model": model,
                    "max_tokens": self.max_tokens,
                    "messages": messages,
                    "stream": true,
                });
                if !self.system.is_empty() {
                    b["system"] = json!(self.system);
                }
                (format!("{}/v1/messages", self.base), b)
            }
        };
        let mut req = Request::get(url);
        req.body = Some(body.to_string());
        self.auth(req, key)
    }
}

/// One installed or offered model.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Model {
    pub id: String,
    /// Size and quantisation (Ollama), the display name (Anthropic).
    pub detail: String,
}

/// The model list in a `models_request` answer; `None` when the body is not one.
pub fn parse_models(format: Format, body: &str) -> Option<Vec<Model>> {
    let v: Value = serde_json::from_str(body).ok()?;
    let s = |v: &Value| v.as_str().unwrap_or("").to_string();
    match format {
        Format::Ollama => Some(
            v.get("models")?
                .as_array()?
                .iter()
                .filter_map(|m| {
                    let id = m
                        .get("name")
                        .or_else(|| m.get("model"))?
                        .as_str()?
                        .to_string();
                    let d = &m["details"];
                    let detail = [s(&d["parameter_size"]), s(&d["quantization_level"])]
                        .into_iter()
                        .filter(|x| !x.is_empty())
                        .collect::<Vec<_>>()
                        .join(" · ");
                    Some(Model { id, detail })
                })
                .collect(),
        ),
        Format::OpenAi | Format::Anthropic => {
            let mut list: Vec<Model> = v
                .get("data")?
                .as_array()?
                .iter()
                .filter_map(|m| {
                    let id = m.get("id")?.as_str()?.to_string();
                    let detail = s(&m["display_name"]);
                    Some(Model {
                        detail: if detail == id { String::new() } else { detail },
                        id,
                    })
                })
                .collect();
            // OpenAI lists in no order; Anthropic newest first, which is kept.
            if format == Format::OpenAi {
                list.sort_by(|a, b| a.id.cmp(&b.id));
            }
            Some(list)
        }
    }
}

/// What one line of a streamed answer says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Text(String),
    Think(String),
    Done,
    /// The provider's own error message.
    Error(String),
}

/// A streamed answer's parser, one per request (it remembers nothing but the format).
pub struct Parser {
    format: Format,
}

impl Parser {
    pub fn new(format: Format) -> Self {
        Self { format }
    }

    pub fn line(&mut self, line: &str) -> Vec<Event> {
        let line = line.trim_end_matches('\r');
        if line.trim().is_empty() {
            return Vec::new();
        }
        match self.format {
            Format::Ollama => ollama_line(line),
            Format::OpenAi | Format::Anthropic => {
                // SSE: `event:` names and `:` comments carry nothing the data does not; other fields neither.
                let Some(data) = line.strip_prefix("data:") else {
                    // A server that answers 200 with a plain JSON error (some proxies) instead of a stream.
                    return serde_json::from_str::<Value>(line)
                        .ok()
                        .and_then(|v| error_message(&v))
                        .map(|m| vec![Event::Error(m)])
                        .unwrap_or_default();
                };
                let data = data.trim();
                if data == "[DONE]" {
                    return vec![Event::Done];
                }
                let Ok(v) = serde_json::from_str::<Value>(data) else {
                    return Vec::new();
                };
                if self.format == Format::Anthropic {
                    anthropic_event(&v)
                } else {
                    openai_chunk(&v)
                }
            }
        }
    }
}

fn nonempty(v: &Value) -> Option<String> {
    v.as_str().filter(|s| !s.is_empty()).map(str::to_string)
}

fn ollama_line(line: &str) -> Vec<Event> {
    let Ok(v) = serde_json::from_str::<Value>(line) else {
        return Vec::new();
    };
    if let Some(e) = error_message(&v) {
        return vec![Event::Error(e)];
    }
    let mut out = Vec::new();
    if let Some(t) = nonempty(&v["message"]["thinking"]) {
        out.push(Event::Think(t));
    }
    if let Some(t) = nonempty(&v["message"]["content"]) {
        out.push(Event::Text(t));
    }
    if v["done"].as_bool() == Some(true) {
        out.push(Event::Done);
    }
    out
}

fn openai_chunk(v: &Value) -> Vec<Event> {
    if let Some(e) = error_message(v) {
        return vec![Event::Error(e)];
    }
    let mut out = Vec::new();
    let delta = &v["choices"][0]["delta"];
    if let Some(t) = nonempty(&delta["reasoning_content"]).or_else(|| nonempty(&delta["reasoning"]))
    {
        out.push(Event::Think(t));
    }
    if let Some(t) = nonempty(&delta["content"]) {
        out.push(Event::Text(t));
    }
    out
}

fn anthropic_event(v: &Value) -> Vec<Event> {
    match v["type"].as_str().unwrap_or("") {
        "content_block_delta" => {
            let d = &v["delta"];
            match d["type"].as_str().unwrap_or("") {
                "text_delta" => nonempty(&d["text"]).map(Event::Text).into_iter().collect(),
                "thinking_delta" => nonempty(&d["thinking"])
                    .map(Event::Think)
                    .into_iter()
                    .collect(),
                _ => Vec::new(),
            }
        }
        "message_stop" => vec![Event::Done],
        "error" => vec![Event::Error(
            error_message(v).unwrap_or_else(|| "error".into()),
        )],
        _ => Vec::new(),
    }
}

/// `{"error": "…"}`, `{"error": {"message": "…"}}`, `{"message": "…"}` with an error type (shellseikatsu
/// `_describeError`).
pub fn error_message(v: &Value) -> Option<String> {
    match v.get("error")? {
        Value::String(s) => Some(s.clone()),
        Value::Object(o) => o
            .get("message")
            .and_then(|m| m.as_str())
            .map(str::to_string)
            .or_else(|| Some(Value::Object(o.clone()).to_string())),
        Value::Null => None,
        other => Some(other.to_string()),
    }
}

/// Why a request failed, for the document: the i18n key and the provider's own words (`detail`, untranslated).
pub fn describe(format: Format, e: &HttpError) -> (&'static str, String) {
    match e {
        HttpError::Offline(_) => (
            if format == Format::Ollama {
                "mod-ai.error.ollama_unreachable"
            } else {
                "mod-ai.error.unreachable"
            },
            String::new(),
        ),
        HttpError::Status { code, body } => {
            let said = serde_json::from_str::<Value>(body)
                .ok()
                .and_then(|v| error_message(&v))
                .unwrap_or_else(|| body.trim().chars().take(300).collect());
            let detail = if said.is_empty() {
                format!("HTTP {code}")
            } else {
                format!("HTTP {code}: {said}")
            };
            let reason = match code {
                401 | 403 => "mod-ai.error.auth",
                404 => "mod-ai.error.not_found",
                429 => "mod-ai.error.rate_limited",
                500..=599 => "mod-ai.error.server",
                _ => "mod-ai.error.provider",
            };
            (reason, detail)
        }
        HttpError::Body(d) => ("mod-ai.error.cut", d.chars().take(200).collect()),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    struct S(BTreeMap<&'static str, Value>);
    impl Get for S {
        fn str(&self, k: &str) -> Option<String> {
            self.0.get(k).and_then(|v| v.as_str().map(str::to_string))
        }
        fn int(&self, k: &str) -> Option<i64> {
            self.0.get(k).and_then(|v| v.as_i64())
        }
    }

    fn settings(pairs: &[(&'static str, Value)]) -> S {
        S(pairs.iter().cloned().collect())
    }

    #[test]
    fn the_settings_choose_the_provider() {
        let p = Provider::from_settings(&settings(&[]));
        assert_eq!(
            (p.format, p.base.as_str(), p.model.as_str()),
            (Format::Ollama, DEFAULT_OLLAMA, "")
        );
        assert!(p.key.is_none() && p.local());

        let p = Provider::from_settings(&settings(&[
            ("provider", json!("openai")),
            ("openai_url", json!("http://localhost:8080/v1/")),
            ("openai_model", json!(" qwen ")),
            ("openai_key_env", json!("FAKE_KEY")),
            ("ollama_model", json!("ignored")),
        ]));
        assert_eq!(
            (p.base.as_str(), p.model.as_str()),
            ("http://localhost:8080/v1", "qwen")
        );
        assert_eq!(p.key, KeySource::new("FAKE_KEY", ""));
        assert!(p.local());

        let p = Provider::from_settings(&settings(&[("provider", json!("anthropic"))]));
        assert_eq!(p.base, DEFAULT_ANTHROPIC);
        assert!(!p.local());
        for (url, local) in [
            ("http://127.0.0.1:11434", true),
            ("http://[::1]:8080", true),
            ("http://user@localhost/x", true),
            ("https://api.openai.com/v1", false),
            ("http://localhost.evil.example", false),
            ("http://192.168.1.4:11434", false),
        ] {
            let p = Provider {
                base: url.into(),
                ..Provider::from_settings(&settings(&[]))
            };
            assert_eq!(p.local(), local, "{url}");
        }
    }

    #[test]
    fn requests_per_format() {
        let key = ApiKey::new("sk-fake-0000".into());
        let hist = vec![("user".to_string(), "Hi".to_string())];
        let mut p = Provider::from_settings(&settings(&[("system_prompt", json!("Be brief."))]));
        let r = p.chat_request("llama3.2", &hist, None);
        assert_eq!(r.url, "http://127.0.0.1:11434/api/chat");
        let b: Value = serde_json::from_str(r.body.as_deref().unwrap()).unwrap();
        assert_eq!(
            b,
            json!({"model": "llama3.2", "stream": true, "messages": [
                {"role": "system", "content": "Be brief."}, {"role": "user", "content": "Hi"}]})
        );
        assert!(r.headers.is_empty());

        p.format = Format::OpenAi;
        p.base = DEFAULT_OPENAI.into();
        let r = p.chat_request("gpt", &hist, Some(&key));
        assert_eq!(r.url, "https://api.openai.com/v1/chat/completions");
        assert!(matches!(
            r.find("authorization"),
            Some(Header::Secret {
                prefix: "Bearer ",
                ..
            })
        ));
        assert!(
            p.chat_request("gpt", &hist, None)
                .find("authorization")
                .is_none()
        );
        assert_eq!(
            p.models_request(None).url,
            "https://api.openai.com/v1/models"
        );

        p.format = Format::Anthropic;
        p.base = DEFAULT_ANTHROPIC.into();
        let r = p.chat_request("claude", &hist, Some(&key));
        assert_eq!(r.url, "https://api.anthropic.com/v1/messages");
        let b: Value = serde_json::from_str(r.body.as_deref().unwrap()).unwrap();
        assert_eq!(b["system"], "Be brief.");
        assert_eq!(b["max_tokens"], 4096);
        assert_eq!(b["messages"], json!([{"role": "user", "content": "Hi"}]));
        assert!(matches!(r.find("x-api-key"), Some(Header::Secret { .. })));
        assert!(
            matches!(r.find("anthropic-version"), Some(Header::Plain(v)) if v == ANTHROPIC_VERSION)
        );
        assert!(!format!("{r:?}").contains("sk-fake-0000"));
    }

    #[test]
    fn ollama_ndjson_stream() {
        let mut p = Parser::new(Format::Ollama);
        let lines = [
            r#"{"model":"qwen3","created_at":"2026-10-21T10:00:00Z","message":{"role":"assistant","content":"","thinking":"Let me see."},"done":false}"#,
            r#"{"model":"qwen3","message":{"role":"assistant","content":"Hello"},"done":false}"#,
            "",
            r#"{"model":"qwen3","message":{"role":"assistant","content":" there"},"done":false}"#,
            r#"{"model":"qwen3","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","eval_count":12}"#,
        ];
        let ev: Vec<Event> = lines.iter().flat_map(|l| p.line(l)).collect();
        assert_eq!(
            ev,
            vec![
                Event::Think("Let me see.".into()),
                Event::Text("Hello".into()),
                Event::Text(" there".into()),
                Event::Done
            ]
        );
        assert_eq!(
            p.line(r#"{"error":"model 'nope' not found"}"#),
            vec![Event::Error("model 'nope' not found".into())]
        );
        assert!(p.line("not json").is_empty());
    }

    #[test]
    fn openai_sse_stream() {
        let mut p = Parser::new(Format::OpenAi);
        let lines = [
            ": keep-alive",
            r#"data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#,
            r#"data: {"choices":[{"index":0,"delta":{"reasoning_content":"thinking…"}}]}"#,
            "",
            r#"data:{"choices":[{"index":0,"delta":{"content":"```sh\n"}}]}"#,
            r#"data: {"choices":[{"index":0,"delta":{"content":"ls"},"finish_reason":null}]}"#,
            r#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"total_tokens":9}}"#,
            "data: [DONE]",
        ];
        let ev: Vec<Event> = lines.iter().flat_map(|l| p.line(l)).collect();
        assert_eq!(
            ev,
            vec![
                Event::Think("thinking…".into()),
                Event::Text("```sh\n".into()),
                Event::Text("ls".into()),
                Event::Done
            ]
        );
        // OpenRouter's `reasoning`, an error chunk, a plain JSON error body.
        assert_eq!(
            p.line(r#"data: {"choices":[{"delta":{"reasoning":"r"}}]}"#),
            vec![Event::Think("r".into())]
        );
        assert_eq!(
            p.line(r#"data: {"error":{"message":"overloaded","type":"server_error"}}"#),
            vec![Event::Error("overloaded".into())]
        );
        assert_eq!(
            p.line(r#"{"error":{"message":"bad model"}}"#),
            vec![Event::Error("bad model".into())]
        );
        assert!(p.line("event: ping").is_empty());
    }

    #[test]
    fn anthropic_sse_stream() {
        let mut p = Parser::new(Format::Anthropic);
        let lines = [
            "event: message_start",
            r#"data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[]}}"#,
            "event: content_block_start",
            r#"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm."}}"#,
            r#"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"x"}}"#,
            r#"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi!"}}"#,
            "event: ping",
            r#"data: {"type":"ping"}"#,
            r#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
            r#"data: {"type":"message_stop"}"#,
        ];
        let ev: Vec<Event> = lines.iter().flat_map(|l| p.line(l)).collect();
        assert_eq!(
            ev,
            vec![
                Event::Think("Hmm.".into()),
                Event::Text("Hi!".into()),
                Event::Done
            ]
        );
        assert_eq!(
            p.line(r#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
            vec![Event::Error("Overloaded".into())]
        );
    }

    #[test]
    fn model_lists() {
        let tags = r#"{"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","size":2019393189,
            "details":{"family":"llama","parameter_size":"3.2B","quantization_level":"Q4_K_M"}},
            {"name":"qwen3:8b","details":{}}]}"#;
        assert_eq!(
            parse_models(Format::Ollama, tags).unwrap(),
            vec![
                Model {
                    id: "llama3.2:latest".into(),
                    detail: "3.2B · Q4_K_M".into()
                },
                Model {
                    id: "qwen3:8b".into(),
                    detail: String::new()
                },
            ]
        );
        assert_eq!(
            parse_models(Format::Ollama, r#"{"models":[]}"#),
            Some(vec![])
        );
        let openai = r#"{"object":"list","data":[{"id":"gpt-b","object":"model"},{"id":"gpt-a"}]}"#;
        let ids: Vec<String> = parse_models(Format::OpenAi, openai)
            .unwrap()
            .into_iter()
            .map(|m| m.id)
            .collect();
        assert_eq!(ids, vec!["gpt-a", "gpt-b"]);
        let anthropic = r#"{"data":[{"id":"claude-x","display_name":"Claude X","type":"model"}],"has_more":false}"#;
        assert_eq!(
            parse_models(Format::Anthropic, anthropic).unwrap(),
            vec![Model {
                id: "claude-x".into(),
                detail: "Claude X".into()
            }]
        );
        assert_eq!(parse_models(Format::Ollama, "<html>"), None);
    }

    #[test]
    fn errors_are_described() {
        assert_eq!(
            describe(
                Format::Ollama,
                &HttpError::Offline("Connection refused".into())
            )
            .0,
            "mod-ai.error.ollama_unreachable"
        );
        assert_eq!(
            describe(Format::OpenAi, &HttpError::Offline("dns".into())).0,
            "mod-ai.error.unreachable"
        );
        assert_eq!(
            describe(Format::OpenAi, &HttpError::Status {
                code: 401,
                body: r#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.into()
            }),
            ("mod-ai.error.auth", "HTTP 401: Incorrect API key provided".into())
        );
        assert_eq!(
            describe(
                Format::Ollama,
                &HttpError::Status {
                    code: 404,
                    body: r#"{"error":"model \"nope\" not found, try pulling it first"}"#.into()
                }
            ),
            (
                "mod-ai.error.not_found",
                "HTTP 404: model \"nope\" not found, try pulling it first".into()
            )
        );
        assert_eq!(
            describe(
                Format::OpenAi,
                &HttpError::Status {
                    code: 502,
                    body: "".into()
                }
            ),
            ("mod-ai.error.server", "HTTP 502".into())
        );
    }
}
