#!/usr/bin/env python3
"""The ground patterns `[decor] pattern.kind` tiles (W53.4, docs/ux/styles.md §5): made from nothing, CC0.

    python3 -I tools/styles/patterns.py    # writes frontend/components/decor/textures/*.png

- `stripes-<n>.png` (1 × n px, n = 2…8): Aqua's pinstripes — one dark row per period fading into its neighbours (see
  `stripes`). The part sets the strength (the Image's opacity), the palette the colour underneath: the tile itself
  carries no colour.
- `grid-<n>.png` (n × n px): a ruled grid — one dark row and one dark column per period (W53.6: NieR's faint menu grid).
- `dots-<n>.png` (n × n px): one dark pixel per period cell (a pixel polka for pastel desktops).
- `checker-<n>.png` (2n × 2n px): a checker of n px cells, two of the four dark (pastel pixel grounds).
- `brushed.png` (256 × 64 px): brushed metal — black streaks of varying alpha along x, each row its own blend of a few
  sines with whole periods over the tile's width, so the tile repeats without a seam.
Python's standard library only (zlib, struct, math, random with a fixed seed): a rerun reproduces the committed files.
"""
import math
import os
import random
import struct
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "frontend", "components", "decor", "textures")


def png(path, w, h, rows):
    """rows: h lists of w (r, g, b, a) tuples; an 8-bit RGBA PNG."""
    raw = b"".join(b"\0" + bytes(c for px in row for c in px) for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def stripes(n):
    """One dark row per period, its neighbours a quarter as dark, the rest clear: a squared cosine. Jaguar's menu bar
    (guidebookgallery.org pics/gui/desktop/full/macosx102.png, x 600, y 0–21) reads #e9e9e9, #fafafa, #ffffff, #fafafa
    by row % 4 — darkenings of 22, 5, 0, 5 out of 255: this profile at strength 0.086."""
    return [[(0, 0, 0, int(round(255 * ((1 + math.cos(2 * math.pi * y / n)) / 2) ** 2)))] for y in range(n)]


def grid(n):
    return [[(0, 0, 0, 255 if (x == 0 or y == 0) else 0) for x in range(n)] for y in range(n)]


def dots(n):
    return [[(0, 0, 0, 255 if (x == 0 and y == 0) else 0) for x in range(n)] for y in range(n)]


def checker(n):
    return [[(0, 0, 0, 255 if ((x // n) + (y // n)) % 2 == 0 else 0) for x in range(2 * n)] for y in range(2 * n)]


def brushed(w=256, h=64, seed=1984):
    rnd = random.Random(seed)
    rows = []
    for _ in range(h):
        waves = [(rnd.randint(1, 24), rnd.uniform(0, 2 * math.pi), rnd.uniform(0.2, 1.0)) for _ in range(5)]
        base = rnd.uniform(0.15, 0.85)
        row = []
        for x in range(w):
            v = sum(a * math.sin(2 * math.pi * k * x / w + p) for k, p, a in waves) / sum(a for _, _, a in waves)
            row.append((0, 0, 0, max(0, min(255, int(255 * (base + 0.35 * v))))))
        rows.append(row)
    return rows


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n in range(2, 9):
        png(os.path.join(OUT, "stripes-%d.png" % n), 1, n, stripes(n))
        png(os.path.join(OUT, "grid-%d.png" % n), n, n, grid(n))
        png(os.path.join(OUT, "dots-%d.png" % n), n, n, dots(n))
        png(os.path.join(OUT, "checker-%d.png" % n), 2 * n, 2 * n, checker(n))
    png(os.path.join(OUT, "brushed.png"), 256, 64, brushed())
