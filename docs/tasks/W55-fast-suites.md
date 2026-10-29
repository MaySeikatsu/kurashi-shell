# W55-fast-suites — the frontend suites wait for conditions, not for time

Session 17 (user: "all of them make sense"; BACKLOG I307). The runner side is done (`tools/test-suites.sh`: parallel
jobs, a failure re-run alone, `--changed`); this card makes each suite itself faster. Common rules:
`docs/tasks/README.md`. Build dir: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W55-fast-suites`.

Measured before (machine A, serial, 2026-10-29): frame 738 s (72 s of fixed sleeps; the rest restarts, settle waits and the
idle check's wait for a minute flip), dock 192 s (99 s sleeps, 12 starts), sidebars 513 s, bars 13 starts / 100 s sleeps,
stage 63 s sleeps and 49 shots, edge-modules 74 s sleeps.

## Goal (per suite, keeping every check it makes today)
1. **Conditions instead of sleeps.** A shared helper (`frontend/test-lib.sh`: `wait_for <log> <pattern> <timeout>`,
   `wait_settled <surface>`) polls the lines the surfaces already log once they stand (`dock-geom`, `sidebar-opening`,
   `FRAMEGEO`, the geometry logs behind `KURASHI_*_GEOMETRY`/`_LOG`) and returns at once; a fixed sleep stays only where
   the suite measures time itself (an idle window, a reveal's duration).
2. **Motion off where motion is not under test.** Test configs set `theme.motion.profile = "none"` (or `speed = 3`) unless
   the step checks a slide, a morph or an overshoot.
3. **Fewer restarts.** Scenarios that only change settings use `kurashi set` / `config` on the running shell (the daemon
   hot-reloads; the frontend follows) instead of a new daemon + frontend per scenario; a restart only where the check is
   about start-up.
4. **The idle check starts after a minute flip** (or with a frozen test clock) instead of waiting for the next one.

## Owned paths
`frontend/test-*.sh`, `frontend/test-lib.sh` (new), `settings/test*.sh`, `greeter/test.sh`, `mods/*/test/*.sh`.
Not: QML, Rust, `tools/test-suites.sh`.

## Acceptance
`nix develop -c tools/test-suites.sh --all -j 4` green apart from the suites already failing on main (BACKLOG I263,
I274, I287), with each suite's own time in the summary; report before/after seconds per suite. No check removed or
weakened (diff of `fail`/`say` lines reviewed by the lead).
