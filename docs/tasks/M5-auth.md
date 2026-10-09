# Card M5-auth — `kurashi-auth` (PAM authentication for the lock screen)

**Goal.** The daemon side of the lock screen: authenticate the session user via PAM (service
`kurashi`, installed by the NixOS module), without ever blocking the async runtime, with
rate-limiting and honest status for the lock UI. The frontend owns `ext-session-lock` (Quickshell
`WlSessionLock`); the daemon owns the secret handling.

**Owned paths:** `crates/kurashi-auth/`. Common rules: `docs/tasks/README.md` (read first).

**Read:** `nix/nixos-module.nix` (PAM service `kurashi`), `crates/kurashi-services/src/util.rs`
(`DocSink`), `docs/PROTOCOL.md` §3–§4.

**Build:**
1. `trait Authenticator { fn authenticate(&self, user: &str, secret: SecretString) -> Result<(), AuthError> }`
   (blocking; called on `spawn_blocking`) with a real PAM implementation (crate of your choice,
   e.g. `pam-client`; needs `linux-pam` at build time — **do not edit nix files**; if the build needs
   a native input, add a CONTRACT-CHANGE row naming the package and gate the PAM backend behind a
   cargo feature `pam` so the crate builds without it) and a `FakeAuthenticator` for tests.
2. `LockSession` state machine: `Unlocked → Locked → Authenticating → (Unlocked | Locked{failures})`,
   rate limit with backoff after N failures (config struct), lockout reporting, `secret` zeroised
   after use (`zeroize`/`secrecy`), never logged, never in a document.
3. Document `runtime.lock` = `{locked, busy, failures, retry_in_ms?, message_key?}` via `DocSink`
   (i18n keys like `lock.error.wrong_password`, `lock.error.rate_limited`). Commands: `lock()`,
   `submit(secret)`, `cancel()`; the daemon routes an intent `lock.submit` (value = secret string)
   and actions `session.lock` → `lock()`.
4. Multi-message PAM conversations (e.g. "Password:" then OTP) surface as `prompt_key`/`prompt`
   in the doc; echo-on vs echo-off prompts flagged.

**Never authenticate against the real user/PAM stack in tests** — fake only. No manual PAM runs.

**Acceptance (one command):** `cargo test -p kurashi-auth` green (fake backend: success, wrong
secret, rate limiting with time injected, multi-prompt conversation, secret never appears in any
emitted document or Debug output, `submit` never blocks the runtime — run it inside a
current-thread runtime with a slow fake). `cargo build -p kurashi-auth` without the `pam` feature.
Clippy `-D warnings`.
