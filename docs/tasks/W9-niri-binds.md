# Card W9-niri-binds — compositor keybindings for kurashi actions (I8)

**Read first:** `docs/tasks/README.md`, `docs/BACKLOG.md` row I8, `README.md` ("Running", "Command line"),
`nix/hm-module.nix`, `nix/tests/` (+ `just nix-eval-test`), `docs/PROTOCOL.md` §8 (action ids),
niri wiki on binds and `spawn` (https://github.com/YaLTeR/niri/wiki/Configuration:-Key-Bindings) and on
config includes (check whether the niri version in nixpkgs supports `include`; if not, say so).

**Problem:** without compositor binds the shell is mouse/CLI only. Actions exist: `launcher.toggle`,
`notifications.center`, `session.menu`, `session.lock`, `audio.volume.up`, `audio.volume.down`,
`audio.mute.toggle`, `brightness.up`, `brightness.down` (`kurashi act <id>`).

**Owned paths:** `README.md` (a new "Keybindings (niri)" subsection under Running only), `nix/hm-module.nix`,
`nix/tests/**`, `docs/niri-binds.kdl` (new, the copy-paste snippet). NOT crates, frontend, flake.nix.

**Do:** (1) `docs/niri-binds.kdl`: a ready snippet, e.g. `Mod+Space { spawn "kurashi" "act" "launcher.toggle"; }`,
`Mod+N` centre, `Mod+Escape` session menu, `Super+Alt+L` lock, `XF86Audio*` and `XF86MonBrightness*` with
`allow-when-locked=true` (volume/brightness only); comment each line; mention that they replace niri's
defaults for the same keys. (2) README subsection: how to include/copy it, and that `kurashi act` needs
the daemon running. (3) HM: `programs.kurashi.niri.binds.enable` (default false) writes the snippet to
`~/.config/niri/kurashi-binds.kdl` (with the package's `kurashi` store path in `spawn`), plus
`programs.kurashi.niri.binds.keys` (attrs key → action id, defaults as above) to change keys; the
description tells the user to add `include "kurashi-binds.kdl"` to their niri config (or, if niri lacks
include, to paste it). No change unless enabled.

**Acceptance:** `nix develop -c just nix-eval-test` passes with a new eval case: enabled → the generated
file contains `spawn "<store>/bin/kurashi" "act" "launcher.toggle"` for `Mod+Space`; a custom
`keys."Mod+L" = "session.lock"` appears; disabled → no file. If niri is in the devShell/nixpkgs, also
`niri validate -c <tmp config that includes the generated file>` passes (else say so in the report).
