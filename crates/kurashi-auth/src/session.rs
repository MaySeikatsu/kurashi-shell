use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Instant;

use kurashi_services::DocSink;
use serde_json::{Value, json};

use crate::backend::{AuthError, Authenticator, Conversation, PromptKind};
use crate::secret::SecretString;

/// Monotonic milliseconds; injected so rate limiting is testable without sleeping.
pub trait Clock: Send + Sync + 'static {
    fn now_ms(&self) -> u64;
}

pub struct SystemClock(Instant);

impl SystemClock {
    pub fn new() -> Self {
        Self(Instant::now())
    }
}

impl Default for SystemClock {
    fn default() -> Self {
        Self::new()
    }
}

impl Clock for SystemClock {
    fn now_ms(&self) -> u64 {
        u64::try_from(self.0.elapsed().as_millis()).unwrap_or(u64::MAX)
    }
}

#[derive(Default)]
pub struct ManualClock(AtomicU64);

impl ManualClock {
    pub fn advance_ms(&self, ms: u64) {
        self.0.fetch_add(ms, Ordering::SeqCst);
    }
}

impl Clock for ManualClock {
    fn now_ms(&self) -> u64 {
        self.0.load(Ordering::SeqCst)
    }
}

#[derive(Debug, Clone)]
pub struct LockConfig {
    /// Failures before any delay applies.
    pub free_attempts: u32,
    /// Delay after the first over-limit failure; doubles per further failure.
    pub base_delay_ms: u64,
    pub max_delay_ms: u64,
}

impl Default for LockConfig {
    fn default() -> Self {
        Self {
            free_attempts: 3,
            base_delay_ms: 5_000,
            max_delay_ms: 300_000,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubmitOutcome {
    Unlocked,
    /// Wrong secret or backend failure; the doc carries the `message_key`.
    Rejected,
    /// The value answered a pending follow-up prompt of the running conversation.
    Answered,
    /// `cancel()` overtook this attempt; its result was discarded.
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SubmitError {
    #[error("session is not locked")]
    NotLocked,
    #[error("authentication in progress and no prompt is waiting")]
    Busy,
    #[error("rate limited, retry in {retry_in_ms} ms")]
    RateLimited { retry_in_ms: u64 },
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Unlocked,
    Locked,
    Authenticating,
}

struct PromptView {
    kind: PromptKind,
    text: String,
}

struct State {
    phase: Phase,
    failures: u32,
    locked_until_ms: Option<u64>,
    message_key: Option<&'static str>,
    /// Raw PAM info/error text (module-provided, not translatable).
    pam_message: Option<(PromptKind, String)>,
    prompt: Option<PromptView>,
    /// Attempt id: stale results (after cancel) are discarded.
    generation: u64,
    answer_tx: Option<Sender<SecretString>>,
}

struct Inner {
    user: String,
    auth: Arc<dyn Authenticator>,
    sink: Arc<dyn DocSink>,
    clock: Arc<dyn Clock>,
    cfg: LockConfig,
    state: Mutex<State>,
}

#[derive(Clone)]
pub struct LockSession(Arc<Inner>);

impl LockSession {
    pub fn new(
        user: impl Into<String>,
        auth: Arc<dyn Authenticator>,
        sink: Arc<dyn DocSink>,
        clock: Arc<dyn Clock>,
        cfg: LockConfig,
    ) -> Self {
        let inner = Arc::new(Inner {
            user: user.into(),
            auth,
            sink,
            clock,
            cfg,
            state: Mutex::new(State {
                phase: Phase::Unlocked,
                failures: 0,
                locked_until_ms: None,
                message_key: None,
                pam_message: None,
                prompt: None,
                generation: 0,
                answer_tx: None,
            }),
        });
        {
            let st = inner.lock();
            inner.emit(&st);
        }
        Self(inner)
    }

    /// Current `runtime.lock` document (retry countdown computed against the clock now).
    pub fn doc(&self) -> Value {
        self.0.doc(&self.0.lock())
    }

    /// `session.lock` action. No-op when already locked.
    pub fn lock(&self) {
        let mut st = self.0.lock();
        if st.phase != Phase::Unlocked {
            return;
        }
        st.phase = Phase::Locked;
        st.failures = 0;
        st.locked_until_ms = None;
        st.message_key = None;
        self.0.emit(&st);
    }

    /// Abort a running conversation (back to `Locked`, no failure counted).
    pub fn cancel(&self) {
        let mut st = self.0.lock();
        if st.phase != Phase::Authenticating {
            return;
        }
        st.generation += 1;
        st.answer_tx = None; // wakes a conversation blocked on a follow-up prompt
        st.prompt = None;
        st.pam_message = None;
        st.phase = Phase::Locked;
        self.0.emit(&st);
    }

    /// Routes `lock.submit` (value = the secret) and `lock.cancel`; `None` = not ours.
    pub async fn handle_intent(
        &self,
        name: &str,
        value: &Value,
    ) -> Option<Result<SubmitOutcome, SubmitError>> {
        match name {
            "lock.submit" => {
                let secret = SecretString::new(value.as_str().unwrap_or_default());
                Some(self.submit(secret).await)
            }
            "lock.cancel" => {
                self.cancel();
                Some(Ok(SubmitOutcome::Cancelled))
            }
            _ => None,
        }
    }

    /// Routes actions; returns whether the id was ours.
    pub fn handle_action(&self, id: &str) -> bool {
        if id == "session.lock" {
            self.lock();
            true
        } else {
            false
        }
    }

    /// Never blocks the runtime: PAM runs on the blocking pool. While a conversation waits
    /// for a follow-up answer, a second `submit` delivers it and returns `Answered`.
    pub async fn submit(&self, secret: SecretString) -> Result<SubmitOutcome, SubmitError> {
        let (generation, rx) = {
            let mut st = self.0.lock();
            match st.phase {
                Phase::Unlocked => return Err(SubmitError::NotLocked),
                Phase::Authenticating => return self.0.answer(&mut st, secret),
                Phase::Locked => {}
            }
            if let Some(retry) = self.0.retry_in_ms(&st) {
                st.message_key = Some("lock.error.rate_limited");
                self.0.emit(&st);
                return Err(SubmitError::RateLimited { retry_in_ms: retry });
            }
            let (tx, rx) = mpsc::channel();
            st.generation += 1;
            st.phase = Phase::Authenticating;
            st.answer_tx = Some(tx);
            st.message_key = None;
            st.pam_message = None;
            st.prompt = None;
            self.0.emit(&st);
            (st.generation, rx)
        };

        let inner = self.0.clone();
        let result = tokio::task::spawn_blocking(move || {
            let mut conv = Conv {
                inner: inner.clone(),
                generation,
                initial: Some(secret),
                answers: rx,
            };
            inner.auth.authenticate_with(&inner.user, &mut conv)
        })
        .await
        .unwrap_or_else(|_| Err(AuthError::Backend("authenticator panicked".into())));

        let mut st = self.0.lock();
        if st.generation != generation {
            return Ok(SubmitOutcome::Cancelled);
        }
        st.answer_tx = None;
        st.prompt = None;
        st.pam_message = None;
        let outcome = match result {
            Ok(()) => {
                st.phase = Phase::Unlocked;
                st.failures = 0;
                st.locked_until_ms = None;
                st.message_key = None;
                SubmitOutcome::Unlocked
            }
            Err(e) => {
                st.phase = Phase::Locked;
                st.failures += 1;
                st.locked_until_ms = self
                    .0
                    .delay_for(st.failures)
                    .map(|d| self.0.clock.now_ms() + d);
                st.message_key = Some(match e {
                    AuthError::Backend(ref why) => {
                        tracing::warn!(%why, "lock: auth backend failure");
                        "lock.error.unavailable"
                    }
                    _ => "lock.error.wrong_password",
                });
                SubmitOutcome::Rejected
            }
        };
        self.0.emit(&st);
        Ok(outcome)
    }
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn delay_for(&self, failures: u32) -> Option<u64> {
        let over = failures.checked_sub(self.cfg.free_attempts + 1)?;
        let d = self.cfg.base_delay_ms.saturating_mul(1u64 << over.min(20));
        Some(d.min(self.cfg.max_delay_ms))
    }

    fn retry_in_ms(&self, st: &State) -> Option<u64> {
        let left = st.locked_until_ms?.saturating_sub(self.clock.now_ms());
        (left > 0).then_some(left)
    }

    fn answer(&self, st: &mut State, secret: SecretString) -> Result<SubmitOutcome, SubmitError> {
        if st.prompt.is_none() {
            return Err(SubmitError::Busy);
        }
        let Some(tx) = &st.answer_tx else {
            return Err(SubmitError::Busy);
        };
        if tx.send(secret).is_err() {
            return Err(SubmitError::Busy);
        }
        st.prompt = None;
        self.emit(st);
        Ok(SubmitOutcome::Answered)
    }

    fn doc(&self, st: &State) -> Value {
        let mut d = json!({
            "locked": st.phase != Phase::Unlocked,
            "busy": st.phase == Phase::Authenticating && st.prompt.is_none(),
            "failures": st.failures,
        });
        let o = d.as_object_mut().expect("object literal");
        if let Some(ms) = self.retry_in_ms(st) {
            o.insert("retry_in_ms".into(), json!(ms));
        }
        if let Some(k) = st.message_key {
            o.insert("message_key".into(), json!(k));
        }
        if let Some((kind, text)) = &st.pam_message {
            let k = if *kind == PromptKind::Error {
                "error"
            } else {
                "info"
            };
            o.insert("pam_message".into(), json!({"kind": k, "text": text}));
        }
        if let Some(p) = &st.prompt {
            o.insert("prompt".into(), json!(p.text));
            o.insert("prompt_echo".into(), json!(p.kind == PromptKind::EchoOn));
            // Stock PAM wording maps to a translatable key; anything else shows PAM's text.
            if p.text.to_lowercase().contains("password") {
                o.insert("prompt_key".into(), json!("lock.prompt.password"));
            }
        }
        d
    }

    fn emit(&self, st: &State) {
        self.sink.set(self.doc(st));
    }
}

/// Blocking side of the conversation. The first echo-off prompt is answered by the secret that
/// came with `submit`; later prompts are surfaced in the doc and wait for another `submit`.
struct Conv {
    inner: Arc<Inner>,
    generation: u64,
    initial: Option<SecretString>,
    answers: Receiver<SecretString>,
}

impl Conversation for Conv {
    fn prompt(&mut self, kind: PromptKind, text: &str) -> Option<SecretString> {
        if kind == PromptKind::EchoOff {
            if let Some(s) = self.initial.take() {
                return Some(s);
            }
        }
        {
            let mut st = self.inner.lock();
            if st.generation != self.generation {
                return None;
            }
            match kind {
                PromptKind::Info | PromptKind::Error => {
                    st.pam_message = Some((kind, text.trim().to_owned()));
                    self.inner.emit(&st);
                    return None;
                }
                _ => {
                    st.prompt = Some(PromptView {
                        kind,
                        text: text.trim().to_owned(),
                    });
                    self.inner.emit(&st);
                }
            }
        }
        self.answers.recv().ok()
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::time::Duration;

    use kurashi_services::DocSink;
    use serde_json::Value;

    use super::*;
    use crate::FakeAuthenticator;

    struct Quiet;
    impl DocSink for Quiet {
        fn set(&self, _doc: Value) {}
    }

    /// A password, then a second factor that nobody answers: the conversation parks there.
    fn parked_session() -> LockSession {
        let auth = FakeAuthenticator::new("tester", "pw").with_otp("123456", false);
        let session = LockSession::new(
            "tester",
            Arc::new(auth),
            Arc::new(Quiet),
            Arc::new(SystemClock::new()),
            LockConfig::default(),
        );
        session.lock();
        session
    }

    /// Capped wait until the parked conversation shows its second prompt.
    async fn wait_for_prompt(session: &LockSession) {
        for _ in 0..200 {
            if session.doc()["prompt"].is_string() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("the conversation never reached its second prompt");
    }

    /// `cancel` frees a conversation parked on its second prompt: the blocking task ends and the
    /// submit resolves, so nothing waits on a prompt that will never be answered.
    #[tokio::test]
    async fn cancel_releases_a_conversation_parked_on_a_second_prompt() {
        let session = parked_session();
        let submit = tokio::spawn({
            let s = session.clone();
            async move { s.submit(SecretString::new("pw")).await }
        });
        wait_for_prompt(&session).await;
        session.cancel();
        let outcome = tokio::time::timeout(Duration::from_secs(5), submit)
            .await
            .expect("cancel must release the parked conversation")
            .expect("submit task");
        assert_eq!(outcome, Ok(SubmitOutcome::Cancelled));
    }

    /// Without a cancel, a parked conversation must not hold runtime shutdown past the grace
    /// period (kurashid's `SHUTDOWN_GRACE` mechanism). Runs on its own thread so a regression fails
    /// the test instead of hanging it.
    #[test]
    fn runtime_shutdown_is_bounded_while_a_conversation_is_parked() {
        let (done_tx, done_rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .unwrap();
            let session = parked_session();
            let s = session.clone();
            let _submit = rt.spawn(async move { s.submit(SecretString::new("pw")).await });
            rt.block_on(wait_for_prompt(&session));
            rt.shutdown_timeout(Duration::from_millis(200));
            let _ = done_tx.send(());
        });
        done_rx
            .recv_timeout(Duration::from_secs(20))
            .expect("runtime shutdown waited on a parked conversation");
    }
}
