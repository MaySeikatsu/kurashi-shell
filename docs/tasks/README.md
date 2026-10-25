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
3. **One build dir per card (B23, session 6).** Before any cargo command:
   `export CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/<card-name> CARGO_BUILD_JOBS=8`.
   A shared dir handed worktrees each other's builds of path crates (cargo's artifact names do not depend on
   the checkout path): agents tested stale daemons, and one reached a real web service. Your own dir avoids
   that; the lead deletes it after the merge (disk is limited — no `cargo clean`, no extra target dirs).
   Never `cargo run` long-lived binaries: build, then run `$CARGO_TARGET_DIR/debug/<bin>` directly. Prefer
   `cargo test -p <crate>` and `cargo clippy -p <crate>` over workspace-wide commands. If a result still
   contradicts your source, grep the binary for a string you added before trusting it.
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
8. **No report files** (your tools refuse them). Bugs or ideas you notice outside your card go into your
   report under "not done / deviations"; the lead files them in `docs/BACKLOG.md`. Your final message is the report, exactly:
   ```
   branch: <name> · sha: <HEAD>
   acceptance: <command> → <result>
   done: <bullets>
   not done / deviations: <bullets or none>
   contract requests: <CONTRACT-CHANGE row #s or none>
   integration notes for the lead: <how kurashid should wire this, ≤5 bullets>
   ```
9. **Never hang.** Wrap every test/run in `timeout` (`timeout 600 cargo test …`) and use
   `set -o pipefail` when piping into `tail`/`grep`, so a deadlock or failure surfaces in minutes
   (a test once hung 4.5 h unnoticed; a piped failure once got committed).
10. **UX bar.** A user-facing card cites its UX brief (`docs/ux/<feature>.md`) and meets that brief's definition
   of done, not just the function: every state the brief lists (empty, loading, error, offline, unavailable,
   forced) is drawn and screenshotted, keyboard paths work, a11y names exist, motion follows DESIGN-SYSTEM §9.
   Your report lists each definition-of-done item as met / not met.
11. **Token thrift.** Read your card, the files it lists, and the code you need. Don't survey the
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

## Wave 6 (memory first; daemon tasks in disjoint files, none edits `main.rs`)
| Card | Owner paths | Model |
|---|---|---|
| [M3-memory](M3-memory.md) | `frontend/`, `tools/bench/` | sonnet |
| [M2-blur-capability](M2-blur-capability.md) | `crates/kurashi-compositor/`, `kurashid/src/capabilities.rs` | sonnet |
| [M5-island-config](M5-island-config.md) | `kurashid/src/{island,bindings}.rs`, `crates/kurashi-island/` | sonnet |
| [M5-daemon-polish](M5-daemon-polish.md) | `kurashid/src/{wiring,doctor}.rs` | sonnet |


## Wave 7 (Haiku agents, max effort; up to 10 in parallel)
| Card | Owner paths | Model |
|---|---|---|
| [M5-osd-session-daemon](M5-osd-session-daemon.md) | `kurashid/src/{wiring,main,island}.rs`, `kurashi-services/src/brightness.rs`, `kurashi-auth/` | haiku |
| [M5-ui-session](M5-ui-session.md) | `frontend/surfaces/{SessionMenu,Stage}.qml`, faces `BrightnessFace`, `frontend.toml` | haiku |
| [M5-ui-bindings](M5-ui-bindings.md) | `frontend/components/Island.qml`, `frontend/surfaces/Bar.qml`, `frontend/core/` | haiku |
| [M7-run](M7-run.md) | `flake.nix` (apps), `nix/apps.nix`, `README.md` | haiku |
| [M4-tray](M4-tray.md) | `crates/kurashi-tray/` (new) | haiku |
| [M4-bluetooth](M4-bluetooth.md) | `kurashi-services/src/bluetooth.rs` (new) | haiku |
| [M5-settings-search-mods](M5-settings-search-mods.md) | `settings/`, `settings.toml` | haiku |
| [M0-mock-parity](M0-mock-parity.md) | `crates/kurashi-mock/` | haiku |
| [M5-honesty](M5-honesty.md) | `kurashid/tests/honesty.rs` (new) | haiku |
| [R-daemon-review](R-daemon-review.md) | read-only | haiku |
| [M1-inert-reasons](M1-inert-reasons.md) | `kurashi-core` Provenanced (K21), `kurashid/src/config.rs`, honesty test, `settings/core/` | haiku |
| [F-hub-server](F-hub-server.md) | `kurashid/src/{hub,server,clock,workspaces,services}.rs` | haiku |
| [F-notify](F-notify.md) | `crates/kurashi-notify/` | haiku |
| [F-watch-services](F-watch-services.md) | launcher `watch.rs`, services `{media,session,network,power,util}.rs` | haiku |
| [M6-mod-description](M6-mod-description.md) | `crates/kurashi-mods/`, `mods/*/mod.toml`, `mods.toml`, `ModsPage.qml` | haiku |
| [M0-mock-notify](M0-mock-notify.md) | `crates/kurashi-mock/` | haiku |
| [M3-golden](M3-golden.md) | `tools/golden/` | haiku |
| [M4-wire-tray-bt](M4-wire-tray-bt.md) | `kurashid/src/{main,wiring,doctor}.rs`, `kurashi-tray/`, `kurashi-auth/` | haiku |
| [M6-mod-settings](M6-mod-settings.md) | `kurashid/src/config.rs`, `kurashi-mods/`, `settings/` (K22) | haiku |
| [F-services-available](F-services-available.md) | services `{session,media,power,util}.rs`, MediaFace | haiku |
| [R-ux-review](R-ux-review.md) | read-only | haiku |
| [U-components](U-components.md) | `frontend/core/Theme.qml`, `frontend/components/**`, kurashi-theme `stages.rs` | haiku |
| [U-surfaces](U-surfaces.md) | `frontend/surfaces/**`, `shell.qml`, `surfaces.toml` | haiku |

## Wave 8 (session 4, machine B; Haiku agents, max effort; after the machine-B baseline)
| Card | Owner paths | Model |
|---|---|---|
| [S-settings-polish](S-settings-polish.md) | `settings/**`, `i18n/*/settings.toml` | haiku |
| [B-tray-bluetooth](B-tray-bluetooth.md) | `frontend/surfaces/{Bar,Stage}.qml`, `shell.qml`, Island hit area, new tray/BT components, `kurashi-mock`, golden bus isolation | haiku |
| [C-services](C-services.md) | `kurashid/src/{services,wiring(service parts),main(providers)}.rs`, `kurashi-services/src/util.rs`, `kurashi-tray` handle | haiku |
| [L-logind](L-logind.md) | `kurashi-services/src/session.rs` + its tests | haiku |
| [C-mod-sections](C-mod-sections.md) | `crates/kurashi-config/` | haiku |
| [K-hybrid-egl](K-hybrid-egl.md) | `frontend/launch.sh`, `frontend/test-launch.sh`, nix runtime deps | haiku |
Lead (before the wave): K23 tray menu panel (`tray.menu.open`, `runtime.ui.tray`) in kurashid + mock.

## Wave 9 (session 5, machine B; Haiku 5.5 agents, max effort) — the fix wave
| Card | Owner paths | Model |
|---|---|---|
| [W9-bar-volume](W9-bar-volume.md) | Bar slider blocks, `components/Slider.qml`, `frontend.toml`, `frontend/test-volume.sh` | haiku |
| [W9-brightness-session](W9-brightness-session.md) | `kurashi-services/src/{brightness,session}.rs` + tests | haiku |
| [W9-tray](W9-tray.md) | `crates/kurashi-tray/**` | haiku |
| [W9-config-profiles](W9-config-profiles.md) | `kurashid/src/config.rs`, `kurashi-config/`, `config.toml`, `settings/**` (not keys.py), `settings.toml` | haiku |
| [W9-test-helpers](W9-test-helpers.md) | `tools/bench/wl_{keys,pointer}.py`, `frontend/test-{bindings,tray-bt}.sh` | haiku |
| [W9-niri-binds](W9-niri-binds.md) | `README.md` keybindings subsection, `nix/hm-module.nix`, `nix/tests/`, `docs/niri-binds.kdl` | haiku |
Lead (before the wave): contract rows 20–22 (fixtures, mock, PROTOCOL, K27); K24–K26 recorded; B7 per-output PSS.

## Wave 10 (session 5, after wave 9 merges; Haiku 5.5, max effort)
| Card | Owner paths | Model |
|---|---|---|
| [W10-stage-panels](W10-stage-panels.md) | `Stage.qml`, `components/expanded/**`, `QuickPanel.qml`, `BluetoothPanel.qml`, `island.toml` | haiku |
| [W10-bar-quick](W10-bar-quick.md) | Bar right row (one item), `QuickButton.qml`, `frontend.toml` | haiku |
| [W10-mods-daemon](W10-mods-daemon.md) | `kurashi-mods/**`, kurashid `config.rs`/`wiring.rs` mods parts, `kurashi-theme` status tokens | haiku |
| [W10-settings](W10-settings.md) | `settings/**`, `settings.toml` | haiku |
Lead (before): K24 `runtime.ui.face` + `quick.toggle` (daemon + mock, done), K25/K26/I9 contracts (docs + fixture),
I9 schema attribute `choices_from` in kurashi-schema.

## Wave 11 (after wave 10; Haiku 5.5, max effort) — K26 native mods, then the wallpaper mod
| Card | Owner paths | Model |
|---|---|---|
| [W11-native-mods](W11-native-mods.md) | new `kurashi-mod-api`, kurashid `native.rs` + runtime unregister in hub/actions, test mod `hello` | haiku |
| [W11-mod-qml](W11-mod-qml.md) | `frontend/core/ModLoader.qml`, Stage `mod:*` panel, Bar mod widget slot (after W11-native-mods) | haiku |
Then: W12-wallpaper (crate `kurashi-mod-wallpaper`, awww/swww adapters, picker panel) on that mechanism.
Lead (before W11-mod-qml): PROTOCOL §8 `mod.panel.open {id, panel}` → `runtime.ui.panel = "mod:<id>:<panel>"`.

## Wave 12 (session 5; M6 native mods + M7 quick settings; Haiku 5.5, max effort) — after W11-native-mods
| Card | Owner paths | Model |
|---|---|---|
| [W11-mod-qml](W11-mod-qml.md) | `frontend/core/ModLoader.qml`, `SlotHost.qml`, Stage `mod:*` loader, slot hosts in expanded views, mod faces in Island, Bar mod widget slot | haiku |
| [W12-mod-hooks](W12-mod-hooks.md) | `kurashi-mod-api`, kurashid `native.rs`/`island.rs`, manifest kinds, `runtime.slots`, `mod.panel.open`, mock parity (K28) | haiku |
| [W12-wallpaper](W12-wallpaper.md) | `crates/kurashi-mod-wallpaper/**`, `mods/wallpaper/**`, `mod-wallpaper.toml` | haiku |
| [W12-sysmon](W12-sysmon.md) | `crates/kurashi-mod-sysmon/**`, `mods/sysmon/**`, `mod-sysmon.toml` | haiku |
| [W12-weather](W12-weather.md) | `crates/kurashi-mod-weather/**`, `mods/weather/**`, `mod-weather.toml` | haiku |
| [W12-quick-daemon](W12-quick-daemon.md) | kurashid audio/network actions, `network.rs`, mock parity | haiku |
| [W12-quick-ui](W12-quick-ui.md) | `QuickPanel.qml`, `components/quick/**`, Slider clamp (B12) | haiku |
Mod cards each add one line to `kurashid/Cargo.toml` + `main.rs` (lead resolves the trivial conflicts).
Lead (before): `mod.panel.open` in kurashid + mock; PROTOCOL §8 `audio.sink.default`, `network.wifi`.

## Wave 13 (session 5; UX passes from `docs/ux/`; Haiku 5.5, max effort)
| Card | Owner paths | Model |
|---|---|---|
| [W13-settings-ux](W13-settings-ux.md) | `settings/**`, `settings.toml` | haiku |
| [W13-quick-daemon](W13-quick-daemon.md) | network/power/audio/notify services + kurashid blocks + mock parity | haiku |
| [W13-quick-ux](W13-quick-ux.md) (after W11-mod-qml + W13-quick-daemon) | `QuickPanel.qml`, `components/quick/**` — drill-down pages, status sentence, footer | haiku |
| [W13-island-daemon](W13-island-daemon.md) (after W12-mod-hooks) | arbiter secondary/overflow/stale_at, core transient signals | haiku |
| [W13-media-position](W13-media-position.md) | svc.media position/rate/can/players + seek/select actions, mock | haiku |
| [W13-island-views](W13-island-views.md) (after W11-mod-qml + W13-island-daemon) | `components/expanded/**` to `docs/ux/island.md` | haiku |

## Wave 14 (session 5; mod runtime follow-ups, mod UX passes, live all-mods test; Haiku 5.5, max effort)
| Card | Owner paths | Model |
|---|---|---|
| [W14-mod-runtime](W14-mod-runtime.md) | mod-api, kurashi-mods, native.rs, mods part of wiring.rs, adoption lines in the mods | haiku |
| [W14-mods-live](W14-mods-live.md) | `frontend/test-mods-live.sh`, kurashid `test-mods` feature, hello test data | haiku |
| [W14-sysmon-ux](W14-sysmon-ux.md) | sysmon crate + `mods/sysmon` | haiku |
| [W14-wallpaper-ux](W14-wallpaper-ux.md) | wallpaper crate + `mods/wallpaper`, kurashi-theme (wallpaper source, warn role) | haiku |
| [W14-settings-daemon](W14-settings-daemon.md) | profile export/import, `kurashi settings`, `settings.open`, face labels, wl_keys modifiers | haiku |
| [W14-weather-ux](W14-weather-ux.md) | weather crate + `mods/weather` | haiku |

## Wave 15 (2026-10-18, session 6)
| Card | Owner paths | Model |
|---|---|---|
| [W15-profiles](W15-profiles.md) | `crates/kurashi-config/`, kurashid profile actions, `settings/pages/ProfilesPage.qml` | haiku (max) |
| [W15-job-active](W15-job-active.md) | `crates/kurashi-mod-api/`, kurashid `native.rs`, settings mod head | haiku (max) |
| [W15-quick-island-polish](W15-quick-island-polish.md) | quick settings components, VolumeFace, Stage views map, shell.qml `want` | haiku (max) |
| [W15-sysmon-fixes](W15-sysmon-fixes.md) | `crates/kurashi-mod-sysmon/` (not `watch()`), `mods/sysmon/` | haiku (max) |

## Wave 16 (session 6, after wave 15 merges)
| Card | Owner paths | Model |
|---|---|---|
| [W16-peek-frontend](W16-peek-frontend.md) | Stage.qml, Bar.qml hover plumbing, tray/island peeks, sysmon/weather/hello Peek.qml | haiku (max) |
| [W16-test-infra](W16-test-infra.md) | `tools/bench/sandbox.sh`, `crates/kurashi-mock/`, `crates/kurashi-mod-wallpaper/`, test-stage B14 step | haiku (max) |

## Wave 17 (session 7; web dock, K38/K39; contract on main e077403)
| Card | Owner paths | Model |
|---|---|---|
| [W17-webdock-host](W17-webdock-host.md) | `mods/webdock/{host,test,shots}/`, `crates/kurashi-mock/`, `frontend/core/Store.qml` (scoped hello), `i18n/*/mod-webdock.toml` | haiku (max) |
| [W17-webdock-daemon](W17-webdock-daemon.md) | `crates/kurashi-mod-api/`, kurashid `{native,server,main}.rs` + Cargo.toml, new `crates/kurashi-mod-webdock/`, `mods/webdock/mod.toml` | haiku (max) |
| [W17-records](W17-records.md) | `crates/kurashi-mods/src/manifest.rs`, `crates/kurashi-schema/`, kurashid `config.rs` (mod settings), `settings/` | haiku (max) |

## Wave 18 (session 7; contract rows 98–99 on main)
| Card | Owner paths | Model |
|---|---|---|
| [W18-quick-tiles](W18-quick-tiles.md) | SlotHost, QuickPanel, `components/quick/`, wallpaper + hello tiles, `crates/kurashi-mock/`, quick tests | haiku (max) |
| [W18-peeks](W18-peeks.md) | Stage.qml, Bar.qml (peeks), Peeks/PeekSource, test-peek, test-mods-live, `justfile`, weather Peek.qml | haiku (max) |
| [W18-sysmon](W18-sysmon.md) | `crates/kurashi-mod-sysmon/`, `mods/sysmon/`, `mod-sysmon.toml` | haiku (max) |
| [W18-settings](W18-settings.md) | `settings/`, `tools/bench/wl_keys.py` (additive) | haiku (max) |

## Wave 19 (session 7; rows 71–72 and the clock schema keys on main)
| Card | Owner paths | Model |
|---|---|---|
| [W19-side-bars](W19-side-bars.md) | Bar.qml, Island/TrayIcon, faces, sysmon/weather/hello `Widget.qml`, test-sidebars | haiku (max) |
| [W19-weather](W19-weather.md) | `crates/kurashi-mod-weather/`, weather Panel/Face/Peek/Weather.js, weather shots | haiku (max) |
| [W19-wallpaper](W19-wallpaper.md) | wallpaper Panel + components, `crates/kurashi-mod-wallpaper/`, wallpaper test/shots | haiku (max) |
| [W19-calendar](W19-calendar.md) | ClockView, SlotHost, ModLoader (props), `crates/kurashi-mock/`, weather `slots/` + mod.toml, hello slots, test-stage | haiku (max) |
Sandbox names: each card uses names prefixed with its card id (`w19-side-…`, `w19-weather-…`, `w19-wall-…`, `w19-cal-…`).

## Wave 20 (session 8; web dock shell side, K40; contract rows 88, 109–111 on main)
| Card | Owner paths | Model |
|---|---|---|
| [W20-webdock-daemon](W20-webdock-daemon.md) | `crates/kurashi-mod-webdock/`, mock `webdock.rs`, kurashid `tests/webdock.rs`, `i18n/*/mod-webdock.toml` (append) | haiku (max) |
| [W20-webdock-shell](W20-webdock-shell.md) | `frontend/shell.qml` (surfaces), `core/mods.js`, `mods/webdock/qml/`, `test-dock.sh`, `i18n/*/mod-webdock-dock.toml` | haiku (max) |
| [W20-webdock-host](W20-webdock-host.md) | `mods/webdock/host/`, host tests + pages, `i18n/*/mod-webdock-host.toml` | haiku (max) |
| [W20-webdock-nix](W20-webdock-nix.md) | `nix/webdock.nix`, flake entries, HM/NixOS modules, `nix/tests/`, niri binds doc (not `nix/package.nix`) | haiku (max) |
Sandbox names: `w20-dmn-…`, `w20-shell-…`, `w20-host-…`, `w20-nix-…`.

## Wave 32 (session 13, machine A; contract K61–K63 on main 01c4503; base daemon `~/.cache/kurashi-agents-target/w32-base`)
| Card | Owner paths | Model |
|---|---|---|
| [W32-texture-gen](W32-texture-gen.md) | `crates/kurashi-texture/**`, `frontend/shots/texture/*.png` | opus |
| [W32-relief](W32-relief.md) | relief shader, Relief/TileSheet/Light, MorphShape, phone, media covers, Stage/Sidebar/overlay/toasts/lock, Relief lines in Bar/Launcher, test-texture | opus |
| [W32-pen](W32-pen.md) | Block, FrameHost, frames, PenOutline/PenInk, `pen_text` shader, test-pen (phase 2: surface outlines) | opus |
| [W32-settings](W32-settings.md) | `settings/**`, settings i18n (phase 2: Relief in Settings) | opus |
| [W32-controls](W32-controls.md) | Button, IconButton, QuickButton, Chip, ToggleSwitch, Slider, TrayIcon, SidebarButton, KeyButton, QuickTile, launcher rows, dock icons, test-controls | haiku (max) |
Sandbox names: `w32-gen-…`, `w32-rel-…`, `w32-pen-…`, `w32-set-…`, `w32-ctl-…`. `CARGO_BUILD_JOBS=4`.

## Wave 33 (session 13, machine A)
| Card | Owner paths | Model |
|---|---|---|
| [W33-bench](W33-bench.md) | `tools/bench/**`, `docs/BENCH.md` (results), one `justfile` recipe | haiku (max) |

## Wave 34 (session 13, machine A; brief docs/ux/motion.md; contract `theme.icon_theme` on main)
| Card | Owner paths | Model |
|---|---|---|
| [W34-morph-stage](W34-morph-stage.md) | Stage, components/island/**, phone, anchor rect lines in QuickButton/TrayIcon/SidebarButton/Bar, test-morph | opus |
| [W34-morph-sidebar](W34-morph-sidebar.md) | Sidebar, components/sidebar/**, sidebar tests/shots | opus |
| [W34-morph-surfaces](W34-morph-surfaces.md) | Launcher, NotificationCenter, Toasts, NotificationCard, launcher components, toast/launcher tests | opus |
| [W34-app-follow](W34-app-follow.md) | theme export (kurashi-theme export.rs, kurashid theme_export.rs), templates, ThemeExportStatus, theme-export i18n, HM themeExport | haiku (max) |
Sandbox names: `w34-stage-…`, `w34-side-…`, `w34-surf-…`.

## Wave 35 (session 13, machine A)
| Card | Owner paths | Model |
|---|---|---|
| [W35-audit](W35-audit.md) | read-only | haiku (max) |
| [W35-keys](W35-keys.md) | kurashid keys.rs, settings keys page, keys i18n, niri-binds doc | opus |
| [W35-perf](W35-perf.md) | tools/bench, BENCH.md, the frontend files its fixes need (after W34 merges) | opus |
| [W35-webdock-polish](W35-webdock-polish.md) | mods/webdock/**, kurashi-mod-webdock, webdock i18n, test-dock webdock steps | haiku (max) |

## Wave 36 (2026-10-25, session 13) — motion, bar modules, core, desk (contracts: K65)
| Card | Owner paths | Model |
|---|---|---|
| W36-motion | Stage/Launcher/Toasts/NotificationCenter/Sidebar, components/island + sidebar + launcher, ClockView, QuickPanel, docs/ux/motion + sidebar | opus |
| W36-bar | workspaces.rs + niri adapter, Bar/Dock, bar faces, test-tasks/dock, docs/ux/tasks + dock | opus |
| W36-core | crates/kurashid (rest), kurashi-mod-api, schema __private/generate, settings/, mods/wallpaper | opus |
| W36-desk | Desktop.qml + desk components, test-desk, docs/ux/desktop | haiku |

## Wave 37 (2026-10-25, session 13) — terminal material, daemon follow-ups, calendar, quick settings (contracts: K66)
| Card | Owner paths | Model |
|---|---|---|
| W37-ghostty | kurashi-theme export (ghostty), theme_export.rs, docs/ux/terminal-texture, tools/test-ghostty | opus |
| W37-daemon | crates/kurashid (not theme_export.rs), kurashi-mock, CLI, Launcher/Stage.qml | opus |
| W37-calendar | mods/calendar, SlotHost, ClockView, docs/ux/calendar | haiku |
| W37-quick | QuickPanel, components/quick, kurashi-theme tokens.rs, wallpaper tile, docs/ux/quick-settings | haiku |

## Wave 38 (2026-10-25, session 13) — drop shadows, keys, web dock, polish (contracts: K67)
| Card | Owner paths | Model |
|---|---|---|
| W38-shadows | kurashi-theme tokens, kurashid theme.rs (shadow), Theme.qml, Block/SoftShadow, MorphShape/ColumnShape, Bar shadow, settings material | opus |
| W38-keys | keys.rs, schema __private/generate, settings keys page, mock svc.keys, wl_keys | haiku |
| W38-webdock | kurashi-mod-api, mods/webdock, BENCH append | haiku |
| W38-polish | ClockView, calendar Widget, Button/IconButton, test-toasts, DND wiring | haiku |

## Wave 39 (2026-10-25, session 13) — shadows everywhere, a lighter Block
| Card | Owner paths | Model |
|---|---|---|
| W39-shadows2 | notification/lock/polkit/toast/centre shadow lines, ClockView day keys, settings Theme + SheetHost/SectionCard, test-shadows | haiku |
| W39-block | Block/SoftShadow/FocusRing, QuickPanel, Stage/Launcher lazy parts, icon font subset, badge token, bench | opus |

## Wave 40 (2026-10-25, session 13) — island faces restrict (K68)
| Card | Owner paths | Model |
|---|---|---|
| W40-faces | kurashi-island, kurashid island.rs, mock island, settings faces control, docs/ux/island | haiku |
