# Card W14-mods-live — every bundled mod through the real shell, in one test (BACKLOG I21, I34)

**Read first:** `docs/tasks/README.md`, `docs/MODS.md` ("Native mods": mods import `qs.core`/`qs.components`),
`frontend/test-modqml.sh` (has a stand-in proxy for the hello mod), `frontend/core/ModLoader.qml`, `crates/kurashid/src/native.rs`
(`linked()`), `tools/bench/sandbox.sh`, the bundled mods under `mods/`.

**Owned paths:** `frontend/test-mods-live.sh` (new), `frontend/test-modqml.sh` (retire its stand-in), `crates/kurashid/Cargo.toml`
+ `native.rs` (a cargo feature `test-mods` that also links `kurashi-mod-hello`; default builds unchanged),
`crates/kurashid/tests/data/mods/hello/**`, `justfile` (one recipe `mods-live`).

**Do:** `frontend/test-mods-live.sh`: sandbox + real kurashid (built with `--features test-mods`, isolated XDG, no system bus,
data dir = checkout) + frontend; for every bundled mod and hello: `mod.enable`, then exercise each provide its manifest lists
(widget visible in the bar, panel via `mod.panel.open`, face via raising it where the mod has a test action, each slot's host
view), screenshot each, `mod.disable` and assert the component is destroyed; fail on any QML warning/error/binding loop and on
any raw i18n key visible in the a11y names or text (scan `qs.log` debug output or an `Accessible.name` dump). Network mods must
not reach the network: point weather at an unset place. `test-modqml.sh` uses the `test-mods` build instead of its proxy.

**Acceptance:** `just mods-live` green on machine B (`KURASHI_RENDER_NODE=/dev/dri/renderD129`), screenshots read and described,
and it fails when you temporarily reintroduce a relative `frontend/core` import in one mod (prove the guard, then revert).
