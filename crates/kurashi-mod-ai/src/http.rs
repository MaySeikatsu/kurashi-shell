//! The mod's network calls (as the lyrics and calendar mods' `http.rs`): a GET of a whole body (the model lists) and a
//! POST whose answer is read line by line (the streamed reply). Both run on a blocking thread (ureq, rustls), so the
//! daemon's runtime never waits on the network. Behind a trait, so the tests run with an in-memory transport.
//!
//! A request's headers may carry the API key: a [`Header::Secret`], which no `Debug` prints and no error repeats.

use std::fmt;
use std::io::{BufRead, BufReader, Read};
use std::time::Duration;

use kurashi_mod_api::BoxFuture;
use tokio::sync::{mpsc, oneshot};

use crate::key::ApiKey;

/// One header value: plain, or the key (redacted wherever it could be printed).
#[derive(Clone)]
pub enum Header {
    Plain(String),
    /// `prefix` + the key, e.g. `Bearer ` + key.
    Secret {
        prefix: &'static str,
        key: ApiKey,
    },
}

impl Header {
    fn value(&self) -> String {
        match self {
            Self::Plain(v) => v.clone(),
            Self::Secret { prefix, key } => format!("{prefix}{}", key.expose()),
        }
    }
}

impl fmt::Debug for Header {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Plain(v) => write!(f, "{v:?}"),
            Self::Secret { prefix, .. } => write!(f, "\"{prefix}***\""),
        }
    }
}

/// A request: the URL, the headers, and a JSON body for a POST.
#[derive(Clone, Debug)]
pub struct Request {
    pub url: String,
    pub headers: Vec<(&'static str, Header)>,
    pub body: Option<String>,
}

impl Request {
    pub fn get(url: String) -> Self {
        Self {
            url,
            headers: Vec::new(),
            body: None,
        }
    }

    pub fn header(mut self, name: &'static str, value: Header) -> Self {
        self.headers.push((name, value));
        self
    }

    /// The header named so (tests).
    pub fn find(&self, name: &str) -> Option<&Header> {
        self.headers
            .iter()
            .find(|(n, _)| n.eq_ignore_ascii_case(name))
            .map(|(_, v)| v)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HttpError {
    /// No answer: DNS, connect, TLS or a timeout.
    Offline(String),
    /// The server answered with this status; `body` is the start of what it said (for its error message).
    Status { code: u16, body: String },
    /// The answer broke off or could not be read.
    Body(String),
}

/// The lines of a streamed answer, as they arrive; an `Err` ends it (the connection broke).
pub type Lines = mpsc::Receiver<Result<String, HttpError>>;

pub trait Http: Send + Sync {
    /// The whole body of a GET (or a POST with `body`).
    fn fetch(&self, req: Request) -> BoxFuture<Result<String, HttpError>>;
    /// The answer's lines once its headers arrived with a 2xx status. Dropping the receiver ends the request at the
    /// next line.
    fn stream(&self, req: Request) -> BoxFuture<Result<Lines, HttpError>>;
}

/// The real transport: ureq over rustls.
pub struct Ureq {
    connect: Duration,
    /// Until the answer's headers: a local model may take a while to load.
    first_byte: Duration,
    /// The whole body of a streamed answer (a long answer from a slow model).
    stream_body: Duration,
}

impl Ureq {
    pub fn new() -> Self {
        Self {
            connect: Duration::from_secs(5),
            first_byte: Duration::from_secs(180),
            stream_body: Duration::from_secs(900),
        }
    }

    fn agent(&self, body: Duration) -> ureq::Agent {
        let config = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_connect(Some(self.connect))
            .timeout_recv_response(Some(self.first_byte))
            .timeout_recv_body(Some(body))
            .user_agent(concat!(
                "kurashi-mod-ai/",
                env!("CARGO_PKG_VERSION"),
                " (kurashi-shell)"
            ))
            .build();
        ureq::Agent::new_with_config(config)
    }
}

impl Default for Ureq {
    fn default() -> Self {
        Self::new()
    }
}

/// The start of an error body: enough for the provider's message, never a whole page.
const ERROR_BODY_MAX: usize = 16 * 1024;

fn call(agent: &ureq::Agent, req: &Request) -> Result<ureq::http::Response<ureq::Body>, HttpError> {
    let result = match &req.body {
        Some(body) => {
            let mut r = agent.post(&req.url);
            for (n, v) in &req.headers {
                r = r.header(*n, v.value());
            }
            r.content_type("application/json").send(body.as_bytes())
        }
        None => {
            let mut r = agent.get(&req.url);
            for (n, v) in &req.headers {
                r = r.header(*n, v.value());
            }
            r.call()
        }
    };
    // ureq's errors name the host and the cause, never a header.
    let mut response = result.map_err(|e| HttpError::Offline(e.to_string()))?;
    let code = response.status().as_u16();
    if !(200..300).contains(&code) {
        let mut buf = Vec::new();
        let _ = response
            .body_mut()
            .as_reader()
            .take(ERROR_BODY_MAX as u64)
            .read_to_end(&mut buf);
        return Err(HttpError::Status {
            code,
            body: String::from_utf8_lossy(&buf).into_owned(),
        });
    }
    Ok(response)
}

impl Http for Ureq {
    fn fetch(&self, req: Request) -> BoxFuture<Result<String, HttpError>> {
        let agent = self.agent(Duration::from_secs(30));
        Box::pin(async move {
            let run = move || {
                let mut response = call(&agent, &req)?;
                response
                    .body_mut()
                    .read_to_string()
                    .map_err(|e| HttpError::Body(e.to_string()))
            };
            match tokio::task::spawn_blocking(run).await {
                Ok(r) => r,
                Err(e) => Err(HttpError::Offline(e.to_string())),
            }
        })
    }

    fn stream(&self, req: Request) -> BoxFuture<Result<Lines, HttpError>> {
        let agent = self.agent(self.stream_body);
        Box::pin(async move {
            let (head_tx, head_rx) = oneshot::channel();
            let (tx, rx) = mpsc::channel(256);
            tokio::task::spawn_blocking(move || {
                let response = match call(&agent, &req) {
                    Ok(r) => r,
                    Err(e) => {
                        let _ = head_tx.send(Err(e));
                        return;
                    }
                };
                if head_tx.send(Ok(())).is_err() {
                    return;
                }
                let mut reader = BufReader::new(response.into_body().into_reader());
                let mut line = String::new();
                loop {
                    line.clear();
                    match reader.read_line(&mut line) {
                        Ok(0) => return,
                        Ok(_) => {
                            let l = line.trim_end_matches(['\n', '\r']).to_string();
                            if tx.blocking_send(Ok(l)).is_err() {
                                return; // the reply was stopped: dropping the reader closes the connection
                            }
                        }
                        Err(e) => {
                            let _ = tx.blocking_send(Err(HttpError::Body(e.to_string())));
                            return;
                        }
                    }
                }
            });
            match head_rx.await {
                Ok(Ok(())) => Ok(rx),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(HttpError::Offline("the request thread ended".into())),
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_secret_header_is_never_printed() {
        let req = Request::get("https://example.invalid/v1/models".into())
            .header(
                "authorization",
                Header::Secret {
                    prefix: "Bearer ",
                    key: ApiKey::new("sk-test-123456".into()),
                },
            )
            .header("anthropic-version", Header::Plain("2023-06-01".into()));
        let shown = format!("{req:?}");
        assert!(!shown.contains("sk-test-123456"), "{shown}");
        assert!(shown.contains("Bearer ***"));
        assert!(shown.contains("2023-06-01"));
        // The real value is only what goes on the wire.
        assert_eq!(
            req.find("Authorization").unwrap().value(),
            "Bearer sk-test-123456"
        );
    }
}
