#!/usr/bin/env python3
"""The wl_keys.py tokens that type a text (W76: the address field in test-card.sh): a-z and digits as themselves, A-Z
with shift, the punctuation by its keysym name (tools/bench/wl_keys.py CHAR_TOKENS), a space as `space`.
   python3 -I keytokens.py 'file:///tmp/x.html'  →  f i l e colon slash slash slash t m p slash x period h t m l"""
import sys

NAMES = {"-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", ";": "semicolon", "'": "apostrophe",
         "`": "grave", "\\": "backslash", ",": "comma", ".": "period", "/": "slash", ":": "colon", "_": "underscore",
         "+": "plus", "?": "question", "%": "percent", "&": "ampersand", "*": "asterisk", "@": "at", "#": "numbersign",
         "~": "asciitilde", "!": "exclam", '"': "quotedbl", "(": "parenleft", ")": "parenright", "<": "less",
         ">": "greater", "{": "braceleft", "}": "braceright", " ": "space"}
out = []
for c in sys.argv[1]:
    if c.isascii() and (c.islower() or c.isdigit()):
        out.append(c)
    elif c.isascii() and c.isupper():
        out.append("shift+" + c.lower())
    elif c in NAMES:
        out.append(NAMES[c])
    else:
        sys.exit(f"keytokens: no key for {c!r}")
print(" ".join(out))
