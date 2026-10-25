# Card W36-desk — desk cards polish (I136, I119)

**Why:** desk follow-ups reported by W22 and W24: mod cards can't be hidden, titles are not translated, the order ignores
the manifest, the Edit key overlaps the clock. K65 added `desktop.hidden` (lead, merged).

**Read first:** `CLAUDE.md`; `docs/tasks/README.md`; `docs/ux/desktop.md`; DECISIONS K43, K48, K65; BACKLOG I136, I119;
`frontend/surfaces/Desktop.qml` and the desk components it uses; `frontend/test-desk.sh`; one mod with desk cards (`mods/tasks/`).

**Task:**
1. **`desktop.hidden`:** the desk's edit mode gets a hide/show toggle per card (built-in and mod cards); hidden cards are
   left out of the desk and listed in edit mode as "hidden" so they can come back; writes `desktop.hidden` via the
   config set intent (no frontend state of its own).
2. **Titles:** mod desk card titles from `mod-<id>.desk.<name>` (en + ja), falling back to the manifest name.
3. **Order:** a mod's cards follow the manifest's `provides` order (the `qml` map sorts keys; read the order from
   wherever the manifest keeps it, or report what is needed).
4. **Edit key** no longer overlaps the clock's last digit on hover; ThemeExportStatus shortens paths under `$HOME` and
   `$XDG_CONFIG_HOME` both to `~`.
5. Shots: edit mode with a hidden card, the desk without it, ja titles; keyboard: Tab to each card's toggle, Space toggles.

**Owned paths:** `frontend/surfaces/Desktop.qml`, desk components (grep `Desktop.qml` imports), ThemeExportStatus,
`frontend/test-desk.sh` + shots, `i18n/{en,ja}/desktop.toml`, `i18n/{en,ja}/mod-tasks.toml` (desk titles only),
`docs/ux/desktop.md`.

**Acceptance:** `bash frontend/test-desk.sh` passes with the new steps and shots.

**Contract rows:** use CONTRACT-CHANGE rows 395–399 only.

**Env:** `CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/w36-desk CARGO_BUILD_JOBS=4`; sandbox names `w36-desk-…`.
Model: haiku (max effort).
