# W53 — styles that look like their inspiration, each with its own lock screen

**Asked by the user (session 16):** "Rework the existing styles to look closer to their inspiration and integrate deeper
into the whole shell's design language — themes like Windows 95/98, Windows XP, Windows 7, Windows 10/11 should all look
just like their respective Windows counterparts (the current implementation is just not there yet); same for the macOS
inspired theme; SNES is not bad but could be more expressive, same for PlayStation and so on. Expand the styling system
with further components, decoration, or whatever is necessary to implement those styles as close as possible — they
should all also come with their own custom lock screen. Some inspiration can be drawn from the shellseikatsu
lockscreens, but don't just copy — improve on them."
Done already (session 16): styles that were only a palette (catppuccin, rose-pine, tokyo-night) are palettes (K75).

This is a wave, not one card: the lead writes the UX brief first, then splits it (one card per style family plus one for
the shared system), runs them in parallel worktrees and reviews every shot against the brief.

## 0. Read first
- `docs/DESIGN-SYSTEM.md` (tokens, looks, styles, decor packs, "Texture and light"), `docs/DECISIONS.md` K42, K45, K50,
  K53 (style = look + palette + recipe), K59–K62 (material, light, pen), K67 (shadows), K74 (radius, motion), K75.
- `looks/*.toml`, `styles/*.toml`, `palettes/*.toml`; `crates/kurashi-theme` (`appearance.rs` LOOK_KEYS / STYLE_KEYS,
  `tokens.rs`, `decor_recipe`); `frontend/components/Block.qml` (the one chrome shape), `FrameHost.qml` + `frames/`
  (decor frames), `frontend/surfaces/Lock.qml` + `components/LockContent.qml` (today one lock screen for all),
  `greeter` (the login screen reads the theme cache).
- shellseikatsu `~/Documents/projects/quickshell/shellseikatsu/Panels/Lockscreen/LockStyle*.qml` (18 styles: Win11, Win7,
  XP, macOS, PS2, SNES, Retro, RetroTv, Kawaii, Nier, Souls, Hollow, …) and `Services/Modes/*.qml` — inspiration only:
  note what each gets right and what it fakes, then do better (real layout metrics, real states, keyboard, a11y, ja).

## 1. The UX brief (`docs/ux/styles.md`) — before any code
Per style: the reference (OS version, screenshots by URL, measured metrics: title bar height, border widths, bevel
colours, fonts and their free stand-ins, corner radii, shadow, button states, focus ring, scroll bars, menus, tooltips,
the taskbar/menu bar's anatomy and the start button/Apple menu), what maps onto our surfaces (bar ↔ taskbar/menu bar,
island ↔ ?, Stage cards ↔ windows/flyouts, sidebar ↔ action centre/notification centre, dock ↔ dock/taskbar pins,
launcher ↔ start menu/Spotlight, quick settings ↔ control centre, toasts ↔ balloon tips/notifications, lock screen ↔
the OS's lock/login), what we deliberately do not copy (trademarked logos and wallpapers: draw an original mark in the
same spirit, never the real one), states (empty, loading, error, offline), keyboard and a11y (high contrast, reduced
motion, large text keep working), motion (each OS's own timing), multi-output, budget (memory per extra decor ≤ the
current frame allowance; 0 frames idle).

Styles in scope: **win95** (Windows 95/98: grey bevels, the 3D border pair, MS Sans Serif-like bitmap type, the start
button), **luna** (Windows XP), **aero** (Windows 7 glass, its blur and glow), a new **fluent** (Windows 10/11: Mica,
rounded 8 px, Segoe-like type), **aqua** (macOS — pick one era per style, e.g. aqua = 10.x pinstripes, a new modern
macOS one = Big Sur+), **snes**, **ps2** (more expressive: their boot screens, menus, sounds as optional cues), and
review the others (sekai, kawaii, yorha, souls, hallownest, washi, kami, kanso, material, glass, terminal) for the same
depth.

## 2. The shared system (one card, first)
What the styles need that the system lacks today — decided in the brief, likely:
- **Decor components** per slot, chosen by the look (K50 decor packs, rule 4: renderers bind to slots and tokens, never to
  a style's name): title bars on Stage cards, window-style borders (bevel pairs: light/dark outer and inner), a
  start-button slot at the bar's start, a clock/tray well, a menu style (row height, separators, submenu arrows), a
  scroll bar style, a tooltip style, button bevel/press states (Block's chrome gains a `bevel` chrome next to
  outline/ring/hard/soft shadow).
- **Type**: per-look font stacks with free metric-compatible stand-ins (bundled where licences allow), optional bitmap
  rendering (no smoothing) for the 9x looks.
- **Lock screen per style**: `lock.style` follows the look by default (a toggle to keep the plain one); a lock-face slot
  that a look names (`looks/<n>.toml [slots] lock = "<face>"`), the faces in `frontend/components/lock/` — each with the
  clock, the user, the password field and its error/capslock/fingerprint states, keyboard only, the greeter using the
  same face. Contract change (schema key, decor slot list): DECISIONS + PROTOCOL if a document carries it.
- **Sounds** (optional, off by default): a cue set per style through the daemon (Ma: nothing loaded while off).
- Tests: `frontend/test-styles.sh` shooting every style × surface (bar, a Stage card, the launcher, the sidebar, a toast,
  the lock screen) into `frontend/shots/styles/<style>/`, with pixel checks for the bevels and title bars; the lead
  reviews the sheet against the brief.

## 3. One card per family (after the system card merges)
Windows 9x · Windows XP/7 · Windows 10/11 · macOS (both eras) · consoles (SNES, PS2) · fiction (yorha, souls,
hallownest, kawaii) · Japanese (washi, kami, sekai) · modern (kanso, material, glass, terminal). Each card: owned paths
`looks/<style>.toml`, `styles/<style>.toml`, `palettes/<style>.toml`, `frontend/components/decor/<style>/…`,
`frontend/components/lock/<Style>Face.qml`, its i18n keys, its shots; acceptance = its row of the shot sheet matches the
brief, `test-styles.sh <style>` green, no QML warnings, PSS within budget.

## Definition of done
Every style reads as its inspiration at a glance on every surface and on its lock screen; keyboard, a11y and ja work in
each; Settings' style cards show true previews; `just check` and the frontend suites green; BACKLOG rows for every
"later".
