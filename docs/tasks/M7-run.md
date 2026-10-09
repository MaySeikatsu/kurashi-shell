# Card M7-run — `nix run` launchers + "Running" docs

**Goal.** One-command ways to run the shell, and one place that explains all of them.

**Owned paths:** `flake.nix` (add an `apps` output only), new `nix/apps.nix`, `README.md`.
Common rules: `docs/tasks/README.md`.

**Read:** `flake.nix`, `nix/package.nix`, `nix/hm-module.nix`, `nix/nixos-module.nix`, `justfile`,
`frontend/launch.sh`, `frontend/test-real.sh`, `frontend/README.md`, `settings/test.sh` (header).

**Build (`nix/apps.nix`, `writeShellApplication`, all runtime deps in `runtimeInputs`):**
| app | does |
|---|---|
| `default` (`nix run .#`) | live session: start `kurashid` from the package unless a daemon already answers on the socket (`kurashi ping`), then `exec` the package's `share/kurashi/frontend/launch.sh` with `KURASHI_QS` = quickshell's `qs`; stop the daemon it started on exit (trap) |
| `settings` | `qs -p <pkg>/share/kurashi/settings` against the running daemon |
| `mock` | `kurashi-mock` |
| `sandbox` | invisible real-stack smoke test: runs `frontend/test-real.sh` semantics using the package binaries (needs sway, grim, dbus in `runtimeInputs`); screenshots into `./shots-sandbox/` of the CWD |

`README.md` "Running" section: the four ways (sandbox test, live from repo via `nix develop`,
`nix run` apps, NixOS + Home-Manager options incl. `programs.kurashi.{enable,systemd.enable,frontend.enable,settings,enforce}`),
the useful `kurashi` CLI commands (`doctor`, `act …`, `sub …`, `cfg …`), and the warning that the
lock screen needs the NixOS module's PAM service.

**Safety:** NEVER run `nix run .#`, `.#settings` or anything that opens a window on the user's display.
Verify `default`/`settings` with `nix build .#apps…` equivalents (`nix eval .#apps.x86_64-linux.default.program`
+ `nix build` of the script derivation) and `shellcheck` (writeShellApplication runs it).

**Acceptance:** `nix flake check --no-build` passes; `nix run .#sandbox` exits 0 and writes screenshots
(Read one to check); `nix run .#mock -- --help` exits 0.
