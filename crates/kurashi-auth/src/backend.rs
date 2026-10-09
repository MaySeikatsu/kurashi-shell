use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use crate::SecretString;

/// Whether PAM has a service file `dir/service` (`/etc/pam.d/<service>`). Without one PAM falls
/// back to the `other` stack, which the lock screen cannot rely on, so nothing could unlock it.
pub fn service_configured(dir: &Path, service: &str) -> bool {
    dir.join(service).is_file()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PromptKind {
    EchoOff,
    EchoOn,
    /// Informational PAM text; `Conversation::prompt` returns `None` for it.
    Info,
    Error,
}

/// Blocking conversation handed to the backend (lives on the `spawn_blocking` thread).
/// `None` means the conversation was cancelled (or the kind needs no answer): abort.
pub trait Conversation {
    fn prompt(&mut self, kind: PromptKind, text: &str) -> Option<SecretString>;
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum AuthError {
    #[error("authentication failed")]
    WrongSecret,
    #[error("authentication cancelled")]
    Cancelled,
    /// PAM itself failed (service missing, module error). Text is PAM's, never the secret.
    #[error("backend error: {0}")]
    Backend(String),
}

/// Blocking; always call on `spawn_blocking`.
pub trait Authenticator: Send + Sync + 'static {
    /// One-shot: a single secret answers the first password prompt.
    fn authenticate(&self, user: &str, secret: SecretString) -> Result<(), AuthError>;

    /// Full conversation (OTP etc.). Default: ask for the password, then one-shot.
    fn authenticate_with(&self, user: &str, conv: &mut dyn Conversation) -> Result<(), AuthError> {
        let secret = conv
            .prompt(PromptKind::EchoOff, "Password: ")
            .ok_or(AuthError::Cancelled)?;
        self.authenticate(user, secret)
    }
}

/// Test backend: password, optional second factor, optional slowness. Never touches PAM.
pub struct FakeAuthenticator {
    user: String,
    password: String,
    otp: Option<(String, bool)>,
    delay: Duration,
    calls: AtomicUsize,
}

impl FakeAuthenticator {
    pub fn new(user: &str, password: &str) -> Self {
        Self {
            user: user.into(),
            password: password.into(),
            otp: None,
            delay: Duration::ZERO,
            calls: AtomicUsize::new(0),
        }
    }
    /// Require a second prompt; `echo` makes it an echo-on prompt.
    pub fn with_otp(mut self, code: &str, echo: bool) -> Self {
        self.otp = Some((code.into(), echo));
        self
    }
    /// Blocks the calling thread (simulates slow PAM modules / fail delay).
    pub fn with_delay(mut self, d: Duration) -> Self {
        self.delay = d;
        self
    }
    pub fn calls(&self) -> usize {
        self.calls.load(Ordering::SeqCst)
    }
}

impl Authenticator for FakeAuthenticator {
    fn authenticate(&self, user: &str, secret: SecretString) -> Result<(), AuthError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        std::thread::sleep(self.delay);
        if user == self.user && secret.expose() == self.password {
            Ok(())
        } else {
            Err(AuthError::WrongSecret)
        }
    }

    fn authenticate_with(&self, user: &str, conv: &mut dyn Conversation) -> Result<(), AuthError> {
        let pw = conv
            .prompt(PromptKind::EchoOff, "Password: ")
            .ok_or(AuthError::Cancelled)?;
        let Some((code, echo)) = &self.otp else {
            return self.authenticate(user, pw);
        };
        self.calls.fetch_add(1, Ordering::SeqCst);
        std::thread::sleep(self.delay);
        let kind = if *echo {
            PromptKind::EchoOn
        } else {
            PromptKind::EchoOff
        };
        let otp = conv
            .prompt(kind, "Verification code: ")
            .ok_or(AuthError::Cancelled)?;
        if user == self.user && pw.expose() == self.password && otp.expose() == code {
            Ok(())
        } else {
            Err(AuthError::WrongSecret)
        }
    }
}

#[cfg(feature = "pam")]
pub use pam_backend::PamAuthenticator;

#[cfg(feature = "pam")]
mod pam_backend {
    use std::ffi::{CStr, CString};

    use pam_client::{Context, ErrorCode, Flag};

    use super::{AuthError, Authenticator, Conversation, PromptKind};
    use crate::SecretString;

    /// Real PAM. Only constructed by kurashid for the session user; never used in tests.
    pub struct PamAuthenticator {
        service: String,
    }

    impl PamAuthenticator {
        pub fn new(service: &str) -> Self {
            Self {
                service: service.into(),
            }
        }
    }

    struct Bridge<'a>(&'a mut dyn Conversation);

    impl Bridge<'_> {
        fn ask(&mut self, kind: PromptKind, msg: &CStr) -> Result<CString, ErrorCode> {
            let ans = self
                .0
                .prompt(kind, &msg.to_string_lossy())
                .ok_or(ErrorCode::CONV_ERR)?;
            CString::new(ans.expose()).map_err(|_| ErrorCode::CONV_ERR)
        }
    }

    impl pam_client::ConversationHandler for Bridge<'_> {
        fn init(&mut self, _default_user: Option<impl AsRef<str>>) {}
        fn prompt_echo_on(&mut self, msg: &CStr) -> Result<CString, ErrorCode> {
            self.ask(PromptKind::EchoOn, msg)
        }
        fn prompt_echo_off(&mut self, msg: &CStr) -> Result<CString, ErrorCode> {
            self.ask(PromptKind::EchoOff, msg)
        }
        fn text_info(&mut self, msg: &CStr) {
            self.0.prompt(PromptKind::Info, &msg.to_string_lossy());
        }
        fn error_msg(&mut self, msg: &CStr) {
            self.0.prompt(PromptKind::Error, &msg.to_string_lossy());
        }
    }

    impl Authenticator for PamAuthenticator {
        fn authenticate(&self, user: &str, secret: SecretString) -> Result<(), AuthError> {
            struct OneShot(Option<SecretString>);
            impl Conversation for OneShot {
                fn prompt(&mut self, k: PromptKind, _: &str) -> Option<SecretString> {
                    matches!(k, PromptKind::EchoOff | PromptKind::EchoOn)
                        .then(|| self.0.take())
                        .flatten()
                }
            }
            self.authenticate_with(user, &mut OneShot(Some(secret)))
        }

        fn authenticate_with(
            &self,
            user: &str,
            conv: &mut dyn Conversation,
        ) -> Result<(), AuthError> {
            let mut ctx = Context::new(&self.service, Some(user), Bridge(conv))
                .map_err(|e| AuthError::Backend(e.to_string()))?;
            let map = |e: pam_client::Error| match e.code() {
                ErrorCode::AUTH_ERR | ErrorCode::USER_UNKNOWN | ErrorCode::MAXTRIES => {
                    AuthError::WrongSecret
                }
                ErrorCode::CONV_ERR => AuthError::Cancelled,
                _ => AuthError::Backend(e.to_string()),
            };
            ctx.authenticate(Flag::NONE).map_err(map)?;
            ctx.acct_mgmt(Flag::NONE).map_err(map)
        }
    }
}
