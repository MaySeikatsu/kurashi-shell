# Card W33-bench — benches for a textured shell (I181) and the wave 32 BENCH rows

**Why:** wave 32 (K61–K63) added relief shadows, the spotlight, carried sheets, the pen (outlines + text layers), the
masked control relief and Settings as a sheet. Budgets (`docs/BENCH.md`) are acceptance criteria (CLAUDE.md rule 9), but
`tools/bench/measure.py` cannot run the shell with a config, so none of it has numbers yet (BACKLOG I181, I182).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md` (common rules); `docs/BENCH.md` (budgets, the latest results'
format); `tools/bench/README.md`, `tools/bench/measure.py`, `tools/bench/budget.py`, `tools/bench/sandbox.sh`,
`tools/bench/wl_pointer.py`; the `bench` / `bench-gate` recipes in `justfile`; DESIGN-SYSTEM "Texture and light"
(tokens) only as far as you need config keys.

**Task:**
1. **`measure.py --config <file.toml>`** (I181): the real daemon (`--daemon real`) starts with that file as its user
   config (isolated XDG dirs as today). Optional `--script <file>`: timed actions during the measurement window (pointer
   moves via `wl_pointer.py`, `kurashi act …` such as opening the sidebar or the island), so "moving" scenarios have
   frame counts too. Keep the existing behaviour byte-identical without the new flags.
2. **Scenarios** (configs under `tools/bench/testdata/w33/`), each against the real stack, bar + island at rest, then
   the listed motion:
   - `none` — no texture (the reference);
   - `kami` — style kami (paper_dots, shadows on, pen pressure 0.35);
   - `paint-shadows` — paint, shadows on, depth 2;
   - `spotlight` — paint + `theme.light.mode = "spotlight"`, pointer sweeping across the bar for 5 s;
   - `pen-text` — kami + every `theme.pen.text_*` at 0.6 with the quick card open;
   - `controls` — leather + `theme.texture.controls = true`;
   - `carried` vs `fixed` — paper_grid, the sidebar opened and closed 5 times;
   - `everything` — scope everything (the overlay).
   Metrics per scenario: idle frames over 10 s (must be 0), PSS of the frontend and the daemon, CPU over the window,
   wakeups; for the motion scenarios also frames and CPU during the motion.
3. **Quiet machine:** this is machine A (desktop, GTX 1060; no `KURASHI_RENDER_NODE`). Before each measurement check
   that the 1-minute load average is below 1.5 (`/proc/loadavg`); wait (up to 10 min) otherwise and note it. Run each
   scenario 3× and report the median. No other agent builds while you measure (the lead waits for your report), but
   do not touch the user's session; use `--sandbox` names prefixed `w33-bench-`.
4. **`docs/BENCH.md`:** a new results section "2026-10-22 — wave 32, textured shell (machine A, quiet)" with a table
   (scenario × metric), the commit, and a short reading against the budgets: what passes, what does not, deltas vs
   `none`. Do not edit the budgets themselves.
5. `just bench-texture` recipe that runs the scenario set.

**Owned paths:** `tools/bench/**`, `docs/BENCH.md` (append a results section only), one recipe in `justfile`.

**Acceptance (executable):** `just bench-texture` runs every scenario and writes `tools/bench/results/w33-*.json`;
`python3 tools/bench/measure.py --help` shows the new flags; the old `just bench-gate` still works.

**Env / thrift:** build release once: `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w33-bench CARGO_BUILD_JOBS=10
cargo build --workspace --release` (the lead deletes the dir after); never `cargo clean`. Disk is tight (~40 GB free).
Report in README rule 8 format plus the table.
