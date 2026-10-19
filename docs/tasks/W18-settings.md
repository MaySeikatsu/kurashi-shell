# Card W18-settings — Profiles page follow-ups and the records editor's keyboard paths (I64, I81; row 99)

**Decision (lead, session 7; contract row 99, on main):** profile previews and dry runs mark a diff entry whose value
stays and only its source changes with `same_value: true` (PROTOCOL §6, fixture `preview_same_value.json`). The page
uses it instead of comparing values itself.
**Brief:** `docs/ux/settings.md` (profiles, changed view, records control, keyboard).

**Read first:** `docs/tasks/README.md` (rules), K36, PROTOCOL §6 (profile actions) and §5 "Records", I64 and I81 in
`docs/BACKLOG.md`, `docs/tasks/W15-profiles.md`, `settings/pages/ProfilesPage.qml`, the Changed view
(`settings/pages/`), `settings/components/RecordsEdit.qml`, `settings/core/Store.qml`, `settings/test.sh`,
`tools/bench/wl_keys.py`.

**Owned paths:** `settings/**`, `tools/bench/wl_keys.py` (additive keys only; other tests use it),
`i18n/{en,ja}/settings.toml` (append a block marked `# W18-settings`). Not yours: `crates/**`, `frontend/**`.

**Do:**
1. **I64 (2):** a preview line with `same_value` shows a neutral "Now from this profile" (no red "your change replaced"
   chip); lines that change keep today's look.
2. **I64 (3):** the Changed view says when a key's user value is inert because a forced layer holds it back (the value,
   its provenance chip, and "not in effect: <reason>").
3. **I64 (4):** drop the page's own value comparison for the groups; group by `same_value`.
4. **I64 (5):** regenerate `settings/shots/17c-profile-source.png` on purpose and say what changed (K36).
5. **I81:** `wl_keys.py` can type `:` and `/` (and the other URL characters a test needs); `settings/test.sh` adds an
   entry through the records form end to end (id, title, `https://example.org/`), and verifies Alt+Up/Alt+Down moving a
   row, Delete removing one, Up/Down between rows and Enter to edit — fix the editor where a path does not work.
6. **I64 (1)** — design only: an imported profile file that shares its name with a saved profile; propose the smallest
   honest fix as a CONTRACT-CHANGE row (do not implement a contract change).

**Acceptance:** `timeout 900 settings/test.sh` green (real daemon in the sandbox) with new or regenerated shots: a
preview with a same-value line, the Changed view with an inert held-back value, the records add-by-form result, a
reorder by Alt+Down; ja for the new copy. No QML warnings in the log.
