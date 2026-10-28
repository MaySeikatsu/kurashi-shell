# Screen frame — UX brief (K71; cards W43-frame, W44-*)
Status: agreed (lead, session 14, from the user's draft: images 1, 2, 8, 11)

## Job
A thin border round each screen, in the shell's own material, that makes the bar, the dock, the sidebars and the
modules pinned to the edges read as **one sheet**: the screen's contents sit in a window cut into it. It can be turned
on per output, follows the look (fill, chrome outline, texture, pen, light) and, by default, keeps windows inside it
(`layout.frame.reserve`, user decision session 14: on by default, can be turned off).

## References (cited)
- **Caelestia** (`caelestia-dots/shell`, read 2026-10-26): `modules/drawers/ContentWindow.qml` draws the border as one
  full-screen layer window (exclusion `Ignore`), the fill a `BlobInvertedRect` — an SDF rounded box in a fragment
  shader (`plugin/src/Caelestia/Blobs/shaders/blob.frag`, `sdRoundedBox`). `border.thickness` 10 (min 2), `rounding` 25,
  `smoothing` 20 (`plugin/src/Caelestia/Config/borderconfig.hpp`). Space is reserved by `modules/drawers/Exclusions.qml`:
  four 1 × 1 windows, `mask: Region {}`, `exclusiveZone: border.thickness` (the bar's side: the bar's zone). The bar
  shares the border's shape and colour (the frame's left inset *is* the bar's width), so bar and border are one sheet.
  Panels are `BlobRect`s in the same `BlobGroup`, unioned with a circular smooth-min — that blend is their concave
  fillet into the border. Fullscreen drops the thickness to 0. A full-screen `MultiEffect` shadow costs GPU.
  **Taken:** bar = the frame's band on its edge; fillets of panels into the border; the defaults' proportions
  (thin band, rounder inner corners); fullscreen hides it. **Not taken:** the shader and the full-screen window (a
  full-output transparent buffer + a shader per frame; we draw four static strips like `ScreenCorners.qml`, 0 frames
  idle); the four extra exclusion windows (a layer window costs ~3.5 MiB here, I11 — the strips hold the zones).
- **end-4 ii** (`modules/ii/screenCorners`), **shellseikatsu** `Widgets/ScreenCorners.qml`: rounded corners only, no
  band. Ours rounds the panel's *outer* corners; since K74 (session 16) they follow the corner radius R by default
  (`theme.shape.screen_corners_follow`), so screen, band and the frame's inner corners (`R − thickness`) are concentric;
  off, `theme.shape.screen_corners` gives them their own size.
- **KDE Plasma 6**: no frame; floating panels show a margin all round. **macOS / Windows / GNOME**: none.
- **Hyprland decorations / niri `border`**: per-window borders, not a screen frame — a frame does not replace them.

## Beyond the basic job
- The frame is where edge modules live (`edge-modules.md`): a module pinned to an edge grows out of its band.
- A dynamic dock, sidebar or island meets the band with the same fillet it uses against the bar.
- Fullscreen windows: the frame steps aside (band 0, no reserve) while a fullscreen window is on that output — the
  compositor's fullscreen state from `svc.workspaces` (niri: the window's `is_fullscreen` where reported; else the
  frame stays — report, BACKLOG).
- Later: seasonal ornaments in the corners (easter eggs, Shun), the light's sheen running round the band.

## Design
- **Geometry** (from `runtime.layout`, never re-derived): `frame.band.<edge>` per edge — `thickness` where no docked
  bar stands, 0 where one does (the bar is the band there). Inner corners rounded by `frame.radius`, drawn as concave
  fillets in the band's colour over the screen's corner. With a docked bar on top, the fillets hang under the bar's
  ends (image 2). A floating bar stands inside the frame, `gap` from the band (image 8).
- **Surfaces:** four strips per output — top and bottom span the width, left and right the height between them — each
  `band + radius` deep (the fillets of its corners), click-through (`mask: Region {}` except where a module needs
  input), keyboard none, layer Top, namespace `kurashi-frame`. Static `Shape`s: drawn once, 0 frames idle. The strip
  that is its edge's `holder` sets `exclusiveZone = edges.<e>.reserve`; with `frame.reserve` off the strips ignore zones
  and the holders are the bars as without a frame.
- **Look:** fill `Theme.panel` (the bar's fill, its translucency and blur where the compositor has them); line chrome
  rules the band's inner edge in the outline colour, and the bar's rule runs into it without a seam (image 2: "if the
  bar has an outline, it goes on into the frame"); chromes without an outline draw none (flat, keycap and soft draw the
  band as a plain sheet; keycap's ring/shadow belong to blocks, not to the frame). Texture (K59): the band takes the
  material like the bar does, its tiles in **screen coordinates** so bar and band meet without a grain seam. Pen (K62):
  the rule is drawn by the pen as one closed line round the inner edge. Light (K59): the band's relief follows the light
  like the bar's.
- **Settings:** page Layout › Frame: Frame (switch, per output), Thickness, Inner corners, Keep windows inside
  (`reserve`). The preview is the live frame (no separate preview surface).

## Session 15 additions (K74)
- **Bar on hover** (user: "the frame doesn't connect to the edge of the screen if the bar is only shown on hover"): a
  docked hover bar keeps the frame's band (`thickness`) on its edge while it is away, the fillets hanging on the band;
  coming out, it is the band grown thick — its inner edge moves and the frame's fillets, arcs, side bands and rules follow
  it on all four edges, as do the columns joined to it (Caelestia: the bar's width animates from the border's
  thickness). Its overshoot widens it inward and settles.
- **One radius** (user): the inner corners are `theme.shape.radius − thickness` (concentric with an outer corner of R; 0
  at least), the same radius as every dynamic join and the joined dock's and columns' corners; `layout.frame.radius` is
  gone. A square look (`corners = none`) squares the frame too. Screen corners keep their own key (R recommended; whether
  they follow R is open, I269).
- **Screen corners** sit on the overlay layer: nothing the shell draws comes out over the screen's edge.
- A card resting under a bar widget keeps clear of the bands, the inner corner and side bars.

## States
off (no surface at all) · on with a top bar (default) · on with the bar on another edge · on with no bar · floating
bar inside · bar hidden (`visibility: hidden`) — the band stands where the bar was · fullscreen window (band 0 on that
output) · reserve off (windows under the band; the band is drawn over them) · several outputs with different settings ·
line / flat / keycap / soft / pen chromes · light and dark · reduce transparency (opaque fill) · high contrast (flat,
outline forced) · screen corners on and off · 720 p and 4 K outputs.

## Fit and constraints
Ma: four static strips, nothing animates while nothing changes; turning the frame on or off animates the band once
(≤ 240 ms, `motion.std`), cut under reduce motion. Budget: per output ≤ +2 MiB PSS for the strips (they replace
nothing; the bar's own budget stays), 0 idle frames, no wakeups. Shōjiki: `frame.reserve` off says "windows go under
the frame". Rule 4: the frame binds only to tokens (`panel`, `outline`, `radius.*`, texture tokens). Contracts:
`runtime.layout` (PROTOCOL §3.1).

## Definition of done
- [ ] frame on/off per output; windows tile inside it with reserve on (niri **and** the sway sandbox: zone + margin
      arithmetic differs between them), under it with reserve off
- [ ] a docked top bar and the band are one sheet: same fill, no seam in washi (paper grain) and sekai; the line-chrome
      rule runs from the bar round the inner fillet into the band
- [ ] floating bar inside the frame (image 8); bar on each of the four edges; no bar
- [ ] inner radius 0 and 48; thickness 2 and 32; screen corners on together with the frame
- [ ] fullscreen: band steps aside, comes back after
- [ ] idle 0 frames; PSS per output measured (pairs) and in BENCH
- [ ] shots: `frontend/shots/frame/<decor>/*.png` for washi, sekai, glass, win95, terminal; light + dark

## Later
Ornaments in the corners (BACKLOG) · the band's thickness per edge (BACKLOG) · the frame as the light's rim.
