#!/usr/bin/env python3
"""aqua's and vibrancy's sound cues and pointers, made from nothing (W53.4, docs/ux/styles.md §5-§6).

Everything here is synthesised or drawn in this file, and it is never Apple's sounds or cursors: none is read, sampled,
traced or copied, and the output is CC0. aqua carries the Jaguar-to-Tiger mood: crisp glass taps, a bright
two-note chime, a woody thud, and a black arrow with a thin white outline. vibrancy carries the Big Sur-to-Sonoma
mood: airy, rounder and shorter plucks and bubbles, and a black arrow with a thicker white outline and a softer, larger
shadow. Every cue is a short 22 kHz mono clip, well under 50 KiB, and every pointer is a 32 px nominal Xcursor like the
xp7 ones.

    python3 -I tools/styles/mac-assets.py    # writes sounds/{aqua,vibrancy}/*.wav and cursors/{aqua,vibrancy}/
Python's standard library only (wave, struct, math, os); deterministic, so a rerun reproduces the committed files.
"""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RATE = 22050
TAU = 2 * math.pi


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        peak = max(1e-9, max(abs(s) for s in samples))
        gain = 0.7 / peak
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


# -- sound building blocks: each clip is rendered from zero and faded at its ends before it is mixed in -----------

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def render(seconds, voice):
    """A clip of `seconds`, sampled from voice(t) with t in seconds from the clip's start."""
    return [voice(i / RATE) for i in range(int(seconds * RATE))]


def place(buf, start, clip, gain=1.0):
    """Mixes `clip` into `buf` from `start` seconds on, in place."""
    i0 = int(start * RATE)
    for i, s in enumerate(clip[:max(0, len(buf) - i0)]):
        buf[i0 + i] += gain * s
    return buf


def fades(x, fade_in=0.003, fade_out=0.02):
    """Raised-cosine ends: the clip starts and stops at exactly zero, so no edge can click."""
    n = len(x)
    a = max(1, int(fade_in * RATE))
    b = max(1, int(fade_out * RATE))
    for i in range(min(a, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / a)
    for k in range(min(b, n)):
        x[n - 1 - k] *= 0.5 - 0.5 * math.cos(math.pi * k / b)
    return x


def swell(t, attack, decay):
    """A raised-cosine attack (no kink at its start) followed by an exponential decay."""
    rise = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / attack))
    return rise * math.exp(-max(0.0, t - attack) / decay)


def bell(f, t, ratio, index, decay):
    """An FM bell: a sine carrier with a modulator that starts strong and fades; a bright strike, a round ring."""
    return math.sin(TAU * f * t + index * math.exp(-decay * t) * math.sin(TAU * f * ratio * t))


def glide(f0, f1, tau, t):
    """Phase (radians) of a sine whose pitch falls or rises from f0 to f1 with time constant tau."""
    return TAU * (f1 * t + (f0 - f1) * tau * (1 - math.exp(-t / tau)))


def band(seconds, f0, f1, q):
    """White noise from an LCG (no random module) through a band-pass whose centre glides from f0 to f1 (RBJ biquad)."""
    n = int(seconds * RATE)
    seed, x1, x2, y1, y2 = 1, 0.0, 0.0, 0.0, 0.0
    out = []
    for i in range(n):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        s = seed / 0x40000000 - 1.0
        w0 = TAU * (f0 + (f1 - f0) * i / n) / RATE
        alpha = math.sin(w0) / (2 * q)
        a0 = 1 + alpha
        y = (alpha * (s - x2) + 2 * math.cos(w0) * y1 - (1 - alpha) * y2) / a0
        x2, x1 = x1, s
        y2, y1 = y1, y
        out.append(y)
    return out


def whoosh(seconds, f0, f1, q):
    """Band-passed air gliding from f0 to f1 under a soft hump: a window's worth of wind."""
    n = int(seconds * RATE)
    return [s * math.sin(math.pi * i / n) ** 1.5 for i, s in enumerate(band(seconds, f0, f1, q))]


def room(x, taps, mix):
    """A small room: a few feedback delays, each a decaying train of echoes, mixed in under the dry sound."""
    out = list(x)
    for delay, g in taps:
        d = int(delay * RATE)
        y = list(x)
        for n in range(d, len(y)):
            y[n] += g * y[n - d]
        for n in range(len(x)):
            out[n] += mix * (y[n] - x[n]) / len(taps)
    return out


def lowpass(x, fc):
    """A one-pole low-pass, to soften a sound."""
    a = 1 - math.exp(-TAU * fc / RATE)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


# -- the two cue sets ---------------------------------------------------------------------------------------------

def aqua_cues():
    def glass(f, decay):
        """A glass bell: an FM strike whose inharmonic modulator (2.76 times the carrier) rings out, with a twin a hair
        sharp that beats slowly, so the note shimmers instead of sitting still."""
        def v(u):
            return (bell(f, u, 2.76, 1.2, 6.0) + 0.35 * bell(f * 1.005, u, 2.76, 1.2, 6.0)) * swell(u, 0.002, decay)
        return v

    def pop(f0, f1, decay):
        """A pitched pop: a sine that glides from f0 to f1 in a few milliseconds, then dies in a few tens of them."""
        def v(u):
            return math.sin(glide(f0, f1, 0.012, u)) * swell(u, 0.001, decay)
        return v

    def fizz(seconds, f, level):
        """A breath of band-passed noise, the air that leaves a bottle: a 1 ms attack and an 8 ms decay."""
        return [level * s * swell(i / RATE, 0.001, 0.008) for i, s in enumerate(band(seconds, f, f, 3.0))]

    # open: a glass tap on F6 with its inharmonic ring, a rising bloop under it and a puff of air (0.2 s)
    buf = fades(render(0.2, glass(1396.91, 0.06)), 0.001, 0.04)
    place(buf, 0.0, fades(render(0.12, pop(560.0, 1050.0, 0.03)), 0.001, 0.03), 0.55)
    place(buf, 0.0, fizz(0.03, 2400.0, 0.25))
    open_ = fades(buf, 0.001, 0.03)

    # close: the same pop going down, lower and softer, with less air: the cork settling back (0.14 s)
    buf = fades(render(0.14, pop(900.0, 360.0, 0.05)), 0.001, 0.03)
    place(buf, 0.0, fizz(0.02, 1500.0, 0.18))
    close = fades(buf, 0.001, 0.03)

    # notify: two glass bells, B5 then E6 (a rising fourth), each echoed once in a small room (0.6 s)
    buf = silence(0.6)
    place(buf, 0.0, fades(render(0.45, glass(987.77, 0.2)), 0.002, 0.08))
    place(buf, 0.13, fades(render(0.45, glass(1318.51, 0.2)), 0.002, 0.08), 0.9)
    notify = fades(room(buf, ((0.045, 0.3),), 0.25), 0.002, 0.06)

    # error: a woody thud, a body that drops in pitch with two wood modes ringing over it, then a softer knock (0.3 s)
    def thud(f, amp):
        """A low body gliding down, plus a 470 Hz and a 1290 Hz wood mode that die within a few milliseconds."""
        def v(u):
            body = math.sin(glide(f, f * 0.62, 0.02, u)) * swell(u, 0.001, 0.1)
            wood = 0.5 * math.sin(TAU * 470.0 * u) * math.exp(-u / 0.012)
            wood += 0.25 * math.sin(TAU * 1290.0 * u) * math.exp(-u / 0.006)
            return amp * (body + wood)
        return v

    buf = silence(0.3)
    place(buf, 0.0, fades(render(0.2, thud(196.0, 0.8)), 0.001, 0.04))
    place(buf, 0.11, fades(render(0.18, thud(147.0, 0.5)), 0.001, 0.04))
    error = fades(buf, 0.002, 0.02)

    # unlock: D5, A5, D6 and F#6 ring up one after another, each glass bell settling into the next (1.0 s)
    buf = silence(1.0)
    for k, f in enumerate((587.33, 880.00, 1174.66, 1479.98)):
        place(buf, 0.095 * k, fades(render(0.55, glass(f, 0.3)), 0.002, 0.1), 0.8)
    unlock = fades(room(buf, ((0.037, 0.45), (0.061, 0.35)), 0.35), 0.003, 0.2)

    return {"unlock": unlock, "error": error, "notify": notify, "open": open_, "close": close}


def vibrancy_cues():
    def pluck(f, decay):
        """A soft marimba-like pluck: a round sine with a quiet fourth partial that dies first, under a 3 ms attack."""
        def v(u):
            quiet = 0.16 * math.sin(TAU * 4 * f * u) * math.exp(-u / (0.35 * decay))
            return (math.sin(TAU * f * u) + quiet) * swell(u, 0.003, decay)
        return v

    def bubble(f0, f1):
        """A bubble: a soft sine that glides from f0 to f1 in about 40 ms and rounds off, with no hard start."""
        def v(u):
            return math.sin(glide(f0, f1, 0.02, u)) * swell(u, 0.004, 0.05)
        return v

    # open: a marimba pluck on B5 with a bubble rising under it, a little shorter than aqua's tap (0.16 s)
    buf = fades(render(0.16, pluck(987.77, 0.1)), 0.002, 0.04)
    place(buf, 0.0, fades(render(0.1, bubble(560.0, 860.0)), 0.002, 0.03), 0.35)
    open_ = fades(buf, 0.002, 0.03)

    # close: the same pluck on E5 with a bubble falling away under it, lower and quicker (0.12 s)
    buf = fades(render(0.12, pluck(659.26, 0.08)), 0.002, 0.04)
    place(buf, 0.0, fades(render(0.1, bubble(820.0, 500.0)), 0.002, 0.03), 0.3)
    close = fades(buf, 0.002, 0.03)

    # notify: a gentle two-note chime, G5 then D6 (a rising fifth), each plucked softly with a little air (0.5 s)
    buf = silence(0.5)
    place(buf, 0.0, fades(render(0.4, pluck(783.99, 0.2)), 0.003, 0.08), 0.9)
    place(buf, 0.14, fades(render(0.36, pluck(1174.66, 0.22)), 0.003, 0.08), 0.8)
    notify = fades(room(buf, ((0.07, 0.25),), 0.2), 0.003, 0.06)

    # error: a muted low blip, a soft sine that dips only a little, its octave softened under it (0.16 s)
    def boop(u):
        """A soft low blip: a sine dipping from 210 Hz to 180 Hz with its octave at a fifth of the level."""
        body = math.sin(glide(210.0, 180.0, 0.03, u)) + 0.2 * math.sin(glide(420.0, 360.0, 0.03, u))
        return body * swell(u, 0.004, 0.06)

    error = fades(lowpass(render(0.16, boop), 1400.0), 0.003, 0.03)

    # unlock: G5, B5, D6, G6 and B6 plucked up the scale, each a touch louder, over a faint rising air (0.8 s)
    buf = silence(0.8)
    for k, f in enumerate((783.99, 987.77, 1174.66, 1567.98, 1975.53)):
        place(buf, 0.07 * k, fades(render(0.5, pluck(f, 0.3)), 0.003, 0.1), 0.6 + 0.05 * k)
    place(buf, 0.0, whoosh(0.7, 2600.0, 6200.0, 2.5), 0.1)
    unlock = fades(room(buf, ((0.05, 0.3), (0.083, 0.25)), 0.3), 0.004, 0.2)

    return {"unlock": unlock, "error": error, "notify": notify, "open": open_, "close": close}


# -- the two pointers ---------------------------------------------------------------------------------------------
# Each pointer is a polygon in pixels, y running down, with its tip at (0, -0.5) so that the tip's own cell is solid and
# the hotspot (0, 0) sits on the tip. A cell is solid when its centre lies inside the polygon. Solid cells whose centre
# lies within the outline's width of an edge are the white outline, the rest is the black body, and the shadow is the
# silhouette blurred and cast down-right. It all follows the drawing, so an edit to the shape keeps its shadow right.

AQUA_ARROW = [(0.0, -0.5), (0.0, 16.6), (3.5, 13.2), (5.9, 21.4), (9.4, 20.6), (6.2, 12.4), (8.6, 10.6)]
VIBRANCY_ARROW = [(0.0, -0.5), (0.0, 17.0), (4.8, 13.1), (7.4, 20.2), (12.7, 18.9), (9.7, 14.0), (11.5, 12.2)]


def inside(poly, x, y):
    """Even-odd test: is the point (x, y) inside the polygon?"""
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < xi + (y - yi) * (xj - xi) / (yj - yi):
            hit = not hit
        j = i
    return hit


def silhouette(poly, w, h):
    """The solid cells of a w x h grid: a cell is solid when its centre is inside the polygon."""
    return [[inside(poly, x + 0.5, y + 0.5) for x in range(w)] for y in range(h)]


def edge_distance(poly, x, y):
    """The distance in pixels from (x, y) to the nearest edge of the polygon."""
    best = float("inf")
    for i in range(len(poly)):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % len(poly)]
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
        best = min(best, math.hypot(x - ax - t * vx, y - ay - t * vy))
    return best


def blur(grid, sigma):
    """A separable Gaussian blur of a 0/1 grid, zero outside it, so a silhouette fades out at its edge."""
    r = int(math.ceil(3 * sigma))
    k = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-r, r + 1)]
    total = sum(k)
    k = [v / total for v in k]
    h, w = len(grid), len(grid[0])
    rows = [[sum(k[i + r] * grid[y][x + i] for i in range(-r, r + 1) if 0 <= x + i < w) for x in range(w)]
            for y in range(h)]
    return [[sum(k[j + r] * rows[y + j][x] for j in range(-r, r + 1) if 0 <= y + j < h) for x in range(w)]
            for y in range(h)]


def pointer_raster(poly, outline, shadow):
    """The 1x pointer as rows of premultiplied ARGB: a white outline `outline` px wide, measured from the drawing's
    edges, round a black body, and a black shadow whose alpha is the blurred silhouette moved by (dx, dy) and scaled by
    `peak`. Black has no colour, so its alpha is the whole top byte."""
    dx, dy, sigma, peak = shadow
    pad_x = dx + int(math.ceil(3 * sigma)) + 1
    pad_y = dy + int(math.ceil(3 * sigma)) + 1
    w = int(math.ceil(max(x for x, _ in poly))) + pad_x
    h = int(math.ceil(max(y for _, y in poly))) + pad_y
    solid = silhouette(poly, w, h)
    moved = [[y >= dy and x >= dx and solid[y - dy][x - dx] for x in range(w)] for y in range(h)]
    soft = blur(moved, sigma)
    raster = []
    for y in range(h):
        row = []
        for x in range(w):
            if not solid[y][x]:
                row.append((int(255 * peak * soft[y][x] + 0.5)) << 24)
            elif edge_distance(poly, x + 0.5, y + 0.5) < outline:
                row.append(0xFFFFFFFF)
            else:
                row.append(0xFF000000)
        raster.append(row)
    return raster


def cursor_image(raster, nominal, scale):
    """Pixels of the raster at `scale` in a `nominal`-px square, the drawing's top-left at the square's origin."""
    px = [0] * (nominal * nominal)
    for y, row in enumerate(raster):
        for x, argb in enumerate(row):
            for dy in range(scale):
                for dx in range(scale):
                    X, Y = x * scale + dx, y * scale + dy
                    if X < nominal and Y < nominal:
                        px[Y * nominal + X] = argb
    return px


def write_xcursor(path, raster, sizes):
    """An Xcursor file (the libXcursor format: 'Xcur', a table of contents, one image chunk per nominal size)."""
    images = [(n, cursor_image(raster, n, s)) for n, s in sizes]
    header = 16
    toc = 12 * len(images)
    out = struct.pack("<4sIII", b"Xcur", header, 0x10000, len(images))
    pos = header + toc
    chunks = b""
    for n, _px in images:
        out += struct.pack("<III", 0xFFFD0002, n, pos)
        pos += 36 + 4 * n * n
    for n, px in images:
        chunks += struct.pack("<IIIIIIIII", 36, 0xFFFD0002, n, 1, n, n, 0, 0, 0)
        chunks += struct.pack("<%dI" % len(px), *px)
    with open(path, "wb") as f:
        f.write(out + chunks)


def write_set(style, cues, poly, outline, shadow, comment):
    snd = os.path.join(ROOT, "sounds", style)
    os.makedirs(snd, exist_ok=True)
    for name, samples in cues.items():
        write_wav(os.path.join(snd, name + ".wav"), samples)
    cur = os.path.join(ROOT, "cursors", style)
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-%s\nComment=%s\nInherits=default\n" % (style, comment))
    # 1 px per art pixel at 24 and 32, doubled at 48 and 64, as xp7's sets do.
    sizes = [(24, 1), (32, 1), (48, 2), (64, 2)]
    write_xcursor(os.path.join(cur, "cursors", "default"), pointer_raster(poly, outline, shadow), sizes)
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


def main():
    # outline = the white rim's width in px; shadow = (dx, dy, blur sigma, peak alpha). aqua's rim is one pixel and its
    # shadow short and crisp; vibrancy's rim is thicker and its shadow larger and softer.
    write_set("aqua", aqua_cues(), AQUA_ARROW, 1.0, (1, 1, 0.9, 0.5),
              "The Mac OS X-era black arrow with a thin white outline and a soft shadow "
              "(W53.4, CC0, drawn in tools/styles/mac-assets.py)")
    write_set("vibrancy", vibrancy_cues(), VIBRANCY_ARROW, 1.6, (1, 2, 1.6, 0.42),
              "The macOS 11-14-era black arrow with a thicker white outline and a larger, softer shadow "
              "(W53.4, CC0, drawn in tools/styles/mac-assets.py)")


if __name__ == "__main__":
    main()
