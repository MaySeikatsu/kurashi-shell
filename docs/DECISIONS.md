# Decisions (K-ids)

Format: **K#** status — decision. *Why* (lesson / evidence). Status: 🟢 decided · 🟡 provisional
· 🔴 revoked. Cite K-ids in code comments where a decision explains non-obvious code.

**K1** 🟢 Mods are renderer-independent: `mod.toml` + daemon logic; native tier (v0.2) for
first-party, portable tier (declarative UI + Luau) in v0.3; WASM only on demand.
*Why:* noctalia v5 proved manifest + Luau + typed settings ([plugin docs](https://docs.noctalia.dev/noctalia/plugins/development/));
decoupling mods from the renderer keeps the framework choice reversible. shellseikatsu plugins
shared the main engine with no isolation.

**K2** 🟢 Daemon-first: `kurashid` (Rust) owns all state, config, theming, services, actions,
mods; frontends are thin views; Settings is a separate on-demand process.
*Why:* shellseikatsu had 109 Processes and logic spread over 60 QML singletons; WormShell D1/D2;
DMS's Go backend; services survive any renderer swap.

**K3** 🟢 Renderer = **Quickshell (Qt 6 / QML)** as the thin view over `kurashid` (decided by the M0
bake-off, 2026-10-09). Only candidate passing all hard gates (xdg_popup on layer surfaces, session
lock, ext-background-effect binding, IME); idle-silent (0 wakeups, ~0 commits); only one with hot
reload; ~4× cheaper per agent task (103k tokens / 7 min vs ~180k / 30 min). Score 8.7 vs gtk4 6.2,
slint 6.1, iced 5.2, gpui 2.5 (matrix in `BAKEOFF.md`).
*Why not the others:* gpui — `gpui_linux` re-arms `wl_surface.frame` and commits forever (61
commits/s idle), no session lock, KDE blur only ([zed gpui_linux](https://github.com/zed-industries/zed/tree/main/crates/gpui));
iced — no blur yet, 118 wakeups/s + 233 futex/s idle, no screencopy ([iced_layershell](https://github.com/waycrate/exwlshelleventloop));
slint — custom platform has no IME, no shader API, CPU-only (its 25 MiB is the software renderer);
gtk4 — no session-lock API, popups only as 2nd layer surface (+77 MiB), GskGLShader dead in 4.22.
*Re-evaluation clause (user, 2026-10-09):* reopen with a fresh bake-off if Quickshell restricts a
feature, the feel goal (quick, smooth, polished, snappy) or quick iteration, or a native stack
passes IME + blur + lock with hot reload. Mods stay renderer-independent (K1) and the probes stay in
`probes/` as the re-run baseline. Known cost: memory over budget → K16.

**K4** 🟢 IPC framing is NDJSON (not length-prefixed).
*Why:* trivially parsed by every candidate frontend (QML `SplitParser`, GLib, tokio
`LinesCodec`); JSON escapes newlines so framing is unambiguous. Supersedes WormShell D42.

**K5** 🟢 Provenance everywhere: every resolved value is `{value, source, forced_by?, reason?}`;
resolution `default → theme → profile → user → forced`, per output.
*Why:* shellseikatsu sliders were silently overridden by presets; shaders ran with toggles off.

**K6** 🟢 One schema source: Rust types + `#[kurashi(...)]` derive generate defaults, validation,
settings pages, example config, docs.
*Why:* shellseikatsu kept ConfigService (330 props), SettingsSchema and docs in sync by hand.

**K7** 🟢 Profiles are full snapshots with section-level partial load as one transaction, diff
preview and undo. *Why:* user decision 2026-10-08.

**K8** 🟢 Decor pack = typed slots + recipe at layer `theme:<pack>`; no renderer branches on
theme names. *Why:* 14 preset-name branches in 6 shellseikatsu files.

**K9** 🟢 Island (島) arbitration is daemon-side and deterministic: pinned > transient(TTL) >
relevance > default. *Why:* testable, consistent across outputs and renderers.

**K10** 🟢 Universal input slots (left/right/middle/hover/scroll ±shift) bound to Actions with
schema defaults, user-overridable per type/instance. *Why:* user requirement; one model (Kanso).

**K11** 🟢 Nix-first: flake (devShell, packages, NixOS + HM modules, systemd user units) from
M0. *Why:* user requirement; reproducible agents and benches.

**K12** 🟢 License GPL-3.0-or-later. *Why:* compatible with Quickshell (LGPL), iced (MIT),
reference shells; keeps forks open.

**K13** 🟢 i18n (en, ja) from day one via string keys. *Why:* Japanese copy is part of the
identity; retrofitting i18n is expensive (WormShell D30 deferral rejected).

**K14** 🟢 Session handover: every session ends by updating `docs/HANDOVER.md` (state, next
steps, open decisions, pickup prompt). *Why:* user requirement; multi-session project.

**K15** 🟢 Nix-declared settings form their own provenance layer `nix`
(`default → nix → theme → profile → user → forced`), read from `~/.config/kurashi/managed.toml`
(Home-Manager `programs.kurashi.settings`); `enforce = true` turns them into `forced:nix`. The
daemon keeps writing the live `config.toml`. *Why:* HM files are read-only store symlinks, which
conflicts with a daemon-written config; users still see "set by Home-Manager" in Settings.

**K16** 🟡 PSS budget revised: v0.1 frontend PSS ≤ **150 MiB @ 1 output, +≤ 6 MiB per extra output**
(was "≤ 50 % of shellseikatsu" = 108 MiB). *Why:* every GPU-rendered candidate measured 144–156 MiB
at 1 output on NVIDIA (bake-off quiet run); the trivial Quickshell floor is already 110 MiB
(libnvidia 27 · Qt 21 · ICU/fonts/other libs 49 · heap 46). 108 MiB is unreachable without software
rendering, which costs shaders and smooth animation. The shellseikatsu comparison stays as a
reported ratio (probe = 67 % of 216 MiB). Kaizen targets: ICU data, unused Qt modules, lazy popups.


**K17** 🟢 Protocol v1 completed for the M1 freeze: typed `apply` ops (`set`/`reset`, optional
`output`, `dry_run` → `preview`), `cfg.why` layers with one `active`, typed `rejected` errors
(`code` = i18n key), `done.data`, server-pushed `snap` without `id`, `welcome.instance`, the
`config` / `schema.settings` / `i18n` documents, and **daemon patches = merge-patch diff of
old → new** (`kurashi_ipc::diff_patch`, documents contain no `null`). All additive for the probe
subset. *Why:* RFC 7396 can't delete a member without an explicit `null`; a hand-written patch
would leave stale `forced_by`/`reason` on screen — a Shōjiki violation. Diffing makes every
patch exact by construction (property-tested). Instance ids avoid trusting cached revisions
across daemon restarts.

**K18** 🟢 Loading a profile clears the user overrides in the loaded sections (all sections when
none are given), in the same undoable transaction. *Why:* a profile that loads "successfully" but
changes nothing visible because older user pins win would be dishonest (Shōjiki); the diff
preview shows the cleared pins and undo restores them. Forced values are never saved into or
cleared by profiles. (`kurashi-config`, M1.4.)

**K19** 🟢 The Stage is one content-sized overlay layer surface, permanently mapped but transparent,
input-less and rendering 0 frames while hidden, retargeted to the focused output. *Why:* unmapping
per open leaked ~5 MiB/cycle; per-output stages, PopupWindow and destroy/recreate all measured worse.
Popup-open PSS 221 → 112 MiB. **Budget:** an interim raise of the per-output budget to +10 MiB was
reverted the same day — the bench gate (M7.2) now measures the second output against the
popup-closed reading (popup memory stays resident after closing) and finds **+0.8 MiB**, so +6 stands.

**K20** 🟢 A locked session survives daemon restarts and crashes: `kurashid` writes a `locked`
marker next to its socket in `$XDG_RUNTIME_DIR/kurashi/` while locked and starts locked when it
finds one; the frontend stays locked while disconnected (and the compositor keeps the
ext-session-lock if the frontend dies). *Why:* the lock-UI work showed a restarted daemon reported
`locked:false` and the surface unlocked — killing a process must never unlock the screen. The
runtime dir is cleared on logout, so a stale marker can't outlive the session.
