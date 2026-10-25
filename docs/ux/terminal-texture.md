# UX brief: the material in the terminal (I174, card W37; K49, K59, K61)

The shell's material (paper, stone, brush and the rest, `docs/ux/texture.md`) stops at the terminal: K49 exports the
palette to foot, kitty, alacritty and ghostty, but the page under the text stays flat. Ghostty is the one common Linux
terminal with a shader hook (`custom-shader`). The ghostty export now also writes a generated shader that lays a relief
close to the active kind over the terminal's background. The rule over all of it is that **readability beats texture
strength**: the relief never touches text, and it backs away from text by a few pixels.

User (session 13, item f): terminal textures. BACKLOG I174.

## What each terminal allows
| Terminal | Hook | What the material can be there |
|---|---|---|
| **ghostty** (1.0+, checked on 1.3.1) | `custom-shader = <file>` (repeatable, run in order): GLSL in Shadertoy style, `mainImage(out vec4, in vec2)`. `iChannel0` is the rendered terminal, `iResolution` is in device px. `iTime`, `iFrame` and the cursor uniforms (`iCurrentCursor`, …) are there too, and 1.3 adds the colours (`iBackgroundColor`, `iPalette[256]`, …). There is no texture of your own: `iChannel1-3` do not exist and `iMouse`/`iDate` are not supported. `custom-shader-animation = true` (default) runs a frame loop while the window is focused, `false` draws only when the terminal does, `always` runs it unfocused too. A theme file may set any option but `theme` and `config-file`, so `custom-shader` can go in the theme. A shader that fails to compile is ignored and the error only goes to the log. | **a procedural relief per kind, computed per pixel.** This is the card's target. |
| **Windows Terminal** | `experimental.pixelShaderPath` (HLSL, the terminal as a texture) and `backgroundImage` | The precedent for terminal shaders (retro/CRT effects). Not on Linux. |
| **kitty** | No user shaders. `background_image` (PNG; `background_image_layout tiled`), `background_tint` | A *baked tile* as a tiled background image could carry the material (the daemon already bakes previews). The light would be baked in and there would be no text margin. Idea, not built (see "Not done"). |
| **WezTerm** | No user shaders (WebGPU/OpenGL internally). `background` layers with images, gradients and `hsb` | Same as kitty: a baked tile is possible, no live relief. |
| **foot, alacritty, GNOME Terminal / Ptyxis, Konsole** | Colours and alpha only. Konsole's colour scheme can name a wallpaper picture | Colours only, as K49 already exports them. |
| **Rio** | RetroArch `.slangp` filters (CRT and the like) | Possible, but a niche terminal. Not now. |
| **Compositors** | Hyprland `decoration:screen_shader` (the whole screen). niri, sway: none | I164: a later Hyprland adapter. The `everything` scope already overlays apps. |

How other shells handle it: none of the Quickshell shells (Caelestia, end-4, DankMaterialShell, Noctalia) or HyprPanel
textures the terminal. matugen setups theme ghostty's colours only, and rice configs share ghostty shaders for CRT,
bloom and cursor trails. GNOME, KDE, COSMIC and macOS have no materials. So this is new ground, and the bar is "does
not cost a single legible pixel".

## Model
- **Where:** target `ghostty` in `theme.export` (opt-in, K49). The export writes `ghostty/themes/kurashi` as before. The
  template's `{{ghostty.shader}}` line becomes
  `custom-shader = <$XDG_CONFIG_HOME>/ghostty/shaders/kurashi.glsl` and `custom-shader-animation = false` while the
  material is on for the shell, and stays empty otherwise. The shader file is written **before** the theme that names
  it, and only when its content changes (K49). The path is absolute, so it never depends on how ghostty resolves a
  relative one.
- **What:** `crates/kurashi-theme/src/ghostty_shader.rs`. One GLSL recipe per kind (hash, value noise, fBm, Voronoi):
  - paper: fibres, felt, pores and a formation cloud
  - paper_dots/lines/grid: the quiet stock with 24 px rulings, printed as ink, or pressed in with the tint off
  - fabric: a plain weave with slubs
  - wool: knit loops with fuzz
  - stone: fractal grain, pits and fine veins
  - halftone: dots at 45°
  - metal: brushed lines and scratches
  - leather: pebbled cells, pores and creases
  - wood: rings, late wood and pores
  - paint and brush: bristle grooves along a wandering stroke, with ridges where a stroke ends

  `theme.texture.wrinkles` adds creases. `theme.texture.cracks` adds Voronoi crack lines: jagged for stone, straight
  for glass.
- **Light and response:** the theme's tokens are baked in as constants: `light.dir` (rounded to 0.01, so the daytime
  sun rewrites the file only when it really moves), `light.color`, `texture.amp` (the shell's legibility cap included),
  `gloss`, `shininess`, `depth`, `lit`, `ink`, `ink_alpha`, and `scale` × the tile's device scale. The shading is
  `kurashi_texture::shade_with` line for line, without the spotlight's beam and the relief shadows. The terminal has
  its own sheet from its top-left corner, y down. The pointer, spotlight and wallpaper lamps show as their static
  direction: a terminal knows neither the pointer nor where its window sits.
- **Readability:**
  - Only pixels of the baked background colour (`color.surface`, the colour the template gives ghostty) get the
    relief, in either encoding (sRGB, or linear when ghostty blends linearly). Unpremultiplied, so `background-opacity`
    works.
  - No pixel within 3 px of anything that is not background (40 taps of `iChannel0`) gets it, and it fades in over the
    next 3.5 px. Text, the cursor, selections, reverse-video rows and coloured cells pass through bit for bit, and so do
    the pixels right round them.
  - Measured in the sandbox: 0 changed non-background pixels, and text contrast against its surroundings within
    0.62 % at worst (1 % allowed).
- **Static:** the shader reads no time, and the line sets `custom-shader-animation = false`. It runs only when ghostty
  draws a frame (output, typing, resize) and never while the terminal is idle (Ma).

## States
| State | Result |
|---|---|
| Material on, scope `shell` / `shell_wallpaper` | Shader written, the theme names it |
| Kind `none`, high contrast / reduce transparency (forced off), the tile still generating | No line. A shader file left from before becomes a **pass-through** (`PASS_THROUGH`), so a config that still names it (a terminal not reloaded yet, a line copied by hand) keeps working and shows the terminal unchanged. This is K49's legacy-stub rule. A fresh config gets no file at all. |
| Scope `wallpaper` | No line: the material is not on the shell's surfaces |
| Scope `everything` | No line: the click-through overlay already lies over the terminal, and a shader would shade it twice |
| Kind without a recipe | Can't happen for today's 13 kinds: kurashid's test holds `KINDS` to `kurashi_texture::Kind::ALL`, so a new kind fails CI until it gets a recipe. An unknown name reports `Off::Kind` and writes no line. |
| ghostty not installed | Harmless files nobody reads. Settings shows the target and its include line as for every target. |
| ghostty not reloaded | Ghostty reads its config at start and on `reload_config` (default ctrl+shift+,). Colours behave the same way today (K49). |
| The user's own `background = …` over the theme | The baked colour no longer matches, so no pixel gets the relief: honest, never wrong. Ghostty 1.3's `iBackgroundColor` could follow it, but older ghostty would then fail to compile the shader (silently ignored). |
| The user's own `custom-shader` in their config | `custom-shader` is repeatable, and ghostty runs the listed shaders in order. Whether ghostty keeps the theme's entry beside the user's own depends on its merge rule, which is not tested here. |
| Shader compile failure (a future ghostty) | Ghostty ignores the shader (log only) and the terminal stays plain. The generator test compiles every kind with glslang using ghostty's prefix. |
| Svc document | Today the `svc.theme_export` entry says nothing about the shader. CONTRACT-CHANGE row 401 asks for `targets[].shader` (on, or off and why) so Settings can say so. |

## Keyboard, a11y
- No new controls: `theme.export` and `theme.texture.*` are existing schema rows.
- High contrast forces the texture off, and with it the shader.
- Text pixels are never altered (tested), so screen-reader-free legibility and any terminal zoom or font size keep
  their contrast. The margin scales with the output scale (`DEV`).

## Motion
None. The relief is still and never animates (the animation loop is off). On resize the sheet stays anchored to the
top-left corner, so it does not swim.

## Multi-output
One shader for every ghostty window. Device px per sheet px is the largest output's scale (the tile's), as for the
shell's tile. On a lower-scale output the grain draws a little coarser.

## Budget (GPU per frame, only when ghostty draws)
- One full-window pass.
- Per pixel: 41 `iChannel0` taps, early out on non-background pixels, then 3 height evaluations (central value plus
  two differences).
- Light recipes (paper, rulings, fabric, metal): about 6 value noises per evaluation, so about 80 hashes per pixel.
- The heaviest (stone or leather with cracks): about 15 noises plus a 3×3 Voronoi, so about 250 hashes per pixel.
- Estimate: 1–3 ms per frame at 1080p on an integrated GPU, and about 4× that at 4K. During fast scrolling at 4K on an
  iGPU this can cost frames with the heavy kinds.
- Idle: 0 frames, 0 wakeups (static shader, no animation loop).
- **Not measured yet:** a BENCH row (ghostty frame time with and without the shader, per kind, 1080p and 4K) is the
  open item. Pre-computing the noise as a texture is impossible, since ghostty has no extra samplers.

## Definition of done
| Item | Status |
|---|---|
| Find what ghostty allows; write it here | met (from ghostty 1.3.1's own `+show-config --docs`) |
| Ghostty export writes `ghostty/shaders/kurashi.glsl` + `custom-shader` only while the material is on for the shell; the old file handled as K49's legacy rule | met (pass-through stub; test `ghostty_writes_its_shader_while_the_material_is_on`) |
| Procedural relief per kind, light, colour, `lit`, depth baked; cracks | met (13 recipes, wrinkles, stone/glass cracks) |
| Relief only on background pixels; text, cursor, selection untouched; text contrast within 1 % | met (sandbox: 0 changed non-background pixels; max contrast Δ 0.62 %) |
| `custom-shader-animation` off, static | met |
| Unit test per kind: compiles with glslang (ghostty's prefix), no unfilled placeholder; a golden | met (`every_kind_compiles_and_is_filled`, `golden_paper_dots`) |
| States: material off, kind without a match, ghostty missing | met (above; tests for off / scope / unknown kind) |
| Shots: two kinds × light/dark beside plain, `ls --color`, htop-like text, zoomed crop | met: `tools/shots/ghostty/{kami,stone}-{light,dark}.png` (plain left, material right) and `*-zoom.png` (plain above) |
| Budget measured | **not met**: estimate only (above) |
| Settings shows the shader's state | **not met**: needs CONTRACT-CHANGE row 401 |
