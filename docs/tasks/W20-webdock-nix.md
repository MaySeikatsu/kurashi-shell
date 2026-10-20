# Card W20-webdock-nix — the web host as its own package, Home-Manager/NixOS options, `Mod+B` (W17.6; K38, K39, K40)

**Decision (user, sessions 7–8):** the web engine never enters the base closure: `kurashi` stays free of QtWebEngine,
and `kurashi-webdock` (the patched Quickshell `qs-webengine`, K39) is installed only when the user turns the dock on.
Home-Manager sets the pins (they show as forced in Settings, K15) and binds `Mod+B` to `webdock.toggle` (K40).
**Brief:** `docs/ux/webdock.md` ("Implementation steps" 5, "States" → Unavailable: host not installed).

**Read first:** `docs/tasks/README.md` (rules), DECISIONS K38, K39, K40, K15, MODS.md "Web dock" (settings, `pins`
records) and "Host processes" (PATH lookup, `Missing`), `flake.nix`, `nix/{quickshell-webengine.nix,hm-module.nix,nixos-module.nix,package.nix}`
(read-only for package.nix), `nix/tests/`, `docs/niri-binds.kdl`, README "Keybindings", `mods/webdock/mod.toml`.

**Owned paths:** new `nix/webdock.nix`, `flake.nix` (only the `packages`/`checks` entries for the web dock),
`nix/hm-module.nix`, `nix/nixos-module.nix`, `nix/tests/**`, `docs/niri-binds.kdl`, README "Keybindings"
subsection. **Not yours: `nix/package.nix`** (it has another session's uncommitted change — do not touch or format
it), `nix/quickshell-webengine.nix` (read-only; wrap it), `crates/**`, `mods/**`.

**Do:**
1. `packages.kurashi-webdock` (`nix/webdock.nix`): `qs-webengine` on PATH plus what the host needs at run time;
   `packages.kurashi` unchanged. A check that the base closure has no QtWebEngine
   (`nix path-info -r` of `kurashi` has no `qtwebengine`) and the web dock's does.
2. Make sure the installed `kurashi` carries `mods/webdock/host/` with a working `core` link (the link points into
   `frontend/core` of the same output); if it does not, report it (package.nix is not yours) with the fix.
3. Home-Manager `programs.kurashi.webdock = { enable; package; pins; edge; … }`: `enable` adds the package to
   `home.packages` and turns the mod on in the config kurashi reads; `pins` (a list of submodules matching the
   `pins` records: `id`, `title`, `target`, `view`, `profile`, `icon`) and any other option write the mod's settings
   in the Nix (forced) layer, like the existing options do. `keybind` (default `"Mod+B"`, `null` = none) adds the niri
   bind that runs `webdock.toggle` through the `kurashi` CLI (check the CLI's exact syntax in `crates/kurashi`).
   NixOS option parity where the existing module mirrors HM.
4. `docs/niri-binds.kdl` + README: the `Mod+B` line and the option names.

**Acceptance:** `nix build .#kurashi-webdock` and `nix build .#kurashi` succeed; the closure check passes (and fails
when you point it at the web dock's closure, to prove it can); the HM/NixOS module eval tests in `nix/tests/` cover
`webdock.enable` on/off, a pin list and `keybind = null` (`nix flake check` or the repo's module-test command, wrapped
in `timeout`). Report the closure sizes of both packages.
