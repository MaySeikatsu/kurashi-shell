#!/usr/bin/env python3
"""kanso's, glass's and terminal's sounds and pointers, made from nothing (W53.8; docs/ux/styles.md "kanso", "glass",
"terminal"; K80 decided 6, 11).

Everything here is synthesised or drawn in this file: no system's, terminal emulator's or app's sound or pointer is read,
sampled, traced or imitated note-for-note, and the output is CC0.

kanso (the plain form): quiet sine tones with a soft wooden knock under them and short decays — nothing that asks for
attention. A rising fifth unlocks, a soft falling second marks an error, one round tone notifies, a short knock opens
and a lower one closes. The pointer is a plain arrow: near-black fill, a white 1.5 px rim, a faint soft shadow.

glass (Vitreus/pleamar): glassy chimes — sine partials at the inharmonic ratios of a struck glass (1, 2.32, 4.25, 6.63),
a 2 ms strike and long, bright decays in a small airy room. Two chimes a sixth apart unlock, a low muted pair marks an
error, one clear chime notifies, a soft high ping rises for open and falls for close. The pointer is a frosted arrow:
white at 82 % opacity, a bright 1 px rim and a soft shadow, supersampled.

terminal: a terminal's bell, the way a small speaker beeps — square waves through a gentle low-pass, hard on and off
with only a 2 ms ramp (no reverb). One short blip notifies (the bell), two low beeps mark an error, a rising pair
unlocks, a 25 ms key tick opens and a lower one closes. The pointer is a 1-bit arrow on a 12 × 19 grid, white with a
black outline, scaled by whole numbers with hard alpha (a console mouse cursor in spirit, drawn here).

    python3 tools/styles/modern-assets.py    # writes sounds/{kanso,glass,terminal} and cursors/{kanso,glass,terminal}
Python's standard library only (math, os, struct, wave); deterministic, so a rerun reproduces the committed files.
"""
import math
import os
import struct
import wave

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
RATE = 22050
MAX_BYTES = 50 * 1024  # the budget per cue (docs/ux/styles.md "Sounds")
TAU = 2 * math.pi


# --- sound helpers (as consoles-assets.py) ------------------------------------------------------------------------------

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
    i0 = int(round(start * RATE))
    for k in range(int(round(length * RATE))):
        if i0 + k < len(buf):
            buf[i0 + k] += voice(k / RATE)


def room(samples, delay=0.11, feedback=0.25, level=0.18):
    d = int(delay * RATE)
    buf = [0.0] * len(samples)
    out = list(samples)
    for i in range(len(samples)):
        echo = buf[i - d] if i >= d else 0.0
        buf[i] = samples[i] + feedback * echo
        out[i] += level * echo
    return out


def lowpass(samples, cutoff):
    """A one-pole low-pass (a small speaker's dull top)."""
    a = 1.0 - math.exp(-TAU * cutoff / RATE)
    y = 0.0
    out = []
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def finish(samples):
    """A 25 ms raised-cosine fade to exactly 0 at the last sample, so no cue ends on a click."""
    fade = min(int(0.025 * RATE), len(samples) // 2)
    for k in range(fade):
        samples[-1 - k] *= 0.5 - 0.5 * math.cos(math.pi * k / fade)
    return samples


def lcg_noise(seed, n):
    x = seed & 0xFFFFFFFF
    out = []
    for _ in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out.append(x / 2147483648.0 - 1.0)
    return out


def write_wav(path, samples, level):
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
    with wave.open(path, "rb") as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, RATE), path
        n = w.getnframes()
        s = struct.unpack("<%dh" % n, w.readframes(n))
    size = os.path.getsize(path)
    assert size <= MAX_BYTES, "%s is %d bytes" % (path, size)
    assert abs(s[0]) <= 330 and abs(s[-1]) <= 330, path
    rms = math.sqrt(sum(x * x for x in s) / float(n)) / 32767.0
    return n / float(RATE), size, max(abs(x) for x in s) / 32767.0, 20 * math.log10(max(rms, 1e-9))


def silence(seconds):
    return [0.0] * int(round(seconds * RATE))


# --- kanso: quiet sine tones -------------------------------------------------------------------------------------------

def soft_tone(f, u, length, tau):
    """A round tone: the sine with a little of its octave, a 6 ms attack and an exponential decay."""
    body = math.sin(TAU * f * u) + 0.18 * math.sin(TAU * 2 * f * u) * math.exp(-u / (tau * 0.4))
    return ramp(u, 0.006) * math.exp(-u / tau) * window(u, length, 0.05) * body


def knock(f, u, length):
    """A soft wooden knock: a fast-decaying sine with a pitch drop and a breath of noise."""
    p = f * u - 0.5 * f * 0.3 * u * u / 0.03 if u < 0.03 else f * 0.03 - 0.5 * f * 0.3 * 0.03 + f * 0.7 * (u - 0.03)
    return ramp(u, 0.002) * math.exp(-u / 0.028) * window(u, length, 0.02) * math.sin(TAU * p)


def kanso_cues():
    cues = {}
    b = silence(0.75)
    mix(b, 0.00, 0.40, lambda u: soft_tone(523.25, u, 0.40, 0.16))   # C5
    mix(b, 0.09, 0.62, lambda u: soft_tone(783.99, u, 0.62, 0.22))   # G5: a rising fifth
    cues["unlock"] = b
    b = silence(0.55)
    mix(b, 0.00, 0.22, lambda u: soft_tone(392.00, u, 0.22, 0.10))   # G4
    mix(b, 0.13, 0.40, lambda u: soft_tone(349.23, u, 0.40, 0.14))   # F4: a soft falling second
    cues["error"] = b
    b = silence(0.6)
    mix(b, 0.00, 0.58, lambda u: soft_tone(659.25, u, 0.58, 0.2))    # E5
    mix(b, 0.00, 0.05, lambda u: 0.5 * knock(1300.0, u, 0.05))
    cues["notify"] = b
    b = silence(0.12)
    mix(b, 0.00, 0.10, lambda u: knock(900.0, u, 0.10))
    cues["open"] = b
    b = silence(0.12)
    mix(b, 0.00, 0.10, lambda u: knock(700.0, u, 0.10))
    cues["close"] = b
    return {k: finish(room(v, 0.07, 0.15, 0.08)) for k, v in cues.items()}


# --- glass: struck-glass chimes ----------------------------------------------------------------------------------------

GLASS_PARTIALS = ((1.0, 1.0, 1.0), (2.32, 0.45, 0.55), (4.25, 0.22, 0.32), (6.63, 0.10, 0.2))


def chime(f, u, length, tau, damp=1.0):
    """A struck glass: inharmonic sine partials (ratio, level, decay share), a 2 ms strike, a long decay."""
    s = 0.0
    for ratio, level, share in GLASS_PARTIALS:
        s += level * damp ** (ratio - 1) * math.exp(-u / (tau * share)) * math.sin(TAU * f * ratio * u)
    return ramp(u, 0.002) * window(u, length, 0.08) * s


def glass_cues():
    cues = {}
    b = silence(0.95)
    mix(b, 0.00, 0.80, lambda u: chime(880.00, u, 0.80, 0.35))       # A5
    mix(b, 0.11, 0.84, lambda u: chime(1479.98, u, 0.84, 0.42))      # F#6: a major sixth up
    cues["unlock"] = b
    b = silence(0.6)
    mix(b, 0.00, 0.30, lambda u: chime(311.13, u, 0.30, 0.09, 0.4))  # D#4, muted
    mix(b, 0.15, 0.42, lambda u: chime(293.66, u, 0.42, 0.11, 0.4))  # D4
    cues["error"] = b
    b = silence(0.85)
    mix(b, 0.00, 0.85, lambda u: chime(1318.51, u, 0.85, 0.4))       # E6
    cues["notify"] = b

    def ping(f0, f1, length):
        def v(u):
            ph = f0 * u + 0.5 * (f1 - f0) * u * u / length
            return ramp(u, 0.004) * math.exp(-u / 0.07) * window(u, length, 0.04) * (
                math.sin(TAU * ph) + 0.25 * math.sin(TAU * 2.32 * ph))
        return v
    b = silence(0.2)
    mix(b, 0.00, 0.18, ping(1760.0, 2350.0, 0.18))
    cues["open"] = b
    b = silence(0.2)
    mix(b, 0.00, 0.18, ping(2350.0, 1760.0, 0.18))
    cues["close"] = b
    return {k: finish(room(v, 0.09, 0.32, 0.22)) for k, v in cues.items()}


# --- terminal: the bell --------------------------------------------------------------------------------------------------

def beep(f, u, length):
    """A small speaker's beep: a square wave, 2 ms on and off, nothing else."""
    sq = 1.0 if (f * u) % 1.0 < 0.5 else -1.0
    return ramp(u, 0.002) * window(u, length, 0.004) * sq


def terminal_cues():
    def seq(notes, seconds):
        b = silence(seconds)
        for start, f, length, lvl in notes:
            mix(b, start, length, lambda u, f=f, length=length, lvl=lvl: lvl * beep(f, u, length))
        return lowpass(b, 3200)
    cues = {
        # Unlock: a rising pair, the second a fourth up.
        "unlock": seq([(0.00, 660.0, 0.07, 1.0), (0.10, 880.0, 0.11, 1.0)], 0.3),
        # Error: two low beeps.
        "error": seq([(0.00, 330.0, 0.12, 1.0), (0.18, 330.0, 0.12, 1.0)], 0.4),
        # Notify: the bell — one short blip.
        "notify": seq([(0.00, 784.0, 0.11, 1.0)], 0.2),
        # Open and close: key ticks.
        "open": seq([(0.00, 1568.0, 0.025, 0.6)], 0.08),
        "close": seq([(0.00, 1046.5, 0.025, 0.6)], 0.08),
    }
    return {k: finish(v) for k, v in cues.items()}


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


# An arrow in 32 units, tip at (2, 2): kanso's and glass's (their own proportions, not a system cursor's outline).
ARROW = [(2, 2), (2, 24.5), (7.6, 19.4), (11.2, 27.4), (15.0, 25.8), (11.6, 18.0), (19.0, 18.0)]
SMOOTH_SIZES = (24, 32, 48, 64)


def smooth_pixels(nominal, fill, fill_a, rim, rim_w, shadow_a):
    """Premultiplied ARGB of the arrow: fill (alpha fill_a) inside a rim, a soft shadow 1.5 units down-right."""
    k = nominal / 32.0
    poly = [(x * k, y * k) for x, y in ARROW]
    shadow = [(x + 1.5 * k, y + 1.5 * k) for x, y in poly]
    line = rim_w * k
    reach = 3.0 * k
    ss = 4
    px = []
    for y in range(nominal):
        for x in range(nominal):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    X = x + (sx + 0.5) / ss
                    Y = y + (sy + 0.5) / ss
                    if inside(X, Y, poly):
                        d = dist_to_edges(X, Y, poly)
                        colour, alpha = (rim, 1.0) if d < line else (fill, fill_a)
                        # what the frosted fill lets through is the shadow under it
                        if alpha < 1.0 and inside(X, Y, shadow):
                            acc[3] += shadow_a * (1 - alpha)
                    else:
                        if inside(X, Y, shadow):
                            colour, alpha = (0.0, 0.0, 0.0), shadow_a
                        else:
                            d = dist_to_edges(X, Y, shadow)
                            if d >= reach:
                                continue
                            colour, alpha = (0.0, 0.0, 0.0), shadow_a * (1 - d / reach) ** 2
                    acc[0] += colour[0] * alpha
                    acc[1] += colour[1] * alpha
                    acc[2] += colour[2] * alpha
                    acc[3] += alpha
            n = ss * ss
            R, G, B, A = (int(round(min(1.0, v / n) * 255)) for v in acc)
            px.append((A << 24) | (R << 16) | (G << 8) | B)
    return px


# terminal: a 1-bit arrow on a 12 × 19 grid: '#' black outline, 'w' white.
TERM_ART = [
    "#...........",
    "##..........",
    "#w#.........",
    "#ww#........",
    "#www#.......",
    "#wwww#......",
    "#wwwww#.....",
    "#wwwwww#....",
    "#wwwwwww#...",
    "#wwwwwwww#..",
    "#wwwwwwwww#.",
    "#wwwwww#####",
    "#www#ww#....",
    "#ww#.#ww#...",
    "#w#..#ww#...",
    "##....#ww#..",
    "......#ww#..",
    ".......#ww#.",
    "........##..",
]
TERM_COLOURS = {"#": 0xFF000000, "w": 0xFFFFFFFF}
TERM_SIZES = (24, 48, 72)   # the 19-row art × 1, 2, 3 in a square of 24 per step


def term_pixels(size):
    k = size // 24
    px = [0] * (size * size)
    for ay, row in enumerate(TERM_ART):
        assert len(row) == 12, (ay, row)
        for ax, ch in enumerate(row):
            colour = TERM_COLOURS.get(ch)
            if colour is None:
                continue
            for dy in range(k):
                for dx in range(k):
                    px[(ay * k + dy) * size + ax * k + dx] = colour
    return px


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
    for set_name, cues in (("kanso", kanso_cues()), ("glass", glass_cues()), ("terminal", terminal_cues())):
        folder = os.path.join(ROOT, "sounds", set_name)
        os.makedirs(folder, exist_ok=True)
        for cue, samples in cues.items():
            path = os.path.join(folder, cue + ".wav")
            write_wav(path, samples, 0.45 if set_name != "terminal" else 0.35)
            sec, size, peak, rms = describe(path)
            print("%s/%-6s %5.3f s  %5.1f KiB  peak %.3f  rms %6.1f dBFS" % (set_name, cue, sec, size / 1024.0, peak, rms))
    write_cursor_set(
        "kanso", "A plain near-black arrow with a white rim (W53.8, CC0, drawn in tools/styles/modern-assets.py)",
        [(n, round(2 * n / 32), round(2 * n / 32), smooth_pixels(n, (0.11, 0.11, 0.11), 1.0, (1.0, 1.0, 1.0), 1.5, 0.28))
         for n in SMOOTH_SIZES])
    write_cursor_set(
        "glass", "A frosted white arrow with a bright rim and a soft shadow (W53.8, CC0, drawn in tools/styles/modern-assets.py)",
        [(n, round(2 * n / 32), round(2 * n / 32), smooth_pixels(n, (1.0, 1.0, 1.0), 0.82, (0.55, 0.62, 0.72), 1.0, 0.3))
         for n in SMOOTH_SIZES])
    write_cursor_set(
        "terminal", "A 1-bit arrow, white with a black outline, on a 12 × 19 grid (W53.8, CC0, drawn in tools/styles/modern-assets.py)",
        [(n, 0, 0, term_pixels(n)) for n in TERM_SIZES])
    print("cursors kanso/glass sizes %s, terminal %s" % (SMOOTH_SIZES, TERM_SIZES))


if __name__ == "__main__":
    main()
