#!/usr/bin/env python3
"""win95's sound cues and pointer, made from nothing (W53.1, docs/ux/styles.md §1, K80 Decided 6 and 11).

Everything here is synthesised or drawn in this file — no vendor's sound or cursor is read, sampled or traced — and the
output is CC0. The cues follow the bevel era's spirit only: a short fanfare to unlock, a chord stab for an error, a bell
for a notification, a click up and down for the launcher. The pointer is the black-outlined white arrow of that era,
drawn pixel by pixel below.

    python3 tools/styles/win95-assets.py    # writes sounds/win95/*.wav and cursors/win95/
Python's standard library only (wave, struct, math); deterministic, so a rerun reproduces the committed files.
"""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RATE = 22050


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        peak = max(1e-9, max(abs(s) for s in samples))
        gain = 0.7 / peak
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


def env(t, attack, decay):
    """A linear attack and an exponential decay."""
    return (t / attack if t < attack else 1.0) * math.exp(-max(0.0, t - attack) / decay)


def bell(f, t):
    """An FM bell: a sine carrier with an inharmonic modulator whose depth fades."""
    return math.sin(2 * math.pi * f * t + 2.2 * math.exp(-t * 6) * math.sin(2 * math.pi * f * 1.4 * t))


def square(f, t, soft=8):
    """A band-limited square (odd harmonics up to `soft`)."""
    return sum(math.sin(2 * math.pi * f * k * t) / k for k in range(1, soft + 1, 2))


def render(seconds, voice):
    return [voice(i / RATE) for i in range(int(seconds * RATE))]


def cues():
    def unlock(t):  # a rising two-step fanfare: C5 then a G5-C6 dyad
        s = 0.0
        if t < 0.16:
            s += bell(523.25, t) * env(t, 0.004, 0.09)
        if t >= 0.12:
            u = t - 0.12
            s += (bell(783.99, u) + 0.7 * bell(1046.5, u)) * env(u, 0.006, 0.22)
        return s

    def error(t):  # a short chord stab: E4, G#4, B4 on soft squares
        return sum(square(f, t) for f in (329.63, 415.30, 493.88)) * env(t, 0.003, 0.08)

    def notify(t):  # one bell at A5 with a bright partial
        return (bell(880.0, t) + 0.25 * math.sin(2 * math.pi * 880.0 * 2.76 * t)) * env(t, 0.002, 0.18)

    def sweep(f0, f1):
        def v(t):
            d = 0.11
            f = f0 + (f1 - f0) * min(1.0, t / d)
            return square(f, t, 5) * env(t, 0.002, 0.03)
        return v

    return {
        "unlock": render(0.85, unlock),
        "error": render(0.45, error),
        "notify": render(0.7, notify),
        "open": render(0.14, sweep(600, 1200)),
        "close": render(0.14, sweep(1100, 550)),
    }


# The arrow: X = black outline, . = white, space = clear. 12 × 19, the hotspot at its tip (0, 0).
ARROW = [
    "X",
    "XX",
    "X.X",
    "X..X",
    "X...X",
    "X....X",
    "X.....X",
    "X......X",
    "X.......X",
    "X........X",
    "X.....XXXXX",
    "X..X..X",
    "X.X X..X",
    "XX  X..X",
    "X    X..X",
    "     X..X",
    "      X..X",
    "      X..X",
    "       XX",
]


def cursor_image(nominal, scale):
    """ARGB (premultiplied, little-endian) pixels of the arrow at `scale` in a `nominal`-px square."""
    px = [0] * (nominal * nominal)
    for y, row in enumerate(ARROW):
        for x, ch in enumerate(row):
            if ch == " ":
                continue
            argb = 0xFF000000 if ch == "X" else 0xFFFFFFFF
            for dy in range(scale):
                for dx in range(scale):
                    X, Y = x * scale + dx, y * scale + dy
                    if X < nominal and Y < nominal:
                        px[Y * nominal + X] = argb
    return px


def write_xcursor(path, sizes):
    """An Xcursor file (the libXcursor format: 'Xcur', a table of contents, one image chunk per nominal size)."""
    images = [(n, s, cursor_image(n, s)) for n, s in sizes]
    header = 16
    toc = 12 * len(images)
    out = struct.pack("<4sIII", b"Xcur", header, 0x10000, len(images))
    pos = header + toc
    chunks = b""
    for n, _s, _px in images:
        out += struct.pack("<III", 0xFFFD0002, n, pos)
        pos += 36 + 4 * n * n
    for n, _s, pxs in images:
        chunks += struct.pack("<IIIIIIIII", 36, 0xFFFD0002, n, 1, n, n, 0, 0, 0)
        chunks += struct.pack("<%dI" % len(pxs), *pxs)
    with open(path, "wb") as f:
        f.write(out + chunks)


def main():
    snd = os.path.join(ROOT, "sounds", "win95")
    os.makedirs(snd, exist_ok=True)
    for name, samples in cues().items():
        write_wav(os.path.join(snd, name + ".wav"), samples)
    cur = os.path.join(ROOT, "cursors", "win95")
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-win95\nComment=The bevel era's black-outlined white arrow (W53.1, CC0, "
                "drawn in tools/styles/win95-assets.py)\nInherits=default\n")
    # 1 px per art pixel at 24 and 32 (9x drew its 32 px cursors 1:1), doubled at 48 and 64.
    write_xcursor(os.path.join(cur, "cursors", "default"), [(24, 1), (32, 1), (48, 2), (64, 2)])
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


if __name__ == "__main__":
    main()
