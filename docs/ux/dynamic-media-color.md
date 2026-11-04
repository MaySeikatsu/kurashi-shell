# Dynamic Media Color — UX brief (K87)
Status: agreed (user, session 22: prototype on their live shell, "just like imagined").

## Job
With one switch, the whole shell and the apps that follow its theme take the colours of the track playing now, and text stays
readable. Off, everything is as the user left it. A change of track never flashes: by default the colours fade.

## References
- **Ours:** the Now Playing card's cover colours (`svc.media.art_colors`, K48), from the same extraction as the wallpaper
  palette (K34). The card is the look the user asked the shell to take.
- **Quickshell shells:** DMS `MediaAccentService`, shellseikatsu `MediaColorService`: cover colours for media surfaces; K48
  took the idea from them. Here they drive the whole theme.
- **Android Material You, Windows 11 "accent from wallpaper", KDE accent from wallpaper:** a theme derived from a picture,
  but one that changes rarely and with no transition worth a setting. A track changes every few minutes, so the transition
  is part of this feature.

## Design
- **Switch:** Settings › Appearance › Colours, `theme.colors.media.follow` (off by default).
- **Tone** (`theme.colors.media.tone`): `cover` (default), the card's own colours, so a light style goes dark while they are
  in effect; `keep`, the user's light or dark in the cover's hue.
- **Change of colour** (`theme.colors.media.blend`, `blend_ms`, 1200 ms): `fade` (default), `wheel_closest` and
  `wheel_furthest` (round the colour wheel, the short or the long way, half as long again), `direct`.
- **The Now Playing card keeps its behaviour** (user): its own cover colours, changing at once. An option for it: I398.
- **What takes part:** every colour token, through the daemon, so bar, title bars, decor, Settings and exported apps agree.
  Meanings stay (error, warning, success, status). The material's ink and strength are worked out from the new colours, so a paper or a grid stays legible on them.
- **Honesty (rule 2):** the palette's row keeps showing the user's palette; a theme note says the colours come from the track,
  and the scheme's status line says "Following the track playing now".

## States
Off · on with a track (colours in effect) · on, track without a cover yet: the last colours hold, so a skip does not flash ·
on, cover unreadable, first track: the palette · on, no track: blends back to the palette, the switch stays on · paused: stays
· reduce motion or a profile that does not move: a cut · daemon restart: the same, once `svc.media` answers.

## Contrast
Text is at least the `theme.colors.contrast` target (4.5, 5.5 or 7:1) against the surface, every container and the selection:
text is pushed away first, then the containers lean less, and a mid-tone cover that no ink reads on moves away from its ink.
`media_tint.rs`'s tests sweep pale, grey, saturated and near-black covers. During a light↔dark blend text crosses the
background's lightness for an instant: a shorter blend shortens it.

## Keyboard, a11y
Ordinary Settings rows, from the schema. Reduce motion cuts. High contrast raises the target.

## Multi-output
One theme, as ever.

## Fit
A stage over the tokens (rule 1, rule 4), never a config change, so undo, profiles and "Back to …" are untouched. Previews in
Settings stay in the user's palette. Motion profiles do not apply: this is a colour change, with its own setting.

## Budget
Idle cost none: the blender's timer runs only during a blend, and the daemon holds `svc.media` only while the switch is on
(rule 5). A blend re-evaluates the colour bindings at about 30 Hz for its length.

## Definition of done
`frontend/test-dynamic-media.sh`: off leaves the theme alone; on recolours including a look's list tokens; colours in between
under fade; `direct` cuts; `keep` stays light; no track returns; off restores every token and the config holds only the switch.
Seen on niri under a custom style (YoRHa), by the user on the prototype.
