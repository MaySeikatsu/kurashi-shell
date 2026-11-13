# W86 — Work sessions: a first-party plugin over noren (session 33, I517; Opus)

**The user (session 33):** a project's whole working state saved and restored as one — "make this feature a highly integrated
first party plugin. noren isn't very popular yet and people might not benefit without it, so it should be a plugin." After
choosing a session it **asks where to open it**: the default terminal window, **in the shell** (the terminal mod's drop-down,
W83/W85), or **another installed terminal**. Home-Manager ships noren and its dependencies **only when an option is on —
off by default**. Polished and native, as everything else.
**noren** (github.com/MaySeikatsu/noren, the user's; a flake; Rust; needs zellij, zoxide, fzf, git, eza on PATH):
`noren list [zellij|zoxide|config|all|hidden]` prints tab-separated `kind  name  path  state  display`
(e.g. `zellij  kurashi  /home/…/kurashi-shell  exited  ⊗ kurashi`), `noren resolve <target> --format json`,
`noren connect <name-or-path>` (attach/create/resurrect), `noren snapshot [name]` / `snapshots` / `restore`, `noren pin`,
`noren window`. Read its README for the rest; never write to its config.
**The plugin** (mod `sessions`, native like the terminal; manifest `requires` noren on PATH — without it the mod is
offered but inert with the reason and a pointer to the HM option, Shōjiki):
1. **Launcher** (K150 provider, no prefix by default; an optional prefix setting): noren's sessions and folders as rows (name,
   path, state: running/exited/pinned, the icon), ranked with the launcher's frecency; Enter opens the **"Open in…" step**
   inside the launcher: *In Kurashi* (the terminal mod: a new tab in the drop-down, attached via `noren connect`),
   *Terminal window* (the default terminal, `launcher.terminal`), and each other installed terminal found on PATH (foot,
   kitty, ghostty, alacritty, wezterm, konsole, gnome-terminal…); a setting picks a default (`ask` by default) and the step
   remembers the last choice per project if the user ticks it.
2. **The desk with it** (the "work session"): per project (keyed by noren's path), a snapshot of the desk — the niri workspace,
   the windows (app id, title, column, width, floating rect) through the compositor adapter, the web dock's open pages and
   the terminal mod's tabs — saved by "Save desk as project" (launcher row, desktop right-click menu row, a key) and
   restored on open (launch what is missing, place what is there; never kill windows). Restoring is a choice per project
   (terminal only / terminal + desk).
3. **Glances**: a bar module (current project, a click lists sessions), a sidebar section (sessions with state, pin, kill,
   snapshot), the right-click menus' "Open project…".
4. **Home-Manager**: `programs.kurashi.sessions.enable` (default **false**) — enables the mod and ships noren (flake input
   `github:MaySeikatsu/noren`, follows nixpkgs) with zellij, zoxide, fzf, git, eza on the daemon's PATH and in
   `home.packages`; `programs.kurashi.sessions.package` to override. Nothing of it without the option.
**Steps.** UX brief `docs/ux/sessions.md` first (tmux/zellij session pickers, sesh, JetBrains/VS Code "recent projects",
macOS Stage Manager sets, GNOME Workspaces' saved sessions, KDE Activities; states: no noren, noren but no sessions, a
missing path, a session already attached elsewhere, a terminal not installed; keyboard, a11y, Ma, multi-output) → the mod
(daemon crate, launcher provider, actions, document) → the "Open in…" step → the desk snapshot → glances → HM.
**Owned paths.** `crates/kurashi-mod-sessions/**`, `mods/sessions/**`, `docs/ux/sessions.md`, i18n `mod-sessions*`,
`nix/hm-module.nix` (the `sessions` options only), `flake.nix` (the noren input and its package line only),
`crates/kurashi-compositor` read-only (window listing/placement: CONTRACT-CHANGE row for anything missing).
**Acceptance.** `mods/sessions/test/test-sessions.sh` on nested niri with a stub `noren` on PATH (prints fixed `list` lines,
logs `connect`): the launcher lists the sessions; Enter → "Open in…" with the in-shell terminal and a stub terminal;
choosing in-shell opens the drop-down with `noren connect kurashi` run; save desk → restore places a test window back; the
mod without noren says why; `nix/tests/sessions-eval.nix` (the HM option off ships nothing, on ships noren).
**Build dir** `~/.cache/kurashi-agents-target/w86`.
