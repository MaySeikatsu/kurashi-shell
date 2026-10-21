//! The AI mod as the daemon runs it: enabled through a `ModCtx`, its service started with a publish sink and a settings
//! feed, driven by its actions. Everything it talks to is in memory: the provider (each test scripts what it answers),
//! secret-tool, the environment (fake variables only), the clipboard and the clock. Nothing leaves the process.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_ai::{
    AiMod, ApiKey, Clipboard, Env, Http, HttpError, KeyError, Lines, Request, Secrets,
};
use kurashi_mod_api::{
    ActionError, ActionFn, BoxFuture, FaceUpdate, Hooks, ModCtx, NativeMod, Registration,
    ServiceFn, Settings, SettingsError, Values,
};
use serde_json::{Value, json};
use tokio::sync::{mpsc, watch};

// ------------------------------------------------------------------ fakes

enum Script {
    Body(Result<String, HttpError>),
    /// Lines, `gap` apart; then the stream ends, or (`hold`) stays open until the request is dropped.
    Stream {
        lines: Vec<String>,
        gap: Duration,
        hold: bool,
    },
    Refuse(HttpError),
}

type ScriptFn = Box<dyn Fn(&Request) -> Script + Send>;

struct Fake {
    script: Mutex<ScriptFn>,
    log: Mutex<Vec<Request>>,
}

impl Fake {
    fn new(f: impl Fn(&Request) -> Script + Send + 'static) -> Arc<Self> {
        Arc::new(Self {
            script: Mutex::new(Box::new(f)),
            log: Mutex::new(Vec::new()),
        })
    }
    fn set(&self, f: impl Fn(&Request) -> Script + Send + 'static) {
        *self.script.lock().unwrap() = Box::new(f);
    }
    fn urls(&self) -> Vec<String> {
        self.log
            .lock()
            .unwrap()
            .iter()
            .map(|r| r.url.clone())
            .collect()
    }
    fn last(&self) -> Request {
        self.log.lock().unwrap().last().cloned().expect("a request")
    }
}

impl Http for Fake {
    fn fetch(&self, req: Request) -> BoxFuture<Result<String, HttpError>> {
        self.log.lock().unwrap().push(req.clone());
        let r = match (self.script.lock().unwrap())(&req) {
            Script::Body(b) => b,
            Script::Refuse(e) => Err(e),
            Script::Stream { lines, .. } => Ok(lines.join("\n")),
        };
        Box::pin(async move { r })
    }
    fn stream(&self, req: Request) -> BoxFuture<Result<Lines, HttpError>> {
        self.log.lock().unwrap().push(req.clone());
        let script = (self.script.lock().unwrap())(&req);
        Box::pin(async move {
            match script {
                Script::Refuse(e) => Err(e),
                Script::Body(Err(e)) => Err(e),
                Script::Body(Ok(b)) => {
                    let (tx, rx) = mpsc::channel(8);
                    tokio::spawn(async move {
                        let _ = tx.send(Ok(b)).await;
                    });
                    Ok(rx)
                }
                Script::Stream { lines, gap, hold } => {
                    let (tx, rx) = mpsc::channel(4);
                    tokio::spawn(async move {
                        for l in lines {
                            if !gap.is_zero() {
                                tokio::time::sleep(gap).await;
                            }
                            if tx.send(Ok(l)).await.is_err() {
                                return;
                            }
                        }
                        if hold {
                            tx.closed().await;
                        }
                    });
                    Ok(rx)
                }
            }
        })
    }
}

struct NoSecrets;
impl Secrets for NoSecrets {
    fn lookup(&self, _attrs: Vec<String>) -> BoxFuture<Result<Option<ApiKey>, KeyError>> {
        Box::pin(async { Err(KeyError::NoSecretTool) })
    }
}

#[derive(Default)]
struct Clip(Mutex<Vec<String>>);
impl Clipboard for Clip {
    fn copy(&self, text: String) -> BoxFuture<Result<(), &'static str>> {
        self.0.lock().unwrap().push(text);
        Box::pin(async { Ok(()) })
    }
}

/// The daemon's end of the settings writes: the value goes into the feed.
struct Writes {
    feed: Arc<watch::Sender<Values>>,
    log: Mutex<Vec<(String, Value)>>,
}
impl Hooks for Writes {
    fn face(&self, _: &str, _: FaceUpdate) {}
    fn choices_changed(&self, _: &str) {}
    fn set_setting(&self, key: &str, value: Value) -> Result<(), SettingsError> {
        self.log.lock().unwrap().push((key.into(), value.clone()));
        self.feed.send_modify(|v| {
            v.insert(key.into(), value);
        });
        Ok(())
    }
}

// ------------------------------------------------------------------ harness

const FAKE_KEY: &str = "sk-fake-test-key-0123456789";

struct Running {
    actions: BTreeMap<String, ActionFn>,
    docs: watch::Receiver<Vec<Value>>,
    settings: Arc<watch::Sender<Values>>,
    hooks: Arc<Writes>,
    clip: Arc<Clip>,
    dir: tempfile::TempDir,
    _task: tokio::task::JoinHandle<()>,
}

impl Running {
    async fn act(&self, id: &str, args: Value) -> Result<Option<Value>, ActionError> {
        (self.actions[id])(args).await
    }
    async fn until(&mut self, what: &str, ok: impl Fn(&Value) -> bool) -> Value {
        let r = tokio::time::timeout(Duration::from_secs(30), async {
            loop {
                if let Some(v) = self.docs.borrow_and_update().last().filter(|v| ok(v)) {
                    return v.clone();
                }
                self.docs.changed().await.expect("sink");
            }
        })
        .await;
        r.unwrap_or_else(|_| {
            panic!(
                "timed out waiting for {what}; got {:#}",
                self.docs.borrow().last().unwrap_or(&Value::Null)
            )
        })
    }
    fn published(&self) -> Vec<Value> {
        self.docs.borrow().clone()
    }
    fn set(&self, key: &str, v: Value) {
        self.settings.send_modify(|s| {
            s.insert(key.into(), v);
        });
    }
}

fn defaults() -> Values {
    [
        ("provider", json!("ollama")),
        ("ollama_url", json!("http://127.0.0.1:11434")),
        ("ollama_model", json!("")),
        ("openai_url", json!("https://api.openai.com/v1")),
        ("openai_model", json!("")),
        ("openai_key_env", json!("OPENAI_API_KEY")),
        ("openai_key_secret", json!("")),
        ("anthropic_url", json!("https://api.anthropic.com")),
        ("anthropic_model", json!("")),
        ("anthropic_key_env", json!("ANTHROPIC_API_KEY")),
        ("anthropic_key_secret", json!("")),
        ("max_tokens", json!(4096)),
        ("system_prompt", json!("")),
        ("history", json!(50)),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v))
    .collect()
}

/// The only variables the mod sees: fake ones.
fn fake_env() -> Env {
    Arc::new(|name| match name {
        "FAKE_OPENAI_KEY" => Some(FAKE_KEY.to_string()),
        _ => None,
    })
}

fn enable(fake: Arc<Fake>, values: &[(&str, Value)]) -> Running {
    let dir = tempfile::tempdir().unwrap();
    let clip = Arc::new(Clip::default());
    let m = AiMod::with(
        fake,
        Arc::new(NoSecrets),
        fake_env(),
        clip.clone(),
        Arc::new(|| 1_790_000_000_000),
        dir.path().to_path_buf(),
    );
    let mut v = defaults();
    for (k, val) in values {
        v.insert((*k).into(), val.clone());
    }
    let settings = Arc::new(watch::channel(v).0);
    let hooks = Arc::new(Writes {
        feed: settings.clone(),
        log: Mutex::new(Vec::new()),
    });
    let provides: Vec<String> = ["service:ai", "action:ai.*", "panel:ai"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let mut ctx = ModCtx::new(
        &provides,
        Settings::new(settings.subscribe()),
        hooks.clone(),
    );
    m.enable(&mut ctx).expect("enable");
    let mut service: Option<ServiceFn> = None;
    let mut actions = BTreeMap::new();
    for r in ctx.finish().expect("finish") {
        match r {
            Registration::Service { id, initial, run } => {
                assert_eq!(id, "ai");
                assert_eq!(initial["available"], true);
                service = Some(run);
            }
            Registration::Action { id, handler, .. } => {
                actions.insert(id, handler);
            }
            _ => panic!("unexpected registration"),
        }
    }
    let sink = Arc::new(watch::channel(Vec::<Value>::new()).0);
    let docs = sink.subscribe();
    let s = sink.clone();
    let publish: kurashi_mod_api::Publish = Arc::new(move |v| s.send_modify(|d| d.push(v)));
    let task = tokio::spawn((service.unwrap())(
        publish,
        Settings::new(settings.subscribe()),
    ));
    Running {
        actions,
        docs,
        settings,
        hooks,
        clip,
        dir,
        _task: task,
    }
}

fn tags() -> Script {
    Script::Body(Ok(json!({"models": [
        {"name": "llama3.2:latest", "details": {"parameter_size": "3.2B", "quantization_level": "Q4_K_M"}},
        {"name": "qwen3:8b", "details": {}}]})
    .to_string()))
}

fn ndjson(tokens: &[&str]) -> Vec<String> {
    let mut v: Vec<String> = tokens
        .iter()
        .map(|t| json!({"model": "llama3.2:latest", "message": {"role": "assistant", "content": t}, "done": false}).to_string())
        .collect();
    v.push(json!({"model": "llama3.2:latest", "message": {"role": "assistant", "content": ""}, "done": true, "done_reason": "stop"}).to_string());
    v
}

fn ollama(
    tokens: &'static [&'static str],
    gap: Duration,
) -> impl Fn(&Request) -> Script + Send + 'static {
    move |r: &Request| {
        if r.url.ends_with("/api/tags") {
            tags()
        } else {
            Script::Stream {
                lines: ndjson(tokens),
                gap,
                hold: false,
            }
        }
    }
}

fn last_answer(d: &Value) -> Value {
    d["current"]["messages"]
        .as_array()
        .and_then(|m| m.last())
        .cloned()
        .unwrap_or(Value::Null)
}

// ------------------------------------------------------------------ tests

#[tokio::test]
async fn opening_the_panel_asks_nothing() {
    let fake = Fake::new(|_| panic!("no request may be sent"));
    let mut r = enable(fake.clone(), &[]);
    let d = r
        .until("the first document", |d| d.get("provider").is_some())
        .await;
    assert_eq!(d["busy"], false);
    assert_eq!(d["provider"]["id"], "ollama");
    assert_eq!(d["provider"]["state"], "unknown");
    assert_eq!(d["provider"]["local"], true);
    assert_eq!(d["provider"]["url"], "http://127.0.0.1:11434");
    assert!(d["provider"].get("model").is_none());
    assert_eq!(d["models"], json!({"state": "idle", "list": []}));
    assert_eq!(d["current"], json!({"messages": []}));
    assert_eq!(d["conversations"], json!([]));
    assert_eq!(d["saving"], true);
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(fake.urls().is_empty());
}

#[tokio::test]
async fn an_ollama_answer_streams_into_blocks_and_is_saved() {
    const TOKENS: &[&str] = &[
        "Here",
        " is",
        " one:\n\n",
        "```sh\n",
        "ls -la",
        "\n```",
        "\n\nDone.",
    ];
    let fake = Fake::new(ollama(TOKENS, Duration::from_millis(5)));
    let mut r = enable(fake.clone(), &[]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    let ok = r
        .act("ai.ask", json!({"text": "  How do I list files?  "}))
        .await
        .unwrap()
        .unwrap();
    let id = ok["conversation"].as_str().unwrap().to_string();
    let d = r
        .until("the question and the reply", |d| d["busy"] == true)
        .await;
    assert_eq!(
        d["current"]["messages"][0],
        json!({"role": "user", "text": "How do I list files?"})
    );
    assert_eq!(d["current"]["title"], "How do I list files?");
    let d = r
        .until("the answer", |d| {
            d["busy"] == false
                && d["current"]["messages"]
                    .as_array()
                    .is_some_and(|m| m.len() == 2)
        })
        .await;
    // Ollama's first installed model, since the settings name none; the tags were asked once.
    assert_eq!(
        fake.urls(),
        vec![
            "http://127.0.0.1:11434/api/tags",
            "http://127.0.0.1:11434/api/chat"
        ]
    );
    let body: Value = serde_json::from_str(fake.last().body.as_deref().unwrap()).unwrap();
    assert_eq!(body["model"], "llama3.2:latest");
    assert_eq!(body["stream"], true);
    assert_eq!(
        body["messages"],
        json!([{"role": "user", "content": "How do I list files?"}])
    );
    assert_eq!(d["provider"]["model"], "llama3.2:latest");
    assert_eq!(d["provider"]["auto"], true);
    assert_eq!(d["provider"]["state"], "ready");
    assert_eq!(
        d["models"]["list"][0],
        json!({"id": "llama3.2:latest", "detail": "3.2B · Q4_K_M"})
    );
    assert_eq!(
        last_answer(&d),
        json!({"role": "assistant", "model": "llama3.2:latest", "blocks": [
            {"kind": "text", "text": "Here is one:"},
            {"kind": "code", "lang": "sh", "text": "ls -la"},
            {"kind": "text", "text": "Done."}]})
    );
    assert!(d.get("reply").is_none());
    assert_eq!(
        d["conversations"],
        json!([{"id": id, "title": "How do I list files?", "updated": 1_790_000_000}])
    );
    // While it streamed, the reply grew (the code block open at some point).
    assert!(r.published().iter().any(|d| d["reply"]["waiting"] == true));
    // The file on disk.
    let file = r
        .dir
        .path()
        .join("conversations")
        .join(format!("{id}.json"));
    let saved: Value = serde_json::from_str(&std::fs::read_to_string(file).unwrap()).unwrap();
    assert_eq!(
        saved["messages"][1]["text"],
        "Here is one:\n\n```sh\nls -la\n```\n\nDone."
    );
    assert_eq!(saved["messages"][1]["provider"], "ollama");

    // A second question in the same conversation sends the history.
    r.act("ai.ask", json!({"text": "And hidden ones?"}))
        .await
        .unwrap();
    r.until("the second answer", |d| {
        d["busy"] == false
            && d["current"]["messages"]
                .as_array()
                .is_some_and(|m| m.len() == 4)
    })
    .await;
    let body: Value = serde_json::from_str(fake.last().body.as_deref().unwrap()).unwrap();
    assert_eq!(body["messages"].as_array().unwrap().len(), 3);
    assert_eq!(body["messages"][1]["role"], "assistant");
    // The model was known: no second tags request.
    assert_eq!(
        fake.urls()
            .iter()
            .filter(|u| u.ends_with("/api/tags"))
            .count(),
        1
    );
}

#[tokio::test(start_paused = true)]
async fn the_answer_reaches_the_document_in_coarse_chunks() {
    // 200 tokens 10 ms apart: two seconds of streaming.
    static MANY: std::sync::OnceLock<Vec<&'static str>> = std::sync::OnceLock::new();
    let tokens: &'static [&'static str] = MANY.get_or_init(|| vec!["tok "; 200]);
    let fake = Fake::new(move |r: &Request| {
        if r.url.ends_with("/api/tags") {
            tags()
        } else {
            Script::Stream {
                lines: ndjson(tokens),
                gap: Duration::from_millis(10),
                hold: false,
            }
        }
    });
    let mut r = enable(fake, &[("ollama_model", json!("llama3.2"))]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    r.act("ai.ask", json!({"text": "count"})).await.unwrap();
    let d = r
        .until("the answer", |d| {
            d["busy"] == false
                && d["current"]["messages"]
                    .as_array()
                    .is_some_and(|m| m.len() == 2)
        })
        .await;
    assert_eq!(
        last_answer(&d)["blocks"][0]["text"]
            .as_str()
            .unwrap()
            .matches("tok")
            .count(),
        200
    );
    let growing = r
        .published()
        .iter()
        .filter(|d| d.get("reply").is_some())
        .count();
    // ≤ 10 patches a second over ~2 s, plus the first (waiting) and a final one.
    assert!(
        growing <= 23,
        "{growing} reply documents for 2 s of streaming"
    );
    assert!(
        growing >= 10,
        "the reply should grow while it streams ({growing})"
    );
}

#[tokio::test]
async fn ollama_not_running_is_said_plainly() {
    let fake = Fake::new(|_| Script::Refuse(HttpError::Offline("Connection refused".into())));
    let mut r = enable(fake, &[("ollama_model", json!("llama3.2"))]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    r.act("ai.ask", json!({"text": "hi"})).await.unwrap();
    let d = r
        .until("the error", |d| {
            d["busy"] == false
                && d["current"]["messages"]
                    .as_array()
                    .is_some_and(|m| m.len() == 2)
        })
        .await;
    assert_eq!(
        last_answer(&d),
        json!({"role": "assistant", "blocks": [], "model": "llama3.2", "error": "mod-ai.error.ollama_unreachable"})
    );
    assert_eq!(d["provider"]["state"], "error");
    assert_eq!(d["provider"]["reason"], "mod-ai.error.ollama_unreachable");
    // The model list says the same.
    r.act("ai.models", json!({})).await.unwrap();
    let d = r
        .until("the models error", |d| d["models"]["state"] == "error")
        .await;
    assert_eq!(d["models"]["reason"], "mod-ai.error.ollama_unreachable");
}

#[tokio::test]
async fn no_installed_model_and_no_chosen_model() {
    let fake = Fake::new(|_| Script::Body(Ok(r#"{"models":[]}"#.into())));
    let mut r = enable(fake, &[]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    r.act("ai.ask", json!({"text": "hi"})).await.unwrap();
    let d = r
        .until("the error", |d| {
            d["busy"] == false && last_answer(d)["role"] == "assistant"
        })
        .await;
    assert_eq!(last_answer(&d)["error"], "mod-ai.error.no_models");

    r.set("provider", json!("anthropic"));
    r.set("anthropic_key_env", json!(""));
    r.act("ai.regenerate", json!({})).await.unwrap();
    let d = r
        .until("no model", |d| {
            d["busy"] == false && last_answer(d)["error"] == "mod-ai.error.no_model"
        })
        .await;
    assert_eq!(d["provider"]["id"], "anthropic");
    assert_eq!(d["provider"]["local"], false);
    assert_eq!(d["current"]["messages"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn stop_keeps_what_was_written() {
    let fake = Fake::new(|_| Script::Stream {
        lines: vec![json!({"message": {"content": "Partial answer"}, "done": false}).to_string()],
        gap: Duration::ZERO,
        hold: true,
    });
    let mut r = enable(fake, &[("ollama_model", json!("llama3.2"))]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    r.act("ai.ask", json!({"text": "write a lot"}))
        .await
        .unwrap();
    r.until("the partial reply", |d| {
        d["reply"]["blocks"][0]["text"] == "Partial answer"
    })
    .await;
    assert_eq!(
        r.act("ai.ask", json!({"text": "again"})).await,
        Err(ActionError::Unavailable("mod-ai.error.busy".into()))
    );
    assert!(r.act("ai.new", json!({})).await.is_err());
    r.act("ai.stop", json!({})).await.unwrap();
    let d = r
        .until("stopped", |d| {
            d["busy"] == false && last_answer(d)["role"] == "assistant"
        })
        .await;
    assert_eq!(
        last_answer(&d),
        json!({"role": "assistant", "model": "llama3.2", "stopped": true,
               "blocks": [{"kind": "text", "text": "Partial answer"}]})
    );
    // Regenerate replaces it.
    r.act("ai.regenerate", json!({})).await.unwrap();
    r.until("busy again", |d| d["busy"] == true).await;
    r.act("ai.stop", json!({})).await.unwrap();
    let d = r.until("stopped again", |d| d["busy"] == false).await;
    assert_eq!(d["current"]["messages"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn openai_with_a_key_from_the_environment_never_shows_the_key() {
    let fake = Fake::new(|r: &Request| {
        if r.url.ends_with("/models") {
            return Script::Body(Ok(
                json!({"data": [{"id": "fake-b"}, {"id": "fake-a"}]}).to_string()
            ));
        }
        Script::Stream {
            lines: vec![
                r#"data: {"choices":[{"delta":{"reasoning_content":"Thinking about it."}}]}"#
                    .into(),
                r#"data: {"choices":[{"delta":{"content":"Hi!"}}]}"#.into(),
                "data: [DONE]".into(),
            ],
            gap: Duration::ZERO,
            hold: false,
        }
    });
    let mut r = enable(
        fake.clone(),
        &[
            ("provider", json!("openai")),
            ("openai_url", json!("http://127.0.0.1:9/v1")),
            ("openai_key_env", json!("FAKE_OPENAI_KEY")),
            ("openai_key_secret", json!("service fake-openai")),
        ],
    );
    let d = r.until("ready", |d| d.get("provider").is_some()).await;
    assert_eq!(
        d["provider"]["key"],
        "secret-tool (service fake-openai), $FAKE_OPENAI_KEY"
    );
    assert!(d["provider"].get("url").is_none());
    r.act("ai.models", json!({})).await.unwrap();
    let d = r.until("models", |d| d["models"]["state"] == "ready").await;
    assert_eq!(
        d["models"]["list"],
        json!([{"id": "fake-a"}, {"id": "fake-b"}])
    );
    // The picker writes the provider's model setting.
    r.act("ai.model", json!({"model": "fake-a"})).await.unwrap();
    assert_eq!(
        r.hooks.log.lock().unwrap().last().unwrap(),
        &("openai_model".to_string(), json!("fake-a"))
    );
    r.until("the model in effect", |d| {
        d["provider"]["model"] == "fake-a"
    })
    .await;

    r.act("ai.ask", json!({"text": "hello"})).await.unwrap();
    let d = r
        .until("the answer", |d| {
            d["busy"] == false && last_answer(d)["role"] == "assistant"
        })
        .await;
    assert_eq!(
        last_answer(&d)["blocks"],
        json!([{"kind": "think", "text": "Thinking about it."}, {"kind": "text", "text": "Hi!"}])
    );
    let req = fake.last();
    assert_eq!(req.url, "http://127.0.0.1:9/v1/chat/completions");
    match req.find("authorization") {
        Some(kurashi_mod_ai::Header::Secret { prefix, key }) => {
            assert_eq!(*prefix, "Bearer ");
            assert_eq!(key.expose(), FAKE_KEY);
        }
        other => panic!("no bearer header: {other:?}"),
    }
    assert!(!format!("{req:?}").contains(FAKE_KEY));
    // A provider error that quotes the key: masked.
    fake.set(|_| {
        Script::Refuse(HttpError::Status {
            code: 401,
            body: json!({"error": {"message": format!("Incorrect API key provided: {FAKE_KEY}.")}})
                .to_string(),
        })
    });
    r.act("ai.ask", json!({"text": "again"})).await.unwrap();
    let d = r
        .until("the auth error", |d| {
            d["busy"] == false && last_answer(d)["error"] == "mod-ai.error.auth"
        })
        .await;
    assert_eq!(
        last_answer(&d)["detail"],
        "HTTP 401: Incorrect API key provided: ***."
    );
    // No document ever carried the key, nor the saved files.
    for d in r.published() {
        assert!(!d.to_string().contains(FAKE_KEY));
    }
    for f in std::fs::read_dir(r.dir.path().join("conversations")).unwrap() {
        assert!(
            !std::fs::read_to_string(f.unwrap().path())
                .unwrap()
                .contains(FAKE_KEY)
        );
    }
}

#[tokio::test]
async fn a_missing_key_names_where_it_was_looked_for() {
    let fake = Fake::new(|_| panic!("nothing may be sent without a key"));
    let mut r = enable(
        fake,
        &[
            ("provider", json!("openai")),
            ("openai_model", json!("m")),
            ("openai_key_env", json!("UNSET_FAKE_KEY")),
        ],
    );
    r.until("ready", |d| d.get("provider").is_some()).await;
    r.act("ai.ask", json!({"text": "hi"})).await.unwrap();
    let d = r
        .until("no key", |d| {
            d["busy"] == false && last_answer(d)["role"] == "assistant"
        })
        .await;
    assert_eq!(last_answer(&d)["error"], "mod-ai.error.no_key");
    assert_eq!(last_answer(&d)["detail"], "$UNSET_FAKE_KEY");
    assert_eq!(d["provider"]["state"], "error");
}

#[tokio::test]
async fn conversations_open_copy_and_delete() {
    const TOKENS: &[&str] = &["<think>plan</think>Use:\n```py\nprint(1)\n```"];
    let fake = Fake::new(ollama(TOKENS, Duration::ZERO));
    let mut r = enable(fake, &[("ollama_model", json!("llama3.2"))]);
    r.until("ready", |d| d.get("provider").is_some()).await;
    let first = r
        .act("ai.ask", json!({"text": "one"}))
        .await
        .unwrap()
        .unwrap()["conversation"]
        .as_str()
        .unwrap()
        .to_string();
    r.until("answer 1", |d| {
        d["busy"] == false && last_answer(d)["role"] == "assistant"
    })
    .await;

    r.act("ai.copy", json!({"message": 1})).await.unwrap();
    r.act("ai.copy", json!({"message": 1, "block": 2}))
        .await
        .unwrap();
    r.act("ai.copy", json!({"message": 0})).await.unwrap();
    assert_eq!(
        *r.clip.0.lock().unwrap(),
        vec!["Use:\n\n```py\nprint(1)\n```", "print(1)", "one"]
    );
    assert!(r.act("ai.copy", json!({"message": 9})).await.is_err());

    r.act("ai.new", json!({})).await.unwrap();
    let d = r
        .until("a new chat", |d| d["current"] == json!({"messages": []}))
        .await;
    assert_eq!(d["conversations"].as_array().unwrap().len(), 1);
    r.act("ai.ask", json!({"text": "two"})).await.unwrap();
    let d = r
        .until("answer 2", |d| {
            d["busy"] == false && d["conversations"].as_array().is_some_and(|c| c.len() == 2)
        })
        .await;
    assert_eq!(d["conversations"][0]["title"], "two");

    r.act("ai.open", json!({"id": first})).await.unwrap();
    let d = r
        .until("the first again", |d| d["current"]["id"] == first.as_str())
        .await;
    assert_eq!(d["current"]["messages"][0]["text"], "one");
    assert!(
        r.act("ai.open", json!({"id": "../../etc/passwd"}))
            .await
            .is_err()
    );

    r.act("ai.delete", json!({"id": first})).await.unwrap();
    let d = r
        .until("deleted", |d| {
            d["conversations"].as_array().is_some_and(|c| c.len() == 1)
        })
        .await;
    assert_eq!(d["current"], json!({"messages": []}));
    assert!(
        !r.dir
            .path()
            .join("conversations")
            .join(format!("{first}.json"))
            .exists()
    );

    // history = 0: nothing is saved.
    r.set("history", json!(0));
    r.act("ai.ask", json!({"text": "secret"})).await.unwrap();
    let d = r
        .until("answer 3", |d| {
            d["busy"] == false && d["saving"] == false && last_answer(d)["role"] == "assistant"
        })
        .await;
    assert_eq!(d["conversations"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn bad_arguments_are_refused() {
    let fake = Fake::new(|_| panic!("no request"));
    let r = enable(fake, &[]);
    for args in [json!({}), json!({"text": "   "}), json!({"text": 3})] {
        assert_eq!(
            r.act("ai.ask", args).await,
            Err(ActionError::Invalid("error.args.invalid".into()))
        );
    }
    assert_eq!(
        r.act("ai.regenerate", json!({})).await,
        Err(ActionError::Invalid("mod-ai.error.nothing".into()))
    );
    assert!(r.act("ai.model", json!({"model": 1})).await.is_err());
    assert!(r.act("ai.delete", json!({"id": "nope"})).await.is_err());
}
