# Card W21-island-morph — a dynamic island that morphs (K42; user session 9, INSPIRATION.md)

**User:** "It also shows the concept of the dynamic island type module performed properly, ours is kinda stiff and non
functional at the moment." Copy what works in the references; do not invent what they already solved.
**References (read the code, it is in the lead's scratchpad clone; copy freely, MIT/GPL compatible for ideas):**
- **Capsule** (moiCR/Capsule, GPUI): `crates/app/src/capsule/animator.rs` — the island is ONE shape whose size springs
  between module sizes; width and height use different damping (`apple_island_morph_with_bounciness`: on expand width
  leads, height follows; on contract the reverse), optional squash & stretch mid-flight, content cross-fades in
  *after* the size (fade + scale 0.98→1, ≤160 ms, restarted on rapid changes, interruptible: a retarget starts from the
  displayed size). Idle = flip-clock; satellites = small bubbles beside the island for OSDs (`satellite/`).
- **Vitreus** (natepayn3/Vitreus): every panel is a drawer that grows out of the bar, joined by a liquid neck (concave
  fillets where the drawer meets the bar), same spring, folds back into it.
- **SekaiPop** (Blapples/SekaiPop): keycap blocks (now `Block.qml`), things pop up with OutBack and get "swallowed"
  when they turn off instead of fading.
Clones: `/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad/insp/{Capsule,Vitreus,SekaiPop}` (read-only).

**Read first:** `CLAUDE.md`, `docs/ux/island.md`, DESIGN-SYSTEM §4 "Chrome and the sekai decor" + §8, DECISIONS K42
(+ K16 Stage sizing, K24, K30, K35), `frontend/core/Theme.qml` (new tokens: keycap, outlineW, ringW, shadowDy, line,
ring, overshoot, springOn, spring, damping, iconFamily, selected, dataColor), `frontend/components/{Block,Icon}.qml`,
`frontend/components/Island.qml`, `frontend/surfaces/Stage.qml`, `frontend/components/faces/*`,
`frontend/components/expanded/*`.

**Owned paths:** `frontend/components/Island.qml`, `frontend/components/faces/**`, `frontend/components/expanded/**`,
`frontend/surfaces/Stage.qml`, new files under `frontend/components/island/**`, `frontend/test-stage.sh`,
`frontend/test-peek.sh`, `frontend/shots/{stage,island,peek}/**`, `docs/ux/island.md` (add a "Session 9 morph"
section), `i18n/{en,ja}/island.toml` (append). **Not yours:** `frontend/surfaces/Bar.qml` and every other surface,
`frontend/components/{Block,Icon,Button,IconButton,Chip,Slider,ToggleSwitch,NotificationCard,QuickPanel,QuickButton}.qml`
and `frontend/components/quick/**` (the lead and W21-phone restyle those in parallel — use them, don't edit them),
`frontend/core/**`, all Rust. A need outside → `docs/CONTRACT-CHANGE.md` row + say so in the report. Sandbox names
start with `w21-isl-`.

**Do:**
1. **One shape, pill → card.** When the island's card opens (`runtime.ui.panel` island / a face view), the Stage draws
   a shape that starts at the bar pill's exact rect and springs to the card's rect (Capsule's asymmetric width/height
   spring, `Theme.spring/damping`, interruptible), content fades in after; closing folds back into the pill. While the
   shape is out the bar's pill is hidden (the Island reads `runtime.ui` itself) so there is one island, never two. The
   Stage stays content-sized (K16): it may grow to cover the bar's strip above the card for the morph's duration. Top
   bar first; bottom bar mirrored; side bars may keep a slide-out.
2. **Liquid neck** (Vitreus): on a top/bottom bar the open card is joined to the bar by concave fillets (radius
   `Theme.rLg`), in the card's own colour, so it grows *out of* the bar. Keycap chrome: the card is a `Block` (outline,
   ring, hard shadow); flat chrome: fill + `Theme.outline` hairline.
3. **The pill** is a `Block` (`ringScale` ~0.5 so it fits the bar), its width/height retarget with a spring; a face change
   cross-fades + slides content (Capsule `ContentTransition::FadeScale`). Hover: grows a few px (spring) with the peek.
4. **Live faces:** media — tiny animated level bars beside the title while playing (visibility-gated, stopped when
   paused/hidden or `springOn` false); clock — flip digits on minute change (Capsule idle flip-clock); volume/brightness
   transients — the pill widens to show an icon + a level bar that fills with a spring (Apple/Capsule OSD), then
   swallows back. Icons via `Icon.qml` (Material Symbols names: schedule, music_note, volume_up, volume_off,
   brightness_6, notifications, bolt, bluetooth …) with the old glyphs as `glyph` fallback.
5. **Expanded views** (`expanded/*`) restyled with `Block`/`Icon` and tonal `Theme.selected` instead of accent fills;
   media view: big rounded art, keycap transport buttons, progress as a thick pill; clock view: month grid cells as
   small blocks with today lit.
6. Ma: nothing animates while hidden; no timers while idle; reduce-motion (`Theme.springOn` false) snaps.

**Acceptance:** `nix develop -c frontend/test-stage.sh` and `nix develop -c frontend/test-peek.sh` green (update
their expectations where the morph changes geometry, never delete a check); `nix develop -c frontend/test-look.sh
sekai` and `... wa-iro 'theme.decor = "none"'` produce `island.png` showing the card grown from the bar; add a
`LOOK_STEPS` step or your own script that grabs **3 frames mid-morph** (e.g. grim at 40/120/250 ms after
`kurashi act island.expand`) into `frontend/shots/island/morph-*.png` proving one continuous shape. No QML errors in
the logs. Report: what you built, screenshots paths, the per-output idle cost if you measured it, follow-ups as
backlog suggestions (the lead files them).
