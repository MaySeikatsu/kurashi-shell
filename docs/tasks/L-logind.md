# Card L-logind — resolve the user's graphical session explicitly

**Read first:** `crates/kurashi-services/src/session.rs`, `crates/kurashi-services/tests/session.rs`
(+ `tests/common/`), `docs/PROGRESS.md` row F.4 ("TODO: explicit logind session for systemd --user"),
logind D-Bus API (`org.freedesktop.login1.Manager`, `.User` `Display`/`Sessions`, `.Session` `Type`,
`Class`, `Active`, `Remote`; https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

**Problem:** `svc.session` reads `/org/freedesktop/login1/session/auto`. For a `systemd --user`
service (how the HM module runs kurashid) the caller belongs to no session, so logind answers nothing
and `svc.session` stays `available:false`: idle/locked hints never arrive.

**Owned paths:** `crates/kurashi-services/src/session.rs`, `crates/kurashi-services/tests/session.rs`,
`crates/kurashi-services/tests/common/` (additions only). NOT `util.rs` (card C-services), not the
`start(conn, sink)` signature, not kurashid.
Common rules: `docs/tasks/README.md`.

**Do:** resolve the session object path once per start (and again when logind's `NameOwnerChanged`
or the user's `Display` property changes), in this order: `$XDG_SESSION_ID` if set and logind knows it
(`GetSession`); else the user's `Display` session (`/org/freedesktop/login1/user/self` → `Display`);
else the first of the user's `Sessions` that is `Type` wayland/x11, `Class` user, not `Remote`, preferring
`Active`; else `session/auto` (today's behaviour). Watch PropertiesChanged on the resolved path only.
`lock()` keeps `LockSessions`. Add `"session": "<id>"` to the document only if PROTOCOL allows it — it
does not today, so do NOT add fields; write a CONTRACT-CHANGE row if you think it is needed.

**Acceptance:** tests on the private bus with a fake logind (extend `tests/common`): (a) no
`XDG_SESSION_ID`, `user/self` `Display` points at a session with IdleHint true → document
`available:true, idle_hint:true`; (b) `session/auto` unknown but a matching session in `Sessions` → found;
(c) nothing matches → `available:false` as today; (d) `Display` changes → the new session's hints
follow. `timeout 600 cargo test -p kurashi-services`, clippy -D warnings. Env is read through a
parameter you can set in tests (edition 2024: no `set_var`).
