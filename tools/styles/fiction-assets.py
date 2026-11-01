#!/usr/bin/env python3
"""The fiction family's sound cues and pointers, made from nothing (W53.6, docs/ux/styles.md §9.1-§9.4).

Everything here is synthesised or drawn in this file — never a game's sounds, cursors or art: none is read, sampled,
traced or copied, and the output is CC0. Each set carries its source's mood in our own notes:
- kawaii (Needy Streamer Overload's pastel desktop): chiptune square-wave blips, bright and bouncy, a sparkle shimmer;
  a chunky pink pixel arrow with a white rim and a plum edge.
- yorha (NieR:Automata's menus): soft, short sine blips with a thin echo, a muted electronic buzz for an error; a slim
  dark-ink arrow with a parchment rim, no shadow.
- souls (Dark Souls' menus): low, slow, reverberant — a hushed swell, a distant bell, a deep hit; an ember crackle and a
  warm rising swell to unlock; a slender black arrow with an antique-gold rim and a long soft shadow.
- hallownest (Hollow Knight's menus): delicate glassy tings and a music-box pair, a muted pluck for an error; a pale
  needle of an arrow with a deep blue-black rim.
Every cue is a short 22 kHz mono clip under 50 KiB; every pointer a 32 px nominal Xcursor like the others.

    python3 -I tools/styles/fiction-assets.py    # writes sounds/{kawaii,yorha,souls,hallownest}/ and cursors/<same>/
Python's standard library only; deterministic (fixed seeds), so a rerun reproduces the committed files. The shared
building blocks (wav writer, envelopes, FM bell, filters, the Xcursor writer) come from mac-assets.py beside it.
"""
import importlib.util
import sys

sys.dont_write_bytecode = True
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("mac_assets", os.path.join(HERE, "mac-assets.py"))
mac = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mac)

ROOT, RATE, TAU = mac.ROOT, mac.RATE, mac.TAU
render, place, fades, swell, bell, silence, room, lowpass = (
    mac.render, mac.place, mac.fades, mac.swell, mac.bell, mac.silence, mac.room, mac.lowpass)


def note(n):
    """The frequency of MIDI note n."""
    return 440.0 * 2 ** ((n - 69) / 12)


def square(f, t, duty=0.5):
    """A band-limited-ish square: the first few odd harmonics, so it buzzes like a chip without aliasing hiss."""
    return sum(math.sin(TAU * f * k * t) / k for k in (1, 3, 5, 7, 9)) * (4 / math.pi) * (0.6 if duty == 0.5 else 0.5)


def noise(seconds, seed, decay):
    rnd = random.Random(seed)
    return [rnd.uniform(-1, 1) * math.exp(-(i / RATE) / decay) for i in range(int(seconds * RATE))]


# -- kawaii: chip blips ----------------------------------------------------------------------------------------------

def kawaii_cues():
    def blip(n, dur=0.07, level=1.0):
        f = note(n)
        return fades(render(dur, lambda u: level * square(f, u) * swell(u, 0.003, dur * 0.5)), 0.002, 0.01)

    def arp(notes, gap, dur=0.07, tail=0.15):
        buf = silence(gap * len(notes) + dur + tail)
        for i, n in enumerate(notes):
            place(buf, i * gap, blip(n, dur), 0.8)
        return buf

    def shimmer(start_note, seconds):
        f = note(start_note)
        return fades(render(seconds, lambda u: 0.35 * bell(f, u, 3.5, 2.0, 9.0) * swell(u, 0.005, 0.12)), 0.003, 0.05)

    unlock = arp([72, 76, 79, 84], 0.07, 0.08, 0.3)
    place(unlock, 0.3, shimmer(96, 0.3), 0.6)
    notify = arp([84, 88, 91], 0.06, 0.06, 0.2)
    place(notify, 0.2, shimmer(100, 0.25), 0.5)
    return {
        "open": arp([76, 83], 0.05, 0.06, 0.08),
        "close": arp([83, 76], 0.05, 0.06, 0.08),
        "notify": room(notify, [(0.05, 0.25)], 0.3),
        "error": arp([64, 61], 0.11, 0.1, 0.1),
        "unlock": room(unlock, [(0.06, 0.25)], 0.3),
    }


# -- yorha: soft sine blips with a thin echo --------------------------------------------------------------------------

def yorha_cues():
    def blip(f, dur=0.05, level=1.0):
        def v(u):
            return level * (0.7 * math.sin(TAU * f * u) + 0.3 * math.sin(TAU * f * 1.006 * u + 0.4)) * swell(u, 0.002, dur * 0.4)
        return fades(render(dur * 2.5, v), 0.002, 0.02)

    def tick(seed):
        return lowpass(fades(noise(0.012, seed, 0.004), 0.0005, 0.004), 5000)

    def echoed(buf):
        return room(buf, [(0.09, 0.32), (0.18, 0.14)], 1.0)

    def seq(parts, length):
        buf = silence(length)
        for start, clip, gain in parts:
            place(buf, start, clip, gain)
        return buf

    buzz = fades(render(0.16, lambda u: (0.6 * math.sin(TAU * 196 * u) + 0.4 * square(98, u)) * swell(u, 0.004, 0.06)), 0.003, 0.03)
    sweep = fades(render(0.32, lambda u: math.sin(mac.glide(660, 1760, 0.12, u)) * swell(u, 0.01, 0.12)), 0.004, 0.06)
    return {
        "open": echoed(seq([(0, tick(1), 0.4), (0.0, blip(1568), 0.8), (0.055, blip(2093), 0.7)], 0.5)),
        "close": echoed(seq([(0, tick(2), 0.3), (0.0, blip(1319), 0.7)], 0.45)),
        "notify": echoed(seq([(0, blip(1760), 0.8), (0.09, blip(1760), 0.55), (0.18, blip(2349), 0.7)], 0.7)),
        "error": seq([(0, buzz, 0.9), (0.2, buzz, 0.8)], 0.5),
        "unlock": echoed(seq([(0, sweep, 0.8), (0.3, blip(2637, 0.08), 0.6)], 0.9)),
    }


# -- souls: low, slow, reverberant ------------------------------------------------------------------------------------

def souls_cues():
    hall = [(0.11, 0.42), (0.23, 0.3), (0.37, 0.2), (0.53, 0.12), (0.71, 0.07)]

    def hush(seconds, fc, seed, level=1.0):
        n = noise(seconds, seed, 10.0)
        env = [swell(i / RATE, seconds * 0.45, seconds * 0.35) for i in range(len(n))]
        return fades(lowpass([a * b * level for a, b in zip(n, env)], fc), 0.01, 0.08)

    def low(f, seconds, level=1.0):
        return fades(render(seconds, lambda u: level * math.sin(TAU * f * u) * swell(u, 0.02, seconds * 0.3)), 0.005, 0.08)

    def toll(f, seconds, level=1.0):
        return fades(render(seconds, lambda u: level * bell(f, u, 2.76, 2.4, 3.0) * swell(u, 0.004, seconds * 0.35)), 0.003, 0.1)

    def mix(length, parts):
        buf = silence(length)
        for start, clip, gain in parts:
            place(buf, start, clip, gain)
        return buf

    crackle = silence(0.6)
    rnd = random.Random(7)
    for _ in range(14):
        place(crackle, rnd.uniform(0, 0.5), lowpass(fades(noise(0.008, rnd.randint(0, 999), 0.003), 0.0005, 0.003), 3500),
              rnd.uniform(0.2, 0.6))
    return {
        "open": room(mix(0.7, [(0, hush(0.45, 900, 11), 0.7), (0.05, low(110, 0.4), 0.5)]), hall, 0.5),
        "close": room(mix(0.6, [(0, low(82, 0.3), 0.7), (0, hush(0.25, 600, 12), 0.4)]), hall, 0.4),
        "notify": room(mix(1.1, [(0, toll(440, 1.05), 0.7), (0, toll(659, 0.8), 0.25)]), hall, 0.55),
        "error": room(mix(1.0, [(0, low(55, 0.7, 1.0), 0.9), (0, hush(0.5, 300, 13), 0.6)]), hall, 0.45),
        "unlock": room(mix(1.15, [(0, crackle, 0.7), (0.1, hush(0.8, 1400, 14), 0.6), (0.25, low(110, 0.85), 0.45),
                                  (0.45, toll(220, 0.7), 0.4)]), hall, 0.55),
    }


# -- hallownest: glassy tings and a music box ------------------------------------------------------------------------

def hallownest_cues():
    cave = [(0.07, 0.35), (0.16, 0.24), (0.27, 0.15), (0.41, 0.09)]

    def ting(n, seconds=0.5, level=1.0):
        f = note(n)
        return fades(render(seconds, lambda u: level * bell(f, u, 4.0, 1.4, 7.0) * swell(u, 0.002, seconds * 0.3)), 0.002, 0.06)

    def pluck(n, seconds=0.25):
        f = note(n)
        return fades(lowpass(render(seconds, lambda u: square(f, u) * swell(u, 0.002, 0.05)), 1200), 0.002, 0.05)

    def seq(length, parts):
        buf = silence(length)
        for start, clip, gain in parts:
            place(buf, start, clip, gain)
        return buf

    return {
        "open": room(seq(0.6, [(0, ting(88, 0.45), 0.6)]), cave, 0.5),
        "close": room(seq(0.6, [(0, ting(81, 0.45), 0.45)]), cave, 0.5),
        "notify": room(seq(0.9, [(0, ting(88, 0.5), 0.6), (0.14, ting(83, 0.6), 0.55)]), cave, 0.5),
        "error": room(seq(0.6, [(0, pluck(50), 0.6), (0.12, pluck(47), 0.6)]), cave, 0.35),
        "unlock": room(seq(1.1, [(0, ting(91, 0.6), 0.5), (0.12, ting(88, 0.6), 0.5), (0.24, ting(84, 0.7), 0.5),
                                 (0.36, ting(79, 0.74), 0.55)]), cave, 0.55),
    }


# -- the pointers: the mac-assets rasteriser with each set's own body and rim colours ---------------------------------

KAWAII_ARROW = [(0.0, -0.5), (0.0, 15.0), (4.0, 11.5), (6.5, 17.5), (10.0, 16.0), (7.5, 10.5), (12.0, 10.5)]
YORHA_ARROW = [(0.0, -0.5), (0.0, 17.5), (3.6, 13.8), (6.2, 20.6), (8.6, 19.6), (6.0, 12.8), (10.8, 12.8)]
SOULS_ARROW = [(0.0, -0.5), (0.0, 19.0), (3.2, 15.0), (6.6, 22.4), (8.8, 21.4), (5.6, 14.0), (10.0, 13.4)]
HALLOW_ARROW = [(0.0, -0.5), (0.4, 20.0), (2.6, 16.6), (5.2, 22.0), (7.0, 21.2), (4.6, 15.6), (8.8, 15.2)]


def argb(hexcol, a=255):
    v = int(hexcol.lstrip("#"), 16)
    r, g, b = (v >> 16) & 255, (v >> 8) & 255, v & 255
    return (a << 24) | (r << 16) | (g << 8) | b


def pointer(poly, rim_w, body, rim, edge, shadow):
    """`rim_w` px of `rim` inside the drawing's edge round a `body`, and `edge` (or None) one cell outside it; a shadow
    as mac-assets' (dx, dy, sigma, peak), or None."""
    dx, dy, sigma, peak = shadow or (0, 0, 0.6, 0.0)
    pad = 2 + dx + int(math.ceil(3 * sigma))
    w = int(math.ceil(max(x for x, _ in poly))) + pad + 1
    h = int(math.ceil(max(y for _, y in poly))) + pad + 1
    solid = mac.silhouette(poly, w, h)
    moved = [[y >= dy and x >= dx and solid[y - dy][x - dx] for x in range(w)] for y in range(h)]
    soft = mac.blur(moved, sigma) if peak > 0 else [[0] * w for _ in range(h)]
    near = lambda x, y: any(0 <= x + i < w and 0 <= y + j < h and solid[y + j][x + i]
                            for i in (-1, 0, 1) for j in (-1, 0, 1))
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            if solid[y][x]:
                row.append(rim if mac.edge_distance(poly, x + 0.5, y + 0.5) < rim_w else body)
            elif edge is not None and near(x, y):
                row.append(edge)
            else:
                row.append((int(255 * peak * soft[y][x] + 0.5)) << 24)
        out.append(row)
    return out


def write_set(style, cues, raster, comment):
    snd = os.path.join(ROOT, "sounds", style)
    os.makedirs(snd, exist_ok=True)
    for name, samples in cues.items():
        mac.write_wav(os.path.join(snd, name + ".wav"), samples)
    cur = os.path.join(ROOT, "cursors", style)
    os.makedirs(os.path.join(cur, "cursors"), exist_ok=True)
    with open(os.path.join(cur, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=kurashi-%s\nComment=%s\nInherits=default\n" % (style, comment))
    mac.write_xcursor(os.path.join(cur, "cursors", "default"), raster, [(24, 1), (32, 1), (48, 2), (64, 2)])
    for alias in ("left_ptr", "arrow", "top_left_arrow"):
        link = os.path.join(cur, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


def premul(hexcol, a):
    """A colour at alpha a, premultiplied (Xcursor pixels are premultiplied ARGB)."""
    v = int(hexcol.lstrip("#"), 16)
    r, g, b = (v >> 16) & 255, (v >> 8) & 255, v & 255
    return (int(a * 255) << 24) | (int(r * a) << 16) | (int(g * a) << 8) | int(b * a)


def main():
    write_set("kawaii", kawaii_cues(),
              pointer(KAWAII_ARROW, 1.2, argb("#ff8fc8"), argb("#ffffff"), argb("#7a4a8c"), None),
              "A chunky pastel-pink pixel arrow with a white rim and a plum edge (W53.6, CC0, tools/styles/fiction-assets.py)")
    write_set("yorha", yorha_cues(),
              pointer(YORHA_ARROW, 1.0, argb("#46433a"), argb("#dcd6bf"), None, None),
              "A slim dark-ink arrow with a parchment rim, flat (W53.6, CC0, tools/styles/fiction-assets.py)")
    write_set("souls", souls_cues(),
              pointer(SOULS_ARROW, 1.0, argb("#16120c"), argb("#c9a45c"), None, (2, 3, 1.8, 0.5)),
              "A slender black arrow with an antique-gold rim and a long soft shadow (W53.6, CC0, tools/styles/fiction-assets.py)")
    write_set("hallownest", hallownest_cues(),
              pointer(HALLOW_ARROW, 1.0, argb("#eef3f7"), argb("#e6edf2"), premul("#0c1018", 0.9), (1, 2, 1.2, 0.35)),
              "A pale needle of an arrow with a deep blue-black edge (W53.6, CC0, tools/styles/fiction-assets.py)")


if __name__ == "__main__":
    main()
