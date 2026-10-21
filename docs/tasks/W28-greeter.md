# Card W28-greeter — a greetd greeter in the shell's look (roadmap v0.3 "themed lockscreens"; DMS Greetd)

**User (session 10):** "get the desktop shell as complete and usable as possible … take actual code from DMS, Noctalia,
Caelestia, ii." The login screen is the first thing a user sees; it should be the lock screen's sibling.

**References:** DMS `…/scratchpad/insp/DankMaterialShell/quickshell/Modules/Greetd/**` (README, GreeterContent,
GreeterUserPicker, GreetdMemory, GreeterUserTheme — how it reads the user's theme without their session) and
`…/DankMaterialShell/distro/nix/**` (the NixOS greeter module); Quickshell 0.3.1 `Quickshell.Services.Greetd`.
(`…/scratchpad` = `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad`.)

**Read first:** `CLAUDE.md`; DECISIONS K15 (Nix), K42/K45/K50 (looks); `frontend/components/LockContent.qml`,
`frontend/surfaces/Lock.qml`, `nix/nixos-module.nix`, `nix/package.nix`, `docs/ux/` lock notes.

**Owned paths:** new `greeter/**` (its own small Quickshell config: `shell.qml`, a Theme reader of a cached theme JSON,
the greeter view reusing `frontend/components/LockContent.qml` pieces by import path where possible),
`nix/nixos-module.nix` (option `services.kurashi.greeter.enable` → greetd with `cage`/`niri`-less `quickshell` in a
minimal compositor, as DMS does), `nix/package.nix` (install `greeter/`), a theme cache written by kurashid —
**only** a small new module `crates/kurashid/src/greeter_cache.rs` + one registration line: on theme change, write
`$XDG_STATE_HOME/kurashi/greeter-theme.json` (tokens + wallpaper path) and, when the greeter option asks, a copy to a
world-readable path the greeter user may read (`/var/lib/kurashi-greeter/<user>.json`, via the HM/NixOS module's
tmpfiles), `docs/ux/greeter.md`, `i18n/{en,ja}/greeter.toml`, a test `greeter/test.sh`. Contract rows ≥ 210. Sandbox
names `w28-grt-`.

**Do:** users (from AccountsService or /etc/passwd ≥ 1000), sessions (`/run/current-system/sw/share/wayland-sessions`,
`/usr/share/wayland-sessions`), last user/session remembered (DMS GreetdMemory), password via greetd's
auth_message/response, errors and retries, power keys (suspend/reboot/poweroff via logind), the keycap clock and
backdrop of the last user's look (cached theme), keyboard-first. **Testing without a real greetd:** run the greeter
in the sandbox against a fake greetd socket (a small python server speaking the greetd JSON IPC) — never install or
start greetd on the machine, never touch /etc.

**Acceptance:** `greeter/test.sh` (fake greetd: wrong password → message, right one → `start_session` with the chosen
session's command), shots under sekai and none; `nix build .#kurashi` and an eval check of the NixOS option (no
activation). Report (terse).
