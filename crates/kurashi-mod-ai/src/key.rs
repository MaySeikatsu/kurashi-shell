//! API keys (docs/ux/ai.md "Keys and privacy"; I134). A key is never a setting: the settings name where it is — an
//! environment variable (`OPENAI_API_KEY`, shellseikatsu's `keyEnv`) or secret-tool attributes (`service openai`: the
//! key `secret-tool lookup service openai` prints, libsecret as ii's keyring). It is looked up for each request and
//! dropped after it; [`ApiKey`] has no `Display` and its `Debug` prints `***`, and errors name the source, not the key.

use std::fmt;
use std::sync::Arc;

use kurashi_mod_api::BoxFuture;
use tokio::io::AsyncReadExt;
use tokio::process::Command;

/// A key, kept out of every printout.
#[derive(Clone, PartialEq, Eq)]
pub struct ApiKey(String);

impl ApiKey {
    pub fn new(key: String) -> Self {
        Self(key)
    }

    /// The key itself, for the request header and nothing else.
    pub fn expose(&self) -> &str {
        &self.0
    }

    /// `text` with every occurrence of the key masked (a provider's error message may quote it).
    pub fn redact(&self, text: &str) -> String {
        if self.0.len() < 4 {
            return text.to_string();
        }
        text.replace(&self.0, "***")
    }
}

impl fmt::Debug for ApiKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ApiKey(***)")
    }
}

/// Where a provider's key is looked up, as its settings say.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeySource {
    /// secret-tool attributes (`attr value …`), empty for none. Tried first.
    pub secret: Vec<String>,
    /// An environment variable's name, empty for none.
    pub env: String,
}

impl KeySource {
    /// From the settings' strings: `secret` is split at white space.
    pub fn new(env: &str, secret: &str) -> Self {
        Self {
            secret: secret.split_whitespace().map(str::to_string).collect(),
            env: env.trim().to_string(),
        }
    }

    /// No source at all: the server needs no key (a local OpenAI-compatible server).
    pub fn is_none(&self) -> bool {
        self.secret.is_empty() && self.env.is_empty()
    }

    /// How Settings and the panel name the source: `$OPENAI_API_KEY`, `secret-tool (service openai)`.
    pub fn describe(&self) -> String {
        match (self.secret.is_empty(), self.env.is_empty()) {
            (true, true) => String::new(),
            (true, false) => format!("${}", self.env),
            (false, true) => format!("secret-tool ({})", self.secret.join(" ")),
            (false, false) => format!("secret-tool ({}), ${}", self.secret.join(" "), self.env),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyError {
    /// Neither source has a key.
    Missing,
    /// secret-tool is not installed.
    NoSecretTool,
    /// secret-tool failed (a locked keyring the user dismissed, no secret service).
    SecretTool(String),
    /// The attributes are not `attr value` pairs.
    BadAttributes,
}

impl KeyError {
    pub fn reason(&self) -> &'static str {
        match self {
            Self::Missing => "mod-ai.error.no_key",
            Self::NoSecretTool => "mod-ai.error.no_secret_tool",
            Self::SecretTool(_) => "mod-ai.error.secret_tool",
            Self::BadAttributes => "mod-ai.error.secret_attributes",
        }
    }
}

/// libsecret's command-line client, behind a trait for the tests.
pub trait Secrets: Send + Sync {
    /// `secret-tool lookup <attrs>`: `Ok(None)` when no item matches.
    fn lookup(&self, attrs: Vec<String>) -> BoxFuture<Result<Option<ApiKey>, KeyError>>;
}

/// The environment, behind a function for the tests.
pub type Env = Arc<dyn Fn(&str) -> Option<String> + Send + Sync>;

pub fn system_env() -> Env {
    Arc::new(|name| std::env::var(name).ok())
}

/// The real secret-tool (a program: `exec:secret-tool`).
pub struct SecretTool {
    pub binary: String,
}

impl Default for SecretTool {
    fn default() -> Self {
        Self {
            binary: "secret-tool".into(),
        }
    }
}

impl Secrets for SecretTool {
    fn lookup(&self, attrs: Vec<String>) -> BoxFuture<Result<Option<ApiKey>, KeyError>> {
        let binary = self.binary.clone();
        Box::pin(async move {
            let mut child = Command::new(&binary)
                .arg("lookup")
                .args(&attrs)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::null())
                .kill_on_drop(true)
                .spawn()
                .map_err(|e| match e.kind() {
                    std::io::ErrorKind::NotFound => KeyError::NoSecretTool,
                    _ => KeyError::SecretTool(e.kind().to_string()),
                })?;
            let mut out = String::new();
            if let Some(mut stdout) = child.stdout.take() {
                stdout
                    .read_to_string(&mut out)
                    .await
                    .map_err(|e| KeyError::SecretTool(e.kind().to_string()))?;
            }
            let status = child
                .wait()
                .await
                .map_err(|e| KeyError::SecretTool(e.kind().to_string()))?;
            // secret-tool prints the secret without a newline on a terminal and with one otherwise; exit 1 = no item.
            let key = out.trim_end_matches(['\n', '\r']).to_string();
            if !status.success() || key.is_empty() {
                return match status.code() {
                    Some(1) | Some(0) => Ok(None),
                    _ => Err(KeyError::SecretTool(format!("exit {status}"))),
                };
            }
            Ok(Some(ApiKey::new(key)))
        })
    }
}

/// The key of `source`: secret-tool first when it names attributes, then the environment variable. `Ok(None)` for a
/// source that names nothing (a keyless server).
pub async fn lookup(
    source: &KeySource,
    secrets: &dyn Secrets,
    env: &Env,
) -> Result<Option<ApiKey>, KeyError> {
    if source.is_none() {
        return Ok(None);
    }
    let mut first_err = None;
    if !source.secret.is_empty() {
        if source.secret.len() % 2 != 0 {
            first_err = Some(KeyError::BadAttributes);
        } else {
            match secrets.lookup(source.secret.clone()).await {
                Ok(Some(k)) => return Ok(Some(k)),
                Ok(None) => {}
                Err(e) => first_err = Some(e),
            }
        }
    }
    if !source.env.is_empty()
        && let Some(v) = env(&source.env).map(|v| v.trim().to_string())
        && !v.is_empty()
    {
        return Ok(Some(ApiKey::new(v)));
    }
    Err(first_err.unwrap_or(KeyError::Missing))
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    struct Fake {
        answer: Result<Option<ApiKey>, KeyError>,
        asked: Mutex<Vec<Vec<String>>>,
    }

    impl Secrets for Fake {
        fn lookup(&self, attrs: Vec<String>) -> BoxFuture<Result<Option<ApiKey>, KeyError>> {
            self.asked.lock().unwrap().push(attrs);
            let a = self.answer.clone();
            Box::pin(async move { a })
        }
    }

    fn fake(answer: Result<Option<ApiKey>, KeyError>) -> Fake {
        Fake {
            answer,
            asked: Mutex::new(Vec::new()),
        }
    }

    fn env_with(name: &'static str, value: &'static str) -> Env {
        Arc::new(move |n| (n == name).then(|| value.to_string()))
    }

    #[tokio::test]
    async fn secret_tool_first_then_the_environment() {
        let src = KeySource::new("FAKE_AI_KEY", "service  openai");
        assert_eq!(src.secret, vec!["service", "openai"]);
        assert_eq!(src.describe(), "secret-tool (service openai), $FAKE_AI_KEY");

        let s = fake(Ok(Some(ApiKey::new("from-keyring-0001".into()))));
        let k = lookup(&src, &s, &env_with("FAKE_AI_KEY", "from-env-0002"))
            .await
            .unwrap();
        assert_eq!(k.unwrap().expose(), "from-keyring-0001");
        assert_eq!(s.asked.lock().unwrap()[0], vec!["service", "openai"]);

        let s = fake(Ok(None));
        let k = lookup(&src, &s, &env_with("FAKE_AI_KEY", " from-env-0002\n"))
            .await
            .unwrap();
        assert_eq!(k.unwrap().expose(), "from-env-0002");

        // secret-tool missing, the variable set: the variable.
        let s = fake(Err(KeyError::NoSecretTool));
        let k = lookup(&src, &s, &env_with("FAKE_AI_KEY", "from-env-0002"))
            .await
            .unwrap();
        assert_eq!(k.unwrap().expose(), "from-env-0002");
        // Neither: the secret-tool error says why.
        let k = lookup(&src, &s, &env_with("OTHER", "x")).await;
        assert_eq!(k, Err(KeyError::NoSecretTool));
    }

    #[tokio::test]
    async fn no_source_no_key_and_missing_keys() {
        let s = fake(Ok(None));
        let env = env_with("FAKE_AI_KEY", "v");
        assert_eq!(lookup(&KeySource::new("", ""), &s, &env).await, Ok(None));
        assert!(s.asked.lock().unwrap().is_empty());
        assert_eq!(
            lookup(&KeySource::new("UNSET_FAKE", ""), &s, &env).await,
            Err(KeyError::Missing)
        );
        assert_eq!(
            lookup(&KeySource::new("", "service"), &s, &env).await,
            Err(KeyError::BadAttributes)
        );
        // An empty variable is no key.
        assert_eq!(
            lookup(&KeySource::new("E", ""), &s, &env_with("E", "  ")).await,
            Err(KeyError::Missing)
        );
    }

    #[test]
    fn the_key_is_never_printed() {
        let k = ApiKey::new("sk-fake-abcdef123456".into());
        assert_eq!(format!("{k:?}"), "ApiKey(***)");
        assert_eq!(format!("{:?}", Some(k.clone())), "Some(ApiKey(***))");
        assert_eq!(
            k.redact("Incorrect API key provided: sk-fake-abcdef123456."),
            "Incorrect API key provided: ***."
        );
        for e in [
            KeyError::Missing,
            KeyError::NoSecretTool,
            KeyError::BadAttributes,
        ] {
            assert!(e.reason().starts_with("mod-ai.error."));
        }
    }

    #[tokio::test]
    async fn the_real_secret_tool_is_run_as_a_program() {
        // A stand-in that prints a key for `lookup service fake` and fails otherwise.
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("secret-tool");
        std::fs::write(
            &bin,
            "#!/bin/sh\n[ \"$1 $2 $3\" = \"lookup service fake\" ] && { printf 'sk-from-fake-tool\\n'; exit 0; }\nexit 1\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let tool = SecretTool {
            binary: bin.to_string_lossy().into_owned(),
        };
        let k = tool
            .lookup(vec!["service".into(), "fake".into()])
            .await
            .unwrap();
        assert_eq!(k.unwrap().expose(), "sk-from-fake-tool");
        assert_eq!(
            tool.lookup(vec!["service".into(), "other".into()]).await,
            Ok(None)
        );
        let missing = SecretTool {
            binary: dir.path().join("nope").to_string_lossy().into_owned(),
        };
        assert_eq!(
            missing.lookup(vec!["a".into(), "b".into()]).await,
            Err(KeyError::NoSecretTool)
        );
    }
}
