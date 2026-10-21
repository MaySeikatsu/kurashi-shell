//! The chat's state, its actions and the `mod.ai` document (docs/ux/ai.md "Fit").
//!
//! The state lives in a watch the actions change; the service (running while the document has a subscriber, rule 5)
//! publishes it. A reply is a task of its own, started by `ai.ask` / `ai.regenerate`: it keeps running while the panel
//! is closed, is saved when it ends, and stops on `ai.stop` or when the mod is disabled. The answer's text is copied
//! into the state at most every [`FLUSH`] — the document grows in coarse chunks, never per token. Nothing is requested
//! unless the user asks: no probe on open, no model-list polling (the list is fetched by `ai.models`).

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_mod_api::{ActionError, Publish, Settings, SettingsWriter};
use serde_json::{Map, Value, json};
use tokio::sync::{Notify, watch};
use tokio::task::JoinHandle;
use tokio::time::Instant;

use crate::blocks;
use crate::clip::Clipboard;
use crate::http::Http;
use crate::key::{self, ApiKey, Env, Secrets};
use crate::provider::{self, Event, Format, Model, Parser, Provider};
use crate::store::{self, Conversation, Message, Role, Store, Summary};

/// Unix milliseconds. Tests pass a fixed one.
pub type Clock = Arc<dyn Fn() -> i64 + Send + Sync>;

/// How often a streaming answer reaches the document: at most 10 patches a second.
pub const FLUSH: Duration = Duration::from_millis(100);

const ARGS_INVALID: &str = "error.args.invalid";
const BUSY: &str = "mod-ai.error.busy";
/// The longest question taken (characters).
const MAX_QUESTION: usize = 32_000;

/// What the mod talks to; the daemon's are real, the tests' are in memory.
pub struct Deps {
    pub http: Arc<dyn Http>,
    pub secrets: Arc<dyn Secrets>,
    pub env: Env,
    pub clipboard: Arc<dyn Clipboard>,
    pub clock: Clock,
    /// `$XDG_DATA_HOME/kurashi/ai`.
    pub data_dir: PathBuf,
}

/// The answer being written.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Reply {
    pub conversation: String,
    pub provider: String,
    pub model: String,
    pub text: String,
}

/// The model list of one provider (its id and address), as last fetched.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Models {
    pub of: String,
    /// `idle`, `loading`, `ready`, `error`.
    pub state: &'static str,
    pub list: Vec<Model>,
    pub reason: &'static str,
    pub detail: String,
}

/// The last outcome with one provider (its id and address): it answered, or why it did not.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Note {
    pub of: String,
    pub ok: bool,
    pub reason: &'static str,
    pub detail: String,
}

#[derive(Debug, Clone, Default)]
pub struct State {
    pub listed: bool,
    pub conversations: Vec<Summary>,
    pub current: Option<Conversation>,
    pub reply: Option<Reply>,
    pub models: Models,
    pub note: Option<Note>,
    /// Ollama's first installed model, used while the settings name none: (provider, model).
    pub auto_model: Option<(String, String)>,
}

/// A provider's identity for the notes: a change of address is another server.
fn of(p: &Provider) -> String {
    format!("{} {}", p.format.id(), p.base)
}

struct Task {
    stop: Arc<Notify>,
    handle: JoinHandle<()>,
}

/// What the service, the actions and the reply task share, per enable.
pub struct Engine {
    pub deps: Deps,
    pub store: Store,
    pub state: watch::Sender<State>,
    pub settings: Settings,
}

/// Per enable: the engine and the reply task. Dropped with the mod's registrations (disable), which stops the task.
pub struct Shared {
    pub engine: Arc<Engine>,
    writer: SettingsWriter,
    task: Mutex<Option<Task>>,
    models_task: Mutex<Option<JoinHandle<()>>>,
}

impl Drop for Shared {
    fn drop(&mut self) {
        if let Some(t) = self.task.lock().unwrap().take() {
            t.handle.abort();
        }
        if let Some(t) = self.models_task.lock().unwrap().take() {
            t.abort();
        }
    }
}

fn history_keep(s: &Settings) -> usize {
    s.get("history")
        .and_then(|v| v.as_i64())
        .unwrap_or(50)
        .clamp(0, 10_000) as usize
}

impl Engine {
    fn now_s(&self) -> i64 {
        (self.deps.clock)() / 1000
    }

    fn ensure_listed(&self) {
        if self.state.borrow().listed {
            return;
        }
        let list = self.store.list();
        self.state.send_modify(|s| {
            if !s.listed {
                s.listed = true;
                s.conversations = list;
            }
        });
    }

    /// Writes `c` and puts it first in the list (inside the state's lock, so saves keep their order).
    fn save_into(&self, s: &mut State, c: &Conversation) {
        let keep = history_keep(&self.settings);
        let _ = self.store.save(c, keep);
        s.conversations.retain(|x| x.id != c.id);
        if keep > 0 {
            s.conversations.insert(0, c.summary());
            s.conversations.truncate(keep);
        }
    }
}

impl Shared {
    pub fn new(deps: Deps, settings: Settings, writer: SettingsWriter) -> Self {
        let store = Store::new(deps.data_dir.clone());
        Self {
            engine: Arc::new(Engine {
                deps,
                store,
                state: watch::channel(State::default()).0,
                settings,
            }),
            writer,
            task: Mutex::new(None),
            models_task: Mutex::new(None),
        }
    }

    fn busy(&self) -> bool {
        self.engine.state.borrow().reply.is_some()
    }

    fn start_reply(&self) {
        let stop = Arc::new(Notify::new());
        let handle = tokio::spawn(generate(self.engine.clone(), stop.clone()));
        if let Some(old) = self.task.lock().unwrap().replace(Task { stop, handle }) {
            old.handle.abort();
        }
    }

    /// `ai.ask {text}` → `{conversation}`: the question joins the current conversation (a new one when none) and the
    /// answer starts.
    pub fn ask(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let text = args["text"]
            .as_str()
            .map(str::trim)
            .filter(|t| !t.is_empty() && t.chars().count() <= MAX_QUESTION)
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?
            .to_string();
        let e = &self.engine;
        e.ensure_listed();
        let now_ms = (e.deps.clock)();
        let mut answer = Err(ActionError::Unavailable(BUSY.into()));
        e.state.send_modify(|s| {
            if s.reply.is_some() {
                return;
            }
            let mut c = s
                .current
                .take()
                .unwrap_or_else(|| Conversation::new(e.store.new_id(now_ms), now_ms / 1000));
            if c.title.is_empty() {
                c.title = store::title_of(&text);
            }
            c.messages.push(Message::user(text.clone(), now_ms / 1000));
            c.updated = now_ms / 1000;
            e.save_into(s, &c);
            s.reply = Some(Reply {
                conversation: c.id.clone(),
                ..Reply::default()
            });
            answer = Ok(Some(json!({"conversation": c.id})));
            s.current = Some(c);
        });
        if answer.is_ok() {
            self.start_reply();
        }
        answer
    }

    /// `ai.regenerate {}`: the last answer again (after an error, a stop, or to get another one).
    pub fn regenerate(&self) -> Result<Option<Value>, ActionError> {
        let e = &self.engine;
        let mut answer = Err(ActionError::Invalid("mod-ai.error.nothing".into()));
        e.state.send_modify(|s| {
            if s.reply.is_some() {
                answer = Err(ActionError::Unavailable(BUSY.into()));
                return;
            }
            let Some(c) = s.current.as_mut() else { return };
            if c.messages.last().is_some_and(|m| m.role == Role::Assistant) {
                c.messages.pop();
            }
            if !c.messages.last().is_some_and(|m| m.role == Role::User) {
                return;
            }
            let c = c.clone();
            e.save_into(s, &c);
            s.reply = Some(Reply {
                conversation: c.id.clone(),
                ..Reply::default()
            });
            answer = Ok(None);
        });
        if answer.is_ok() {
            self.start_reply();
        }
        answer
    }

    /// `ai.stop {}`: the answer ends where it is (kept, marked stopped).
    pub fn stop(&self) -> Result<Option<Value>, ActionError> {
        if let Some(t) = self.task.lock().unwrap().as_ref() {
            t.stop.notify_one();
        }
        Ok(None)
    }

    /// `ai.new {}`: an empty conversation (saved with its first question).
    pub fn new_chat(&self) -> Result<Option<Value>, ActionError> {
        if self.busy() {
            return Err(ActionError::Unavailable(BUSY.into()));
        }
        self.engine.state.send_modify(|s| s.current = None);
        Ok(None)
    }

    /// `ai.open {id}`: a saved conversation.
    pub fn open(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let id = args["id"]
            .as_str()
            .filter(|i| store::valid_id(i))
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
        if self.busy() {
            return Err(ActionError::Unavailable(BUSY.into()));
        }
        let e = &self.engine;
        e.ensure_listed();
        let c = e
            .store
            .load(id)
            .ok_or_else(|| ActionError::Invalid("mod-ai.error.unknown_conversation".into()))?;
        e.state.send_modify(|s| s.current = Some(c));
        Ok(None)
    }

    /// `ai.delete {id}`: removes a saved conversation (the current one too: the panel shows a new chat).
    pub fn delete(&self, args: &Value) -> Result<Option<Value>, ActionError> {
        let id = args["id"]
            .as_str()
            .filter(|i| store::valid_id(i))
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?
            .to_string();
        let e = &self.engine;
        e.ensure_listed();
        if e.state
            .borrow()
            .reply
            .as_ref()
            .is_some_and(|r| r.conversation == id)
        {
            return Err(ActionError::Unavailable(BUSY.into()));
        }
        let removed = e.store.delete(&id);
        let mut known = false;
        e.state.send_modify(|s| {
            known = s.conversations.iter().any(|c| c.id == id)
                || s.current.as_ref().is_some_and(|c| c.id == id);
            s.conversations.retain(|c| c.id != id);
            if s.current.as_ref().is_some_and(|c| c.id == id) {
                s.current = None;
            }
        });
        if removed || known {
            Ok(None)
        } else {
            Err(ActionError::Invalid(
                "mod-ai.error.unknown_conversation".into(),
            ))
        }
    }

    /// `ai.models {}`: fetches the model list of the provider in effect (and so finds out whether it answers).
    pub fn models(&self) -> Result<Option<Value>, ActionError> {
        let e = self.engine.clone();
        let mut slot = self.models_task.lock().unwrap();
        if slot.as_ref().is_some_and(|t| !t.is_finished()) {
            return Ok(None);
        }
        *slot = Some(tokio::spawn(async move {
            let p = Provider::from_settings(&e.settings);
            let _ = fetch_models(&e, &p).await;
        }));
        Ok(None)
    }

    /// `ai.model {model}`: the provider's model setting (`mods.ai.<provider>_model`, a settings write: undoable).
    pub async fn set_model(&self, args: Value) -> Result<Option<Value>, ActionError> {
        let model = args["model"]
            .as_str()
            .map(str::trim)
            .filter(|m| m.len() <= 200)
            .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?
            .to_string();
        let p = Provider::from_settings(&self.engine.settings);
        self.writer
            .set(&format!("{}_model", p.format.id()), json!(model))
            .await
            .map_err(|e| ActionError::Invalid(e.i18n_key().into()))?;
        Ok(None)
    }

    /// `ai.copy {message, block?}`: a message of the current conversation (an answer without its think blocks), or one
    /// of its blocks, onto the clipboard.
    pub async fn copy(&self, args: Value) -> Result<Option<Value>, ActionError> {
        let index = |k: &str| -> Result<Option<usize>, ActionError> {
            match &args[k] {
                Value::Null => Ok(None),
                v => v
                    .as_u64()
                    .map(|n| Some(n as usize))
                    .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into())),
            }
        };
        let msg = index("message")?.ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
        let block = index("block")?;
        let text = {
            let s = self.engine.state.borrow();
            let m = s
                .current
                .as_ref()
                .and_then(|c| c.messages.get(msg))
                .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?;
            match (block, m.role) {
                (Some(b), _) => blocks::split(&m.text)
                    .into_iter()
                    .nth(b)
                    .map(|b| b.text)
                    .ok_or_else(|| ActionError::Invalid(ARGS_INVALID.into()))?,
                (None, Role::User) => m.text.clone(),
                (None, Role::Assistant) => blocks::without_think(&m.text),
            }
        };
        self.engine
            .deps
            .clipboard
            .copy(text)
            .await
            .map_err(|k| ActionError::Unavailable(k.into()))?;
        Ok(None)
    }
}

/// The key of `p`, or the reason (and the source's name) why there is none.
async fn key_of(e: &Engine, p: &Provider) -> Result<Option<ApiKey>, (&'static str, String)> {
    key::lookup(&p.key, e.deps.secrets.as_ref(), &e.deps.env)
        .await
        .map_err(|err| (err.reason(), p.key.describe()))
}

fn note(e: &Engine, p: &Provider, ok: bool, reason: &'static str, detail: String) {
    let n = Note {
        of: of(p),
        ok,
        reason,
        detail,
    };
    e.state.send_if_modified(|s| {
        if s.note.as_ref() == Some(&n) {
            return false;
        }
        s.note = Some(n);
        true
    });
}

/// The model list of `p` into the state; the list (or why there is none).
async fn fetch_models(e: &Engine, p: &Provider) -> Result<Vec<Model>, (&'static str, String)> {
    let of = of(p);
    e.state.send_modify(|s| {
        s.models = Models {
            of: of.clone(),
            state: "loading",
            list: std::mem::take(&mut s.models.list),
            ..Models::default()
        }
    });
    let result = async {
        let key = key_of(e, p).await?;
        let body = e
            .deps
            .http
            .fetch(p.models_request(key.as_ref()))
            .await
            .map_err(|err| {
                let (r, d) = provider::describe(p.format, &err);
                (r, key.as_ref().map(|k| k.redact(&d)).unwrap_or(d))
            })?;
        provider::parse_models(p.format, &body).ok_or(("mod-ai.error.answer", String::new()))
    }
    .await;
    match &result {
        Ok(list) => {
            note(e, p, true, "", String::new());
            e.state.send_modify(|s| {
                s.models = Models {
                    of: of.clone(),
                    state: "ready",
                    list: list.clone(),
                    ..Models::default()
                };
                if p.format == Format::Ollama {
                    s.auto_model = list.first().map(|m| (of.clone(), m.id.clone()));
                }
            });
        }
        Err((reason, detail)) => {
            note(e, p, false, reason, detail.clone());
            e.state.send_modify(|s| {
                s.models = Models {
                    of: of.clone(),
                    state: "error",
                    list: Vec::new(),
                    reason,
                    detail: detail.clone(),
                }
            });
        }
    }
    result
}

/// What is sent: the conversation's questions and good answers (without think blocks), ending with a question.
fn history(c: &Conversation) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for m in &c.messages {
        let text = match m.role {
            Role::User => m.text.trim().to_string(),
            Role::Assistant if m.error.is_empty() => {
                blocks::without_think(&m.text).trim().to_string()
            }
            Role::Assistant => String::new(),
        };
        if text.is_empty() {
            continue;
        }
        // Two questions in a row (the answer between them failed): the later one stands for both.
        if let Some(last) = out.last_mut()
            && last.0 == m.role.id()
        {
            last.1 = format!("{}\n\n{}", last.1, text);
            continue;
        }
        out.push((m.role.id().to_string(), text));
    }
    out
}

/// The answer's text as it grows: the reasoning between `<think>` marks (ii's `OpenAiApiStrategy` does the same), so
/// one splitter draws both a model's own `<think>` and a provider's reasoning field.
#[derive(Default)]
struct Grow {
    text: String,
    thinking: bool,
}

impl Grow {
    fn push(&mut self, ev: &Event) {
        match ev {
            Event::Think(t) => {
                if !self.thinking {
                    if !self.text.is_empty() {
                        self.text.push_str("\n\n");
                    }
                    self.text.push_str(blocks::THINK_OPEN);
                    self.text.push('\n');
                    self.thinking = true;
                }
                self.text.push_str(t);
            }
            Event::Text(t) => {
                self.close();
                self.text.push_str(t);
            }
            Event::Done | Event::Error(_) => {}
        }
    }

    fn close(&mut self) {
        if self.thinking {
            self.text.push('\n');
            self.text.push_str(blocks::THINK_CLOSE);
            self.text.push_str("\n\n");
            self.thinking = false;
        }
    }
}

/// How a reply ended.
struct End {
    text: String,
    model: String,
    provider: String,
    error: &'static str,
    detail: String,
    stopped: bool,
}

/// The reply task: resolve the provider, its key and model, stream the answer into the state, save it.
async fn generate(e: Arc<Engine>, stop: Arc<Notify>) {
    let p = Provider::from_settings(&e.settings);
    let end = answer(&e, &p, &stop).await;
    finish(&e, &p, end);
}

/// `f`, unless the reply is stopped first (`None`). A stop between two waits is kept by the `Notify`'s permit.
async fn or_stop<T>(stop: &Notify, f: impl std::future::Future<Output = T>) -> Option<T> {
    tokio::select! {
        biased;
        () = stop.notified() => None,
        v = f => Some(v),
    }
}

async fn answer(e: &Engine, p: &Provider, stop: &Notify) -> End {
    let mut end = End {
        text: String::new(),
        model: String::new(),
        provider: p.format.id().into(),
        error: "",
        detail: String::new(),
        stopped: false,
    };
    let fail = |mut end: End, (reason, detail): (&'static str, String)| {
        end.error = reason;
        end.detail = detail;
        end
    };
    let stopped = |mut end: End| {
        end.stopped = true;
        end
    };
    let key = match or_stop(stop, key_of(e, p)).await {
        None => return stopped(end),
        Some(Ok(k)) => k,
        Some(Err(r)) => return fail(end, r),
    };
    let model = if !p.model.is_empty() {
        p.model.clone()
    } else if p.format == Format::Ollama {
        let known = e
            .state
            .borrow()
            .auto_model
            .as_ref()
            .filter(|(o, _)| *o == of(p))
            .map(|(_, m)| m.clone());
        match known {
            Some(m) => m,
            None => match or_stop(stop, fetch_models(e, p)).await {
                None => return stopped(end),
                Some(Ok(list)) => match list.into_iter().next() {
                    Some(m) => m.id,
                    None => return fail(end, ("mod-ai.error.no_models", String::new())),
                },
                Some(Err(r)) => return fail(end, r),
            },
        }
    } else {
        return fail(end, ("mod-ai.error.no_model", String::new()));
    };
    end.model = model.clone();
    let hist = {
        let mut s = e
            .state
            .borrow()
            .current
            .clone()
            .map(|c| history(&c))
            .unwrap_or_default();
        if !s.last().is_some_and(|(r, _)| r == "user") {
            s.clear();
        }
        s
    };
    if hist.is_empty() {
        return fail(end, ("mod-ai.error.nothing", String::new()));
    }
    e.state.send_modify(|s| {
        if let Some(r) = s.reply.as_mut() {
            r.provider = p.format.id().into();
            r.model = model.clone();
        }
    });
    let redact = |d: String| key.as_ref().map(|k| k.redact(&d)).unwrap_or(d);
    let started = or_stop(
        stop,
        e.deps
            .http
            .stream(p.chat_request(&model, &hist, key.as_ref())),
    )
    .await;
    let mut lines = match started {
        None => return stopped(end),
        Some(Ok(l)) => l,
        Some(Err(err)) => {
            let (r, d) = provider::describe(p.format, &err);
            return fail(end, (r, redact(d)));
        }
    };
    let mut parser = Parser::new(p.format);
    let mut grow = Grow::default();
    let mut shown = 0usize;
    let mut last_flush = Instant::now() - FLUSH;
    let flush = |grow: &Grow, shown: &mut usize| {
        if grow.text.len() == *shown {
            return;
        }
        *shown = grow.text.len();
        e.state.send_modify(|s| {
            if let Some(r) = s.reply.as_mut() {
                r.text.clone_from(&grow.text);
            }
        });
    };
    let mut done = false;
    loop {
        let dirty = grow.text.len() != shown;
        tokio::select! {
            biased;
            () = stop.notified() => {
                end.stopped = true;
                break;
            }
            line = lines.recv() => match line {
                None => break,
                Some(Err(err)) => {
                    let (r, d) = provider::describe(p.format, &err);
                    end.error = r;
                    end.detail = redact(d);
                    break;
                }
                Some(Ok(line)) => {
                    let mut over = false;
                    for ev in parser.line(&line) {
                        match &ev {
                            Event::Done => { done = true; over = true; }
                            Event::Error(m) => {
                                end.error = "mod-ai.error.provider";
                                end.detail = redact(m.clone());
                                over = true;
                            }
                            _ => grow.push(&ev),
                        }
                    }
                    if over {
                        break;
                    }
                    if Instant::now() >= last_flush + FLUSH {
                        flush(&grow, &mut shown);
                        last_flush = Instant::now();
                    }
                }
            },
            () = tokio::time::sleep_until(last_flush + FLUSH), if dirty => {
                flush(&grow, &mut shown);
                last_flush = Instant::now();
            }
        }
    }
    drop(lines);
    grow.close();
    end.text = grow.text.trim().to_string();
    if end.error.is_empty() && !end.stopped && end.text.is_empty() {
        end.error = if done {
            "mod-ai.error.empty"
        } else {
            "mod-ai.error.cut"
        };
    }
    end
}

/// The reply becomes the conversation's answer, and the conversation is saved.
fn finish(e: &Engine, p: &Provider, end: End) {
    let now = e.now_s();
    let reached = end.error.is_empty()
        || !matches!(
            end.error,
            "mod-ai.error.ollama_unreachable"
                | "mod-ai.error.unreachable"
                | "mod-ai.error.no_key"
                | "mod-ai.error.no_secret_tool"
                | "mod-ai.error.secret_tool"
                | "mod-ai.error.secret_attributes"
                | "mod-ai.error.auth"
        );
    if !end.stopped || !end.text.is_empty() {
        note(
            e,
            p,
            reached,
            if reached { "" } else { end.error },
            if reached {
                String::new()
            } else {
                end.detail.clone()
            },
        );
    }
    e.state.send_modify(|s| {
        let Some(reply) = s.reply.take() else { return };
        let Some(mut c) = s.current.take().filter(|c| c.id == reply.conversation) else {
            return;
        };
        c.messages.push(Message {
            role: Role::Assistant,
            text: end.text,
            at: now,
            provider: end.provider,
            model: end.model,
            error: end.error.into(),
            detail: end.detail,
            stopped: end.stopped,
        });
        c.updated = now;
        e.save_into(s, &c);
        s.current = Some(c);
    });
}

// ------------------------------------------------------------------ the document

fn blocks_json(text: &str) -> Vec<Value> {
    blocks::split(text).iter().map(|b| b.json()).collect()
}

fn message_json(m: &Message) -> Value {
    let mut o = Map::new();
    o.insert("role".into(), json!(m.role.id()));
    match m.role {
        Role::User => {
            o.insert("text".into(), json!(m.text));
        }
        Role::Assistant => {
            o.insert("blocks".into(), Value::Array(blocks_json(&m.text)));
            for (k, v) in [
                ("model", &m.model),
                ("error", &m.error),
                ("detail", &m.detail),
            ] {
                if !v.is_empty() {
                    o.insert(k.into(), json!(v));
                }
            }
            if m.stopped {
                o.insert("stopped".into(), json!(true));
            }
        }
    }
    Value::Object(o)
}

/// `mod.ai` (docs/ux/ai.md; contract row 222): `{available, busy, saving, provider {id, model?, auto?, local, url?,
/// key?, state: unknown|ready|error, reason?, detail?}, models {state: idle|loading|ready|error, list: [{id, detail?}],
/// reason?, detail?}, conversations: [{id, title, updated}], current {id?, title?, messages: [message]}, reply?
/// {model?, blocks, waiting}}`. A message is `{role: user, text}` or `{role: assistant, blocks: [{kind:
/// text|code|think, text, lang?, open?}], model?, error?, detail?, stopped?}`. Absent keys, no null.
pub fn doc(s: &State, settings: &Settings) -> Value {
    let p = Provider::from_settings(settings);
    let of = of(&p);
    let mut prov = Map::new();
    prov.insert("id".into(), json!(p.format.id()));
    let auto = s
        .auto_model
        .as_ref()
        .filter(|(o, _)| *o == of)
        .map(|(_, m)| m.clone());
    if !p.model.is_empty() {
        prov.insert("model".into(), json!(p.model));
    } else if p.format == Format::Ollama
        && let Some(m) = auto
    {
        prov.insert("model".into(), json!(m));
        prov.insert("auto".into(), json!(true));
    }
    prov.insert("local".into(), json!(p.local()));
    if p.format == Format::Ollama {
        prov.insert("url".into(), json!(p.base));
    }
    if !p.key.is_none() {
        prov.insert("key".into(), json!(p.key.describe()));
    }
    match s.note.as_ref().filter(|n| n.of == of) {
        None => {
            prov.insert("state".into(), json!("unknown"));
        }
        Some(n) if n.ok => {
            prov.insert("state".into(), json!("ready"));
        }
        Some(n) => {
            prov.insert("state".into(), json!("error"));
            prov.insert("reason".into(), json!(n.reason));
            if !n.detail.is_empty() {
                prov.insert("detail".into(), json!(n.detail));
            }
        }
    }

    let mut models = Map::new();
    if s.models.of == of && !s.models.state.is_empty() {
        models.insert("state".into(), json!(s.models.state));
        models.insert(
            "list".into(),
            Value::Array(
                s.models
                    .list
                    .iter()
                    .map(|m| {
                        let mut v = json!({"id": m.id});
                        if !m.detail.is_empty() {
                            v["detail"] = json!(m.detail);
                        }
                        v
                    })
                    .collect(),
            ),
        );
        if !s.models.reason.is_empty() {
            models.insert("reason".into(), json!(s.models.reason));
        }
        if !s.models.detail.is_empty() {
            models.insert("detail".into(), json!(s.models.detail));
        }
    } else {
        models.insert("state".into(), json!("idle"));
        models.insert("list".into(), json!([]));
    }

    let mut current = Map::new();
    if let Some(c) = &s.current {
        current.insert("id".into(), json!(c.id));
        current.insert("title".into(), json!(c.title));
        current.insert(
            "messages".into(),
            Value::Array(c.messages.iter().map(message_json).collect()),
        );
    } else {
        current.insert("messages".into(), json!([]));
    }

    let mut d = json!({
        "available": true,
        "busy": s.reply.is_some(),
        "saving": history_keep(settings) > 0,
        "provider": Value::Object(prov),
        "models": Value::Object(models),
        "conversations": s.conversations.iter().map(|c| json!({"id": c.id, "title": c.title, "updated": c.updated})).collect::<Vec<_>>(),
        "current": Value::Object(current),
    });
    if let Some(r) = &s.reply {
        let mut v = json!({"blocks": blocks_json(&r.text), "waiting": r.text.trim().is_empty()});
        if !r.model.is_empty() {
            v["model"] = json!(r.model);
        }
        d["reply"] = v;
    }
    d
}

/// The document before the service ran: nothing known yet.
pub fn initial() -> Value {
    json!({"available": true, "busy": false, "loading": true})
}

/// `mod.ai`'s service: publishes the state while subscribed (the reply task runs on its own).
pub async fn run(shared: Arc<Shared>, publish: Publish, mut settings: Settings) {
    let e = shared.engine.clone();
    drop(shared);
    e.ensure_listed();
    let mut rx = e.state.subscribe();
    let mut last = Value::Null;
    loop {
        let d = doc(&rx.borrow_and_update(), &settings);
        if d != last {
            publish(d.clone());
            last = d;
        }
        tokio::select! {
            r = rx.changed() => if r.is_err() { return },
            alive = settings.changed() => if !alive { return },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conv(msgs: &[(Role, &str, &str)]) -> Conversation {
        let mut c = Conversation::new("1".into(), 0);
        for (role, text, error) in msgs {
            let mut m = Message::user((*text).into(), 0);
            m.role = *role;
            m.error = (*error).into();
            c.messages.push(m);
        }
        c
    }

    #[test]
    fn history_sends_questions_and_good_answers() {
        let c = conv(&[
            (Role::User, "a", ""),
            (Role::Assistant, "<think>x</think>A", ""),
            (Role::User, "b", ""),
            (Role::Assistant, "", "mod-ai.error.ollama_unreachable"),
            (Role::User, "c", ""),
        ]);
        assert_eq!(
            history(&c),
            vec![
                ("user".into(), "a".into()),
                ("assistant".into(), "A".into()),
                ("user".into(), "b\n\nc".into())
            ]
        );
    }

    #[test]
    fn reasoning_is_marked_as_think() {
        let mut g = Grow::default();
        for ev in [
            Event::Think("hm".into()),
            Event::Think(" ok".into()),
            Event::Text("Answer".into()),
        ] {
            g.push(&ev);
        }
        assert_eq!(g.text, "<think>\nhm ok\n</think>\n\nAnswer");
        let b = blocks::split(&g.text);
        assert_eq!(
            (b[0].kind.clone(), b[0].text.as_str()),
            (blocks::Kind::Think, "hm ok")
        );
        assert_eq!(b[1].text, "Answer");
    }
}
