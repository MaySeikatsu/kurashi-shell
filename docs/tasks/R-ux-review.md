# Card R-ux-review — read-only UX/visual review of the shell (feel: quick, smooth, polished)

**Owned paths:** none — read-only. No commits. You MAY run the sandbox tests to produce
screenshots (they write into `frontend/shots/real/` and `settings/shots/`; restore them with
`git checkout -- frontend/shots settings/shots` before you finish). Common rules: `docs/tasks/README.md`.

**Read:** `docs/VISION.md`, `docs/DESIGN-SYSTEM.md`, `frontend/README.md`, the QML under
`frontend/surfaces/`, `frontend/components/`, `settings/pages/`; screenshots from
`nix develop -c frontend/test-real.sh ux-review` and `nix develop -c settings/test.sh`.

**Review against the design system and the goal "quick, smooth, polished, snappy, calm" (Ma, Kanso):**
spacing/alignment consistency, typographic hierarchy, contrast (WCAG AA), token usage (hard-coded
colours/sizes in QML = finding), motion (durations/easing per DESIGN-SYSTEM, interruptibility,
reduce-motion respected), focus/keyboard paths, empty/error states, i18n (strings not via keys,
Japanese text clipping), hit-target sizes, anything that looks unfinished.

**Report:** standard format; `done:` = findings ranked by user impact, each with file:line (or
screenshot + region), what is wrong, the concrete fix. Separate "bugs" from "taste". Max ~25
findings; precision over volume.
