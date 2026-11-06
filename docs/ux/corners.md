# Corners that match — UX brief
Status: implemented (functional) (I426, K96, session 24)

## Job
Every corner the eye compares should be the same corner: the window cut into the frame, the compositor's windows, desktop widgets, the dock, what merges into a bar. One slider sets them all; a surface can take its own.

## What was wrong (user, session 24, with screenshots)
Under washi (radius 9) with a 10 px frame: the frame's inner corner was **0** (K74 took radius − thickness), windows **9**, widgets and dock **13** (`rLg + 4`), the fillets of a card **4.5** (`rLg / 2`). Four numbers for one idea, and the frame's was the most visible.

## References
- **Caelestia** (`plugin/src/Caelestia/Config/borderconfig.hpp`, read 2026-11-06): one `border.rounding` (25) for the hole, a thickness of 10 beside it, panels at `appearance.rounding`. The hole's radius is what you set, not what is left of it.
- **end-4 ii**: one rounding token with a scale; windows taken from it by the config it writes.
- **macOS Tahoe, Windows 11**: fixed per surface class, all near one family; nothing shows a square next to a round.
- **DankMaterialShell**: one corner radius slider; windows follow by a generated config.
- **COSMIC**: a roundness setting (Round, Slightly, Square) across windows and shell.

## Design
- **The hole's radius is the radius you see.** K74's "R − thickness" kept outer and inner concentric by moving the inner; K96 moves the outer: frame corner = `R`, screen's corner = `R + thickness`, so the band stays one width round the corner and is as wide at the corner as elsewhere. (Square hole: square screen corner.)
- **Tokens**: `radius.frame`, `radius.join`, `radius.window`, `radius.widget`, `radius.dock`, each `radius.lg` until the surface has its own. Squircle scale and a square look apply to them as to `radius.lg`.
- **Settings** (Shape): `theme.shape.radius` as before, and under it Frame corners, Merging corners, Window corners, Desktop widget corners, Dock corners: a slider whose lowest step reads **Auto**. Each carries provenance like any row. A square look makes them inert, and the row says why.
- **What takes what**: frame → `radius.frame`, and the outer corner. Fillets of the dock, sidebars, edge modules, Stage and launcher cards → `radius.join`. niri, Hyprland, MangoWM → `radius.window`. Widgets, mods' desk cards → `radius.widget`. Dock → `radius.dock`. Launcher, centre, polkit, media, sidebars floating → `radius.lg`.
- **No nesting at the outer level**: a floating sidebar in a frame no longer takes the hole's radius less its gap (K74's `nested`); it matches. Content inside a card still nests: the plate in a card, a section in a sidebar.

## States
Auto: follows R. Own value: exact. `corners = none`: all 0, the rows inert, with the reason. Frame off: the hole's token unused; the screen's corner = the join's (no band to add). `screen_corners_follow` off: its own size, as before. Multi-output: thickness per output, so `frame.screen_radius` per output.

## Keyboard, a11y, motion, budget
Generated rows: keyboard and screen reader as every slider; "Auto" is read as the value. Changing a corner rebuilds static paths once; idle unchanged (0 frames). No new surface.

## Fit
Bigger joined corners need room in the Stage's, launcher's and dock's windows: they already keep a `neckR` of room, now at the join's radius. The dynamic popups that merge (I428) use the same token.

## Definition of done
- [x] On niri under washi with a 10 px band: the hole, window and widget corners read as one (`frontend/test-corners.sh`, pixels and tokens).
- [x] Each own value reaches only its own surface. A square look squares them all.
- [x] Screen corner concentric on every output.
- [ ] Reviewed by the user on their desktop.
