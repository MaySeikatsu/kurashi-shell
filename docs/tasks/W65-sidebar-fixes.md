# W65-sidebar-fixes — the sidebar keeps its page; a pin holds on its own monitor (B46, B47)

Model: Haiku 5.5 (clear scope, two small fixes). Branch `fix/s26-sidebar-fixes`. Common rules: `docs/tasks/README.md`.
Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w65`.

## Goal
1. **B46.** A sidebar in pages mode opens on the page it showed last. Today: open, pick another tab, close, open again →
   back on the first page. Cause: `LeftColumn.current` (`frontend/components/sidebar/LeftColumn.qml:50`) starts at 0
   whenever the column's Loader (`frontend/surfaces/Sidebar.qml` ~826, `sourceComponent: sb.mode === "pages" ? leftC : rightC`)
   makes it again. Keep the last page per side and output in view state outside the Loader (a property on the per-screen
   column delegate `col`, or a small map on the Sidebar root keyed `side|output`), and bind `LeftColumn.current` to it /
   write it back on tab change. Key it by the tab's **id**, not its index, so a reordered or hidden section does not move it;
   fall back to the first shown tab when the remembered one is gone. View state only: no config key, no daemon change.
2. **B47.** Pinning pins on every monitor. It should pin only on the output whose pin was clicked.
   - `crates/kurashi-schema/src/v1.rs` (macro `sidebar_side!`, field `pinned`, ~line 2037): add `per_output` to its
     `#[kurashi(...)]` (look at `bar.*` fields near line 232/304 for the syntax). The daemon already resolves layout config per
     output (`crates/kurashid/src/wiring.rs` ~3070 reads `sidebar.{side}.pinned` into each output's `SidebarConfig`): verify the
     resolver there takes the output's slot; fix it if not.
   - `frontend/components/sidebar/SidebarPin.qml:20`: send the op with the output:
     `Store.apply([{ set: "sidebar." + side + ".pinned", value: !pinned, output: <this column's output name> }])`
     (ops carry `output`, see `crates/kurashi-ipc` doc comment `{"reset":"theme.motion","output":"DP-1"}`). The pin's
     `pinned` state must read this output's value (from the column's `vis`/layout entry), not the global one.
   - A pin set earlier without an output (global, from before) must still unpin: when unpinning on an output whose value comes
     from the global slot, reset/clear correctly so the result is "unpinned here" and the UI never shows a pin that is not
     in effect (Shōjiki, rule 2).
   - Regenerate whatever the schema generates (`config.example.toml`, docs) the way the repo does it (`just` recipes / tests
     tell you if a generated file is stale).

## Owned paths
`frontend/components/sidebar/LeftColumn.qml`, `frontend/components/sidebar/SidebarPin.qml`, `frontend/surfaces/Sidebar.qml`,
`crates/kurashi-schema/src/v1.rs` (the `pinned` field only), files the schema generates, `crates/kurashid/src/wiring.rs`
(the sidebar resolver only, if needed), `frontend/test-sidebars.sh` (add steps).

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`. Out-of-scope needs → `docs/CONTRACT-CHANGE.md`.

## Acceptance
- `nix develop -c just check` green (fmt, clippy -D warnings, cargo test), incl. a test in kurashi-config or kurashid that a
  `sidebar.left.pinned` set for `DP-1` pins DP-1's left sidebar only.
- `frontend/test-sidebars.sh` gets two steps and passes (run with `timeout`): (a) left sidebar, pick the 2nd tab, close,
  open → 2nd tab shown; (b) two outputs (the suite's sandbox can make two; see how `frontend/test-light-outputs.sh` does it),
  pin on output 1 → output 2's left sidebar not pinned.
- The user tests on their live session afterwards; do not start anything on the real display.

## Report
The README's report format. Token thrift: read only the files named here and what they call.
