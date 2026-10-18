# Card W16-test-infra — tests that cannot reach the network, a mock with real focus, no nulls (I58, row 80, B25)

**Why:** B23 — a stale sandbox daemon fetched the real Open-Meteo forecast; B14's two-output re-pick has no runtime
check because the mock marks every output's workspace focused (row 80); `mod.wallpaper` carries `"theme": {"image":
null}` although documents never contain `null` (PROTOCOL §1; a patched client then sees the key absent, a fresh
snapshot shows null — B25).

**Read first:** `docs/tasks/README.md` (rule 3: your build dir `~/.cache/kurashi-agents-target/W16-infra`),
`tools/bench/sandbox.sh`, `frontend/test-mods-live.sh` (read-only: how it starts kurashid), `crates/kurashi-mock/src/{state,documents}.rs`,
PROTOCOL §1 and §8 (`svc.workspaces`, mock control messages), `crates/kurashi-mod-wallpaper/src/{lib,supervisor}.rs`.

**Owned paths:** `tools/bench/sandbox.sh` (+ a new helper under `tools/bench/` if needed), `crates/kurashi-mock/**`,
`crates/kurashi-mod-wallpaper/**`, `mods/wallpaper/qml/**` (only where the `theme.image` absence must be read),
`frontend/test-stage.sh` (one new two-output B14 step at the end; do not change existing steps).

**Do:**
1. **I58:** everything the sandbox starts (sway, the frontend, kurashid, the mock) runs without network: a network
   namespace (`unshare -n` via `unshare --user --map-root-user --net` or `bwrap --unshare-net`, whichever works
   rootless here inside `nix develop`; loopback up), unless a test opts in explicitly (`KURASHI_SANDBOX_NET=1`, not
   used by any test today). Unix sockets and the sandbox's own D-Bus keep working. Prove it: a sandbox step that
   tries `curl https://example.com` from inside fails, and `just mods-live` + `frontend/test-real.sh` stay green.
2. **Row 80:** the mock's `svc.workspaces` marks `focused` only on the focused output; a mock control
   (`mock.focus {output}`) moves focus. Then add the B14 runtime step to `frontend/test-stage.sh`: two headless
   outputs, focus the second, `quick.toggle` → the Stage card is on the second output; focus the first, toggle again →
   first. Read the shots.
3. **B25:** `mod.wallpaper` omits absent values instead of `null` (`theme` without `image`, any other nulls); readers
   (K34 in kurashid reads `theme.image` as optional already; the picker QML) treat absent as none. Add a crate test that
   walks the document and finds no `null`.
**Acceptance:** `cargo test -p kurashi-mock -p kurashi-mod-wallpaper`, clippy/fmt clean; `frontend/test-stage.sh`
(with the new B14 step) and `just mods-live` green on machine B (`KURASHI_RENDER_NODE=/dev/dri/renderD129`); the
no-network proof in the log. Report each item met / not met.
