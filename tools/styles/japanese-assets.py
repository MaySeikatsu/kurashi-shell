#!/usr/bin/env python3
"""washi's, kami's and sekai's sounds and pointers, made from nothing (W53.7; docs/ux/styles.md §9; K80 decided 6, 11).

Everything here is synthesised or drawn in this file: no recording, sample or another product's sound or pointer is
read, traced or imitated, and the output is CC0.

washi (paper and ink): paper and a soft bell. Rustles are band-passed noise in short crinkle grains; a brush tap is a soft
low thump with a breath of noise; the notify and unlock bell is an original inharmonic struck-bowl tone (partials at
1, 2.76, 5.40 and 8.93 × the fundamental, as a thin metal bowl's modes, each decaying at its own rate).
kami (a notebook page): pencil and paper. A pencil tick is a few ms of bright band-passed noise over a tiny wood knock; a
pencil scratch is noise with a fast irregular grain (graphite catching the paper's tooth); a page turn is a swoosh whose
band slides down as the sheet falls.
sekai (pop keycaps): mechanical keys and pops. A key press is a bright click (a switch's leaf) and a low thock (the cap
bottoming out on the plate); a release is a lighter click; a pop is a sine whose pitch drops fast, as a bubble's.

The pointers: washi a brush (筆: a sumi tuft on a bamboo handle, tip at the hotspot), kami a pencil (graphite tip, wood,
a blue body, an eraser), sekai a pop arrow (white with a thick ink outline and a hard ink shadow down-right, the keycap
chrome's). Polygons rendered with 4 × 4 supersampling, premultiplied ARGB, sizes 24, 32, 48, 64.

    python3 -I tools/styles/japanese-assets.py   # writes sounds/{washi,kami,sekai} and cursors/{washi,kami,sekai}
Python's standard library only; deterministic, so a rerun reproduces the committed files.
"""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RATE = 22050
MAX_BYTES = 50 * 1024
TAU = 2 * math.pi
SIZES = (24, 32, 48, 64)


# --- sound helpers ------------------------------------------------------------------------------------------------------

class Rng:
    """A 32-bit LCG: deterministic noise and jitter (no random module)."""
    def __init__(self, seed):
        self.x = seed & 0xFFFFFFFF

    def next(self):
        self.x = (1664525 * self.x + 1013904223) & 0xFFFFFFFF
        return self.x / 4294967296.0

    def noise(self):
        return 2.0 * self.next() - 1.0


def buf(seconds):
    return [0.0] * int(round(seconds * RATE))


def biquad(samples, kind, f, q):
    """RBJ biquad (low/high/band pass) run over samples, in place-free style (returns a new list)."""
    w0 = TAU * f / RATE
    cw, sw = math.cos(w0), math.sin(w0)
    a = sw / (2 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:  # band pass, 0 dB peak
        b0, b1, b2 = a, 0.0, -a
    a0, a1, a2 = 1 + a, -2 * cw, 1 - a
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for x in samples:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def env_ad(u, attack, decay):
    """A raised-cosine attack, then an exponential decay with time constant `decay`."""
    if u < 0:
        return 0.0
    if u < attack:
        return 0.5 - 0.5 * math.cos(math.pi * u / attack)
    return math.exp(-(u - attack) / decay)


def add(dst, start, src, gain=1.0):
    i0 = int(round(start * RATE))
    for k, v in enumerate(src):
        if 0 <= i0 + k < len(dst):
            dst[i0 + k] += gain * v


def finish(samples):
    """A 20 ms raised-cosine fade to exactly 0 at both ends' last samples (no click)."""
    n = int(0.02 * RATE)
    for k in range(n):
        g = 0.5 - 0.5 * math.cos(math.pi * k / n)
        samples[-1 - k] *= g
    samples[0] = 0.0
    return samples


def write_wav(path, samples, level=0.5):
    gain = level / max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, s * gain)) * 32767))) for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    size = os.path.getsize(path)
    assert size <= MAX_BYTES, "%s is %d bytes" % (path, size)
    return size


# --- the voices ---------------------------------------------------------------------------------------------------------

def noise_burst(seconds, seed, f, q, kind="bp", attack=0.004, decay=0.05, grain=None):
    """Filtered noise under an envelope; `grain` = (rate Hz, depth) modulates it with irregular crinkles."""
    r = Rng(seed)
    n = int(seconds * RATE)
    raw = [r.noise() for _ in range(n)]
    sig = biquad(raw, kind, f, q)
    out = []
    g, gt = 1.0, 0.0
    for k, v in enumerate(sig):
        u = k / RATE
        if grain:
            gt -= 1.0 / RATE
            if gt <= 0:
                gt = (0.5 + r.next()) / grain[0]
                g = 1.0 - grain[1] * r.next()
        out.append(v * env_ad(u, attack, decay) * (g if grain else 1.0))
    return out


def thump(seconds, f0, f1, decay, seed=7):
    """A soft low knock: a sine sliding from f0 to f1, a breath of noise on its attack."""
    r = Rng(seed)
    out = []
    ph = 0.0
    for k in range(int(seconds * RATE)):
        u = k / RATE
        f = f1 + (f0 - f1) * math.exp(-u / 0.03)
        ph += f / RATE
        out.append(math.sin(TAU * ph) * env_ad(u, 0.003, decay) + 0.25 * r.noise() * env_ad(u, 0.001, 0.008))
    return out


def bowl(seconds, f, level=1.0):
    """An original struck-bowl tone: inharmonic partials, each its own decay; a soft 6 ms strike."""
    parts = [(1.0, 1.0, 0.55), (2.76, 0.5, 0.32), (5.40, 0.22, 0.16), (8.93, 0.1, 0.08)]
    out = []
    for k in range(int(seconds * RATE)):
        u = k / RATE
        v = 0.0
        for ratio, amp, dec in parts:
            # a slow beat between two near modes, as a real bowl's slightly split pairs
            v += amp * math.sin(TAU * f * ratio * u) * (1 + 0.15 * math.sin(TAU * 3.1 * ratio * u)) * env_ad(u, 0.006, dec)
        out.append(level * v)
    return out


def pop(seconds, f0, f1, seed=3):
    """A bubble pop: a sine dropping fast from f0 to f1 with a quick decay, a tick on top."""
    r = Rng(seed)
    out = []
    ph = 0.0
    for k in range(int(seconds * RATE)):
        u = k / RATE
        f = f1 + (f0 - f1) * math.exp(-u / 0.018)
        ph += f / RATE
        out.append(math.sin(TAU * ph) * env_ad(u, 0.002, 0.06) + 0.15 * r.noise() * env_ad(u, 0.0005, 0.003))
    return out


def key_press(seed, bright=1.0, body=1.0):
    """A mechanical key: the switch's click (bright band-passed noise, a few ms) and the cap's thock (a low knock)."""
    out = buf(0.14)
    add(out, 0.0, noise_burst(0.03, seed, 4200, 1.4, decay=0.004), 0.9 * bright)
    add(out, 0.006, thump(0.12, 320, 190, 0.028, seed + 1), 0.7 * body)
    return out


# --- the sets -----------------------------------------------------------------------------------------------------------

def washi_cues():
    def rustle(seconds, seed, f=2600):
        a = noise_burst(seconds, seed, f, 0.7, attack=0.03, decay=seconds * 0.35, grain=(70, 0.85))
        return biquad(a, "hp", 500, 0.7)
    cues = {}
    # open: a sheet lifted — a short rustle
    o = buf(0.42)
    add(o, 0.0, rustle(0.42, 11), 1.0)
    cues["open"] = o
    # close: the brush set down — a soft knock with a breath
    c = buf(0.3)
    add(c, 0.0, thump(0.3, 170, 95, 0.06, 13), 1.0)
    add(c, 0.0, noise_burst(0.12, 14, 1800, 0.8, attack=0.01, decay=0.03), 0.25)
    cues["close"] = c
    # notify: the bowl, struck once, high and soft
    n = buf(1.0)
    add(n, 0.0, bowl(1.0, 988), 1.0)
    cues["notify"] = n
    # unlock: a sheet slides away, then the bowl a fourth lower
    u = buf(1.05)
    add(u, 0.0, rustle(0.36, 15, 2000), 0.8)
    add(u, 0.22, bowl(0.83, 740), 1.0)
    cues["unlock"] = u
    # error: two dull brush taps, the second lower
    e = buf(0.5)
    add(e, 0.0, thump(0.25, 150, 90, 0.05, 17), 1.0)
    add(e, 0.2, thump(0.3, 120, 70, 0.06, 18), 1.0)
    cues["error"] = e
    return cues


def kami_cues():
    def tick(seed):
        t = buf(0.08)
        add(t, 0.0, noise_burst(0.03, seed, 3400, 2.2, attack=0.0008, decay=0.004), 1.0)
        add(t, 0.002, thump(0.06, 900, 600, 0.012, seed + 1), 0.35)
        return t

    def scratch(seconds, seed):
        return noise_burst(seconds, seed, 2900, 1.6, attack=0.02, decay=seconds * 0.6, grain=(140, 0.9))

    def page(seconds, seed):
        r = Rng(seed)
        raw = [r.noise() for _ in range(int(seconds * RATE))]
        out = []
        lp = 0.0
        for k, v in enumerate(raw):
            u = k / RATE
            cut = 6000 * math.exp(-u / (seconds * 0.45)) + 400
            a = 1 - math.exp(-TAU * cut / RATE)
            lp += a * (v - lp)
            out.append(lp * env_ad(u, seconds * 0.25, seconds * 0.3))
        return biquad(out, "hp", 250, 0.7)
    cues = {}
    o = buf(0.45)
    add(o, 0.0, page(0.45, 21), 1.0)
    cues["open"] = o
    cues["close"] = tick(23)
    n = buf(0.3)
    add(n, 0.0, tick(25), 1.0)
    add(n, 0.14, tick(27), 0.85)
    cues["notify"] = n
    e = buf(0.62)
    add(e, 0.0, scratch(0.22, 29), 1.0)
    add(e, 0.3, scratch(0.26, 31), 1.0)
    cues["error"] = e
    u = buf(0.8)
    add(u, 0.0, page(0.5, 33), 0.9)
    add(u, 0.5, tick(35), 1.0)
    cues["unlock"] = u
    return cues


def sekai_cues():
    cues = {}
    cues["open"] = key_press(41)
    cl = buf(0.1)
    add(cl, 0.0, noise_burst(0.025, 43, 5200, 1.6, decay=0.003), 0.8)
    add(cl, 0.004, thump(0.08, 420, 300, 0.015, 44), 0.35)
    cues["close"] = cl
    n = buf(0.36)
    add(n, 0.0, pop(0.16, 1500, 760, 45), 1.0)
    add(n, 0.12, pop(0.2, 2000, 1010, 46), 1.0)
    cues["notify"] = n
    e = buf(0.4)
    add(e, 0.0, key_press(47, bright=0.4, body=1.3), 1.0)
    add(e, 0.16, key_press(49, bright=0.3, body=1.3), 1.0)
    cues["error"] = e
    u = buf(0.75)
    for i, t in enumerate((0.0, 0.07, 0.14)):
        add(u, t, key_press(51 + 2 * i), 0.8)
    add(u, 0.28, pop(0.2, 1320, 660, 57), 0.9)
    add(u, 0.38, pop(0.3, 1660, 830, 58), 1.0)
    cues["unlock"] = u
    return cues


# --- pointers -----------------------------------------------------------------------------------------------------------

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


def along(t, w, a=(0.0, 0.0), b=(1.0, 1.0)):
    """A point `t` of the way from a to b, `w` px off the line to its right (the art is drawn along the diagonal)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy)
    return (a[0] + dx * t - dy / n * w, a[1] + dy * t + dx / n * w)


def render(nominal, layers, outline, line, shadow=None):
    """Premultiplied ARGB words: `layers` = [(poly in 32-px art units, (r, g, b))] painted in order; `outline` the
    colour of a `line`-px edge round their union; `shadow` = (dx, dy, (r, g, b)) a hard copy of the union behind it."""
    k = nominal / 32.0
    polys = [([(x * k, y * k) for x, y in p], col) for p, col in layers]
    lw = line * k
    ss = 4
    out = []
    for y in range(nominal):
        for x in range(nominal):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    X = x + (sx + 0.5) / ss
                    Y = y + (sy + 0.5) / ss
                    col = None
                    for p, c in polys:
                        if inside(X, Y, p):
                            col = c
                    if col is not None:
                        # the outline: a point of the union within `line` px of its edge (some probe there is outside)
                        near = any(not any(inside(X + ox * lw, Y + oy * lw, q) for q, _ in polys)
                                   for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1), (0.7, 0.7), (-0.7, -0.7),
                                                  (0.7, -0.7), (-0.7, 0.7)))
                        c = outline if near else col
                        acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 1.0
                    elif shadow and any(inside(X - shadow[0] * k, Y - shadow[1] * k, p) for p, _ in polys):
                        c = shadow[2]
                        acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 1.0
            n = ss * ss
            R, G, B, A = (int(round(v / n)) if i < 3 else int(round(v / n * 255)) for i, v in enumerate(acc))
            out.append((A << 24) | (R << 16) | (G << 8) | B)
    return out


def brush_layers():
    # The art runs down the diagonal from the tip (1, 1); lengths in 32-px units along it.
    L = 38.0
    a, b = (1.0, 1.0), (1.0 + L / math.sqrt(2), 1.0 + L / math.sqrt(2))
    tuft = [along(0.0, 0, a, b)] + [along(t, w, a, b) for t, w in ((0.06, 1.2), (0.14, 2.6), (0.24, 3.3), (0.32, 3.2))] \
        + [along(0.36, 2.2, a, b), along(0.36, -2.2, a, b)] \
        + [along(t, -w, a, b) for t, w in ((0.32, 3.2), (0.24, 3.3), (0.14, 2.6), (0.06, 1.2))]
    band = [along(0.35, 2.4, a, b), along(0.40, 2.4, a, b), along(0.40, -2.4, a, b), along(0.35, -2.4, a, b)]
    handle = [along(0.40, 1.9, a, b), along(0.98, 1.6, a, b), along(1.0, 0.0, a, b), along(0.98, -1.6, a, b),
              along(0.40, -1.9, a, b)]
    return [(handle, (0xc9, 0xa8, 0x62)), (band, (0x8a, 0x2b, 0x2e)), (tuft, (0x1e, 0x1c, 0x20))]


def pencil_layers():
    L = 36.0
    a, b = (1.0, 1.0), (1.0 + L / math.sqrt(2), 1.0 + L / math.sqrt(2))
    lead = [along(0.0, 0, a, b), along(0.1, 1.0, a, b), along(0.1, -1.0, a, b)]
    wood = [along(0.0, 0, a, b), along(0.26, 3.0, a, b), along(0.26, -3.0, a, b)]
    body = [along(0.26, 3.0, a, b), along(0.80, 3.0, a, b), along(0.80, -3.0, a, b), along(0.26, -3.0, a, b)]
    stripe = [along(0.26, 0.6, a, b), along(0.80, 0.6, a, b), along(0.80, -0.6, a, b), along(0.26, -0.6, a, b)]
    ferrule = [along(0.80, 3.1, a, b), along(0.88, 3.1, a, b), along(0.88, -3.1, a, b), along(0.80, -3.1, a, b)]
    eraser = [along(0.88, 3.0, a, b), along(0.98, 2.6, a, b), along(1.0, 0.0, a, b), along(0.98, -2.6, a, b),
              along(0.88, -3.0, a, b)]
    return [(wood, (0xe8, 0xc9, 0x9a)), (lead, (0x3a, 0x3b, 0x40)), (body, (0x3f, 0x6c, 0xb3)),
            (stripe, (0x6d, 0x93, 0xd0)), (ferrule, (0xc0, 0xc4, 0xcc)), (eraser, (0xe8, 0x8f, 0x96))]


def arrow_layers():
    arrow = [(1, 1), (1, 21), (6, 16.5), (9.6, 24.5), (13.2, 23), (9.8, 15.2), (16.5, 15.2)]
    return [(arrow, (0xff, 0xff, 0xff))]


def write_xcursor(path, images):
    header = 16
    out = struct.pack("<4sIII", b"Xcur", header, 0x10000, len(images))
    pos = header + 12 * len(images)
    for n, _hx, _hy, _px in images:
        out += struct.pack("<III", 0xFFFD0002, n, pos)
        pos += 36 + 4 * n * n
    chunks = b""
    for n, hx, hy, px in images:
        chunks += struct.pack("<IIIIIIIII", 36, 0xFFFD0002, n, 1, n, n, hx, hy, 0)
        chunks += struct.pack("<%dI" % len(px), *px)
    with open(path, "wb") as f:
        f.write(out + chunks)


def write_cursor_set(name, comment, images):
    cur = os.path.join(ROOT, "cursors", name)
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-%s\nComment=%s\nInherits=default\n" % (name, comment))
    write_xcursor(os.path.join(cur, "cursors", "default"), images)
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


def main():
    for set_name, cues in (("washi", washi_cues()), ("kami", kami_cues()), ("sekai", sekai_cues())):
        folder = os.path.join(ROOT, "sounds", set_name)
        os.makedirs(folder, exist_ok=True)
        for cue, samples in cues.items():
            path = os.path.join(folder, cue + ".wav")
            size = write_wav(path, finish(samples), 0.5)
            print("%s/%-6s %5.3f s  %5.1f KiB" % (set_name, cue, len(samples) / RATE, size / 1024.0))
    ink = (0x1e, 0x1c, 0x20)
    paper = (0xfb, 0xf8, 0xf1)
    hot = lambda n: int(round(n / 32.0))
    write_cursor_set("washi", "A brush: a sumi tuft on a bamboo handle (W53.7, CC0, tools/styles/japanese-assets.py)",
                     [(n, hot(n), hot(n), render(n, brush_layers(), paper, 0.9)) for n in SIZES])
    write_cursor_set("kami", "A pencil: graphite, wood, a blue body, an eraser (W53.7, CC0, tools/styles/japanese-assets.py)",
                     [(n, hot(n), hot(n), render(n, pencil_layers(), (0x1d, 0x1f, 0x26), 0.9)) for n in SIZES])
    write_cursor_set("sekai", "A pop arrow: white, a thick ink outline, a hard ink shadow (W53.7, CC0, "
                     "tools/styles/japanese-assets.py)",
                     [(n, hot(n), hot(n), render(n, arrow_layers(), (0x12, 0x11, 0x20), 1.8, (2, 2, (0x12, 0x11, 0x20))))
                      for n in SIZES])
    print("cursors washi, kami, sekai: sizes %s" % (SIZES,))


if __name__ == "__main__":
    main()
