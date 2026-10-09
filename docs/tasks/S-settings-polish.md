# Card S-settings-polish — settings app a11y, honesty and calm (UX review R.2, settings part)

**Read first:** `docs/reviews/2026-10-09-ux-review.md` (findings by number), `docs/DESIGN-SYSTEM.md` §6–§7,
`settings/test.sh`, `settings/core/Store.qml`, `frontend/components/FocusRing.qml` and
`frontend/core/Theme.qml` (the frontend already fixed the same findings in U.1 — reuse its patterns,
e.g. `fgOnAccent`, `controlH`, the focus ring, but do not import from `frontend/`).

**Owned paths:** `settings/**`, `i18n/{en,ja}/settings.toml`. NOT `frontend/`, `crates/`, other i18n domains.
Common rules: `docs/tasks/README.md`.

**Fix (settings app only):**
- 3: every control reachable and operable by keyboard — Toggle, Segmented, Slider, TextField, ListEdit,
  Button, sidebar entries, profile chips, breadcrumbs: `activeFocusOnTab`, Return/Space activate,
  arrows for Segmented/Slider, a 1 px focus-visible ring from Theme (only while focused by keyboard),
  `Accessible.name`/`role` from the row label.
- 4/5: text on accent uses `color.on_accent` (add `Theme.fgOnAccent`); page titles and breadcrumbs in
  `Theme.fg`, never accent; outline-on-container contrast as the frontend Theme does it.
- 7: Profiles success message survives (preview first, then the message).
- 8: Profiles Save enabled while typing a name (bind to text, not onAccepted).
- 9: Mods empty state: no env vars or paths in copy — say where in plain words (i18n key).
- 11: hit targets ≥ 32 px (`control.height` token → `Theme.controlH`); enlarge hit areas, keep visuals.
- 13: daemon messages never reach the user in English: map `code`s to catalog keys (ModsPage,
  ProfilesPage `m.msg`, OS error text) the way `Store.errorText` does; unknown codes → one generic
  translated line + the code (never raw `msg`).
- 17: cap the label column (a max width, not 36 % of any window).
- 18: one page-header pattern (title in `Theme.fg`, sections as dim labels) on every page.
- 23: Undo/Redo enabled only when there is something to undo/redo (derive from daemon replies, no
  local history); "Advanced" as a real Toggle; mods shown by name, not raw id; no stray dashes.
New strings: en + ja in `i18n/{en,ja}/settings.toml` (ja: natural Japanese, not romaji).

**Build constraint:** do NOT build Rust. Use the prebuilt binaries from `KURASHI_BIN_DIR` (the lead
gives the path in the prompt) for `settings/test.sh`.

**Acceptance:** `settings/test.sh` passes with no QML errors; extend it with one keyboard-only step
(Tab to a toggle, Space flips it, screenshot shows the focus ring) and Read every screenshot; keep the
existing screenshots meaningful (regenerate them; commit only those the change affects).
