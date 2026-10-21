# UX brief — Styles, looks and palettes (K42, K45, I104, K53)

Since K53 an appearance is three kinds of pack. A **style** is a whole aesthetic picked in one choice — a look, a
palette, the scheme, density and motion — and applying one recreates it exactly. A **look** is the form and feel
without colours (chrome, corners, material, motion, type and its frame art). A **palette** is colours only. None of
them ever moves
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
`theme.style` (default `washi`, or `none` = your own), `theme.look`, `theme.colors.palette` (K53). The style's and the
look's recipes are one `theme:` layer under the user's own values; every value they set names its pack as its source
(`style:washi`, `look:sekai`), which Settings words as "From the style Washi". Four chromes (flat, keycap, soft, line)
are drawn by the same components from tokens (rule 4). DESIGN-SYSTEM "Chrome and decor packs" has the tables.

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

## Settings (I104; W29, K53)
References: **KDE** Global Theme (colours + Plasma style + window decoration under one pick: our Style ⊃ Look +
Palette), its "apply" overwriting what you tweaked is the complaint we answer with the "differs from" line;
**GNOME** Appearance (style = light/dark + accent only); **Noctalia** colour-scheme tab (a section title, one line of
what it does, a grid of swatch cards with a check); **shellseikatsu** mode presets (one preset recreates a whole
aesthetic, then single settings on top); **ii** wallpaper/scheme picker (a category row above a grid); **macOS**
Appearance (three big previews, one line each).

The Appearance page opens with three blocks, in this order: **Style**, **Look**, **Palette**. Each block is a card
whose title is the setting's name and whose first line says what the kind is (Style "a whole aesthetic: look, colours,
motion — applying one resets your appearance changes"; Look "the form and feel without colours"; Palette "colours
only"). Under it the provenance of the value in effect: "From the style Washi", "Yours" with Reset, a profile, Nix.
Then the detail sections as before (scheme and the accessibility colour keys, shape, material, motion, layout, type).
- **Categories** (styles, looks): a row of chips — Modern · Inspired · Retro · Gaming & fiction · Your own — only
  categories that have packs, each with its count; one category is open at a time, the current pack's by default. A
  chip is a tab: Left/Right move between chips, Return/Space open one, Tab goes on into its cards. "None (your own)"
  (styles) is a plain card in front of the chips, always shown.
- **Cards:** a small scene drawn from the tokens the daemon resolved for that pack (`theme.previews`): ground, a bar
  of three blocks, a card with "Aa あ" in its font and its accent. A look with frame art (`frame`) gets a hint of it:
  corner brackets in the ink colour and a frame mark — the frame components themselves belong to the shell's process,
  and a hint costs four rectangles. Only the open category's cards exist.
- **Picking:** a style card applies the style (`theme.style.apply`: your appearance values are reset, one undo
  step); "None (your own)" only sets `theme.style = none` and keeps your values; a look card applies the look
  (`theme.look.apply`: your look values reset, the style's palette stays); a palette card sets the palette (with the
  live preview it always had). Styles and looks are not previewed by arrow keys — an arrow press must never reset
  settings — so in those groups arrows move the focus and Return/Space/click pick (WAI-ARIA radio group with manual
  activation). Palettes keep "arrows preview, Return keeps, Escape puts back".
- **Changed from the style:** while `theme.appearance.overrides` is not empty, a line under the Style block: "3
  settings differ from Washi: Chrome, Corners, Palette · Reset to Washi" (labels from the schema catalogue, at most
  four then "…"). Reset applies the current style again (one undo step). With style `none` there is no such line.
- **Light or dark** (K53 amendment) is the user's mode: the scheme switch sits in the Palette block, under the cards
  (they are drawn in the scheme in effect), its chip "Recommended by the style Washi" until you pick, then "Yours".
  Applying a style keeps it, and the Style block's line says so. It is never listed as a difference from the style.
- The selection is a frame plus a check and a bold caption, never colour alone.

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

## States (Settings, W29)
default (washi, nothing changed: no "differs" line) · style picked (its category open) · user value on top (the
"differs" line, the row's chip "Yours") · look picked over the style (Look block "Yours", the Palette block still "From
the style …") · style none (no line; blocks say "Default" or "Yours") · a user pack without a category ("Your own"
chip) · disconnected (blocks greyed, picks off) · refused action (the reason under the block) · search (the rows show as
plain rows with their cards).

## Washi's paper (W29)
Washi's look carries a frame, `paper`: a very fine fibre grain and a soft hairline in the ink colour (`Theme.fg`, low
alpha), a little stronger on the lock/greeter ground. The grain is one small tile (an SVG made once per ink colour,
from a fixed seed so every block shows the same paper) that the image cache shares between all blocks; it never
animates. Small blocks (bar groups, keys) get a fainter grain — more on a 20 px key reads as dirt.

## Definition of done
- Five looks visibly distinct on every surface (bar, island pill and card, quick settings, launcher, notifications,
  session, lock, web dock, desk) with an identical layout (test-look shots, `frontend/shots/look/<decor>/`).
- A test keeps recipes to `theme.*` keys.
- Settings shows the cards with keyboard preview; the Japanese copy names each look.
- W29: three blocks named Style, Look, Palette with their lines; categories with counts; picking a style resets the
  user's appearance values (daemon) and the "differs" line comes and goes; shots under washi, sekai and win95, each
  category open once (`settings/shots/appearance/`); paper on bar, card and lock ground in light and dark
  (`frontend/shots/look/washi*/`).
