# Fonts and the font mix — UX brief (session 23, I176, I415, K93)
Status: v1. Test `frontend/test-font-mix.sh`; the builder's tests shape real text through a real shaper. Reviewed on nested niri (kami).

## Job
Text that looks written by a hand: "when a human is writing a letter it doesn't always look the same, there is usually variation". Pick several fonts, how many of them to mix, or a shipped preset; it works with any fonts, a user's own included. Every font setting sits on one page.

## How others do it
- **Handwriting fonts with contextual alternates** (Shantell Sans, Caveat): `calt` rotates a font's own variants. It is the same mechanism this uses, but only for a font that was drawn with them: Kalam has none.
- **Calligraphr**: makes a font from a person's handwriting, each letter up to a few variants in one font: the model for the plugin (I415).
- **Windows, macOS, KDE, GNOME**: a font picker and a size; no mixing. Quickshell shells: a family string.
No desktop shell found mixes fonts per letter.

## Design
- **One generated font.** kurashid builds one TTF holding the fonts' letters (`kurashi_theme::font_mix`), each letter one glyph per font, with a `calt` feature moving on a phase per letter. Every `Text` in the shell takes it as its family, and the shaper does the rest: elide, layout cost and the 180 files that use `Theme.families` stay as they are. The first design was rich-text spans per label: same look (`docs/media/fonts/comparison.png`: rows G against C and D), ten times the layout cost, no elide.
- **Words.** A word starts at phase 0: it looks the same wherever it stands, and a live label does not re-mix when its neighbour changes. "ll" never repeats a glyph within a word of up to as many letters as fonts.
- **Each letter has its own order** of fonts, so a word does not simply step down the list.
- **Sizes** are matched to the first font by the height of each font's own "x", because OS/2's are often wrong (Handlee's by half).
- **What does not mix**: digits and punctuation stay in the first font (a counter must not jump); non-Latin scripts other than Greek and Cyrillic fall through to the next family as before (Japanese takes `family_jp`).
- **Lost, stated:** kerning and ligatures of the source fonts, and mark positioning. Handwriting fonts barely notice; a user mixing a text face will. A variable font contributes its default instance.
- **Settings.** `theme.typography.mix.preset` (off, handwriting, custom), `count` (2 to 8, of the list from the first), `fonts` (any installed family, in order; the first gives the sizes). The page **Fonts** holds these and the existing family, Japanese family and scale; its top card is the comparison the user chose: one font, then two, three, four of the list, each drawn in the real mix.
- **Preset.** Handwriting: Kalam, Patrick Hand, Handlee, Gochi Hand, packaged in `nix/handwriting-fonts.nix`.
- **The plugin (I415).** The mix takes any family fontconfig has, and the offers refresh when a font folder changes. A mod that makes fonts from a person's handwriting only has to install them and set the list; it needs nothing new from the shell.
- **Licence.** OFL allows derivatives under another name: the mix is "Kurashi Mix <hash>". A mix made from a user's proprietary fonts is for their machine: it stays in the cache.

## States
- Off: nothing built, nothing loaded.
- Building: the theme keeps the plain family until the file is there (first use only: 100 to 300 ms off the runtime), then republishes. The file is the cache's `kurashi/fonts/mix-<hash>.ttf`; the hash covers the files and their times, so an updated font makes a new one. At most 16 stay.
- A font not installed: left out, and the card names it (Shōjiki). Fewer than two left: the plain family, and the card says a mix needs two.
- Unreadable font: logged, the plain family.

## Keyboard and a11y
Settings' rows as any other. Large text scales it as any font. No reduce-motion issue: it does not move. A mix may read worse for some people, and it is off by default.

## Motion
None. Stable by construction: the same text is always the same glyphs.

## Multi-output, Island, Stage
Nothing of their own: a font. The greeter does not follow yet (its own copy of the look, I416).

## Budget
No cost at rest and none per label over any font. One build per set of fonts. Apps are not affected.

## Definition of done
Any two fonts mix; the preset's fonts ship; the comparison shows the real mix; a missing font is said; nothing runs at rest.
