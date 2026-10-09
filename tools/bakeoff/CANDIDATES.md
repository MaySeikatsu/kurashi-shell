# Bake-off candidates — per-framework hints (append to the task card for each agent)

## quickshell
- Quickshell 0.3.x from nixpkgs (`qs -p archive/bakeoff-probes/quickshell`). QML only; no Rust in the probe.
- IPC: `Socket` + `SplitParser { splitMarker: "\n" }`; write with `socket.write(JSON.stringify(m) + "\n")`.
- Windows: `Variants { model: Quickshell.screens }` + `PanelWindow`; popup via `PopupWindow` with
  `anchor.window` + `anchor.rect` (**never** assign `anchor.item` dynamically — segfaults in 0.3).
- Blur: `BackgroundEffect.blurRegion: Region {...}` (must be a Region or null, never a bool).
- Shader: `ShaderEffect` needs a precompiled `.qsb` (`qsb --qt6 -o x.frag.qsb x.frag`, qtshadertools
  from nixpkgs); premultiplied alpha output; drive time with `FrameAnimation { running: popup visible }`.
- First-frame gate: `Connections { target: someItem.Window.window; function onFrameSwapped() {…} }`.
- Runtime mod UI: recursive `Loader`/`Repeater` choosing a `Component` per node type.
- Quickshell gotchas: a binding on `font.variableAxes` reading `font.*` crashes; never start a
  `Process` from another Process's completion handler.

## iced
- iced 0.14 + `iced_layershell` (check crates.io for the newest version compatible with iced 0.14;
  read its examples for multi-window/multi-output and popups) — `iced_sessionlock` exists (don't build).
- Socket: tokio `UnixStream` in a `Subscription` (stream) → messages; NDJSON lines.
- Shader: `iced::widget::shader` (wgpu). Note wgpu vs tiny-skia renderer memory if easy.
- Blur: check if `iced_layershell` exposes the raw `wl_surface`; otherwise report ✘ with reason.
- Animation: iced 0.14 animation APIs (`Animation`, `Animated`) or manual with frame subscription
  that stops when idle.

## slint
- Slint (latest 1.x). Layer-shell: own glue via smithay-client-toolkit **or** `layer-shika`
  (AGPL — acceptable for the probe only, note it).
- Runtime mod UI: `slint-interpreter` to compile a `.slint` snippet generated from the `ui` tree,
  or a generic recursive component. Report which.
- Custom shaders: Slint has no shader API in `.slint`; report what is possible (e.g. render into an
  image buffer) and mark ✘/partial honestly.

## gpui
- `gpui` from crates.io (or zed git if the layer-shell API needs it) + optionally `gpui-component`.
- Layer shell: `WindowKind::LayerShell(LayerShellOptions{..})`; check popup support on layer
  surfaces (`AnchoredPopup`?). Reference: github.com/andre-brandao/gpui-shell.
- Shaders: no public custom-shader API known — verify and report.

## gtk4
- gtk4-rs + `relm4` + `gtk4-layer-shell` crate (Wayle is a real-world reference).
- Shader: `GtkGLArea` (or `gsk` GL shader node if available) — report which.
- Popup: `GtkPopover` on the layer surface, or a second layer-shell window.
- Blur: no GTK API; check raw `wl_surface` access via `gdk4-wayland` → ext-background-effect.
- Runtime mod UI: build widgets from the tree at runtime (natural in GTK).
