#!/usr/bin/env python3
"""luna's and aero's sound cues and pointers, made from nothing (W53.2, docs/ux/styles.md §2-§3, K80 Decided 6 and 11).

Everything here is synthesised or drawn in this file: no vendor's sound or cursor is read, sampled, traced or copied,
and the output is CC0. The cues only carry the moods of the two eras: luna's warm, rounded glass-synth chimes and aero's
airy, spacious crystal, all short 22 kHz mono clips. The pointers are our own arrows, a rounder one for luna and a
slimmer one for aero, each with a soft drop shadow cast down-right from the drawing itself.

    python3 -I tools/styles/xp7-assets.py    # writes sounds/{luna,aero}/*.wav and cursors/{luna,aero}/
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


def tone(f, t, partials=((1, 1.0), (2, 0.25)), detune=0.003):
    """A soft stack of partials, each a pair of sines a hair apart: the chorus of a warm synth voice."""
    v = 0.0
    for k, a in partials:
        v += a * (math.sin(TAU * f * k * t) + math.sin(TAU * f * k * (1 + detune) * t))
    return 0.5 * v


def bell(f, t, ratio, index, decay):
    """An FM bell: a sine carrier with a modulator that starts strong and fades; a bright strike, a round ring."""
    return math.sin(TAU * f * t + index * math.exp(-decay * t) * math.sin(TAU * f * ratio * t))


def glide(f0, f1, tau, t):
    """Phase (radians) of a sine whose pitch falls or rises from f0 to f1 with time constant tau."""
    return TAU * (f1 * t + (f0 - f1) * tau * (1 - math.exp(-t / tau)))


def chirp(f0, f1, seconds, t):
    """Phase (radians) of a linear sweep from f0 to f1 over `seconds`."""
    return TAU * (f0 * t + (f1 - f0) * t * t / (2 * seconds))


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
    """A one-pole low-pass, to soften an echo."""
    a = 1 - math.exp(-TAU * fc / RATE)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


# -- the two cue sets ---------------------------------------------------------------------------------------------

def luna_cues():
    def pad(f, u):
        """A glassy note: a chorused stack with a faint octave shimmer that breathes at 5.5 Hz."""
        body = tone(f, u, ((1, 1.0), (2, 0.28), (3, 0.09)), detune=0.004)
        glint = 0.14 * tone(2 * f, u, ((1, 1.0),), detune=0.003) * (0.6 + 0.4 * math.sin(TAU * 5.5 * u))
        return (body + glint) * swell(u, 0.03, 0.3)

    def bonk(f0, f1):
        """A soft low body that drops in pitch, with a rounder second partial."""
        def v(u):
            ph = glide(f0, f1, 0.02, u)
            return (math.sin(ph) + 0.25 * math.sin(2 * ph)) * swell(u, 0.002, 0.07)
        return v

    def chime(f):
        """A soft FM bell with a slightly detuned twin: round, with a short bright strike."""
        def v(u):
            return (bell(f, u, 2.0, 1.1, 7.0) + 0.5 * bell(f * 1.004, u, 2.0, 1.1, 7.0)) * swell(u, 0.004, 0.22)
        return v

    def tick(u):
        """The tiny click of a window opening: a 3 kHz blip that dies in 3 ms."""
        return 0.35 * math.sin(TAU * 3000 * u) * math.exp(-u / 0.003)

    def sweep(f0, f1, tick_at):
        buf = whoosh(0.15, f0, f1, 0.9)
        place(buf, tick_at, fades(render(0.012, tick), 0.0005, 0.004))
        return fades(buf, 0.004, 0.03)

    # unlock: an E-flat major arpeggio, Bb4 Eb5 G5 Bb5, each glassy note ringing into the next
    buf = silence(0.9)
    for k, f in enumerate((466.16, 622.25, 783.99, 932.33)):
        place(buf, 0.09 * k, fades(render(0.7, lambda u, f=f: pad(f, u)), 0.003, 0.05))
    unlock = fades(room(buf, ((0.037, 0.5), (0.053, 0.42), (0.089, 0.3)), 0.35), 0.004, 0.25)

    # error: a low two-note bonk, the second a fourth lower, each dropping in pitch
    buf = silence(0.36)
    place(buf, 0.0, fades(render(0.2, bonk(330.0, 262.0)), 0.002, 0.03))
    place(buf, 0.12, fades(render(0.22, bonk(247.0, 196.0)), 0.002, 0.03), 0.8)
    error = fades(buf, 0.002, 0.02)

    # notify: a ding on E5 and a dong a fifth up on B5, soft FM bells
    buf = silence(0.7)
    place(buf, 0.0, fades(render(0.6, chime(659.26)), 0.003, 0.04))
    place(buf, 0.16, fades(render(0.5, chime(987.77)), 0.003, 0.04), 0.9)
    notify = fades(room(buf, ((0.029, 0.4), (0.043, 0.33)), 0.3), 0.003, 0.06)

    return {
        "unlock": unlock,
        "error": error,
        "notify": notify,
        "open": sweep(700.0, 2400.0, 0.11),
        "close": sweep(2400.0, 700.0, 0.04),
    }


def aero_cues():
    seconds = 0.18

    def air(f, u):
        """An airy voice: two soft partials, lightly detuned and barely bright."""
        return tone(f, u, ((1, 1.0), (2, 0.1), (3, 0.04)), detune=0.0025)

    def bloom(u):
        """A slow bloom: 0.35 s to full, a short hold, then a long fade."""
        rise = 0.5 - 0.5 * math.cos(math.pi * min(1.0, u / 0.35))
        return rise * (1.0 if u < 0.55 else math.exp(-(u - 0.55) / 0.16))

    def sparkle(f):
        """A glassy high partial that flicks on and rings out in a tenth of a second."""
        def v(u):
            return 0.1 * math.sin(TAU * f * u) * swell(u, 0.003, 0.09)
        return v

    def crystal(u):
        """One crystalline strike: a high FM chime with an inharmonic modulator, clear and quick."""
        return bell(1318.51, u, 3.5, 1.4, 5.0) * swell(u, 0.002, 0.35)

    def tock(f):
        """A muted glass tock: a short sine plus a quieter ring partial at 2.76 times that dies faster."""
        def v(u):
            ring = 0.2 * math.sin(TAU * f * 2.76 * u) * math.exp(-u / 0.02)
            return (math.sin(TAU * f * u) + ring) * swell(u, 0.002, 0.028)
        return v

    def breath(f0, f1):
        """The tonal part of a sweep: a thin sine gliding f0 to f1 under a hump."""
        return render(seconds, lambda u: 0.12 * math.sin(chirp(f0, f1, seconds, u)) * math.sin(math.pi * u / seconds))

    def sweep(f0, f1, t0, t1):
        buf = whoosh(seconds, f0, f1, 0.6)
        place(buf, 0.0, breath(t0, t1))
        return fades(buf, 0.01, 0.04)

    # unlock: a C major ninth blooming slowly (C4 G4 B4 D5 E5), glassy sparkles above it, then a fade out
    buf = silence(0.95)
    for f in (261.63, 392.00, 493.88, 587.33, 659.26):
        place(buf, 0.0, render(0.95, lambda u, f=f: 0.5 * air(f, u) * bloom(u)))
    for f, t0 in ((2093.0, 0.3), (2637.0, 0.42), (3136.0, 0.55)):
        place(buf, t0, fades(render(0.4, sparkle(f)), 0.002, 0.04))
    unlock = fades(room(buf, ((0.041, 0.58), (0.061, 0.5), (0.097, 0.42)), 0.45), 0.006, 0.2)

    # error: a muted two-tone glass tock, C6 then G5
    buf = silence(0.3)
    place(buf, 0.0, fades(render(0.16, tock(1046.5)), 0.001, 0.02), 0.8)
    place(buf, 0.1, fades(render(0.16, tock(783.99)), 0.001, 0.02), 0.6)
    error = fades(buf, 0.002, 0.03)

    # notify: one crystalline chime and two softened echoes after it, then a little room
    dry = fades(render(0.6, crystal), 0.002, 0.04)
    buf = silence(0.7)
    place(buf, 0.0, dry)
    place(buf, 0.24, lowpass(dry, 2600), 0.4)
    place(buf, 0.48, lowpass(dry, 1600), 0.16)
    notify = fades(room(buf, ((0.05, 0.45), (0.077, 0.4)), 0.25), 0.002, 0.06)

    return {
        "unlock": unlock,
        "error": error,
        "notify": notify,
        "open": sweep(1400.0, 3400.0, 1200.0, 2400.0),
        "close": sweep(3400.0, 1400.0, 2400.0, 1200.0),
    }


# -- the two pointers ---------------------------------------------------------------------------------------------
# X = black outline, . = white fill, space = clear; the hotspot is the tip at (0, 0). The shadow is not drawn by hand:
# drop_shadow() casts it down-right from the outline, so an edit to the drawing keeps its shadow right.

LUNA_ARROW = [
    "X",
    "XX",
    "X.X",
    "X..X",
    "X...X",
    "X....X",
    "X.....X",
    "X......X",
    "X.......X",
    "X........XX",
    "X..X.....XXX",
    "X.X X...X",
    "XX  X...X",
    "X    X..X",
    "     X..X",
    "     X..X",
    "      X..X",
    "      X..X",
    "       XX",
]

AERO_ARROW = [
    "X",
    "X",
    "XX",
    "X.X",
    "X..X",
    "X...X",
    "X...X",
    "X....X",
    "X.....X",
    "X......X",
    "X.......X",
    "X.......X",
    "X......XXX",
    "X.XX..X",
    "XX  X.X",
    "X   X..X",
    "    X..X",
    "     X.X",
    "     X.X",
    "      XXX",
]

# Premultiplied ARGB: black has no colour, so its alpha is the whole top byte (0x5A000000 is 35 % black).
LUNA_PALETTE = {"X": 0xFF000000, ".": 0xFFFFFFFF, "s": 0x5A000000, "t": 0x2A000000}
AERO_PALETTE = {"X": 0xFF000000, ".": 0xFFFFFFFF, "s": 0x40000000, "t": 0x18000000}


def drop_shadow(art):
    """The drawing as a character grid, with a two-step shadow cast down-right: a clear cell takes 's' when the drawing
    sits one step up-left of it, else 't' when it sits two steps up-left (the far, softer edge)."""
    def solid(x, y):
        return 0 <= y < len(art) and 0 <= x < len(art[y]) and art[y][x] in "X."

    width = max(map(len, art)) + 2
    grid = []
    for y in range(len(art) + 2):
        row = ""
        for x in range(width):
            ch = art[y][x] if y < len(art) and x < len(art[y]) else " "
            if ch == " ":
                ch = "s" if solid(x - 1, y - 1) else "t" if solid(x - 2, y - 2) else " "
            row += ch
        grid.append(row)
    return grid


def cursor_image(grid, palette, nominal, scale):
    """Pixels of the grid at `scale` in a `nominal`-px square, the drawing's top-left at the square's origin."""
    px = [0] * (nominal * nominal)
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch not in palette:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    X, Y = x * scale + dx, y * scale + dy
                    if X < nominal and Y < nominal:
                        px[Y * nominal + X] = palette[ch]
    return px


def write_xcursor(path, grid, palette, sizes):
    """An Xcursor file (the libXcursor format: 'Xcur', a table of contents, one image chunk per nominal size)."""
    images = [(n, cursor_image(grid, palette, n, s)) for n, s in sizes]
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


def write_set(style, cues, art, palette, comment):
    snd = os.path.join(ROOT, "sounds", style)
    os.makedirs(snd, exist_ok=True)
    for name, samples in cues.items():
        write_wav(os.path.join(snd, name + ".wav"), samples)
    cur = os.path.join(ROOT, "cursors", style)
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-%s\nComment=%s\nInherits=default\n" % (style, comment))
    # 1 px per art pixel at 24 and 32, doubled at 48 and 64, as win95's set does.
    sizes = [(24, 1), (32, 1), (48, 2), (64, 2)]
    write_xcursor(os.path.join(cur, "cursors", "default"), drop_shadow(art), palette, sizes)
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


def main():
    write_set("luna", luna_cues(), LUNA_ARROW, LUNA_PALETTE,
              "The XP-era rounded arrow with a soft drop shadow (W53.2, CC0, drawn in tools/styles/xp7-assets.py)")
    write_set("aero", aero_cues(), AERO_ARROW, AERO_PALETTE,
              "The Windows 7-era slim arrow with a softer shadow (W53.2, CC0, drawn in tools/styles/xp7-assets.py)")


if __name__ == "__main__":
    main()
