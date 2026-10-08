# Kurashi-shell (暮らし) — instructions for Claude Code

Wayland desktop shell for **niri** (first), designed for Hyprland / MangoWM / Sway adapters.
Rust daemon `kurashid` owns all state; the frontend is a thin view. Nix-first.
Read `docs/VISION.md` once, then the doc for the area you touch (map below).

## Hard rules
1. **Daemon owns state.** Config, profiles, theming, services, actions, mods, relevance
   (Island) live in Rust. Frontends subscribe, render, send intents. No business logic,
   polling or Processes in the frontend.
2. **Shōjiki (honesty).** Never show a value that is not in effect. Every config value travels as
   `{value, source, forced_by?, reason?}`; UI shows provenance and why a control is inert.
3. **One schema.** Config types in Rust + `#[kurashi(...)]` attributes generate defaults,
   validation, settings pages, `config.example.toml`, docs. Never hand-maintain a parallel list.
4. **No renderer branches on theme/profile names.** Identity lives in decor packs (slots +
   recipe) and tokens. Renderers bind to component tokens only.
5. **Ma (idle = silent).** Hidden UI renders 0 frames and polls nothing; services are refcounted
   (start on first subscriber, stop on last). Every animation/timer has a visibility gate.
6. **Contracts are code.** Protocol types live in `crates/kurashi-ipc` with golden fixtures in
   `fixtures/ipc/`. Changing a shape = update fixture + `docs/PROTOCOL.md` + DECISIONS entry.
   Subagents never change contracts: they add an entry to `docs/CONTRACT-CHANGE.md`.
7. **Nix-first.** Every tool comes from `nix develop`; every artifact builds with `nix build`;
   NixOS + Home-Manager modules stay working. Flakes only see git-tracked files — `git add` new
   files before `nix build`.
8. **i18n from day one.** User-facing strings via keys in `i18n/{en,ja}.toml`. Code identifiers
   English; Japanese lives in copy, docs and profile names.
9. **Budgets (docs/BENCH.md) are acceptance criteria**, not aspirations.

## Workflow
- `main` is always green. Work on `feat/<milestone>-<topic>` (e.g. `feat/m1-protocol`).
- Merge with `git merge --no-ff` only after the step's verification checklist passes
  (tests, clippy, bench where relevant). Update `docs/PROGRESS.md` in the same branch.
- Commit messages: conventional (`feat:`, `fix:`, `perf:`, `docs:`, `refactor:`, `test:`).
  **No AI attribution / Co-Authored-By lines.**
- New architectural choices → `docs/DECISIONS.md` (K-ids, cite the lesson/evidence + URLs).
- **Session start:** read `docs/HANDOVER.md` (latest entry) and continue its "Next steps".
- **Session end (K14):** add a new top entry to `docs/HANDOVER.md` — state, what was merged,
  next steps (concrete, ordered), open decisions/risks, anything half-done and where it lives —
  and commit it. The pickup prompt at the top of that file must keep working.

## Commands (inside `nix develop`)
```sh
just              # list recipes
just check        # fmt-check + clippy -D warnings + cargo test
just dev          # run kurashid + frontend against the real session
just mock         # run kurashi-mock (fake daemon for frontend work)
just sandbox      # headless sway sandbox (invisible) for frontend smoke tests
just bench <cmd>  # idle frames, PSS, CPU, wakeups → tools/bench/results/
nix build .#kurashid   # packaged daemon
```

## Docs map
| Doc | Covers |
|---|---|
| `docs/VISION.md` | philosophy (Ma, Kanso, Shōjiki, Kaizen, Omotenashi, Shun), goals, non-goals |
| `docs/ARCHITECTURE.md` | process model, crates, state ownership, surfaces, data flow |
| `docs/PROTOCOL.md` | IPC v1: framing, handshake, revisions, transactions, intents |
| `docs/DESIGN-SYSTEM.md` | tokens, theming pipeline, decor packs, motion, components, Island |
| `docs/MODS.md` | mod manifest, tiers, lifecycle, Luau host API, settings integration |
| `docs/DECISIONS.md` | K-decisions log |
| `docs/ROADMAP.md` / `PROGRESS.md` | milestones / step tracker (`M{n}.{step}`) |
| `docs/BENCH.md` / `BAKEOFF.md` | measured numbers / frontend framework comparison |
| `docs/CONTRACT-CHANGE.md` | requested contract changes from subagents |
| `docs/HANDOVER.md` | session handovers + pickup prompt (read first, write last) |

## Subagent task cards
Every delegated task gets a card: goal · owned paths (edit only these) · frozen contracts to code
against · one executable acceptance test · token thrift (read only listed files, terse report) ·
out-of-scope needs → `docs/CONTRACT-CHANGE.md`. Work happens in an isolated git worktree.

## Testing without disturbing the user's session
Never start the shell on the user's display unless asked. Use `just sandbox` (headless sway,
own `XDG_RUNTIME_DIR` under `/tmp/kurashi-sb-*`, own `HOME`), screenshots via `grim`, and kill
only PIDs whose environ carries that runtime dir. For screencopy tests use the gles2 renderer.
