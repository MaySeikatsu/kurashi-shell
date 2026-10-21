# Card W30-island-line — the open island meets the bar under line chrome

**User (session 12):** "When the dynamic island is open with Line chrome active, it seems disconnected on the merge to
the bar since the island is going straight down and the extended island part merging into the bar, both not really
meet at the same point." Line chrome is the default now (look `washi`, style `washi`), also `terminal`, `win95`,
`souls`, `hallownest`.

**Read first:** `CLAUDE.md`; `docs/ux/island.md` ("Session 9 morph"); DECISIONS K43/K44 (morph), K45 (chromes);
`docs/DESIGN-SYSTEM.md` (chrome tokens); then the island's shape code under `frontend/components/island/**` and
`frontend/surfaces/Bar.qml` where the pill/card joins the bar (the flare / neck / outline path), and
`frontend/components/frames/Paper.qml` (washi's frame draws over the outline).

**Task:** reproduce with `frontend/test-island-morph.sh washi 'theme.style = "washi"'` (and `terminal`,
`'theme.style = "none"' 'theme.chrome = "line"'`), look at the open/rest frames, and make the outline of the open card
one continuous line with the bar: the card's side outline and the bar's outline must meet at the same point (the
neck/flare joins where the bar's edge is, no step, no gap, no double line, no overshoot), in light and dark, at
`theme.shape.corners` rounded/none/squircle and radius scales 0.5/1/2, with the bar at top and bottom, and during the
morph (40/120/250 ms frames). Other chromes (flat, keycap, soft) must not change — compare their shots before/after.
Tokens only (rule 4): no branch on look/style names; a branch on the chrome *token* is allowed only if the shape
already does so.

**Owned paths:** `frontend/components/island/**`, the island-join parts of `frontend/surfaces/Bar.qml`,
`frontend/components/frames/**` (only if the frame causes it), `frontend/test-island-morph.sh`, `frontend/shots/island/**`,
`docs/ux/island.md` (a short note). Contract changes → `docs/CONTRACT-CHANGE.md` rows 260–269.

**Acceptance (executable):** `frontend/test-island-morph.sh` for washi, terminal, sekai and glass all succeed, with
shots `frontend/shots/island/morph-{washi,terminal}-*.png` showing the join; add a pixel check to the script (or a new
`frontend/test-island-join.sh`) that samples the outline colour along the join under line chrome and fails on a gap
or step > 1 px. `frontend/test-real.sh`, `test-stage.sh`, `test-quick.sh` stay green. `just check` green.

**Thrift:** read only what is listed; terse report with before/after shot paths, CONTRACT-CHANGE rows, backlog ideas.
Build with `--features kurashid/test-mods` before sandbox tests. Never start the shell on the user's display. Machine B:
`export KURASHI_RENDER_NODE=/dev/dri/renderD129` for screencopy.
