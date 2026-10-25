# Card W41-icons — install the icon font subset; a cheaper paper grain (rows 445–447; I194, I199)

**Why:** W39-block built "Kurashi Symbols Rounded/Sharp" (`nix/icon-font.nix`, 411 names; Sharp 8.9 → 0.68 MB, icon font
RSS 22.5 → 13.9 MiB) but nothing installs it yet; and the default look's quick card spends most of its 48 ms rebuilding the
Paper frame's grain SVG per block (memoised in a scratch run: 21 ms). K68: core budget ≤ 150 MiB PSS at one output.

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; DECISIONS K68; BENCH "2026-10-25 — W39 block"; CONTRACT-CHANGE rows 445–447;
`nix/{icon-font.nix,icon-subset.py,icon-names.py,icon-names.txt}`, `nix/package.nix`, the HM and NixOS modules (font
defaults), `flake.nix` devShell, `crates/kurashi-theme/src/tokens.rs` (`font.icons`), `frontend/components/Icon.qml`,
`frontend/components/frames/Paper.qml`, `tools/bench/{block-identity.sh,quick-open.sh}`.

**Task:**
1. **Row 445:** the package installs the subset fonts (package.nix, HM + NixOS font defaults, the devShell's `XDG_DATA_DIRS`);
   `font.icons` prefers "Kurashi Symbols Sharp/Rounded" and falls back to Material Symbols. Pixel identity with
   `block-identity.sh` across kanso/sekai/glass/terminal/washi.
2. **Row 446:** a name missing from the subset never draws as text: Icon.qml falls back to the full Material Symbols family
   for that glyph (or a generic glyph if neither has it); a check (`cargo test` or a script in `just check`) that every icon
   name used in `frontend/`, `settings/` and bundled `mods/` is in `icon-names.txt`; mods may list extra names in their
   manifest (`icons = [...]`) which the subset build includes — or document that third-party mods fall back to the full font.
3. **Row 447:** memoise the grain tile in `frames/Paper.qml` (one per size/seed, shared); identity shots; quick card warm build
   before/after under washi with `quick-open.sh`.
4. `just bench-gate` back-to-back before/after pairs (W39's lesson: absolute PSS drifts by day); report PSS @1 output against 150.

**Owned paths:** `nix/**`, `flake.nix` (devShell env only), `crates/kurashi-theme/src/tokens.rs` (font token only) + goldens,
`frontend/components/{Icon.qml,frames/Paper.qml}`, `crates/kurashi-mods/src/manifest.rs` (an `icons` field only, if chosen),
`tools/bench/**`, `docs/BENCH.md` (append), a check script under `tools/`.

**Acceptance:** `nix build .#kurashid` and the frontend package build; identity 0 strong pixels; the icon-name check in `just check`;
quick card washi warm ≤ 25 ms; PSS pairs reported.

**Contract rows:** CONTRACT-CHANGE rows 455–459 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w41-icons CARGO_BUILD_JOBS=6`; sandbox names `w41-icons-…`;
the disk is nearly full — no extra target dirs. Model: haiku (max effort).
