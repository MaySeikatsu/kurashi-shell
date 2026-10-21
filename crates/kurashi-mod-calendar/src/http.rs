//! The mod's one network call, a GET with a timeout on a blocking thread (copied from `kurashi-mod-weather`'s
//! `http.rs`): behind a trait, so tests run with an in-memory transport or a local server.

use std::time::Duration;

use kurashi_mod_api::BoxFuture;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HttpError {
    /// No answer: DNS, connect, TLS or the timeout.
    Offline(String),
    /// The server answered with this status.
    Status(u16),
    /// The body could not be read as text.
    Body(String),
}

pub trait Http: Send + Sync {
    fn get(&self, url: String) -> BoxFuture<Result<String, HttpError>>;
}

/// The real transport: ureq over rustls, one timeout for the whole request, gzip.
pub struct Ureq {
    timeout: Duration,
}

impl Ureq {
    pub fn new() -> Self {
        Self {
            timeout: Duration::from_secs(20),
        }
    }
}

impl Default for Ureq {
    fn default() -> Self {
        Self::new()
    }
}

impl Http for Ureq {
    fn get(&self, url: String) -> BoxFuture<Result<String, HttpError>> {
        let timeout = self.timeout;
        Box::pin(async move {
            match tokio::task::spawn_blocking(move || fetch_blocking(&url, timeout)).await {
                Ok(result) => result,
                Err(e) => Err(HttpError::Offline(e.to_string())),
            }
        })
    }
}

/// Calendars run to a few MB; a feed past this is refused rather than held in memory.
const MAX_BODY: u64 = 16 << 20;

fn fetch_blocking(url: &str, timeout: Duration) -> Result<String, HttpError> {
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .user_agent(concat!("kurashi-mod-calendar/", env!("CARGO_PKG_VERSION")))
        .build();
    let agent = ureq::Agent::new_with_config(config);
    match agent.get(url).call() {
        Ok(mut response) => response
            .body_mut()
            .with_config()
            .limit(MAX_BODY)
            .read_to_string()
            .map_err(|e| HttpError::Body(e.to_string())),
        Err(ureq::Error::StatusCode(code)) => Err(HttpError::Status(code)),
        Err(e) => Err(HttpError::Offline(e.to_string())),
    }
}
