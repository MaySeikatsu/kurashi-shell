# W85 — The terminal, polished to the shell's bar (session 33; Opus)

**Base.** `feat/s33-context-menus` (W83 merged). **The user:** "highly polished and deeply integrated, it should all feel
native, not like an afterthought." W83 works in every place (docs/ux/terminal.md "As built"); the lead's review of its shots
found it below that bar. Fix, seen on nested niri in **three looks** (washi, kami or sekai, material) light and dark:
1. Notices (a missing folder, starting, exited, crashed): the shell's own notice — the card's notice strip / Refusal style,
   i18n, an action where one helps (Restart, Open Settings) — not red text over the terminal.
2. The tab row: the shell's tab style (the sidebar's tab row: keys, the current one tonal, the "+" and the pin at its end,
   wheel scroll, a cut end blending), the favourites as keys in a "+" menu (a TrayMenu) and in the module's right-click
   menu (rows 780/781 of W82's menu system if merged; else the module menu), the bar field's Tab picker.
3. No pop-in: the terminal's text is there as the sheet lands (map the host's window under the sheet before it rests, or
   hold the last frame), measured with a burst.
4. The ANSI colours from the look: publish `term.*` tokens (CONTRACT-CHANGE 785; the lead authorises: kurashi-theme +
   the look files, derived from the palette where a look has none), so a terminal in kami looks like kami.
5. The status mode's finished/failed and "a command finished" in the island (OSC 133 from the shell: document what the
   user adds to fish/bash/zsh, or inject it for the shell the mod starts) — if cheap; else say so.
6. Two outputs: the drop-down on the focused one, the bar card on its module's; a BENCH entry for the host.
**Owned paths.** `mods/terminal/**`, `crates/kurashi-mod-terminal/**`, `docs/ux/terminal.md`, i18n `mod-terminal*`,
`crates/kurashi-theme` + `looks/*.toml` only for `term.*`. **Acceptance.** `mods/terminal/test/test-terminal.sh` green, new
steps for each item; bursts and shots in the three looks. Build dir `~/.cache/kurashi-agents-target/w85`.
