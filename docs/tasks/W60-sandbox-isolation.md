# W60 — the sandbox holds no real data (I345)

Session 19. Common rules: `docs/tasks/README.md`. Model: Opus (test infra is shared by every suite). Run `just suites` before the merge.

## Why
The audit of committed screenshots (I345) found real data in them: the user's prompt and hostname from a terminal that
the niri style tests opened, the real /proc and ~/Pictures in `test-mods-live.sh`, and the installed-app list in every
launcher shot. Screenshots are no longer tracked (`**/shots/` is gitignored, history rewritten), but shots still get
reviewed, attached to PRs and shown in chats. Make the sandbox incapable of showing the user's data at all.

## Owned paths
`tools/bench/sandbox.sh`, `tools/bench/niri-sandbox.sh`, `frontend/test-lib.sh`, `frontend/test-mods-live.sh`, the
style/desk scenes that spawn a terminal (`frontend/test-styles.sh` and its helpers), new fixtures under `tools/fixtures/`
(apps, wallpapers, home).

## Build
- `sandbox.sh:106` keeps `HOME="$HOME"`: give the sandbox its own `HOME` under its runtime dir, with
  `XDG_{CONFIG,DATA,CACHE,STATE}_HOME` inside it. Keep exactly the variables tools need (nix profile `PATH`, the
  `NIX_*` ones), as a list in the script with a comment for each.
- `XDG_DATA_DIRS` pinned to a fixture `applications/` with ~15 made-up `.desktop` entries (Kura Alpha and similar, as in
  launcher/w26) plus the icon theme the shell ships. No real app list.
- `test-mods-live.sh`: sysmon on `KURASHI_SYSMON_ROOT` (the fixture `mods/sysmon/test-states.sh` uses), wallpaper on
  a fixture folder of generated gradients.
- Every terminal a scene spawns (foot, ghostty) starts with `env -i` and the fixture HOME, the shell `sh` and
  `PS1='kura@sandbox:~$ '`. No inherited prompt, cwd or worktree path.
- A guard in `test-lib.sh`: after each shot, fail when the image contains the user's hostname or `$USER@`, using `tesseract`
  if the dev shell has it. Without it, at least fail on a cwd under `$HOME/Projects` in any spawned process's environ.

## Acceptance
`just suites` green. Re-shoot `styles/{aqua,vibrancy,fluent}` desk scenes, `modslive/*` and a launcher scene. None of
them shows the user's name, host, apps, processes or pictures (the lead checks them). `grep -r "$HOME" /tmp/kurashi-sb-*/env*`
finds nothing outside the fixture.
