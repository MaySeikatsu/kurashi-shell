# W64 — Every form on the dock, the bar's reveal and the web dock (session 21, user)

**Goal.** The user: "all animations should be available for all components". Since d8513d0f every form but liquid
serves every surface class in the forms meta (`crates/kurashi-motion/src/forms.rs`); this card makes three hosts that
still ignore the motion forms actually draw them, shape and sheet forms both, exactly like the sidebar and the toasts:
1. **Dock** (`frontend/surfaces/Dock.qml`): its `SurfaceForm` has `sheets: false` and no card-level FormHost, so a sheet
   form (genie, fold, roll, drop, pixelate …) falls back to the slide. Give it a FormHost like `Sidebar.qml` (W59.3/
   W59.9a: `sbHost`, `SheetRest`, the shadow/fillet/blur handover, the press point) and set `sheets: true`. aqua's genie
   must pour out of / into the dock's edge (the dock is the genie's natural target).
2. **Bar "show on hover" / "empty desktop"** (`frontend/surfaces/Bar.qml`, EdgeReveal): the bar slides in on its own
   Behavior. Run the reveal through `SurfaceForm`/`FormHost` with `surface: "bar"` (role `fast`, brief §6), so
   `theme.motion.form.bar.{open,close}` (and the default) apply; `slide` must look exactly as today.
3. **Web dock** (`mods/webdock/qml/DockWindow.qml`: hard-coded 180 ms `NumberAnimation`s for the strip and the card;
   the overlay/floating panel mode, not the niri-window mode `host/SideWindow.qml`): the card/panel opens and closes
   through the shell's FormHost with `surface: "panel"` (the strip itself may stay a slide on the profile's `fast`
   curve). `mods/webdock/host/core` links `frontend/core`; add the same kind of link for `frontend/components/motion`
   (and `frontend/shaders/motion` if needed) so the host loads the shell's forms — no copies. Reduce motion stays fades.

**Owned paths.** `frontend/surfaces/Dock.qml`, `frontend/surfaces/Bar.qml` (+ the EdgeReveal file it uses, if the
reveal lives there), `mods/webdock/qml/`, `mods/webdock/host/` (links only, plus `shell.qml` if an import is needed),
`frontend/test-dock.sh`, `mods/webdock/test/`, a new `frontend/test-motion-hosts.sh` if useful.

**Frozen (the lead edits these in parallel — read, never edit).** Everything under `frontend/components/motion/`
(FormHost, SurfaceForm, SheetForm, SheetRest, ShapeLayer, the forms), `frontend/core/`, `frontend/surfaces/Stage.qml`,
`Sidebar.qml`, `Toasts.qml`, `crates/`, `motion/`, `styles/`, `settings/`. Need a change there → CONTRACT-CHANGE row and a
local stand-in.

**Rules that bite here.** Ma: at rest no layer, no Loader item, no timer — the sidebar leaked +11 MiB USS once (W59.9a,
`980b7de9`: outline rects made only while they step); measure USS before/after 20 open/close cycles. The landing is
seamless: frames at p = 0.9, 0.97, 1 match the card at rest (no corner pop, no shadow jump). A reversal mid-way continues
the form in flight (SurfaceForm latches).

**Acceptance.** On nested niri (`tools/bench/niri-sandbox.sh`, washi + aqua + kami): for the dock, the bar (visibility
hover) and the web dock's overlay card, one frame sheet each for `genie`, `fold`, `pixelate`, `iris` and `slide`
(`MOTION_SLOW` style: `theme.motion.speed = 0.25`), plus a USS line before/after 20 cycles. `just suites --changed` green
(test-dock, test-bars, webdock's tests), `just check` green. Shots stay local (I345: the sandbox sees the real HOME —
film no sidebar, launcher or terminal).

**Model.** Opus (landing seams and Ma need judgement).

**Thrift.** Read this card, `docs/ux/motion-engine.md` §5–§7 and §9, `Sidebar.qml`'s form parts (lines ~230–280 and
~500–850) as the pattern, `Toasts.qml`'s FormHost, then your files. Terse report per `docs/tasks/README.md`. Build in
`CARGO_TARGET_DIR=$HOME/.cache/kurashi-agents-target/W64`. No AI attribution in commits.
