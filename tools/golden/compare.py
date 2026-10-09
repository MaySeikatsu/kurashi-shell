#!/usr/bin/env python3
"""Golden-screenshot comparison for tools/golden/run.sh (stdlib only: PNG via zlib).

  compare.py --size PNG W H                geometry of one capture (exit 1 if different)
  compare.py --check REF_DIR OUT_DIR STATE...
                                           compare OUT_DIR/STATE.png with REF_DIR/STATE.png

Pass rule: at most 0.5 % of the UNMASKED pixels may differ by more than 16/255 in any channel.
On failure the state, the count and the x-clusters of differing pixels (x0,y0)-(x1,y1) are
printed; those boxes are how MASKS were derived. The diff image OUT_DIR/STATE.diff.png is white
where pixels differ, grey where they are masked and black where they match.

MASKS are (x, y, w, h) in capture pixels (1920x1080), keyed by state; "*" applies to all states.
The clock changes every minute, so its regions are masked: the bar clock (`HH:MM`, right end of
the bar, in every state) and the island face (`HH:MM · Fri` at the top centre, weekday included).
Derivation: take references, wait for the minute to flip, run the check with no masks, read the
clusters, then pad 20 px horizontally and 4 px vertically.
"""
import os
import struct
import sys
import zlib

TOLERANCE = 16        # per channel, out of 255: a difference of exactly 16 passes
MAX_FRACTION = 0.005  # share of unmasked pixels allowed to differ
CLUSTER_GAP = 24      # columns closer than this are reported as one region

MASKS = {
    "*": [
        (913, 7, 95, 18),   # island face `HH:MM · Fri`, top centre: text x 933-987, y 11-20
        (1859, 7, 61, 18),  # bar clock `HH:MM`, right end: text x 1879-1907, y 11-20
    ],
    "launcher-open": [
        (699, 368, 5, 28),  # search caret (blinks): x 702, y 370-393
    ],
}

CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}  # PNG colour type -> samples per pixel (8-bit, non-interlaced)


def _chunks(data):
    pos = 8
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        yield kind, data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IEND":
            return


def _header(data, path):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    for kind, body in _chunks(data):
        if kind == b"IHDR":
            return struct.unpack(">IIBBBBB", body)
    raise ValueError(f"{path}: no IHDR chunk")


def png_size(path):
    with open(path, "rb") as f:
        w, h = _header(f.read(), path)[:2]
    return w, h


def _unfilter(ftype, line, prev, bpp):
    n = len(line)
    if ftype == 0:
        return bytearray(line)
    if ftype == 2:
        return bytearray((a + b) & 255 for a, b in zip(line, prev))
    cur = bytearray(n)
    if ftype == 1:  # Sub
        for i in range(n):
            left = cur[i - bpp] if i >= bpp else 0
            cur[i] = (line[i] + left) & 255
    elif ftype == 3:  # Average
        for i in range(n):
            left = cur[i - bpp] if i >= bpp else 0
            cur[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
    elif ftype == 4:  # Paeth
        for i in range(n):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            cur[i] = (line[i] + pred) & 255
    else:
        raise ValueError(f"unknown PNG filter type {ftype}")
    return cur


def read_png(path):
    """Return (width, height, samples per pixel, raw 8-bit samples)."""
    with open(path, "rb") as f:
        data = f.read()
    w, h, depth, ctype, _, _, interlace = _header(data, path)
    if depth != 8 or interlace != 0 or ctype not in CHANNELS:
        raise ValueError(f"{path}: unsupported PNG (depth {depth}, colour type {ctype}, interlace {interlace})")
    bpp = CHANNELS[ctype]
    stride = w * bpp
    raw = zlib.decompress(b"".join(body for kind, body in _chunks(data) if kind == b"IDAT"))
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ftype = raw[pos]
        line = raw[pos + 1:pos + 1 + stride]
        pos += 1 + stride
        cur = _unfilter(ftype, line, prev, bpp)
        out[y * stride:(y + 1) * stride] = cur
        prev = cur
    return w, h, bpp, out


def _mask(w, h, rects):
    m = bytearray(w * h)
    for x, y, rw, rh in rects:
        for yy in range(max(0, y), min(h, y + rh)):
            a = yy * w + max(0, x)
            b = yy * w + min(w, x + rw)
            if b > a:
                m[a:b] = b"\x01" * (b - a)
    return m


def _regions(col_min, col_max):
    regions = []  # [x0, y0, x1, y1]
    for x in range(len(col_max)):
        if col_max[x] < 0:
            continue
        if regions and x - regions[-1][2] <= CLUSTER_GAP:
            r = regions[-1]
            r[2] = x
            r[1] = min(r[1], col_min[x])
            r[3] = max(r[3], col_max[x])
        else:
            regions.append([x, col_min[x], x, col_max[x]])
    return regions


def _write_png(path, w, h, rgb):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(kind, body):
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def compare(ref_path, act_path, rects, diff_path):
    """Return (passed, message). Writes diff_path only when the comparison fails."""
    rw, rh, rbpp, ref = read_png(ref_path)
    aw, ah, abpp, act = read_png(act_path)
    if (rw, rh) != (aw, ah) or rbpp != abpp:
        return False, f"captured {aw}x{ah} ({abpp} samples), reference is {rw}x{rh} ({rbpp} samples)"
    n = rw * rh
    mask = _mask(rw, rh, rects)
    chans = min(3, rbpp)  # alpha is not compared
    differ = bytearray(n)
    total = bad = 0
    col_min = [rh] * rw
    col_max = [-1] * rw
    for p in range(n):
        if mask[p]:
            continue
        total += 1
        base = p * rbpp
        for c in range(chans):
            d = ref[base + c] - act[base + c]
            if d > TOLERANCE or d < -TOLERANCE:
                differ[p] = 1
                bad += 1
                x, y = p % rw, p // rw
                if y < col_min[x]:
                    col_min[x] = y
                if y > col_max[x]:
                    col_max[x] = y
                break
    frac = bad / total if total else 0.0
    passed = frac <= MAX_FRACTION
    summary = f"{bad}/{total} unmasked px differ ({100 * frac:.3f} %, limit {100 * MAX_FRACTION:.1f} %)"
    if passed:
        return True, summary
    rgb = bytearray(n * 3)
    for p in range(n):
        if differ[p]:
            rgb[3 * p:3 * p + 3] = b"\xff\xff\xff"
        elif mask[p]:
            rgb[3 * p:3 * p + 3] = b"\x40\x40\x40"
    _write_png(diff_path, rw, rh, rgb)
    boxes = ", ".join(f"({x0},{y0})-({x1},{y1})" for x0, y0, x1, y1 in _regions(col_min, col_max))
    return False, f"{summary}; regions: {boxes or 'none'}"


def main(argv):
    if len(argv) == 4 and argv[0] == "--size":
        path, w, h = argv[1], int(argv[2]), int(argv[3])
        got = png_size(path)
        if got != (w, h):
            print(f"{path}: captured {got[0]}x{got[1]}, expected {w}x{h}", file=sys.stderr)
            return 1
        return 0
    if len(argv) >= 4 and argv[0] == "--check":
        ref_dir, out_dir, states = argv[1], argv[2], argv[3:]
        failing = []
        for state in states:
            ref = os.path.join(ref_dir, state + ".png")
            act = os.path.join(out_dir, state + ".png")
            diff = os.path.join(out_dir, state + ".diff.png")
            if not os.path.exists(ref):
                print(f"FAIL {state}: no reference {ref} (run tools/golden/run.sh --update)")
                failing.append(state)
                continue
            rects = MASKS.get("*", []) + MASKS.get(state, [])
            passed, msg = compare(ref, act, rects, diff)
            print(f"{'PASS' if passed else 'FAIL'} {state}: {msg}")
            if not passed:
                failing.append(state)
        if failing:
            print(f"golden: failing state(s): {', '.join(failing)} (diff images in {out_dir})")
            return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
