# W58-pointer-light — the pointer light and the spotlight across the whole screen (I311; effects sheet I312)

Session 18. Research + design first (a short DECISIONS entry), then code. Common rules: `docs/tasks/README.md`.

## Ask (user, session 17)
"The texture's light and the shadows should catch the pointer, or the spotlight following the mouse, all over the
screen, not only over the shell's own surfaces. Idea: a transparent overlay that never takes a click, only to know where
the cursor is even over a niri window. If there is a better or more efficient way, come up with it. That sheet could later
carry effects (ripples on a click, a trail behind the cursor, waves)."

## What Wayland allows (checked session 17)
- A client gets pointer motion only while the pointer is over its own surface's input region. A click-through overlay
  (empty input region) therefore receives no motion at all; one with an input region takes the clicks. **The overlay idea
  cannot see the cursor** — it can still *draw* (effects), fed by a position from elsewhere.
- niri 26.04: `zwlr_screencopy` only (it can draw the cursor into a capture, it never reports where); no
  `ext-image-copy-capture` cursor sessions; no cursor position in `niri msg` / the event stream.
- The standard answer is `ext-image-copy-capture-v1` **cursor sessions** (`create_pointer_cursor_session` → `enter`,
  `leave`, `position`, `hotspot` events): event-driven, no polling, exactly "where is the cursor on this output".
  wlroots ≥ 0.19 implements ext-image-copy-capture (check cursor sessions for sway); KWin and Hyprland: check.

## Routes, best first
1. **kurashid subscribes to cursor sessions** (wayland-client in a service, refcounted: only while a light mode or an
   effect needs it — Ma) and publishes `runtime.pointer {output, x, y}` throttled to the frame rate; the frontend's `Light`
   takes it instead of its own HoverHandlers. Works wherever the compositor implements the protocol.
2. **niri: add it.** A small niri patch — implement ext-image-copy-capture cursor sessions, or put the cursor position into
   the IPC event stream — carried in `nix/patches/` (as quickshell's) for the user's NixOS, and offered upstream. Ask the
   user before patching niri.
3. **Honest fallback** where neither exists: the light follows the pointer over the shell's surfaces (today) and rests
   where the pointer left them (not back to the middle); Settings says why (Shōjiki: "this compositor does not tell the
   shell where the pointer is outside its surfaces").
Rejected: raw `/dev/input` (needs the input group, acceleration and absolute devices make the position a guess, a
security smell); polling `hyprctl cursorpos` style IPC (wakeups, Ma).

## Effects sheet (I312, later)
An input-transparent overlay per output, made only while an effect runs (no window at rest: PSS budget), drawing ripples
/ trails / waves from `runtime.pointer` — clicks outside the shell need the same compositor support (a cursor session
reports no buttons), so click ripples are shell-surface-only until then.

## Acceptance
DECISIONS entry with the measured support per compositor (niri, sway, Hyprland); on a supporting setup the light follows
the cursor over windows on niri (shots: spotlight over a terminal); idle 0 wakeups with the light at rest; the fallback
labelled in Settings.
