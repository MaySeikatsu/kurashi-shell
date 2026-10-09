# Card M7-nix-modules — NixOS + Home-Manager modules run the shell

**Goal.** `programs.kurashi.enable = true;` in Home-Manager gives a working session: `kurashid`
and the Quickshell frontend as systemd **user** services bound to the graphical session, the
managed settings layer (K15), and nothing that touches a session where it isn't enabled.

**Owned paths:** `nix/hm-module.nix`, `nix/nixos-module.nix`, `nix/tests/` (new). Common rules:
`docs/tasks/README.md`.

**Read:** both module files, `nix/package.nix` (read-only; the package ships
`share/kurashi/{i18n,palettes,frontend}`), `docs/DECISIONS.md` K11 + K15, `docs/ARCHITECTURE.md` §9,
`frontend/README.md` (how the frontend is launched: `qs -p <dir>`).

**Build:**
1. HM: `kurashid.service` (Type=simple, `After`/`PartOf`/`WantedBy` `graphical-session.target`,
   restart on failure with backoff, `KURASHI_DATA_DIR` unset — the binary knows its prefix) and
   `kurashi-frontend.service` (`qs -p ${pkg}/share/kurashi/frontend`, `After=kurashid.service`,
   `Requires` not `BindsTo` so a daemon restart doesn't kill the frontend — it reconnects).
   Options: `enable`, `package`, `frontend.enable`, `frontend.package` (quickshell),
   `settings` (→ `managed.toml`, K15), `enforce` (→ `_managed.enforce = true`), `extraEnvironment`.
2. NixOS: system-level bits only (e.g. `services.upower.enable` suggestions via `mkDefault`,
   polkit rule for brightness via logind, `environment.systemPackages`) — keep it minimal and
   documented; no user services here.
3. `nix/tests/hm-eval.nix`: an evaluation test that builds the HM activation package for a test
   user with the module enabled and asserts the unit files contain the expected `ExecStart` /
   targets; wire it into `flake.nix` `checks` **only via a CONTRACT-CHANGE row** (flake.nix is
   not yours) — or expose it so `nix build -f nix/tests/hm-eval.nix` works standalone.
4. Never enable or start these units on this machine.

**Acceptance (one command):** `nix build --no-link -f nix/tests/hm-eval.nix` (or the equivalent
you document) succeeds and its assertions pass; `nix flake check --no-build` still evaluates.
