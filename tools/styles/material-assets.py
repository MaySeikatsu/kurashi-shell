#!/usr/bin/env python3
"""material's sounds and pointer, made from nothing (W53.8; docs/ux/styles.md "material"; K80 decided 6, 11).

Everything here is synthesised or drawn in this file: no Android, Pixel or Material sound, ringtone or pointer is read,
sampled, traced or imitated note-for-note, and the output is CC0.

Sound: Material's motion is quick, decelerating and clean, so the cues are short soft plucks — a sine with a little
second and third harmonic, a 4 ms attack and an exponential fall, the way a fingertip tap on glass sounds rather than a
chime. A rising fifth unlocks, two low falling taps mark an error, a three-note rise (a major triad, gentle) notifies, a
single tap that glides up opens and one that glides down closes. A short room (one quiet early reflection) keeps them
from sounding dry. Each cue stays under 0.7 s.

Pointer: a rounded arrow in M3's dark on-surface ink with a white rim and a soft shadow below it, drawn as a polygon
with round joins (each edge offset outward and the corners filled), 4 × 4 supersampled.

    python3 tools/styles/material-assets.py    # writes sounds/material and cursors/material
Python's standard library only; it reuses consoles-assets.py's writers (wav, xcursor) and checks. Deterministic.
"""
import importlib.util
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("consoles_assets", os.path.join(HERE, "consoles-assets.py"))
ca = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ca)
RATE, TAU, ROOT = ca.RATE, ca.TAU, ca.ROOT


# --- sound: soft plucks ---------------------------------------------------------------------------------------------

def pluck(f, u, length, decay):
    """A soft pluck at f Hz: sine + 2nd (0.18) + 3rd (0.06) harmonic, 4 ms raised-cosine attack, exponential fall."""
    if u < 0 or u >= length:
        return 0.0
    env = ca.ramp(u, 0.004) * math.exp(-u / decay) * ca.window(u, length, 0.04)
    p = TAU * f * u
    return env * (math.sin(p) + 0.18 * math.sin(2 * p) + 0.06 * math.sin(3 * p))


def glide_pluck(f0, f1, u, length, decay, t):
    if u < 0 or u >= length:
        return 0.0
    env = ca.ramp(u, 0.004) * math.exp(-u / decay) * ca.window(u, length, 0.04)
    ph = TAU * ca.glide(f0, f1, u, t)
    return env * (math.sin(ph) + 0.12 * math.sin(2 * ph))


def cue(total, notes):
    buf = [0.0] * int(total * RATE)
    for start, length, voice in notes:
        ca.mix(buf, start, length, voice)
    buf = ca.room(buf, delay=0.045, feedback=0.15, level=0.12)
    return ca.finish(buf)


def material_cues():
    # Pitches from A4 = 440 Hz: E5 659.26, B5 987.77, C5 523.25, E5, G5 783.99, A3 220, F3 174.61.
    return {
        "unlock": cue(0.62, [
            (0.00, 0.30, lambda u: pluck(659.26, u, 0.30, 0.09)),
            (0.09, 0.50, lambda u: pluck(987.77, u, 0.50, 0.14)),
        ]),
        "error": cue(0.48, [
            (0.00, 0.20, lambda u: pluck(220.0, u, 0.20, 0.06)),
            (0.13, 0.30, lambda u: pluck(174.61, u, 0.30, 0.08)),
        ]),
        "notify": cue(0.66, [
            (0.00, 0.26, lambda u: pluck(523.25, u, 0.26, 0.07)),
            (0.07, 0.26, lambda u: pluck(659.26, u, 0.26, 0.07)),
            (0.14, 0.46, lambda u: pluck(783.99, u, 0.46, 0.13)),
        ]),
        "open": cue(0.24, [
            (0.00, 0.20, lambda u: glide_pluck(880.0, 1174.66, u, 0.20, 0.05, 0.05)),
        ]),
        "close": cue(0.24, [
            (0.00, 0.20, lambda u: glide_pluck(1174.66, 783.99, u, 0.20, 0.05, 0.05)),
        ]),
    }


# --- the pointer ------------------------------------------------------------------------------------------------------

# A rounded arrow in 32 units, tip at (2, 2): the classic proportions, a little stouter; edges rounded by `RIM`.
ARROW = [(2.0, 2.0), (2.0, 23.0), (7.2, 18.6), (10.6, 26.2), (14.0, 24.8), (10.8, 17.4), (17.6, 17.4)]
INK = (0.114, 0.106, 0.125)      # M3 baseline on-surface (light), #1d1b20
RIM = (1.0, 1.0, 1.0)
SHADOW = (0.0, 0.0, 0.0)
SIZES = (24, 32, 48, 64)


def pixels(nominal):
    k = nominal / 32.0
    poly = [(x * k, y * k) for x, y in ARROW]
    rim = 1.6 * k                  # the white rim outside the ink, round at the corners
    soft = 2.4 * k                 # the shadow's reach, 1 px down at 32
    ss = 4
    out = []
    for y in range(nominal):
        for x in range(nominal):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    X = x + (sx + 0.5) / ss
                    Y = y + (sy + 0.5) / ss
                    if ca.inside(X, Y, poly):
                        colour, alpha = INK, 1.0
                    else:
                        d = ca.dist_to_edges(X, Y, poly)
                        if d < rim:
                            colour, alpha = RIM, 1.0
                        else:
                            ds = ca.dist_to_edges(X - 0.0, Y - 1.0 * k, poly)
                            inside_s = ca.inside(X, Y - 1.0 * k, poly)
                            if inside_s or ds < rim + soft:
                                t = 0.0 if inside_s else max(0.0, (ds - rim) / soft)
                                colour, alpha = SHADOW, 0.32 * (1.0 - min(1.0, t)) ** 2
                            else:
                                continue
                    acc[0] += colour[0] * alpha
                    acc[1] += colour[1] * alpha
                    acc[2] += colour[2] * alpha
                    acc[3] += alpha
            n = ss * ss
            R, G, B, A = (int(round(v / n * 255)) for v in acc)
            out.append((A << 24) | (R << 16) | (G << 8) | B)
    return out


def main():
    folder = os.path.join(ROOT, "sounds", "material")
    os.makedirs(folder, exist_ok=True)
    for name, samples in material_cues().items():
        path = os.path.join(folder, name + ".wav")
        ca.write_wav(path, samples, 0.5)
        s = ca.describe(path)
        print("material/%-6s %5.3f s  %5.1f KiB  peak %.3f  rms %6.1f dBFS  first %+.4f  last %+.4f"
              % (name, s["seconds"], s["bytes"] / 1024.0, s["peak"], s["rms_db"], s["first"], s["last"]))
    ca.write_cursor_set(
        "material",
        "A rounded dark arrow with a white rim and a soft shadow (W53.8, CC0, drawn in tools/styles/material-assets.py)",
        [(n, int(round(2 * n / 32.0)), int(round(2 * n / 32.0)), pixels(n)) for n in SIZES],
    )
    print("cursors/material sizes %s, hotspot round(2n/32)" % (SIZES,))


if __name__ == "__main__":
    main()
