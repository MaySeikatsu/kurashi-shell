# Card W22-styles — every decor a whole look; the keycap island joins its bar group (K45, I115)

**User (session 10):** "sekai should stay an option, other styles should have/keep their distinct look, just as sekai
has its own (WormShell describes it well)"; "everything layout related should stay same and looks/style wise should be
able to change with the themes"; on the keycap island card: "Yes it should join". Work efficiently: prototype in QML
first, don't compile Rust (you should not need to — the tokens exist), run the heavy scripts once most of it is done.

**References:** WormShell `~/Projects/quickshell/WormShell/docs/05-surface-style.md` (a style = corners, border, alpha,
blur, shadow, insets, motion, type, icons — never layout); clones (read-only) in
`/tmp/claude-1000/-home-maike-Projects-kurashi-shell/dbcea378-a7d4-4c51-ac59-ac9689ce0b5f/scratchpad/insp/{Vitreus,pleamar,SekaiPop,Capsule}`
— Vitreus/pleamar for `soft` (glass rims, soft shadows, pressed = shrink), SekaiPop for keycap.

**Read first:** `CLAUDE.md`; DECISIONS K42 + **K45**; DESIGN-SYSTEM "Chrome and decor packs" (the two tables are the
spec); `frontend/core/Theme.qml` (new: `chromeStyle`, `outlineColor`, `softR`, `softDy`, `softColor`, `pressScale`,
`groups`, `iconFill`, `iconWeight`); `frontend/components/{Block,Icon}.qml`; `frontend/components/island/*`,
`frontend/surfaces/{Bar,Stage}.qml`; `frontend/test-look.sh`.

**Owned paths:** `frontend/components/**`, `frontend/surfaces/**` **except `Desktop.qml`** (W22-tasks owns it),
`mods/webdock/qml/**`, `mods/webdock/host/*.qml`, `frontend/test-look.sh`, `frontend/test-island-morph.sh`,
`frontend/test-stage.sh`, `frontend/shots/**`, `mods/webdock/shots/**`, `docs/ux/island.md`, `docs/ux/COMPOSITION.md`
(a "Looks" section), `i18n/{en,ja}/frontend.toml` and `island.toml` (append only). **Not yours:** `frontend/core/**`,
`settings/**`, all Rust, `Desktop.qml`, `mods/tasks/**`. A token you miss → `docs/CONTRACT-CHANGE.md` row + say so in
the report (don't add it yourself). Sandbox names start with `w22-sty-`.

**Do:**
1. **`Block.qml` draws all four chromes from tokens only** (rule 4: never compare `Theme.chromeStyle`): soft shadow
   (`softR`/`softDy`/`softColor`; `RectangularShadow` from QtQuick.Effects if the Qt has it, else a cheap stacked-rect
   fallback — measure nothing expensive per frame, the shadow is static), outline width `outlineW` in `outlineColor`
   (keycap keeps its ring/hard shadow), press = sink by `shadowDy` (keycap) **or** scale to `pressScale` (soft, flat),
   line chrome = outline only, a quick fill flash on press. Keep `Block`'s public API; callers keep working.
2. **Primitives and surfaces follow:** replace `Theme.keycap` checks that are really about "blocks stand alone" with
   `Theme.groups`, and about "heavier icons" with `Theme.iconFill/iconWeight` (Icon.qml). Keep keycap-only details
   (ring, sink) on their tokens (`ringW`, `shadowDy`). Bar: groups as blocks whenever `Theme.groups`; line chrome reads
   like a terminal status line (outlined boxes, no fills behind text). Walk every surface (bar, island pill + card,
   quick settings phone, launcher, notification centre + toasts, session keys, lock, web dock card/strip/phone) under
   each decor and fix what looks wrong or not distinct.
3. **I115 — the keycap island card joins its bar group:** under keycap chrome the open card connects to the island's
   own bar-group block with a neck (outline continuous around pill-group + neck + card, ring and hard shadow follow the
   joined outline). Soft chrome: the flat liquid neck with the soft shadow under the joined shape. Line chrome: the
   joined outline, no fill tint. Keep one continuous shape through the morph.
4. **I114 glass:** the island shape at `Theme.panel` (translucent) once its path layers no longer show through each
   other (one path, or draw into a layer with `layer.enabled` only while the card is out).
5. **I109** keycap/soft/line styling of the web dock phone's bottom-bar buttons; **I110** a mod's quick tile that is
   not a `QuickTile` gets a `Block` cell.
6. Ma: no animation or timer while hidden; reduce motion (`Theme.springOn` false) snaps; idle frames stay 0.

**Acceptance:** `nix develop -c frontend/test-look.sh <decor> 'theme.decor = "<decor>"'` for `sekai`, `glass`,
`terminal`, `washi`, `none` — five shot sets in `frontend/shots/look/<decor>/` that are visibly distinct from each
other on every surface, with the bar layout (edge, height, widget order) identical across all five;
`frontend/test-island-morph.sh` green with mid-morph frames for keycap (the joined neck) and soft;
`frontend/test-stage.sh`, `frontend/test-quick.sh`, `just webdock` green. No QML warnings in the logs. Report (terse):
what changed per decor, shot paths, follow-ups as backlog suggestions (the lead files them).
