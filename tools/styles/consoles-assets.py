#!/usr/bin/env python3
"""snes's and ps2's sounds and pointers, made from nothing (W53.5; docs/ux/styles.md §7, §8; K80 decided 6, 11).

Everything here is synthesised or drawn in this file: no console's or game's sound, jingle or pointer is read, sampled,
traced or imitated note-for-note, and the output is CC0.

snes (Super Famicom 16-bit RPG menus): dry square-wave chip blips at 12.5, 25 and 50 % pulse duty with short envelopes.
A quick rising major arpeggio unlocks, a low double buzz marks an error, a two-note chirp notifies, and a high tick
(then a lower one) marks open and close. The pointer is a chunky arrow on a 16 × 16 grid, written out below as
strings: white fill, a near-black outline and a grey shading line on the lower-right inner edge. It is scaled by
whole numbers with nearest neighbour, and its alpha is hard (0 or 255).

ps2 (PS2 dashboard): soft ambient pads of detuned sine and triangle layers, an 80–200 ms attack, a long soft release and
a gentle feedback-delay room. A warm chord swell that slides up a step unlocks, a low muted minor dyad marks an error, a
two-tone glass chime pad notifies, and a short airy swell rises or falls for open and close. The pointer is a slim
silver-white arrow drawn as a polygon and rendered with 4 × 4 supersampling, with a 1 px blue-grey outline and a soft
blue glow in place of a shadow.

    python3 tools/styles/consoles-assets.py    # writes sounds/snes, sounds/ps2, cursors/snes and cursors/ps2
Python's standard library only (math, os, struct, wave); deterministic, so a rerun reproduces the committed files.
"""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RATE = 22050
MAX_BYTES = 50 * 1024  # the budget per cue: 1.16 s of 16-bit mono at 22050 Hz, so every cue here is under 1.05 s
TAU = 2 * math.pi


# --- sound: envelopes, voices and the room ----------------------------------------------------------------------------

def ramp(u, attack):
    """A raised-cosine attack: 0 at u = 0 (no click), 1 from u = attack on."""
    if u >= attack:
        return 1.0
    return 0.5 - 0.5 * math.cos(math.pi * max(0.0, u) / attack)


def window(u, length, rel):
    """1 through the note, then a raised-cosine release that reaches exactly 0 at `length`."""
    if u >= length:
        return 0.0
    if u <= length - rel:
        return 1.0
    return 0.5 + 0.5 * math.cos(math.pi * (u - (length - rel)) / rel)


def mix(buf, start, length, voice):
    """Adds voice(u) into buf for `length` seconds from `start`; u counts seconds from the note's own start."""
    i0 = int(round(start * RATE))
    for k in range(int(round(length * RATE))):
        if i0 + k < len(buf):
            buf[i0 + k] += voice(k / RATE)


def glide(f0, f1, u, t):
    """Phase in cycles of a tone that slides linearly from f0 to f1 over t seconds and then holds f1."""
    if u <= t:
        return f0 * u + 0.5 * (f1 - f0) * u * u / t
    return f0 * t + 0.5 * (f1 - f0) * t + f1 * (u - t)


def tri(p):
    """A triangle wave of phase p (cycles): softer than a pulse, with few high partials."""
    return 4.0 * abs((p % 1.0) - 0.5) - 1.0


def pulse(p, duty):
    """A pulse wave of phase p (cycles): +1 for `duty` of each cycle, -1 for the rest."""
    return 1.0 if (p % 1.0) < duty else -1.0


def room(samples, delay=0.19, feedback=0.3, level=0.25):
    """A small room: one feedback delay line mixed back into the dry signal."""
    d = int(delay * RATE)
    buf = [0.0] * len(samples)
    out = list(samples)
    for i in range(len(samples)):
        echo = buf[i - d] if i >= d else 0.0
        buf[i] = samples[i] + feedback * echo
        out[i] += level * echo
    return out


def finish(samples):
    """A 25 ms raised-cosine fade to exactly 0 at the last sample, so no cue ends on a click."""
    fade = int(0.025 * RATE)
    for k in range(fade):
        samples[-1 - k] *= 0.5 - 0.5 * math.cos(math.pi * k / fade)
    return samples


def lcg_noise(seed, n):
    """Deterministic white noise in [-1, 1) from a 32-bit linear congruential generator (no random module)."""
    x = seed & 0xFFFFFFFF
    out = []
    for _ in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out.append(x / 2147483648.0 - 1.0)
    return out


def write_wav(path, samples, level):
    """Mono 16-bit 22050 Hz, normalised so the peak sits at `level` of full scale."""
    gain = level / max(1e-9, max(abs(s) for s in samples))
    data = b"".join(
        struct.pack("<h", int(round(max(-1.0, min(1.0, s * gain)) * 32767))) for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def describe(path):
    """Reads a cue back and checks the format, the size budget and that it starts and ends near silence."""
    with wave.open(path, "rb") as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, RATE), path
        n = w.getnframes()
        s = struct.unpack("<%dh" % n, w.readframes(n))
    size = os.path.getsize(path)
    assert size <= MAX_BYTES, "%s is %d bytes" % (path, size)
    edge = int(0.005 * RATE)
    peak = max(abs(x) for x in s) / 32767.0
    rms = math.sqrt(sum(x * x for x in s) / float(n)) / 32767.0
    assert abs(s[0]) <= 330 and abs(s[-1]) <= 330, path   # within 1 % of full scale at both ends
    return {
        "seconds": n / float(RATE),
        "bytes": size,
        "peak": peak,
        "rms_db": 20 * math.log10(max(rms, 1e-9)),
        "head": max(abs(x) for x in s[:edge]) / 32767.0,
        "tail": max(abs(x) for x in s[-edge:]) / 32767.0,
        "first": s[0] / 32767.0,
        "last": s[-1] / 32767.0,
    }


# --- snes: square-wave chip cues ---------------------------------------------------------------

def chip(f, duty, u, length, tau):
    """A 16-bit chip note: a pulse wave with a quieter octave-down pulse under it, a 3 ms attack and an exponential
    decay (time constant tau), stopped at `length` by a release window so it never clicks."""
    body = 0.8 * pulse(f * u, duty) + 0.2 * pulse(f * u / 2.0, 0.5)
    return ramp(u, 0.003) * math.exp(-u / tau) * window(u, length, 0.03) * body


def buzz(f, u, length):
    """A low buzz: a 12.5 % pulse wave with a 40 Hz throb, held for `length` and released."""
    throb = 0.7 + 0.3 * math.sin(TAU * 40 * u)
    return ramp(u, 0.004) * window(u, length, 0.04) * throb * pulse(f * u, 0.125)


def snes_cues():
    def chip_seq(seq, seconds):
        buf = [0.0] * int(round(seconds * RATE))
        for start, f, duty, length, tau in seq:
            mix(buf, start, length, lambda u, f=f, duty=duty, length=length, tau=tau: chip(f, duty, u, length, tau))
        return buf

    cues = {}
    # Unlock: C5, E5, G5, then C6 (a rising major arpeggio, 70 ms apart); the top note rings on.
    cues["unlock"] = chip_seq([
        (0.00, 523.25, 0.25, 0.16, 0.09),
        (0.07, 659.25, 0.25, 0.16, 0.09),
        (0.14, 783.99, 0.25, 0.16, 0.09),
        (0.21, 1046.50, 0.125, 0.62, 0.24),
    ], 0.9)
    # Error: a low double buzz, G2 then F#2.
    buf = [0.0] * int(round(0.45 * RATE))
    mix(buf, 0.00, 0.14, lambda u: buzz(98.00, u, 0.14))
    mix(buf, 0.18, 0.14, lambda u: buzz(92.50, u, 0.14))
    cues["error"] = buf
    # Notify: a two-note chirp, A5 then D6 (a rising fourth).
    cues["notify"] = chip_seq([(0.00, 880.00, 0.25, 0.10, 0.07), (0.09, 1174.66, 0.125, 0.26, 0.14)], 0.5)
    # Open: one high tick, E6; close: a slightly lower tick, D6.
    cues["open"] = chip_seq([(0.00, 1318.51, 0.25, 0.07, 0.022)], 0.12)
    cues["close"] = chip_seq([(0.00, 1174.66, 0.25, 0.07, 0.022)], 0.12)
    return {name: finish(samples) for name, samples in cues.items()}


# --- ps2: soft ambient pads --------------------------------------------------------------------

def tone_warm(p):
    """Warm pad layers at phase p: a sine, a sine 0.4 % sharp, a triangle 0.4 % flat, and a faint octave."""
    return (math.sin(TAU * p) + 0.6 * math.sin(TAU * 1.004 * p) + 0.35 * tri(0.996 * p)
            + 0.08 * math.sin(TAU * 2 * p)) / 2.0


def tone_muted(p):
    """A muted tone for the error dyad: a sine and a triangle, no bright partials."""
    return math.sin(TAU * p) + 0.45 * tri(p)


def tone_glass(p):
    """A glass tone for the chime: a sine with a quiet octave, a faint inharmonic shimmer and a soft triangle."""
    return math.sin(TAU * p) + 0.22 * math.sin(TAU * 2 * p) + 0.06 * math.sin(TAU * 3.01 * p) + 0.3 * tri(0.997 * p)


def pad_env(u, attack, length):
    """A pad's envelope: a slow attack, then an exponential release that is about 1 % at `length`, stopped by a
    window that reaches exactly 0 there."""
    return ramp(u, attack) * math.exp(-4.6 * max(0.0, u - attack) / (length - attack)) * window(u, length, 0.04)


def pad_voice(f0, f1, t, length, attack, tone, level):
    def voice(u):
        return level * pad_env(u, attack, length) * tone(glide(f0, f1, u, t))
    return voice


def airy(f0, f1, length, seed):
    """An airy swell: a sine that slides from f0 to f1 under a band-passed noise bed, on a pad envelope."""
    n = int(round(length * RATE))
    noise = lcg_noise(seed, n)
    buf = [0.0] * n
    fast = slow = 0.0
    for k in range(n):
        u = k / RATE
        fast += 0.5 * (noise[k] - fast)      # a fast low-pass minus a slow one: a band from about 350 Hz to 1.7 kHz
        slow += 0.1 * (noise[k] - slow)
        bed = fast - slow
        buf[k] = pad_env(u, 0.12, length) * (0.55 * math.sin(TAU * glide(f0, f1, u, length)) + 0.5 * bed)
    return buf


def ps2_cues():
    cues = {}
    # Unlock: a warm chord swell, C major sliding up a whole step to D major over 0.55 s, 180 ms attack.
    buf = [0.0] * int(round(1.0 * RATE))
    for f0, f1 in ((261.63, 293.66), (329.63, 369.99), (392.00, 440.00)):
        mix(buf, 0.0, 1.0, pad_voice(f0, f1, 0.55, 1.0, 0.18, tone_warm, 0.5))
    cues["unlock"] = buf
    # Error: a low, muted minor dyad, D3 and F3, 100 ms attack.
    buf = [0.0] * int(round(0.9 * RATE))
    for f in (146.83, 174.61):
        mix(buf, 0.0, 0.9, pad_voice(f, f, 1.0, 0.9, 0.10, tone_muted, 0.45))
    cues["error"] = buf
    # Notify: a two-tone glass chime pad, F5 then C6 (a fifth up), 90 ms attacks.
    buf = [0.0] * int(round(0.9 * RATE))
    mix(buf, 0.00, 0.85, pad_voice(698.46, 698.46, 1.0, 0.85, 0.09, tone_glass, 0.5))
    mix(buf, 0.16, 0.74, pad_voice(1046.50, 1046.50, 1.0, 0.74, 0.09, tone_glass, 0.45))
    cues["notify"] = buf
    # Open: a short airy swell up; close: a shorter one down, a little lower.
    cues["open"] = airy(620.0, 1240.0, 0.5, 11)
    cues["close"] = airy(1040.0, 520.0, 0.45, 12)
    return {name: finish(room(samples)) for name, samples in cues.items()}


# --- pointers ----------------------------------------------------------------------------------

# snes: a chunky arrow on a 16 × 16 grid, tip at (0, 0). X = near-black outline, W = white fill, g = grey shading on the
# lower-right inner edge, . = transparent. Scaled by whole numbers (16 → 1×, 32 → 2×, 48 → 3×, 64 → 4×).
SNES_ART = [
    "X...............",
    "XX..............",
    "XgX.............",
    "XWgX............",
    "XWWgX...........",
    "XWWWgX..........",
    "XWWWWgX.........",
    "XWWWWWgX........",
    "XWWWWWggX.......",
    "XWWWWgXXXX......",
    "XWWXWgX.........",
    "XWX.XWgX........",
    "XX...XWgX.......",
    "X.....XWgX......",
    ".......XXX......",
    "................",
]
SNES_COLOURS = {"X": 0xFF101010, "W": 0xFFFFFFFF, "g": 0xFF8A8A8A}
SNES_SIZES = (16, 32, 48, 64)

# ps2: a slim silver-white arrow in 32 units, tip at (1, 1). A 1 px blue-grey outline and a blue glow about 3 px wide.
PS2_ARROW = [(1, 1), (1, 21.0), (5.0, 17.0), (7.2, 22.9), (10.4, 21.6), (8.0, 16.4), (13.2, 16.4)]
PS2_SILVER = (0.95, 0.965, 0.985)
PS2_OUTLINE = (0.27, 0.35, 0.48)
PS2_GLOW = (0.498, 0.659, 0.910)   # #7fa8e8
PS2_SIZES = (24, 32, 48, 64)


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


def snes_pixels(size):
    """ARGB words of the snes arrow at `size` px: each art cell becomes a k × k block, hard alpha."""
    assert size % 16 == 0
    k = size // 16
    px = [0] * (size * size)
    for ay, row in enumerate(SNES_ART):
        assert len(row) == 16, (ay, row)
        for ax, ch in enumerate(row):
            colour = SNES_COLOURS.get(ch)
            if colour is None:
                continue
            for dy in range(k):
                for dx in range(k):
                    px[(ay * k + dy) * size + ax * k + dx] = colour
    return px


def ps2_pixels(nominal):
    """Premultiplied ARGB words of the ps2 arrow, 4 × 4 supersampled: fill, outline, then the glow behind it."""
    k = nominal / 32.0
    poly = [(x * k, y * k) for x, y in PS2_ARROW]
    line = max(1.0, k)      # the outline: 1 px at 32, 2 px at 64 (as fluent's)
    glow = 3.0 * k          # the glow reaches about 3 px out at 32
    ss = 4
    px = []
    for y in range(nominal):
        for x in range(nominal):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    X = x + (sx + 0.5) / ss
                    Y = y + (sy + 0.5) / ss
                    d = dist_to_edges(X, Y, poly)
                    if inside(X, Y, poly):
                        colour, alpha = (PS2_OUTLINE if d < line else PS2_SILVER), 1.0
                    elif d < glow:
                        colour, alpha = PS2_GLOW, 0.35 * (1.0 - d / glow) ** 2
                    else:
                        continue
                    acc[0] += colour[0] * alpha
                    acc[1] += colour[1] * alpha
                    acc[2] += colour[2] * alpha
                    acc[3] += alpha
            n = ss * ss
            R, G, B, A = (int(round(v / n * 255)) for v in acc)
            px.append((A << 24) | (R << 16) | (G << 8) | B)
    return px


def write_xcursor(path, images):
    """An Xcursor file (libXcursor's format: 'Xcur', a table of contents, one image chunk per nominal size).
    images: [(nominal, hot_x, hot_y, pixels)] with premultiplied ARGB pixels, row by row."""
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
    for set_name, cues in (("snes", snes_cues()), ("ps2", ps2_cues())):
        folder = os.path.join(ROOT, "sounds", set_name)
        os.makedirs(folder, exist_ok=True)
        for cue, samples in cues.items():
            path = os.path.join(folder, cue + ".wav")
            write_wav(path, samples, 0.5)
            s = describe(path)
            print(("%s/%-6s %5.3f s  %5.1f KiB  peak %.3f  rms %6.1f dBFS  "
                   "first %+.4f  last %+.4f  5 ms max head %.3f tail %.3f")
                  % (set_name, cue, s["seconds"], s["bytes"] / 1024.0, s["peak"], s["rms_db"],
                     s["first"], s["last"], s["head"], s["tail"]))
    write_cursor_set(
        "snes",
        "A chunky white arrow with a near-black outline on a 16 px grid "
        "(W53.5, CC0, drawn in tools/styles/consoles-assets.py)",
        [(n, 0, 0, snes_pixels(n)) for n in SNES_SIZES],
    )
    write_cursor_set(
        "ps2",
        "A slim silver-white arrow with a soft blue glow (W53.5, CC0, drawn in tools/styles/consoles-assets.py)",
        [(n, int(round(n / 32.0)), int(round(n / 32.0)), ps2_pixels(n)) for n in PS2_SIZES],
    )
    print("cursors/snes sizes %s, hotspot (0, 0)" % (SNES_SIZES,))
    print("cursors/ps2 sizes %s, hotspot round(n/32)" % (PS2_SIZES,))


if __name__ == "__main__":
    main()
