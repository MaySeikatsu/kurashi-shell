# Card M6-mod-description — mod descriptions, no nulls in `mods` (CONTRACT-CHANGE row 5, accepted)

**Owned paths:** `crates/kurashi-mods/`, `mods/*/mod.toml`, new `i18n/{en,ja}/mods.toml`,
`settings/pages/ModsPage.qml`, `docs/MODS.md` (manifest section only). Not `settings/core/`
(another agent). Common rules: `docs/tasks/README.md`.

**Build:**
1. Manifest: optional `description` (an i18n key; plain text accepted as fallback like `name`).
   `mods_doc` emits `description` only when present.
2. `mods_doc` currently emits `null`s (`version`, `tier`, `cost` for manifest-less entries):
   documents carry no nulls (PROTOCOL) — omit those keys instead; keep the settings page working
   (it must treat them as absent).
3. Descriptions for the bundled mods (media, easter-eggs) in a new `mods` i18n domain (en + ja,
   calm wording); `docs/MODS.md` manifest example shows the field.
4. `ModsPage.qml`: show the translated description under the name.

**Acceptance:** `timeout 600 cargo test -p kurashi-mods` green with tests for (1) and (2);
`nix develop -c settings/test.sh` passes and `settings/shots/6-mods.png` shows descriptions (Read it).
