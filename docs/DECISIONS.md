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

**K3** 🟡 Renderer chosen by the M0 bake-off (Quickshell, iced, Slint, GPUI, GTK4/Relm4) with a
weighted matrix (runtime 35 %, capability 30 % with hard gates, dev workload 25 %, ecosystem
10 %). QML is the default unless a candidate passes all gates and wins overall.
*Why:* no native Rust stack publishes idle-memory numbers or covers shaders+lock+blur+popups+
hot-reload together (research 2026-10-08); measure, don't assume. → see `BAKEOFF.md`.

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
