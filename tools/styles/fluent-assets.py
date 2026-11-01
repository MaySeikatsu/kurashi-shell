#!/usr/bin/env python3
"""fluent's sound cues and pointer, made from nothing (W53.3, docs/ux/styles.md §4, K80 Decided 6 and 11).

Everything here is synthesised or drawn in this file — no vendor's sound or cursor is read, sampled or traced — and the
output is CC0. The cues follow Windows 11's spirit only: soft, airy, rounded tones with a gentle attack and a little room
around them (a feedback delay) — a rising three-note glass arpeggio to unlock, a low soft two-note fall for an error, a
light two-note chime for a notification, a faint tick up and down for the launcher. The pointer is a slim white arrow with
a 1 px dark outline and a soft shadow, drawn as a polygon here and rendered with 4 × 4 supersampling.

    python3 tools/styles/fluent-assets.py    # writes sounds/fluent/*.wav and cursors/fluent/
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
        gain = 0.6 / peak
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


def env(t, attack, decay):
    """A raised-cosine attack and an exponential decay: no click at the start."""
    a = 0.5 - 0.5 * math.cos(math.pi * t / attack) if t < attack else 1.0
    return a * math.exp(-max(0.0, t - attack) / decay)


def glass(f, t):
    """A soft glass tone: the fundamental, a quiet octave and a faint inharmonic shimmer."""
    w = 2 * math.pi * f * t
    return math.sin(w) + 0.22 * math.sin(2 * w) + 0.06 * math.sin(3.01 * w)


def room(samples, delay=0.071, feedback=0.32, mix=0.28):
    """A small room: one feedback delay line mixed in, then a short fade so the tail ends at 0."""
    d = int(delay * RATE)
    out = list(samples)
    buf = [0.0] * len(out)
    for i in range(len(out)):
        echo = buf[i - d] if i >= d else 0.0
        buf[i] = out[i] + feedback * echo
        out[i] = out[i] + mix * echo
    fade = int(0.04 * RATE)
    for k in range(fade):
        out[-1 - k] *= k / fade
    return out


def render(seconds, voice):
    return room([voice(i / RATE) for i in range(int(seconds * RATE))])


def cues():
    def notes(seq, decay):
        def v(t):
            s = 0.0
            for start, f, g in seq:
                if t >= start:
                    u = t - start
                    s += g * glass(f, u) * env(u, 0.012, decay)
            return s
        return v

    return {
        # D5, A5, D6 rising, each 90 ms after the last.
        "unlock": render(1.0, notes([(0.0, 587.33, 0.8), (0.09, 880.0, 0.8), (0.18, 1174.66, 0.9)], 0.22)),
        # A low soft fall: E4 then C4.
        "error": render(0.6, notes([(0.0, 329.63, 1.0), (0.11, 261.63, 1.0)], 0.12)),
        # A light chime: B5 then E6.
        "notify": render(0.8, notes([(0.0, 987.77, 0.7), (0.1, 1318.51, 0.8)], 0.16)),
        # A faint tick up (open) and down (close).
        "open": render(0.18, notes([(0.0, 1046.5, 0.5), (0.035, 1396.91, 0.5)], 0.03)),
        "close": render(0.18, notes([(0.0, 1396.91, 0.5), (0.035, 1046.5, 0.5)], 0.03)),
    }


# The arrow at 32 px nominal (art units), the tip at (1, 1): a slim, slightly concave arrow with its tail.
ARROW = [(1, 1), (1, 22.5), (6.2, 17.6), (9.6, 25.4), (12.9, 24.0), (9.6, 16.4), (16.8, 16.4)]


def inside(px, py, poly):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def dist_to_edges(px, py, poly):
    best = 1e9
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        dx, dy = x2 - x1, y2 - y1
        t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - x1 - t * dx, py - y1 - t * dy))
    return best


def cursor_image(nominal):
    """ARGB (premultiplied, little-endian) pixels of the arrow in a `nominal`-px square, 4 × 4 supersampled."""
    k = nominal / 32.0
    poly = [(x * k, y * k) for x, y in ARROW]
    shadow = [(x + 1.2 * k, y + 1.6 * k) for x, y in poly]
    line = max(1.0, k)   # the outline: 1 px at 32, 2 at 64
    px = []
    ss = 4
    for y in range(nominal):
        for x in range(nominal):
            white = black = sh = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    X, Y = x + (sx + 0.5) / ss, y + (sy + 0.5) / ss
                    if inside(X, Y, poly):
                        if dist_to_edges(X, Y, poly) < line:
                            black += 1
                        else:
                            white += 1
                    elif inside(X, Y, shadow):
                        sh += 1
            n = ss * ss
            wa, ba, sa = white / n, black / n, 0.28 * sh / n
            a = wa + ba + sa * (1 - wa - ba)
            v = wa  # premultiplied grey: white contributes 1, black and the shadow 0
            A = int(round(min(1.0, a) * 255))
            V = int(round(min(1.0, v) * 255))
            px.append((A << 24) | (V << 16) | (V << 8) | V)
    return px


def write_xcursor(path, sizes):
    """An Xcursor file (the libXcursor format: 'Xcur', a table of contents, one image chunk per nominal size)."""
    images = [(n, cursor_image(n)) for n in sizes]
    header = 16
    out = struct.pack("<4sIII", b"Xcur", header, 0x10000, len(images))
    pos = header + 12 * len(images)
    chunks = b""
    for n, _px in images:
        out += struct.pack("<III", 0xFFFD0002, n, pos)
        pos += 36 + 4 * n * n
    for n, pxs in images:
        hot = max(0, int(round(n / 32.0)))
        chunks += struct.pack("<IIIIIIIII", 36, 0xFFFD0002, n, 1, n, n, hot, hot, 0)
        chunks += struct.pack("<%dI" % len(pxs), *pxs)
    with open(path, "wb") as f:
        f.write(out + chunks)


def main():
    snd = os.path.join(ROOT, "sounds", "fluent")
    os.makedirs(snd, exist_ok=True)
    for name, samples in cues().items():
        write_wav(os.path.join(snd, name + ".wav"), samples)
    cur = os.path.join(ROOT, "cursors", "fluent")
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-fluent\nComment=A slim white arrow with a soft shadow (W53.3, CC0, "
                "drawn in tools/styles/fluent-assets.py)\nInherits=default\n")
    write_xcursor(os.path.join(cur, "cursors", "default"), [24, 32, 48, 64])
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


if __name__ == "__main__":
    main()
