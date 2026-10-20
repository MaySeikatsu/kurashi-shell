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

## Identity packs (W25, v0.3; ported from shellseikatsu, the user's own shell)
Fourteen more packs, each a recipe plus, for the game and OS looks, a frame (DESIGN-SYSTEM "Frames"). Sources, all
in `~/Documents/projects/quickshell/shellseikatsu/`: presets `Services/Modes/<Name>.qml`, palettes
`Services/Appearance.qml` `_<name>Palette()`, frames `Widgets/ThemeDecor/<Name>Frame.qml`, `Widgets/BevelBorder.qml`,
`Widgets/GlassSheen.qml`, `Widgets/SurfaceFrame.qml`, lock grounds `Panels/Lockscreen/LockStyle<Name>.qml` (backdrops
only: our lock keeps its own column, K45).

| pack | from | frame (from) |
|---|---|---|
| catppuccin | `Catppuccin.qml`, `_catppuccinPalette` (+ Latte from catppuccin.com) | — |
| tokyo-night | `Tokyonight.qml`, `_tokyonightPalette` (+ Day from tokyonight.nvim) | — |
| rose-pine | `Rosepine.qml`, `_rosepinePalette` (+ Dawn from rosepinetheme.com) | — |
| material | `Material.qml` (matugen there; the M3 baseline scheme here) | — |
| aqua | `Macos.qml` | sheen (`GlassSheen.qml`) |
| yorha | `Nier.qml`, `_nierPalette` | yorha (`YorhaFrame.qml`, `LockStyleNier.qml`) |
| kawaii | `Kawaii.qml`, `_kawaiiPalette` | kawaii (`KawaiiFrame.qml`, `LockStyleKawaii.qml`) |
| win95 | `Retro.qml`, `_win95Palette` | bevel (`BevelBorder.qml`, `LockStyleRetro.qml`) |
| luna | `Winxp.qml`, `_winxpPalette` | luna (`SurfaceFrame.qml`, `LockStyleXp.qml`) |
| aero | `Win7.qml`, `_win7Palette` | aero (`GlassSheen.qml` + `SurfaceFrame.qml`, `LockStyleWin7.qml`) |
| ps2 | `Ps2.qml`, `_ps2Palette` | ps2 (`Ps2Frame.qml`, `LockStylePs2.qml`) |
| snes | `Snes.qml`, `_snesPalette` | snes (`SnesFrame.qml`, `LockStyleSnes.qml`) |
| hallownest | `HollowKnight.qml`, `_hollowPalette` | hollow (`HollowFrame.qml`, `LockStyleHollow.qml`) |
| souls | `DarkSouls.qml`, `_dsoulsPalette` | ornate (`OrnateFrame.qml`, `LockStyleSouls.qml`) |

Left out on purpose: the Cyberpunk presets (the user's own "isekai" decor comes later, I117), and shellseikatsu's
other game presets (Settlers, osu!, Ultrakill, F-Zero, NFS) for now. Changes from the originals: colours come from
palette roles instead of fixed hex (a pinned palette still fits); motes and fog that drift forever stand still (Ma:
an idle shell renders no frames) — PS2's towers rise once when the lock appears; game palettes were nudged to
text-grade contrast where the originals miss it (the AA test holds every scheme). Single-scheme palettes (the game and
OS ones) say so in the theme notes when the other scheme is asked for. Fonts that are not free (Segoe UI, Tahoma,
SF Pro, Trajan, OptimusPrinceps, W95FA, SST, Press Start 2P) stay first in the chains and fall back to free families;
HM installs Quicksand, Comic Neue, Cinzel, EB Garamond and Roboto. Shots: `frontend/shots/look/<pack>/`, contact sheet
`frontend/shots/look/identity-sheet.png`.

## Definition of done
- Five looks visibly distinct on every surface (bar, island pill and card, quick settings, launcher, notifications,
  session, lock, web dock, desk) with an identical layout (test-look shots, `frontend/shots/look/<decor>/`).
- A test keeps recipes to `theme.*` keys.
- Settings shows the cards with keyboard preview; the Japanese copy names each look.
