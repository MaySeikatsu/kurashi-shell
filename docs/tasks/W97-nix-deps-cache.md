# W97 — A version bump does not rebuild the dependencies under Nix (session 34, K156; I577; lead)

`craneLib.buildDepsOnly` (nix/package.nix) is keyed by `version` (through `commonArgs`) and by the root `Cargo.toml` and
`Cargo.lock`, which carry the workspace's version. Every PR bumps it (K151), so every PR rebuilds ~340 crates in release.

## Steps
1. Measure first: `nix build .#kurashi` after a bump alone (touch nothing else): which derivations rebuild, how long.
2. The dependency derivation gets `version = "0"` and a `dummySrc` built from normalised manifests:
   - root `Cargo.toml` with `[workspace.package] version` replaced by `0.0.0`, and `Cargo.lock` with the version of each
     workspace member (the names under `crates/`) replaced the same way — at evaluation (`builtins.readFile` +
     `builtins.replaceStrings`, written with `pkgs.writeText`), so the result's hash follows its content;
   - crane's `mkDummySrc` reads the manifests at evaluation and takes `cargoLock`; if it cannot take a rewritten root
     manifest without import-from-derivation, build the dummy source by hand (the trimmed manifests crane would write,
     dummy `lib.rs`/`main.rs` per crate — crane's `mkDummySrc.nix` is the reference) or allow IFD for this one derivation
     and say so in the flake.
3. Check: the dependency derivation's store path is the same before and after a bump; the package still builds; the
   `tests` check still reuses the artifacts; `nix flake check` passes.
4. README "Iterating": the table of what `nix build` costs, measured again.

## Acceptance
Two builds around a version bump: the second compiles `kurashi-bin` only (the log has no `kurashi-deps>` lines), with the
times in the README and BENCH.
