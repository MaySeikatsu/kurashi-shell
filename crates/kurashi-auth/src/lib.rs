//! Lock-screen authentication. The frontend owns `ext-session-lock`; this crate owns the secret:
//! PAM runs on `spawn_blocking`, failures are rate-limited, and the secret is never logged,
//! stored in a document or kept after use (`SecretString`).

mod backend;
mod secret;
mod session;

#[cfg(feature = "pam")]
pub use backend::PamAuthenticator;
pub use backend::{AuthError, Authenticator, Conversation, FakeAuthenticator, PromptKind};
pub use secret::SecretString;
pub use session::{
    Clock, LockConfig, LockSession, ManualClock, SubmitError, SubmitOutcome, SystemClock,
};
