# Card M5-launcher — `kurashi-launcher` (app index + query provider)

**Goal.** The data side of the launcher: index desktop entries, answer
`{"t":"query","kind":"launcher","q":"fire"}` fast with ranked results, learn from launches
(frecency), and launch apps correctly — no UI.

**Owned paths:** `crates/kurashi-launcher/`. Common rules: `docs/tasks/README.md`.

**Read:** `docs/PROTOCOL.md` §6 (query/results), `docs/ARCHITECTURE.md` §9 (state paths).

**Build:**
1. Index `.desktop` files from `$XDG_DATA_HOME` + `$XDG_DATA_DIRS` `applications/` (paths passed
   in for tests): Name/GenericName/Keywords/Categories/Exec/Icon/NoDisplay/Hidden/OnlyShowIn/
   NotShowIn/TryExec/Terminal/Actions, localised keys (`Name[ja]`) with a locale argument.
   Re-index on change via `inotify` (crate of your choice) — no polling; debounce.
2. Matching: fuzzy (subsequence + word-boundary bonuses), prefix/acronym boosts, keywords, and
   romaji↔kana tolerance is a stretch goal. Ranking = match score × frecency (decay, persisted
   to a passed-in state file as TOML/JSON). p99 < 2 ms for 500 entries (bench test).
3. Results: `{id, name, generic?, icon, kind:"app"|"action", parent?, score}`; stale query ids are
   the client's problem (PROTOCOL §6).
4. Launch: expand field codes per spec (%f %F %u %U %i %c %k), honour Terminal via a configurable
   terminal command, spawn detached in its own process group with a clean env (no inherited
   `KURASHI_*`), optionally via `systemd-run --user --scope` (flag). Tests only assert the
   command line; they never spawn apps.

**Acceptance (one command):** `cargo test -p kurashi-launcher` green: parsing (incl. localised
keys, actions, NoDisplay/OnlyShowIn), ranking table tests, frecency persistence, inotify re-index
on a temp dir, Exec expansion table, latency bench test. Clippy `-D warnings`.
