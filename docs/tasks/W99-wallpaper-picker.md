# W99 — The wallpaper pickers: room for the pictures, and one set of features

Session 36 (the user, live): the wallpaper menu "should also follow the size of the terminal console … That goes for
the new launcher-integrated wallpaper menu, as well as for the original one. The original one should get replaced anyway
at some point with the new one — but they should reach feature parity."

**Two pickers today.** The *original*: `mods/wallpaper/qml/Panel.qml` (the mod's Stage card, `panel:wallpaper`). The
*new*: `mods/wallpaper/qml/Picker.qml`, the compact picker the appearance menu loads in its Wallpaper pane
(`frontend/components/appearance/AppearanceMenu.qml`; hosts: the launcher, or a Stage card via `appearance.open`).

**Already done by the lead (do not redo):** the Stage's large card (K164, I606: a panel with `property bool cardLarge:
true` gets `bar.card_large_width` × `bar.card_large_height` of the screen at the bar's centre and its height as
`fillHeight`); `Panel.qml` asks for it and takes `fillHeight`, its grid's cells are 220 px when wide; the launcher's
appearance menu takes the same size (`Launcher.qml` `menuW`, `menuH`).

## Goal
1. **Size.** Both pickers use the room: the compact picker's grid has a fixed `columns: 4` and three rows — make its
   columns follow its width (cells about 220 px, at least 4 columns) and its rows the height it is given; the
   appearance menu as a Stage card (`host: "card"`) is a large card too (see how the Stage sizes `appearance`). Check the
   original at the large size: nothing stretched, the preview and the grid share the width sensibly.
2. **Parity.** List what `Panel.qml` can do that `Picker.qml` cannot (tabs Library / Wallhaven, folders and
   breadcrumb, search, sort, the preview with "theme follows the picture" and light/dark, per-output choice, apply,
   random / rotation, keyboard: grid arrows, Tab order, Enter) and bring the compact picker up to it, reusing the
   Panel's pieces: a block both need moves into a shared file under `mods/wallpaper/qml/` (rule 10; `python3
   tools/clones.py --check` must not rise). What cannot be built in this card is listed in the report with the reason.
3. **The backlog rows of this batch** (read each in `docs/BACKLOG.md` first, verify whether it is already done):
   - **I83** leftovers: the output chips' empty leading area; "Span · not yet" (say it is not available yet, or hide
     it); one primary action (Apply), quiet selected states; the theme diff swatches (about 8 px: make them readable);
     "Clear thumbnails" belongs on the mod's Settings page, not in the picker.
   - **I32** leftovers the row still lists as open — do the small ones (keyboard grid and search exercised in the
     suite, duplicate first-page requests at open); leave drag-and-drop, the lock wallpaper and the launcher `look:`
     provider, and say so.
   - **I135**: "Theme not applied yet (no source)" after applying with the theme in the sandbox — find out whether the
     product or the sandbox is wrong; fix it if it is the product.
   - **B88** (the wallpaper is a little behind the shell in a change of colour): look for the cause; fix only if it
     is small and inside the mod, else report what you found.

## Inbox lines taken
None (the wallpaper section of `docs/INBOX.md` is empty). The user's request above is the source.

## Owned paths
`mods/wallpaper/qml/**`, `mods/wallpaper/test/**`, `mods/wallpaper/mod.toml` (settings only), `i18n/{en,ja}/mod-wallpaper.toml`,
`frontend/components/appearance/**`, the `appearance` sizing lines in `frontend/surfaces/Stage.qml` (nothing else in
that file), `crates/kurashi-mod-wallpaper/**` only if I135 or the duplicate requests need it. New options are marked
advanced in the manifest when they are tuning knobs (the user's rule); say which.

## Frozen
`crates/kurashi-ipc`, `fixtures/ipc/`, `docs/PROTOCOL.md`, the Stage's large-card code, `Launcher.qml`. A needed change
there: a row in `docs/CONTRACT-CHANGE.md`.

## Acceptance
- `timeout 2400 nix develop -c tools/test-suites.sh -j 2 <the wallpaper mod's suites and frontend/test-appearance*.sh, as
  `tools/test-suites.sh --list --changed` names them>` green; a failure that also fails on the base is reported as such.
- `python3 tools/clones.py --check` passes; `nix develop -c tools/check-icon-names.sh` passes (regenerate
  `nix/icon-names.txt` as its message says if you added an icon).
- Nested niri (`tools/bench/niri-sandbox.sh`, sandbox name prefix `w99-`), with a folder of at least 12 pictures seeded,
  **light and dark**: the original picker's card (large), the launcher's Wallpaper pane, the appearance card's Wallpaper
  pane; one more look (`theme.look.apply` sekai) for one of them. Shot paths in the report. Keys do not reach nested niri
  for shifted characters: open the launcher with `kurashi act launcher.open '{"query":"wallpaper"}'`.
- The parity list in the report: each feature — had it / added / not added and why.

## Rules
`docs/tasks/README.md` "Common rules" 1–12; your build dir is `$HOME/.cache/kurashi-agents-target/w99`. Never touch
the user's session or display; sandboxes only; kill only PIDs you started. Commit on your branch (`feat(wallpaper): …`),
no AI attribution. Do not push, do not merge. If something blocks you for more than 20 minutes, report it.
