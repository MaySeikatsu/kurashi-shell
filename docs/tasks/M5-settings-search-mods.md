# Card M5-settings-search-mods — settings search + Mods page

**Goal.** Find any setting by typing; see and toggle installed mods.

**Owned paths:** `settings/` only, plus `i18n/{en,ja}/settings.toml`. Common rules: `docs/tasks/README.md`.

**Read:** `settings/` (all), `settings/test.sh`, `crates/kurashid/src/wiring.rs` (`mods` fn: the `mods`
doc and its actions), `docs/MODS.md` (settings integration section).

**Build:**
1. Search field (Ctrl+F or typing on the page list): matches translated label, help and key across
   `schema.settings`; results show page › section › label with the provenance chip; Enter/click
   jumps to the row and highlights it briefly (animation gated, no idle timers).
2. Mods page: list from the `mods` doc (name, description, version, tier, state); enable/disable
   through the daemon's mod actions; errors shown inline with the daemon's message. Empty state text.
3. Extend `settings/test.sh` with shots `5-search.png` (query "blur") and `6-mods.png`
   (create a minimal mod in the sandbox's `$XDG_DATA_HOME`/config mods dir per `docs/MODS.md`).

**Acceptance:** `nix develop -c settings/test.sh` exits 0 with 6 shots; Read 5 and 6 to check.
