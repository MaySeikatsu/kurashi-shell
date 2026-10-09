# Subagent task cards

One card per delegated task (`CLAUDE.md` → "Subagent task cards"). The lead spawns, reviews,
merges, and records progress; agents only build what their card says.

## Common rules (every card includes these)
1. **Ownership.** Edit only the paths your card owns. Everything else is read-only. Never edit
   `Cargo.toml` at the repo root (members are a glob, `crates/*`), `docs/PROGRESS.md`,
   `docs/HANDOVER.md` or another card's paths. Declare new dependencies in **your crate's own**
   `Cargo.toml` (you may reuse existing `[workspace.dependencies]` with `x.workspace = true`).
   Committing the changed root `Cargo.lock` is fine; the lead resolves lock conflicts at merge.
2. **Frozen contracts.** `crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`,
   `crates/kurashi-core` are read-only. If you need a change there (or any doc/shape outside your
   paths), append a row to `docs/CONTRACT-CHANGE.md` (that file is the one shared exception) and
   code against a local stand-in until the lead decides.
3. **Builds wait for each other (shared machine).** Before any cargo command:
   `export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target CARGO_BUILD_JOBS=8`.
   All agents share this dir, so cargo's build lock makes builds take turns ("Blocking waiting for
   file lock" is expected, just wait). Never `cargo run` long-lived binaries (it can hold the
   lock): build, then run `$CARGO_TARGET_DIR/debug/<bin>` directly. Prefer `cargo test -p <crate>`
   and `cargo clippy -p <crate>` over workspace-wide commands. No `cargo clean`.
   **Binaries in the shared dir are overwritten by other worktrees** (`debug/<bin>` is not
   path-hashed): build and copy in one step (`cargo build -p x && cp $CARGO_TARGET_DIR/debug/x
   <your-dir>/`) and run the copy.
4. **Tools come from `nix develop`** (repo root). Run commands as `nix develop -c <cmd>` or inside
   one shell. Flakes only see git-tracked files: `git add` new files before any `nix` command.
5. **Never touch the user's session.** No GUI on the real display; use `tools/bench/sandbox.sh`
   (fails closed since 61d76fa) and only your own sandbox name. Kill only PIDs you started; never
   `pkill`/`killall`. Reading state from the live compositor is allowed only if your card says so,
   and then strictly read-only. Running `kurashid` yourself: isolated `XDG_CONFIG_HOME`,
   `XDG_STATE_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `KURASHI_SOCKET` **and** the sandbox's
   `DBUS_SESSION_BUS_ADDRESS` (the daemon exports a notification server on the session bus).
6. **Quality bar.** `cargo fmt`, `cargo clippy -p <crate> --all-targets -- -D warnings`, tests
   green, `[lints] workspace = true` in every new crate. Code identifiers English; user-facing
   strings only via i18n keys. Comment density like the existing crates (sparse, explain why;
   cite K-ids for non-obvious choices).
7. **Commits** on your worktree branch, conventional messages (`feat(<area>): …`), **no AI
   attribution / Co-Authored-By lines**.
8. **No report files** (your tools refuse them). Your final message is the report, exactly:
   ```
   branch: <name> · sha: <HEAD>
   acceptance: <command> → <result>
   done: <bullets>
   not done / deviations: <bullets or none>
   contract requests: <CONTRACT-CHANGE row #s or none>
   integration notes for the lead: <how kurashid should wire this, ≤5 bullets>
   ```
9. **Token thrift.** Read your card, the files it lists, and the code you need. Don't survey the
   repo. Time-box anything blocked; report it instead.

## Wave 1 (2026-10-09, session 2)
| Card | Owner paths | Model |
|---|---|---|
| [M1-schema](M1-schema.md) | `crates/kurashi-schema/`, `crates/kurashi-schema-derive/` | opus |
| [M1-config](M1-config.md) | `crates/kurashi-config/` | opus |
| [M4-compositor](M4-compositor.md) | `crates/kurashi-compositor/` | sonnet |
| [M2-theme](M2-theme.md) | `crates/kurashi-theme/`, `palettes/` | sonnet |
| [M1.5-frontend](M1.5-frontend.md) | `frontend/` | sonnet |
| [M4-services](M4-services.md) | `crates/kurashi-services/` | sonnet (wave 2) |
| [M5-island](M5-island.md) | `crates/kurashi-island/` | sonnet (wave 2) |
| [M3-stage](M3-stage.md) | `frontend/` | sonnet (wave 2) |
| [M6-mods](M6-mods.md) | `crates/kurashi-mods/`, `mods/` | sonnet (wave 2) |

## Wave 3 (2026-10-09, session 2)
| Card | Owner paths | Model |
|---|---|---|
| [M4-audio](M4-audio.md) | `crates/kurashi-audio/`, `nix/package.nix` | sonnet |
| [M7-nix-modules](M7-nix-modules.md) | `nix/hm-module.nix`, `nix/nixos-module.nix`, `nix/tests/` | sonnet |
| [M5-notifications](M5-notifications.md) | `crates/kurashi-notify/` | sonnet |
| [M5-launcher](M5-launcher.md) | `crates/kurashi-launcher/` | sonnet |
| [M1-cli](M1-cli.md) | `crates/kurashi/` | sonnet (wave 3b) |
| [M1.5-frontend-core](M1.5-frontend-core.md) | `frontend/core/`, `frontend/shell.qml`, … | sonnet (wave 4) |
| [M7-doctor](M7-doctor.md) | `crates/kurashid/src/doctor.rs`, `crates/kurashi/src/`, `i18n/*/doctor.toml` | sonnet (wave 4) |
| [M7-bench](M7-bench.md) | `tools/bench/` | sonnet (wave 4) |
| [M5-auth](M5-auth.md) | `crates/kurashi-auth/` | sonnet (wave 4) |
| [M5-settings](M5-settings.md) | `settings/`, `i18n/{en,ja}/settings.toml` | sonnet (wave 3b) |
Lead (in parallel): config/schema wiring into kurashid (M1.5), theme + notify wiring.

Lead (wave 1–2): protocol v1 completion in `kurashi-ipc` / `kurashid` / `kurashi-mock` / CLI.

## Wave 5 (UI, after frontend-core)
| Card | Owner paths | Model |
|---|---|---|
| [M5-ui-island-faces](M5-ui-island-faces.md) | `frontend/components/Island.qml`, `frontend/components/faces/` | sonnet |
| [M5-ui-notifications](M5-ui-notifications.md) | `frontend/surfaces/{Toasts,NotificationCenter}.qml` | sonnet |
| [M5-ui-launcher](M5-ui-launcher.md) | `frontend/surfaces/Launcher.qml` | sonnet |
| [M5-ui-lock](M5-ui-lock.md) | `frontend/surfaces/Lock.qml` | sonnet |

