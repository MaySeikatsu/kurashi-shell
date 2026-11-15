# W94 — The Mod Editor page (session 34, K154; I563; the full brief; lead with a QML card)

`docs/ux/mod-editor.md` is the brief and its definition of done; the user chose the **full** page. The generator
(`kurashi_mods::scaffold`) and the ruleset (`kurashi_mods::check`) exist; the page holds no knowledge of its own.

## Order (QML first)
1. **Daemon:** `query points` (the registry, with `expected` and the fill), `mod.new {spec}` → `{path, check}` (writes
   into the user's mods folder through `scaffold`; refused with the scaffold's error keys), `mod.check {id | spec}` →
   the report (a draft spec is checked without writing: generate into a temp dir, check, remove), `mod.rescan {}` (the
   registry discovers again without a restart; a new mod appears as `available`; its strings join `i18n`). Fixtures and
   PROTOCOL §6 for each.
2. **Mock:** the same four with canned answers, so the page is built on `just mock`.
3. **Prototype** `settings/pages/ModEditorPage.qml` on the mock: the four groups, the result column (files, live check,
   Create and the three follow-ups), every state of the brief's table; kit components only; `i18n/{en,ja}/mod-editor.toml`.
   Shots on niri, light and dark, two looks → the user looks before the daemon side is wired.
4. **Wire** to the real daemon; the Mods page's "New mod…" row, "Check" and "Open the folder" per user-made mod;
   `> new mod` (a declared command of the core's own).
5. With W93 in: the "Runs on" group offers the host templates.

## Acceptance
The brief's definition of done, item by item, reported met / not met; `settings/test-mod-editor.sh` (new, in the merge
set): a mod made with the keyboard only, turned on, its panel opened; every state shot.
