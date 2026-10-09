# Card W9-brightness-session — SetBrightness on the resolved graphical session (B3)

**Read first:** `docs/tasks/README.md`, `docs/BACKLOG.md` row B3, `crates/kurashi-services/src/brightness.rs`,
`crates/kurashi-services/src/session.rs` (the resolver `resolve()` from card L-logind),
`crates/kurashi-services/tests/` (+ `tests/common/` fake logind), logind `Session.SetBrightness`
(https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

**Problem:** `brightness.rs` calls `SetBrightness` on `/org/freedesktop/login1/session/auto`. For a
`systemd --user` daemon (the HM module) the caller belongs to no session, so the call fails and the
brightness keys/slider do nothing. `session.rs` already resolves the user's graphical session
(XDG_SESSION_ID → user Display → Sessions → auto); reuse it.

**Owned paths:** `crates/kurashi-services/src/brightness.rs`, `crates/kurashi-services/src/session.rs`
(make the resolver reusable: e.g. `pub(crate) async fn resolve_session_path(conn, env) -> String`;
no behaviour change for `svc.session`), `crates/kurashi-services/tests/brightness*.rs` and
`tests/common/` (additions only). NOT `util.rs`, not kurashid, not the document shapes.

**Do:** resolve the session path when the brightness service starts (lazily on the first write is fine)
and cache it; re-resolve once if a call fails with `UnknownObject`/`NoSuchSession`-like errors (the
session went away), then fall back to `session/auto`. Env is read through a parameter you can set in
tests (edition 2024: no `set_var`). Log the resolved path at debug.

**Acceptance:** a private-bus test with the fake logind: no `XDG_SESSION_ID`, `user/self` `Display`
points at session `c2` → a `brightness.set` (or the plan/apply path you test through) calls
`SetBrightness` on `/org/freedesktop/login1/session/c2`, not `session/auto`; a second test: the cached
session disappears → one re-resolve, then success. `timeout 600 cargo test -p kurashi-services`,
`cargo clippy -p kurashi-services --all-targets -- -D warnings`.
