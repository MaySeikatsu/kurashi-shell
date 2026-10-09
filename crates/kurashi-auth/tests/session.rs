use std::sync::{Arc, Mutex};
use std::time::Duration;

use kurashi_auth::{
    FakeAuthenticator, LockConfig, LockSession, ManualClock, SecretString, SubmitError,
    SubmitOutcome,
};
use kurashi_services::DocSink;
use serde_json::Value;

#[derive(Default)]
struct Sink(Mutex<Vec<Value>>);

impl DocSink for Sink {
    fn set(&self, doc: Value) {
        self.0.lock().unwrap().push(doc);
    }
}

impl Sink {
    fn last(&self) -> Value {
        self.0.lock().unwrap().last().cloned().unwrap()
    }
    fn dump(&self) -> String {
        format!("{:?}", self.0.lock().unwrap())
    }
}

fn setup(auth: FakeAuthenticator) -> (LockSession, Arc<Sink>, Arc<ManualClock>) {
    let sink = Arc::new(Sink::default());
    let clock = Arc::new(ManualClock::default());
    let s = LockSession::new(
        "maike",
        Arc::new(auth),
        sink.clone(),
        clock.clone(),
        LockConfig {
            free_attempts: 2,
            base_delay_ms: 1000,
            max_delay_ms: 4000,
        },
    );
    (s, sink, clock)
}

fn pw(s: &str) -> SecretString {
    SecretString::new(s)
}

#[tokio::test]
async fn success_unlocks() {
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2"));
    assert_eq!(sink.last()["locked"], false);
    assert_eq!(s.submit(pw("x")).await, Err(SubmitError::NotLocked));
    s.lock();
    assert_eq!(sink.last()["locked"], true);
    assert_eq!(s.submit(pw("hunter2")).await, Ok(SubmitOutcome::Unlocked));
    let d = sink.last();
    assert_eq!(d["locked"], false);
    assert_eq!(d["failures"], 0);
}

#[tokio::test]
async fn wrong_secret_counts_and_reports() {
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2"));
    s.lock();
    assert_eq!(s.submit(pw("nope")).await, Ok(SubmitOutcome::Rejected));
    let d = sink.last();
    assert_eq!(d["locked"], true);
    assert_eq!(d["failures"], 1);
    assert_eq!(d["message_key"], "lock.error.wrong_password");
    assert!(d.get("retry_in_ms").is_none());
}

#[tokio::test]
async fn rate_limit_with_injected_time() {
    let fake = Arc::new(FakeAuthenticator::new("maike", "hunter2"));
    let sink = Arc::new(Sink::default());
    let clock = Arc::new(ManualClock::default());
    struct Shared(Arc<FakeAuthenticator>);
    impl kurashi_auth::Authenticator for Shared {
        fn authenticate(&self, u: &str, s: SecretString) -> Result<(), kurashi_auth::AuthError> {
            self.0.authenticate(u, s)
        }
    }
    let s = LockSession::new(
        "maike",
        Arc::new(Shared(fake.clone())),
        sink.clone(),
        clock.clone(),
        LockConfig {
            free_attempts: 2,
            base_delay_ms: 1000,
            max_delay_ms: 4000,
        },
    );
    s.lock();
    s.submit(pw("a")).await.unwrap();
    s.submit(pw("b")).await.unwrap(); // 2 free attempts used, no delay yet
    assert!(sink.last().get("retry_in_ms").is_none());
    s.submit(pw("c")).await.unwrap(); // third failure -> 1000 ms
    assert_eq!(sink.last()["retry_in_ms"], 1000);
    let calls = fake.calls();

    // Even the right password is refused during lockout, and PAM is not consulted.
    clock.advance_ms(400);
    assert_eq!(
        s.submit(pw("hunter2")).await,
        Err(SubmitError::RateLimited { retry_in_ms: 600 })
    );
    assert_eq!(fake.calls(), calls);
    assert_eq!(sink.last()["message_key"], "lock.error.rate_limited");
    assert_eq!(s.doc()["retry_in_ms"], 600);

    clock.advance_ms(600);
    assert!(s.doc().get("retry_in_ms").is_none());
    s.submit(pw("d")).await.unwrap(); // fourth failure -> 2000 ms
    assert_eq!(sink.last()["retry_in_ms"], 2000);
    clock.advance_ms(2000);
    s.submit(pw("e")).await.unwrap(); // 4000
    clock.advance_ms(4000);
    s.submit(pw("f")).await.unwrap(); // capped at 4000
    assert_eq!(sink.last()["retry_in_ms"], 4000);
    clock.advance_ms(4000);
    assert_eq!(s.submit(pw("hunter2")).await, Ok(SubmitOutcome::Unlocked));
}

#[tokio::test]
async fn multi_prompt_conversation() {
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2").with_otp("424242", true));
    s.lock();
    let s2 = s.clone();
    let first = tokio::spawn(async move { s2.submit(pw("hunter2")).await });

    // Wait for the follow-up prompt to show up in the doc.
    let doc = loop {
        let d = sink.last();
        if d.get("prompt").is_some() {
            break d;
        }
        tokio::time::sleep(Duration::from_millis(5)).await;
    };
    assert_eq!(doc["prompt"], "Verification code:");
    assert_eq!(doc["prompt_echo"], true);
    assert_eq!(doc["busy"], false);
    assert!(doc.get("prompt_key").is_none());

    assert_eq!(s.submit(pw("424242")).await, Ok(SubmitOutcome::Answered));
    assert_eq!(first.await.unwrap(), Ok(SubmitOutcome::Unlocked));
    assert_eq!(sink.last()["locked"], false);
    assert!(sink.last().get("prompt").is_none());
}

#[tokio::test]
async fn wrong_second_factor_is_rejected_and_cancel_aborts() {
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2").with_otp("424242", false));
    s.lock();
    let s2 = s.clone();
    let first = tokio::spawn(async move { s2.submit(pw("hunter2")).await });
    while sink.last().get("prompt").is_none() {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    assert_eq!(sink.last()["prompt_echo"], false);
    assert_eq!(s.submit(pw("000000")).await, Ok(SubmitOutcome::Answered));
    assert_eq!(first.await.unwrap(), Ok(SubmitOutcome::Rejected));

    // Cancel while waiting for the second factor: no failure counted, back to idle lock.
    let failures = sink.last()["failures"].as_u64().unwrap();
    let s3 = s.clone();
    let second = tokio::spawn(async move { s3.submit(pw("hunter2")).await });
    while sink.last().get("prompt").is_none() {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    s.cancel();
    assert_eq!(second.await.unwrap(), Ok(SubmitOutcome::Cancelled));
    let d = sink.last();
    assert_eq!(d["failures"].as_u64().unwrap(), failures);
    assert_eq!(d["locked"], true);
    assert_eq!(d["busy"], false);
}

#[tokio::test]
async fn secret_never_in_documents_or_debug() {
    let secret = "s3cr3t-needle-9137";
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2"));
    s.lock();
    s.submit(pw(secret)).await.unwrap();
    s.handle_intent("lock.submit", &Value::String(secret.into()))
        .await
        .unwrap()
        .unwrap();
    assert!(!sink.dump().contains(secret));
    assert!(!format!("{:?}", s.doc()).contains(secret));
    let dbg = format!("{:?}", pw(secret));
    assert!(!dbg.contains(secret) && dbg.contains("REDACTED"));
}

#[tokio::test(flavor = "current_thread")]
async fn submit_does_not_block_the_runtime() {
    let (s, _sink, _) =
        setup(FakeAuthenticator::new("maike", "hunter2").with_delay(Duration::from_millis(400)));
    s.lock();
    let s2 = s.clone();
    let auth = tokio::spawn(async move { s2.submit(pw("hunter2")).await });

    // A 400 ms blocking PAM call on a single-threaded runtime: our ticker must keep running.
    let mut ticks = 0;
    let start = std::time::Instant::now();
    while !auth.is_finished() {
        tokio::time::sleep(Duration::from_millis(20)).await;
        ticks += 1;
    }
    assert!(start.elapsed() >= Duration::from_millis(350));
    assert!(ticks >= 5, "runtime starved: {ticks} ticks");
    assert_eq!(auth.await.unwrap(), Ok(SubmitOutcome::Unlocked));
}

#[tokio::test]
async fn routing() {
    let (s, sink, _) = setup(FakeAuthenticator::new("maike", "hunter2"));
    assert!(!s.handle_action("session.suspend"));
    assert!(s.handle_action("session.lock"));
    assert_eq!(sink.last()["locked"], true);
    assert!(s.handle_intent("other", &Value::Null).await.is_none());
}
