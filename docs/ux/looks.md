# UX brief — Looks (decor packs) (K42, K45, I104)

A decor is a whole look picked in one choice: colours, chrome, corners, motion, icons and type. It never moves
anything: the bar stays on its edge at its height, the desk keeps its cards, the island stays where it is. Layout
and look travel together only in a profile, which the user saves on purpose.

## How others do it
- **KDE Plasma Global Themes** bundle colours, icons, cursors, splash and, optionally, a desktop layout. Applying one
  asks with a checkbox whether to take its layout too — the most common complaint is losing a panel layout to a theme.
  We keep layout out of decors entirely; a profile is the "with layout" option.
- **GNOME** offers only accent colour and light/dark: honest and safe, but no identity.
- **macOS** Appearance (light/dark/auto, accent, highlight) and **Windows** Themes (wallpaper, colour, sounds, cursor)
  never touch the dock/taskbar position.
- **Quickshell shells:** Caelestia and end-4 derive schemes from the wallpaper (Material You), DankMaterialShell has
  theme presets plus "matugen"; Noctalia offers colour schemes. All change colours, few change shape language.
  SekaiPop (keycaps), Vitreus/pleamar (glass) show that chrome — how a block is drawn — is what makes a look distinct.
- **WormShell** (predecessor, `docs/05-surface-style.md`): a SurfaceStyle owns corners, border, alpha, blur, shadow,
  insets, motion, type and icons, and is explicitly not a palette and not a layout.

## Our model
`theme.decor` = none | sekai | glass | terminal | washi. A recipe at the `theme:<pack>` layer (K42), under the user's
own values; every value it sets shows `theme:<pack>` as its source. Four chromes (flat, keycap, soft, line) are drawn by
the same components from tokens (rule 4). DESIGN-SYSTEM "Chrome and decor packs" has the tables.

## States
- **Picked:** the shell re-themes in one theme document change; no restart, no flash (the palette animates via the
  normal colour behaviours).
- **User value on top:** a value the user set keeps winning; Settings shows it as "yours" and the decor's value as
  held back in the provenance stack (Shōjiki). Reset on that row brings the decor's value back.
- **Font missing:** the chain falls back to the next installed family; the theme note says which one (K42). HM
  installs the decor fonts by default.
- **High contrast / reduce transparency / reduce motion:** force chrome flat, material solid, motion none over any
  decor, with `forced_by: accessibility` on each row.
- **Mods' decors (later, I103):** a `decor:` provide adds a recipe; an invalid one is refused with a reason.

## Settings (I104)
The Look row is a row of preview cards, each a small scene drawn from the tokens the daemon resolved from that pack's
recipe alone (`theme.decors`): ground, a bar of three blocks, a card with "Aa あ" in the pack's font and its accent.
"Your own" is a plain card. Keyboard as the pill choices: Tab enters, arrows preview (the shell shows the look while the
preview is open), Return/Space pick, Escape puts the old look back. The selection is a frame plus a check and a bold
caption, never colour alone.

## Motion
Colours cross-fade (`Theme.quickMs`); blocks change chrome instantly (a morph between outline and shadow styles reads as
glitchy). Reduce motion: everything snaps.

## Multi-output, budget
One theme for all outputs (per-output overrides stay as they are). The previews cost one resolve per pack, once per
daemon start (cached); the cards are static (0 frames while Settings is idle).

## Definition of done
- Five looks visibly distinct on every surface (bar, island pill and card, quick settings, launcher, notifications,
  session, lock, web dock, desk) with an identical layout (test-look shots, `frontend/shots/look/<decor>/`).
- A test keeps recipes to `theme.*` keys.
- Settings shows the cards with keyboard preview; the Japanese copy names each look.
