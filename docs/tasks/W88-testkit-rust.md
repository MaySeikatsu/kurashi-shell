# W88 — One private D-Bus test bus (session 34, I550; Haiku)

Rule 10 (K153): a block a second file needs moves to one shared place. The private `dbus-daemon` test bus — the scratch
dir, the bus config, the spawn, the address, the kill on drop — is written out in nine files. Common rules:
`docs/tasks/README.md`. Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W88`.

## Goal
1. A dev-only crate `crates/kurashi-testkit` (`publish = false`, `[lints] workspace = true`, no dependency on any kurashi
   crate): `TestBus` (start a private session bus in a scratch dir, `addr()`, stopped and removed on drop) and `Scratch`
   (a temp dir removed on drop), taken from `crates/kurashi-services/tests/common/mod.rs` — keep both listen forms the
   copies use (`unix:tmpdir=` and `unix:path=`), as constructors.
2. Use it, deleting each copy, in: `crates/kurashi-{services,tray,notify}/tests/common/mod.rs` (what is left there is
   that crate's own helpers), `crates/kurashid/tests/{media_actions,quick_pages,quick_actions,services_reconnect}.rs`,
   and the `#[cfg(test)]` modules of `crates/kurashid/src/wiring.rs` and `crates/kurashid/src/os_scheme.rs`.
   `kurashi-testkit` goes into those crates' `[dev-dependencies]` only.
3. No test is removed or weakened; names and assertions stay.

## Owned paths
`crates/kurashi-testkit/**` (new); in the nine files above only the bus and scratch code and the lines that call it;
the `[dev-dependencies]` of `kurashi-services`, `kurashi-tray`, `kurashi-notify`, `kurashid`; `tools/clones-baseline.json`
(rewritten by `python3 tools/clones.py --update` once the count fell). Nothing else.

## Acceptance
```sh
nix develop -c bash -c 'timeout 1500 cargo nextest run -p kurashi-testkit -p kurashi-services -p kurashi-tray -p kurashi-notify -p kurashid \
  && cargo clippy -p kurashi-testkit -p kurashi-services -p kurashi-tray -p kurashi-notify -p kurashid --all-targets -- -D warnings \
  && cargo fmt --all -- --check && python3 tools/clones.py --check'
```
green, and `python3 tools/clones.py --lang rs` shows no pair among those nine files in its top list. Report the `rs`
count before and after.
