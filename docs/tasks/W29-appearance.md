# Card W29-appearance — Settings › Appearance as Style · Look · Palette, by category; washi's paper

**User (session 11):** "a clear differentiation between what a Look, a Style, a Palette or Chrome is … fixed Style
presets that reset/ignore other Appearance related settings to recreate one specific aesthetic … Currently you need to
reset all settings manually to get the default Look again, that's why I'd like to make it clear. I really like the
current overview with the previews of what the Look and Colors be like, but it might make sense to sort them into
different Categories like Modern, Inspired, Retro, Gaming/Fiction or similar to have a better overview about them and
extend those Categories Styles once clicked on the desired category." And: "the paper like (Washi) look as a default
on a fresh install."

**The contract is done (K53, read it in `docs/DECISIONS.md`, and PROTOCOL's `theme` / `theme.previews` rows and
"Appearance actions"):** `theme.style` (default `washi`, offers from source `styles` with `group` = category, plus
`none`), `theme.look` (offers `looks` with `group`), `theme.colors.palette`; actions `theme.style.apply {name}` /
`theme.look.apply {name}` (reset that kind's user values + set, one undo step); `theme.appearance {style, look, palette,
overrides}`; document `theme.previews {styles, looks, palettes}` (each `{name, category?, look?, palette?, frame?,
tokens}`). Categories `modern | inspired | retro | fiction | custom`, labels `appearance.category.<id>` in
`i18n/*/appearance.toml`. Source names in provenance: `theme` kind with name `style:<n>` / `look:<n>`.

**Read first:** `CLAUDE.md`; `docs/ux/looks.md` and `docs/ux/settings.md` (update both — the brief first);
`settings/components/{SettingRow.qml,DecorCards.qml,SectionCard.qml,ProvenanceChip.qml}`, `settings/shell.qml`,
`settings/core/Store.qml`, `settings/test.sh`; `frontend/components/{FrameHost.qml,frames/FrameBase.qml,frames/*.qml}`.
References for the overview: shellseikatsu's preset picker (`~/Documents/projects/quickshell/shellseikatsu/`, its
mode/preset selection UI), Noctalia's colour-scheme page (`~/Documents/projects/quickshell/noctalia-shell-wallust/`),
ii's wallpaper/scheme picker (`~/.config/quickshell/ii/`), GNOME/KDE's "Appearance"/"Global Theme" pages (KDE's
Global Theme ⊃ colours + Plasma style + window decoration is the closest model of Style ⊃ Look + Palette).

**Build (Settings, a thin view — no business logic, the daemon decides what resets):**
1. The Appearance page opens with three blocks, in this order and named exactly so: **Style**, **Look**, **Palette**,
   each with one line saying what it is (i18n en+ja): Style = "a whole aesthetic: look, colours, motion — applying one
   resets your appearance changes"; Look = "the form and feel without colours"; Palette = "colours only". Then the
   detail axes as today (chrome, shape, material, motion, type, density…).
2. **Categories:** the Style and Look blocks show a row of category tabs/chips (Modern · Inspired · Retro · Gaming &
   fiction · Your own — only categories that have packs), each with its count; clicking one expands that category's
   preview cards (one open at a time; the current pack's category opens by default; keyboard: arrows across chips,
   Enter opens, then Tab into the cards — keep DecorCards' roving radio group). "None (your own)" style is a plain card
   in front of the categories.
3. **Cards:** keep the current preview drawing (ground, bar of three blocks, card with "Aa", accent pill) from
   `theme.previews`; add the look's frame art when `frame` is set (reuse `FrameHost`/the frame components scaled down,
   or a light hint — must stay cheap: no Canvas repaint storms; loaded only for the open category). Picking a style
   card calls `theme.style.apply`; a look card `theme.look.apply`; a palette card sets `theme.colors.palette`. Show
   provenance on the Look and Palette blocks: "from the style Washi" vs "yours" (from the config document's sources).
4. **Changed from the style:** when `theme.appearance.overrides` is non-empty, a line under the Style block — "3
   settings differ from Washi: Chrome, Corners, Palette · Reset to Washi" (labels from the schema catalogue); the button
   calls `theme.style.apply` with the current style. Undo works (the existing history).
5. **Washi's paper (frontend art, data-driven):** a new frame `frontend/components/frames/Paper.qml` — washi paper: a
   very subtle fibre/grain texture and a soft deckled hairline in the ink colour (`Theme.fg`, low opacity), a slightly
   stronger version for `ground` (lock screen / greeter backdrop). Generated once (a small tiling image made at build
   time or a static procedural pattern cached as a texture), never animated, 0 cost while hidden. Set
   `[slots] frame = "paper"` in `looks/washi.toml`. Keep the look calm and legible; check light and dark schemes.
6. kurashi-mock: serve `theme.previews` and `theme.appearance` and accept the two actions (so Settings can be
   prototyped against the mock first).

**Owned paths:** `settings/**` (except `settings/shots/` other than your new ones), `frontend/components/frames/Paper.qml`
(+ its qmldir line), `looks/washi.toml` (`[slots]` only), `crates/kurashi-mock/**`, `i18n/{en,ja}/settings.toml`
(or a new `i18n/{en,ja}/settings-appearance.toml`), `docs/ux/looks.md`, `docs/ux/settings.md`. Contract rows 240–249
in `docs/CONTRACT-CHANGE.md` for anything else (e.g. a field the previews lack). Sandbox prefix `w29-ap-`.

**Security:** never start the shell or Settings on the user's display; sandbox only (`tools/bench/sandbox.sh`,
`KURASHI_POLKIT_AGENT=0`).

**Thrift:** prototype in QML against the mock first; build Rust only for the mock (one `cargo build -p kurashi-mock`)
and one `cargo build -p kurashid` for the real-daemon run; `cargo clippy -p kurashi-mock -- -D warnings` at the end.
Delete your worktree's `target/` before reporting.

**Acceptance:** `settings/test.sh` passes end to end (update its appearance steps: pick a style card → the daemon's
`theme.style` changes and earlier user appearance values are gone; change chrome → the "differs from" line appears;
Reset → it disappears; pick a look → `theme.look` is `user`, the style's palette stays), plus a new
`settings/test-appearance.sh` if that is cleaner. Shots in `settings/shots/appearance/`: the page under washi (default),
sekai and win95, each category expanded once, the "differs" line; the paper frame on bar/card/lock ground under washi
light and dark (`frontend/shots/look/` via `frontend/test-look.sh washi`). Report (terse): what was built, rows filed,
follow-ups.
