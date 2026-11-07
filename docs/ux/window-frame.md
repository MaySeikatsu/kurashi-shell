# Window frame colour — UX brief
Status: implemented (functional) (I423, session 24)

## Job
Say which colour rounds the focused window. The compositors took the palette's primary by hand, so under kami a frame was red
while the shell's outlines were blue: two inks where the look means one.

## References
- **niri**: `focus-ring`/`border` `active-color`, a colour or a gradient, per config. **Hyprland**: `col.active_border`, gradients too.
  **sway**: `client.focused` per part. **MangoWM**: `focus_color`.
- **DankMaterialShell, Noctalia, Caelestia**: primary, fixed by the template. **KDE**: the accent or the titlebar's colour, a switch in Colours.
- **macOS, Windows 11**: the accent on the border, as a switch ("Show accent colour on title bars and window borders").

## Design
`theme.window_frame_color`, under Colours beside Window frames: **Accent** (default, as before), **Shell outline**, or a role: Secondary,
Tertiary, Outline, Text. Shell outline is `Theme.frameOutlineColor` opaque: the text's ink, the accent, the chrome's outline, or the
outline role under a chrome that draws none. It follows `theme.outline_ink`, so a look that changes the ink changes the frames.

Covers niri (focus ring, border, tab indicator), Hyprland (active border, group), MangoWM (focus), sway (border, child border). Sway's titlebar
background stays primary with its on-primary text: the frame setting should not risk unreadable titles. Insert hints and locked groups stay as they were.

## States
- Default: nothing changes. - Window frames off: niri's focus ring still takes the colour, and so does any compositor that keeps its own width.
- Compositor not exported: the setting has no effect; Exports on the same page says which are written (Shōjiki). - Unfocused and urgent: outline and error, always.
- Gradients are not offered: one colour matches the shell's one-colour outlines.

## Keyboard, a11y, motion, multi-output, budget
A generated Settings row: keyboard and screen reader as every choice. High contrast leaves it alone. No animation of its own beyond the compositor's.
One colour per session, as the compositors have it. The export is written on change, no idle cost.

## Definition of done
- [x] Default unchanged, each choice in the written config (tests); every compositor template names it (test).
- [x] Seen on niri: changing the setting changes the border live.
- [ ] Hyprland, MangoWM and sway run with the written file by a person who uses them (only the text is checked here).
