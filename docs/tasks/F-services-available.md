# Card F-services-available — `available` on svc.session / svc.media (CONTRACT row 9, accepted)

**Owned paths:** `crates/kurashi-services/src/{session,media,power,util}.rs` + `tests/`,
`fixtures/ipc/` (only goldens for these two docs, if any exist or you add one),
`frontend/components/faces/MediaFace.qml` (only to treat `available:false` as "nothing playing").
Common rules: `docs/tasks/README.md`.

**Build:** `svc.session` and `svc.media` gain `available: bool` (true while the service's bus
stream is alive; false after `util::ended`), so "logind gone" no longer looks like real hints and
"MPRIS stream dead" no longer looks like "no players". `svc.power`: separate "no UPower"
(`available:false`) from "no battery" (`present:false`). Keep every doc null-free.
**Acceptance:** `timeout 600 cargo test -p kurashi-services` green with tests for each flag;
clippy clean; `frontend/test-real.sh` still passes.
