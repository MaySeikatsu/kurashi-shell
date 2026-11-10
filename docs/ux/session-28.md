# Session 28 — UX brief: surface lines, controls, connections, cards that follow, colour flow, text effects, layout moves
Status: built in one session (2026-11-10), seen on nested niri by the lead; **the user has judged none of it in motion**.
One brief for seven features because they were asked for together; each section is short and names what is not done.

## 1. Surfaces without a line (K127)
**Job.** "Even if chrome is set to flat and/or frame outline is off, widgets, cards, dock, sidebars all still get that
outline" (user, session 28). One rule: `Theme.surfaceLineW`. A surface that stands by itself (card, peek, toast,
desktop widget, floating dock or sidebar, the launcher) draws the chrome's own outline where the chrome has one; under
a chrome with none (flat, soft, paint) it draws a hairline only while `theme.frame_outline` is on. What is joined to the
frame or a bar (dock, sidebar, a joined card: `ColumnShape`) follows the frame's outline alone.
**Others.** GNOME and macOS draw no line and separate by shadow; KDE Breeze draws a 1 px line always; Material 3
separates by tone; Caelestia by the sheet's own edge. With Flat there is no shadow either: the user's choice, and On
gives the line back.
**States.** Automatic under flat/soft = Off. Keycap/Lines keep their ink. Menus, tooltips, the polkit dialog keep
their hairline (small popups over anything).
**Done.** `frontend/test-outline.sh` (Automatic = Off pixel for pixel; On differs), seen on niri dark and light.
**Not done.** Keycap chrome with the frame outline Off: the island's morphing card keeps its ink (the chrome's block).

## 2. Controls: sliders and switches (K128)
**Job.** "Build more stylized sliders and toggles … unify them across the whole UI"; the user likes Material's
expressive slider. One face per control for the shell AND Settings (Settings hosted its own plain drawing before): the
look's `[slots] slider|toggle`, or the user's pick (`theme.slider`, `theme.toggle`).
**Faces.** Sliders: Line (the refined default), Expressive (Material 3, 2024), Capsule, Wave (moves only while held),
Blocks, Ink (a brush stroke and a seal's dot: washi, kami), Glow; the looks' Fluent, Classic, Gauge stay theirs.
Switches: Switch (default), Expressive, Capsule, Lamp, Stamp (kami), Flip; Classic stays 9x's.
**Others.** Material 3 expressive slider and switch (handle grows, icon in the thumb); iOS's capsule slider and
stretching knob; Android 13's wave for media; One UI's block volume; Fluent's ringed thumb.
**States.** Rest, hover (halo, knob opens), held (knob widens, wave runs), focus (the host's ring), disabled (50 %),
unavailable (the slider's "⊘", unchanged). On/off never by colour alone: bar and ring marks.
**Keyboard, a11y.** Unchanged: the hosts keep input, roles and names; faces only draw.
**Budget.** Static at rest; Wave's phase runs only while pressed. Keycap chrome and material-on-controls keep the
built-in drawing (ringed knob, relief).
**Settings.** Pictures of the real faces (`ChoiceCards`), also for Chrome (item 6), Connection and its corner.
**Not done.** Vertical variants of the new faces are turned, not redrawn; no parts-sheet row (I326); the picture cards
have no hover preview on the live shell.

## 3. Connections (K129)
**Job.** "Rework connection styles … a separate setting … without being dependent on chrome."
`theme.join`: Automatic (the look's), Joined, Floating (a card of its own under its module, a gap off the bar).
`theme.join_corner`: Rounded, Cut, Steps (I270), Drop, Square — for every joined fillet (cards, the island's card,
dock, sidebars, edge modules), drawn by one path post-processor (`corner.js` `squircled(…, join)`).
**Others.** Caelestia and Noctalia: rounded fillets only; end-4: floating; DankMaterialShell: either; macOS notch
apps: the fillet; pixel shells: stairs.
**Not done (BACKLOG).** The head-and-neck topology under any chrome (a card on a narrow neck) drew wrongly under flat
and was left out; an overlap style; a size of its own for the corner beyond `radius_joins`; the frame's inner corners
keep their radius (they are not joins).

## 4. Cards follow the pointer (K130)
**Job.** A card opened on purpose moves to the monitor the pointer goes to (`bar.popups_follow`, on by default):
it folds where it is and opens on the other screen under the same module. Not hover-opened cards (they close on
leave), not tray menus (they belong to their icon), never sidebars.
**Reading of the request.** "but clicked open widgets (add toggle but make this default)" was read as: cards opened by
a click follow, and that is the default. If the user meant the opposite (clicked cards stay), the switch is the fix.
**Others.** GNOME and KDE keep popups on the monitor of their panel; macOS menu extras stay; Caelestia's popouts are
per monitor.
**Done.** `frontend/test-follow.sh` (two outputs: opens on the focused one, follows, comes back, stays when off; with
motion on and off).
**Not done.** The launcher and the notification centre do not follow; niri focuses an output when the pointer crosses
it, Hyprland and sway by their own focus rules.

## 5. Colour flow (K131)
**Job.** "Color animations for gradients, glow, frame outlines … a proper system." One clock (`core/ColorFlow.qml`),
three takers: the chrome's gradient (moved in `wash.frag` by a phase uniform), the frame's outline and what joins it,
the frame's glow and the Glow chrome's light. Patterns: Drift, Breathe, Cycle, Chase. Colours: Tones, Palette, Rainbow.
Speed. Runs: Always, While something is open (default), While music plays.
**Ma.** Off by default. The clock runs only in its moment; stopped, colours rest where they are. Reduced motion and
the motion profile None turn it off in the daemon. A hand-drawn outline is painted once and tinted on the GPU.
**Others.** Hyprland's animated gradient borders (`borderangle`), KDE's rainbow borders effect, RGB lighting tools'
breathe/cycle/chase vocabulary.
**Not done.** No suite counts frames while it runs or proves none at rest (the idle suites run with it off); Chase on
the line is a pulse, not a light travelling along the path (that needs the line in a shader); the audio-reactive
border (I450) is not this.

## 6. Text effects and fresh text (K132, I473)
**Job.** Effects (Glow, CRT, Candle, Rainbow, Shimmer) and how fresh text appears (Typed, Deciphered, From kana,
Brushed, Rise, Ink). One component, `TextFx`, put inside a `Text`; it hides the glyphs for the moment and draws a copy
with the final layout, so nothing shifts. Scope: Headings, or Every label that carries one.
**Wired.** Card and page titles, the bar clock, notification titles, sidebar headers, desktop widget titles, the
session menu, launcher and polkit headings; labels: quick tiles, level rows, control modules.
**Ma.** A spawn is one short animation; Candle and Shimmer move only while something is open.
**Others.** Old and indie games' typewriter text; "decrypt" text effects; kana-to-letter reveals in Japanese UI
motion; macOS's shimmer on "slide to unlock".
**Not done.** Most body text carries no `TextFx` (hundreds of `Text` items); "each letter written, its lines redrawn"
(stroke order) and sparkle are not built; Rise needs one line; rich text is left alone; no suite.

## 7. Layout moves (K133, I472/I478)
**Job.** A bar that changes its edge travels: Along the sides (default), Parts in the middle, Drips, Fades, Off
(`theme.motion.layout_move`). A click-through overlay per output draws the bar's body on its way; the new bar waits
unseen and comes up under it.
**Not done.** The body is the bar's fill, not a still of its content (the brief's captured picture); sidebars changing
side, the dock changing edge, the frame turning on, a profile switch with several changes at once (only one bar gone
and one come is a move); no suite ("ends pixel-equal to a fresh start"); floating keycap groups travel as a strip.
