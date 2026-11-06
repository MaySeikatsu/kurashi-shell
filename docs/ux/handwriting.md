# Handwriting: draw your own font — UX brief (session 23, I415, K94)
Status: prototype. Test `mods/handwriting/test-handwriting.sh`, in the merge set. Reviewed on nested niri (kami).

## Job
Make a font of your own hand inside the shell, with nothing to print, scan or import. "When a human is writing a letter it doesn't always look the same": draw letters more than once, and Font Mix varies them as a hand does.

## How others do it
- **Microsoft Font Maker** (Windows): a frame per character, inked with a pen, then sample phrases for spacing. A stylus is the practical input; a mouse rarely looks like one's hand.
- **iFontMaker** (iPad): a canvas with baseline and cap-height guides beside the alphabet.
- **Calligraphr** (web): a printed template to scan, several variants per letter, rotated at random; it asks for three or four variants for a convincing hand.
- **Quentin Blake's typeface** (Monotype): four variants rotated so the same shape does not repeat.
This takes the frame and guides of the first two, and the variants of the last two. No template: the user asked for no document imports.

## Flow
1. The panel lists your fonts. Name a new one, Create new font.
2. The first letter without a drawing comes up in the box, its shadow behind it, with lines: capitals, small letters, the line it stands on, tails.
3. Draw with a pointer or pen. **Cancel** leaves, **Retry** clears, **Save and next** goes to the next letter not yet drawn. Enter saves; R retries; Ctrl+Z takes back a stroke; Esc leaves.
4. Beside the box, the whole set: what you drew shows as drawn, the rest as a shadow. A click goes to that letter, to redraw it.
5. Versions 1, 2, 3 (+ up to 8): the same set again. Draw all of them or only the letters you care for.
6. **Make font** writes one font per version with drawings. **Use it** makes one a font, several a mix.

## Details
- **Set.** A–Z, a–z, 0–9, then the common marks. A letter not drawn is not in the font, so the toolkit falls back to the next font, as with any font lacking one.
- **A version borrows.** A letter a version has not drawn takes the first version that has it, so every version covers what any does.
- **Height is where you drew it**, which is what the lines are for; across, a letter starts at a side bearing and is as wide as it was written.
- **Pen.** Fine, Medium, Bold, per font: the strokes are kept, so it can change after drawing.
- **Files.** Strokes in `$XDG_DATA_HOME/kurashi/handwriting/<id>.json`; fonts in `$XDG_DATA_HOME/fonts/kurashi-hand-<id>-<n>.ttf`. The mod's Delete removes both.

## States
No fonts: the name field has the focus. Nothing drawn: Make font is grey. A name of more than 40 characters, or none: refused with its reason. A set a mix cannot build: Settings › Fonts says so.

## Keyboard and a11y
Above. The drawing itself needs a pointer or pen: there is no keyboard way to draw. Buttons and cells are named. Not checked yet on niri by keyboard alone (I419).

## Motion and budget
None of its own beyond the Stage's card. Canvases paint only on a change; the panel exists only while open. Making a font takes milliseconds per version. The mod is off by default.

## Fit
A Stage panel, wider than others: the card's limit went from 720 to 1100 px. Fonts land where fontconfig finds them, so nothing else in the shell needs to know about this mod.

## Not done (I419)
Pen pressure, kerning from sample phrases, a link from Settings › Fonts, the launcher entry.
