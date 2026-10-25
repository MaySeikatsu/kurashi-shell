# The shell's icon font as a subset (W39-block, I194): Material Symbols keeps ~4300 ligatures (8.9 MB Sharp, 15.2 MB
# Rounded) and the shell draws ~400 of them, while the variable font is resident almost whole (8.2 MiB in W35's
# attribution). This keeps the named ligatures, the glyphs the font swaps in by its axes (GSUB FeatureVariations, e.g.
# `settings.fill` at FILL 1) and the letters that spell them, with every axis (FILL, GRAD, opsz, wght), so an icon draws
# exactly as before; the family is renamed so it never shadows a full Material Symbols the system may have.
#   python3 icon-subset.py <MaterialSymbols<Cut>[…].ttf> <names file> <family> <out.ttf>
# A name that is not in the list draws as its letters (Icon.qml cannot tell): nix/icon-names.txt must hold every name the
# shell, its settings and the bundled mods use (nix/icon-names.py regenerates it); see CONTRACT-CHANGE row 446.
import string
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

src, names_file, family, out = sys.argv[1:5]
font = TTFont(src)
rev = {g: chr(c) for c, g in font.getBestCmap().items()}
want = {l.strip() for l in open(names_file) if l.strip() and not l.startswith("#")}
keep, found = set(), set()
for lookup in font["GSUB"].table.LookupList.Lookup:
    for st in lookup.SubTable:
        if st.LookupType == 7:
            st = st.ExtSubTable
        for first, ligs in getattr(st, "ligatures", {}).items():
            for lig in ligs:
                try:
                    name = "".join(rev[c] for c in [first] + list(lig.Component))
                except KeyError:
                    continue
                if name in want:
                    keep.add(lig.LigGlyph)
                    found.add(name)
missing = sorted(want - found)
if missing:
    sys.exit("icon-subset: not in %s: %s" % (src, " ".join(missing)))
base = set(keep)
keep |= {g for g in font.getGlyphOrder() if "." in g and g.split(".", 1)[0] in base}

opts = subset.Options()
opts.layout_features = ["*"]
opts.layout_closure = False      # the letters must not pull every ligature back in
opts.name_IDs = ["*"]
opts.name_languages = ["*"]
opts.notdef_outline = True
opts.glyph_names = True
opts.recalc_bounds = False
s = subset.Subsetter(opts)
s.populate(glyphs=sorted(keep), unicodes=[ord(c) for c in string.ascii_letters + string.digits + "_ "])
s.subset(font)

ps = family.replace(" ", "")
for rec in font["name"].names:
    if rec.nameID in (1, 16):
        rec.string = family
    elif rec.nameID == 4:
        rec.string = family
    elif rec.nameID == 6:
        rec.string = ps
    elif rec.nameID == 3:
        rec.string = ps + "-W39"
font.save(out)
print("%s: %d names, %d glyphs" % (out, len(found), len(font.getGlyphOrder())))
