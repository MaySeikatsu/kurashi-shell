#!/usr/bin/env bash
# The material texture (K59, docs/ux/texture.md), headless, against the real kurashid: the committed relief.frag.qsb is
# the build of its source; the relief on the screen is kurashi_texture::shade, checked pixel by pixel (the tile and the
# daemon's own tokens give the colour every plain pixel must have); the sheet is continuous across the bar and the island
# card; text stays crisp unless asked, and shades when asked; the everything overlay lets clicks through and no shell
# surface shades twice under it; the light moves the relief (four static angles, the pointer, daytime); no texture, no
# relief. K61 (wave 32): the relief fills the open island's whole shape (centre, corners, the neck's fillets: I168); the
# formula with depth 2, relief shadows, lit 0.6, the spotlight at rest and a warm light is shade_at; the spotlight's beam
# follows the pointer and glides back; a sidebar held mid-slide carries its material (`carried`) or not (`fixed`), and
# at rest both are the continuous sheet. Shots go to frontend/shots/texture/shell/, frontend/shots/texture/w32/ and
# frontend/shots/look/kami{,-dark}/ (evidence to look at); the pixel checks decide the exit code.
#   nix develop -c frontend/test-texture.sh
#   Machine B: export KURASHI_RENDER_NODE=/dev/dri/renderD129 first (the sandbox's gles2 renderer).
# The tile is two files (contract rows 280-281): the opaque RGB normal map (`texture.map`) and, when the material prints
# ink, a white RGBA map with the coverage in alpha (`texture.ink_map`): Qt Quick premultiplies textures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/texture/shell
W32=$ROOT/frontend/shots/texture/w32
TMP=${KEEP_TMP:-$(mktemp -d)}; mkdir -p "$TMP"
PIDS=()
trap '[ ${#PIDS[@]} -eq 0 ] || stop_session; [ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
FAILS=0
fail() { echo "test-texture: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
say() { echo "test-texture: $*"; }
TEX=(python3 "$TMP/tex.py")

# ---- the shader is its source's build (the committed .qsb is what the frontend loads) ----
qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$TMP/relief.frag.qsb" "$ROOT/frontend/shaders/relief.frag" \
  || fail "relief.frag does not compile with qsb"
cmp -s "$TMP/relief.frag.qsb" "$ROOT/frontend/shaders/relief.frag.qsb" \
  || fail "relief.frag.qsb is not the build of relief.frag (run: just shaders)"

# ---- the checker (stdlib only): PNG in and out, kurashi_texture::shade, Tile::sample ----
cat > "$TMP/tex.py" <<'PY'
import json, math, struct, sys, zlib


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        n, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    w, h, depth, ctype, _, _, il = ihdr
    assert depth == 8 and il == 0, "8-bit non-interlaced PNG only"
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, bytes(out)


def px(img, x, y):
    w, h, ch, buf = img
    if not (0 <= x < w and 0 <= y < h):
        return (0, 0, 0, 0)
    i = (y * w + x) * ch
    if ch == 4:
        return tuple(buf[i:i + 4])
    if ch == 3:
        return tuple(buf[i:i + 3]) + (255,)
    if ch == 2:
        return (buf[i], buf[i], buf[i], buf[i + 1])
    return (buf[i], buf[i], buf[i], 255)


def write_rgb_png(path, img):
    w, h = img[0], img[1]
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows += bytes(px(img, x, y)[:3])

    def chunk(kind, body):
        c = kind + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def write_rgba_png(path, w, h, pixels):
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows += bytes(pixels[y * w + x])

    def chunk(kind, body):
        c = kind + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def rgb_of(hexstr):
    s = hexstr.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def normalize(v):
    l = max(math.sqrt(dot(v, v)), 1e-6)
    return [v[0] / l, v[1] / l, v[2] / l]


def params(tokens_path, ink_on, out=(2560, 1440)):
    t = json.load(open(tokens_path))
    tok = t.get("data", t).get("tokens", {})
    ink = [c / 255.0 for c in rgb_of(tok["texture.ink"])]
    lc = [c / 255.0 for c in rgb_of(tok["light.color"])]
    p = dict(size=int(tok["texture.tile_px"]), logical=float(tok["texture.tile_logical"]),
             scale=float(tok["texture.scale"]), amp=float(tok["texture.amp"]),
             gloss=float(tok["texture.gloss"]), shin=float(tok["texture.shininess"]),
             ink=ink, ink_alpha=float(tok["texture.ink_alpha"]) if ink_on else 0.0,
             L=[float(v) for v in tok["light.dir"]], Lc=lc, out=out,
             # K61: depth, the light half's weight, relief shadows (and their height map), the spotlight's pin and beam.
             depth=float(tok.get("texture.depth", 1)), lit=float(tok.get("texture.lit", 1)),
             shadow=float(tok.get("texture.shadow", 0)), relief_px=float(tok.get("texture.relief_px", 0)),
             hmap=None, lamp=None, beam=None)
    if p["shadow"] > 0 and tok.get("texture.height_map"):
        p["hmap"] = read_png(tok["texture.height_map"])
    pin = tok.get("light.pin")
    if tok.get("light.mode") == "spotlight" and pin:
        hz = max(float(tok["light.height_px"]), 1.0)
        p["lamp"] = [pin[0] * out[0], pin[1] * out[1], hz]
        a = math.radians(min(max(float(tok.get("light.beam", 35)), 1.0), 89.0))
        # At rest the beam is aimed at the output's middle (the pointer off the shell).
        p["beam"] = [out[0] / 2, out[1] / 2, math.cos(a), math.cos(a / 2)]
    return p


def bilinear(img, size, k, sx, sy):
    # Tile::sample / sample_height: bilinear over the wrapped tile at sheet position (sx, sy), logical px.
    fx, fy = sx * k - 0.5, sy * k - 0.5
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0

    def texel(ix, iy):
        return px(img, ix % size, iy % size)
    a, b = texel(x0, y0), texel(x0 + 1, y0)
    c, d = texel(x0, y0 + 1), texel(x0 + 1, y0 + 1)
    return [((a[i] * (1 - tx) + b[i] * tx) * (1 - ty) + (c[i] * (1 - tx) + d[i] * tx) * ty) / 255.0
            for i in range(4)]


def sample(tile, p, x, y):
    # At the sheet position of the pixel centre (output coordinates).
    return bilinear(tile, p["size"], p["size"] / (p["logical"] * max(p["scale"], 0.01)), x + 0.5, y + 0.5)


def shade(t, p, q=None):
    # kurashi_texture::shade_at, line for line: light_at, beam_at, shadow_at, shade_with (q: the pixel's position).
    L = p["L"]
    k = 1.0
    sh = 0.0
    if p["lamp"] is not None and q is not None:
        lx, ly, hz = p["lamp"]
        L = normalize([lx - q[0], ly - q[1], hz])
        if p["beam"] is not None:
            ax, ay, co, ci = p["beam"]
            axis = normalize([ax - lx, ay - ly, -hz])
            ray = normalize([q[0] - lx, q[1] - ly, -hz])
            c = dot(ray, axis)
            u = min(max((c - co) / max(ci - co, 1e-6), 0.0), 1.0)
            k = 0.3 + 0.7 * u * u * (3 - 2 * u)
    lxy = math.sqrt(L[0] * L[0] + L[1] * L[1])
    if p["shadow"] > 0 and p["relief_px"] > 0 and lxy >= 1e-3 and p["hmap"] is not None and q is not None:
        rp = p["relief_px"]
        dx, dy = L[0] / lxy, L[1] / lxy
        rise = L[2] / lxy
        ln = min(rp / max(rise, 0.05), 24.0)
        hk = p["hmap"][0] / (p["logical"] * max(p["scale"], 0.01))
        h0 = bilinear(p["hmap"], p["hmap"][0], hk, q[0], q[1])[0] * rp
        occ = 0.0
        for i in range(1, 9):
            r = ln * i / 8
            hi = bilinear(p["hmap"], p["hmap"][0], hk, q[0] + dx * r, q[1] + dy * r)[0] * rp
            occ = max(occ, hi - h0 - r * rise)
        sh = p["shadow"] * min(max(occ / max(0.25 * rp, 0.15), 0.0), 1.0)
    nx, ny = 2 * t[0] - 1, 2 * t[1] - 1
    nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
    n = normalize([p["depth"] * nx, p["depth"] * ny, nz])
    cav = 2 * t[2] - 1
    diff = dot(n, L) - L[2]
    h = normalize([L[0], L[1], L[2] + 1])
    spec = p["gloss"] * (max(dot(n, h), 0) ** p["shin"] - max(h[2], 0) ** p["shin"])
    amp = p["amp"]
    v = k * amp * (2 * diff + 0.5 * cav + spec - 2 * sh)
    if v > 0:
        v *= p["lit"]
    v = min(max(v, -amp), amp)
    o = [0.0, 0.0, 0.0, -v] if v < 0 else [p["Lc"][0] * v, p["Lc"][1] * v, p["Lc"][2] * v, v]
    a = t[3] * p["ink_alpha"]
    ink = [p["ink"][0] * a, p["ink"][1] * a, p["ink"][2] * a, a]
    return [o[i] + ink[i] * (1 - o[3]) for i in range(4)]


def expected(tile, p, bg, x, y):
    o = shade(sample(tile, p, x, y), p, (x + 0.5, y + 0.5))
    return [o[i] * 255 + bg[i] * (1 - o[3]) for i in range(3)]


WALL = (0x8f, 0xb8, 0xc8)    # the sandbox's wallpaper colour (session: swaymsg bg)


def plain(img, x, y):
    # A pixel whose 3x3 neighbourhood is one colour: fill, not an edge or a glyph.
    c = px(img, x, y)[:3]
    return all(px(img, x + dx, y + dy)[:3] == c for dx in (-1, 0, 1) for dy in (-1, 0, 1))


def interior(img, x, y, colour):
    return all(px(img, x + dx, y + dy)[:3] == colour for dx in (-1, 0, 1) for dy in (-1, 0, 1))


def main():
    cmd = sys.argv[1]
    if cmd == "join":                      # join RELIEF INK|- DST: the tile in memory (RGBA, ink in A), rows 280-281
        rel = read_png(sys.argv[2])
        ink = read_png(sys.argv[3]) if sys.argv[3] != "-" else None
        w, h = rel[0], rel[1]
        write_rgba_png(sys.argv[4], w, h, [px(rel, x, y)[:3] + ((px(ink, x, y)[3],) if ink else (0,))
                                           for y in range(h) for x in range(w)])
    elif cmd == "pick":                    # pick NOTEX X0 Y0 X1 Y1 N: plain fill points of a box
        img = read_png(sys.argv[2])
        x0, y0, x1, y1, n = map(int, sys.argv[3:8])
        pts = [(x, y) for y in range(y0, y1 + 1, 2) for x in range(x0, x1 + 1, 2) if plain(img, x, y)]
        step = max(1, len(pts) // n)
        for x, y in pts[::step][:n]:
            print(x, y)
    elif cmd == "check":                   # check NORMAL TOKENS SHOT NOTEX POINTS: the formula on the plain points
        tile = read_png(sys.argv[2])
        p = params(sys.argv[3], ink_on=True)
        shot = read_png(sys.argv[4])
        notex = read_png(sys.argv[5])
        worst, n = 0.0, 0
        for line in open(sys.argv[6]):
            x, y = map(int, line.split())
            bg = px(notex, x, y)[:3]
            e = expected(tile, p, bg, x, y)
            got = px(shot, x, y)[:3]
            worst = max(worst, max(abs(e[i] - got[i]) for i in range(3)))
            n += 1
        print("checked", n, "plain pixels, worst error", round(worst, 2), "of 255")
        sys.exit(0 if n >= 10 and worst <= 3.0 else 1)
    elif cmd == "glyphs":                  # glyphs NOTEX X0 Y0 X1 Y1 N: full-coverage glyph pixels (the text colour)
        img = read_png(sys.argv[2])
        x0, y0, x1, y1, n = map(int, sys.argv[3:8])
        counts = {}
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                c = px(img, x, y)[:3]
                counts[c] = counts.get(c, 0) + 1
        ground = max(counts, key=counts.get)

        def lum(c):
            return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
        frequent = [c for c in counts if c != ground and counts[c] >= 8]
        ink = max(frequent, key=lambda c: abs(lum(c) - lum(ground)))
        pts = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1) if px(img, x, y)[:3] == ink]
        step = max(1, len(pts) // n)
        for x, y in pts[::step][:n]:
            print(x, y)
    elif cmd == "meanerr":                 # meanerr NORMAL TOKENS NOTEX SHOT X0 Y0 X1 Y1: the formula over changed pixels
        tile = read_png(sys.argv[2])
        p = params(sys.argv[3], ink_on=True)
        notex = read_png(sys.argv[4])
        shot = read_png(sys.argv[5])
        x0, y0, x1, y1 = map(int, sys.argv[6:10])
        total, n = 0.0, 0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                bg = px(notex, x, y)[:3]
                got = px(shot, x, y)[:3]
                if max(abs(got[i] - bg[i]) for i in range(3)) < 4:
                    continue
                e = expected(tile, p, bg, x, y)
                total += sum(abs(e[i] - got[i]) for i in range(3)) / 3
                n += 1
        mean = total / n if n else 99.0
        print("relief-changed pixels", n, "mean error", round(mean, 2), "of 255")
        sys.exit(0 if n >= 1000 and mean <= 2.0 else 1)
    elif cmd == "glyphcheck":              # glyphcheck NORMAL TOKENS NOTEX ON POINTS: the formula over the glyph colour
        tile = read_png(sys.argv[2])
        p = params(sys.argv[3], ink_on=True)
        notex = read_png(sys.argv[4])
        on = read_png(sys.argv[5])
        total, moved, n = 0.0, 0.0, 0
        for line in open(sys.argv[6]):
            x, y = map(int, line.split())
            glyph = px(notex, x, y)[:3]
            e = expected(tile, p, glyph, x, y)
            got = px(on, x, y)[:3]
            total += sum(abs(e[i] - got[i]) for i in range(3)) / 3
            moved += sum(abs(e[i] - glyph[i]) for i in range(3)) / 3
            n += 1
        mean = total / n if n else 99.0
        shift = moved / n if n else 0.0
        print("glyph pixels", n, "mean error", round(mean, 2), "of 255; the formula moves them by", round(shift, 2))
        # The relief lies over the glyphs: they move (by the formula, at least 1 level) and match it well under that move.
        sys.exit(0 if n >= 4 and shift >= 1.0 and mean <= min(2.0, shift / 3) else 1)
    elif cmd == "same":                    # same A B POINTS: points whose colour is the same in A and B
        a = read_png(sys.argv[2])
        b = read_png(sys.argv[3])
        same = diff = 0
        for line in open(sys.argv[4]):
            x, y = map(int, line.split())
            if px(a, x, y)[:3] == px(b, x, y)[:3]:
                same += 1
            else:
                diff += 1
        print("same", same, "differ", diff)
    elif cmd == "diff":                    # diff A B X0 Y0 X1 Y1: mean colour difference of a box
        a = read_png(sys.argv[2])
        b = read_png(sys.argv[3])
        x0, y0, x1, y1 = map(int, sys.argv[4:8])
        tot = cnt = 0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                pa, pb = px(a, x, y)[:3], px(b, x, y)[:3]
                tot += sum(abs(pa[i] - pb[i]) for i in range(3))
                cnt += 3
        print(round(tot / max(cnt, 1), 3))
    elif cmd == "fgrgb":                   # fgrgb TOKENS: the text colour of the theme, as R,G,B
        t = json.load(open(sys.argv[2]))
        tok = t.get("data", t).get("tokens", {})
        print(",".join(str(c) for c in rgb_of(tok["color.on_surface"])))
    elif cmd == "panel":                   # panel UI: the open panel of runtime.ui ("" when none)
        line = open(sys.argv[2]).readline().strip()
        d = json.loads(line) if line else {}
        print((d.get("data") or {}).get("panel", ""))
    elif cmd == "count":                   # count LOG TEXT: lines of a log that carry TEXT
        print(sum(1 for line in open(sys.argv[2], errors="replace") if sys.argv[3] in line))
    elif cmd == "region":                  # region NORMAL TOKENS NOTEX SHOT NAME X0 Y0 X1 Y1: the relief is there, and right
        # Every plain pixel of the box (3x3 one colour in the reference) must carry the formula: the shot matches it, and
        # the formula moves the box (a box the relief misses, as the island's old disc did at the card's corners, keeps
        # the reference's colours and fails).
        tile = read_png(sys.argv[2])
        notex = read_png(sys.argv[4])
        shot = read_png(sys.argv[5])
        p = params(sys.argv[3], ink_on=True, out=(shot[0], shot[1]))
        name = sys.argv[6]
        x0, y0, x1, y1 = map(int, sys.argv[7:11])
        # A box too small for plain pixels (the neck's fillets, a few px) takes the pixels of the fill's own colour,
        # read at FX FY (the card's plain inside), instead.
        fill = px(notex, int(sys.argv[11]), int(sys.argv[12]))[:3] if len(sys.argv) > 12 else None
        err = moved = 0.0
        n = 0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                c = px(notex, x, y)[:3]
                if c == WALL or (fill is None and not plain(notex, x, y)) or (fill is not None and c != fill):
                    continue
                bg = px(notex, x, y)[:3]
                e = expected(tile, p, bg, x, y)
                got = px(shot, x, y)[:3]
                err += sum(abs(e[i] - got[i]) for i in range(3)) / 3
                moved += sum(abs(e[i] - bg[i]) for i in range(3)) / 3
                n += 1
        err, moved = (err / n, moved / n) if n else (99.0, 0.0)
        print(name, "plain pixels", n, "mean error", round(err, 2), "the formula moves them by", round(moved, 2))
        sys.exit(0 if n >= 3 and err <= min(1.5, 0.5 * moved) and moved >= 0.4 else 1)
    elif cmd == "island":                  # island NOTEX: the open island card's boxes (name x0 y0 x1 y1 per line)
        img = read_png(sys.argv[2])
        w, h = img[0], img[1]
        cx = w // 2
        # The bar's edge: the first wallpaper row far from the card; the card's sides on a row below the bar.
        edge = next(y for y in range(h) if px(img, 40, y)[:3] == WALL)
        row = edge + 120
        xl = next(x for x in range(cx, 0, -1) if px(img, x, row)[:3] == WALL) + 1
        xr = next(x for x in range(cx, w) if px(img, x, row)[:3] == WALL) - 1
        yb = next(y for y in range(edge + 10, h) if px(img, cx, y)[:3] == WALL) - 1
        print("centre", cx - 30, (edge + yb) // 2 - 30, cx + 30, (edge + yb) // 2 + 30)
        print("corner-bl", xl, yb - 14, xl + 14, yb)
        print("corner-br", xr - 14, yb - 14, xr, yb)
        print("fillet-l", xl - 8, edge, xl - 1, edge + 8, xl + 20, edge + 20)
        print("fillet-r", xr + 1, edge, xr + 8, edge + 8, xr - 20, edge + 20)
    elif cmd == "shifted":                 # shifted A B DX X0 Y0 X1 Y1: mean difference of A's box moved by DX against B's box
        a = read_png(sys.argv[2])
        b = read_png(sys.argv[3])
        dx = int(sys.argv[4])
        x0, y0, x1, y1 = map(int, sys.argv[5:9])
        tot = cnt = 0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                pa, pb = px(a, x + dx, y)[:3], px(b, x, y)[:3]
                tot += sum(abs(pa[i] - pb[i]) for i in range(3))
                cnt += 3
        print(round(tot / max(cnt, 1), 3))
    elif cmd == "tok":                     # tok TOKENS KEY: one token's value
        t = json.load(open(sys.argv[2]))
        print(json.dumps(t.get("data", t).get("tokens", {}).get(sys.argv[3])))
    elif cmd == "warm":                    # warm TOKENS: the light's colour is warm (red over blue)
        t = json.load(open(sys.argv[2]))
        c = rgb_of(t.get("data", t)["tokens"]["light.color"])
        print("light.color", c)
        sys.exit(0 if c[0] > c[2] + 20 else 1)
    elif cmd == "pixel":                   # pixel SHOT X Y: the colour of one pixel
        print(",".join(str(c) for c in px(read_png(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))[:3]))


main()
PY

# ---- a session: a fresh headless sandbox, the real kurashid with CONFIG, the fixture tile, the frontend ----
# session NAME TEXTURE(yes|no) CONFIG...: leaves the session up (stop_session ends it); sets W_DIR, QS_LOG, SB.
PIDS=()
SB=""
W_DIR=""
QS_LOG=""
session() {
  local name=$1 texture=$2
  shift 2
  SB=w32-rel-$name
  # The last session's network namespace must not reach the launcher of this one.
  unset LD_PRELOAD KURASHI_SANDBOX_NETNS_PID KURASHI_SANDBOX_NETNS_ID
  eval "$("$ROOT/tools/bench/sandbox.sh" start "$SB" 2>/dev/null)"
  local R=$XDG_RUNTIME_DIR
  W_DIR=$R/work
  mkdir -p "$W_DIR" "$R/kurashi"
  cp "$BIN/kurashid" "$BIN/kurashi" "$W_DIR/"
  export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data \
    XDG_CACHE_HOME=$R/xdg/cache KURASHI_DATA_DIR=$ROOT LC_ALL=C.UTF-8
  mkdir -p "$XDG_CONFIG_HOME/kurashi" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  printf '%s\n' "$@" > "$XDG_CONFIG_HOME/kurashi/config.toml"
  QS_LOG=$R/qs.log
  : > "$R/server.log"
  : > "$QS_LOG"
  env DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" PULSE_SERVER="unix:$R/no-pulse/native" \
    PULSE_RUNTIME_PATH="$R/no-pulse" "$W_DIR/kurashid" >> "$R/server.log" 2>&1 &
  PIDS+=("$!")
  for _ in $(seq 100); do
    [ -S "$KURASHI_SOCKET" ] && timeout 5 "$W_DIR/kurashi" ping >/dev/null 2>&1 && break
    sleep 0.1
  done
  timeout 5 "$W_DIR/kurashi" ping >/dev/null 2>&1 || { echo "test-texture: kurashid did not come up ($name)" >&2; exit 1; }
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  if [ "$texture" = yes ]; then
    local tile=""
    for _ in $(seq 150); do
      tile=$(ls "$XDG_CACHE_HOME"/kurashi/texture/*.png 2>/dev/null | grep -v -- '-ink\.png$' | head -1 || true)
      [ -n "$tile" ] && break
      sleep 0.2
    done
    [ -n "$tile" ] || { echo "test-texture: no tile was generated ($name)" >&2; exit 1; }
    sleep 0.5
  fi
  timeout 10 "$W_DIR/kurashi" sub theme --count 0 --json 2>/dev/null | head -1 > "$TMP/tokens-$name.json" || true
  if [ "$texture" = yes ]; then
    # The tile the theme names (a sandbox cache may hold older generators' files too).
    local map ink
    map=$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); t=t.get("data",t)["tokens"]; print(t["texture.map"])' "$TMP/tokens-$name.json")
    ink=$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); t=t.get("data",t)["tokens"]; print(t["texture.ink_map"] or "-")' "$TMP/tokens-$name.json")
    "${TEX[@]}" join "$map" "$ink" "$TMP/normal-$name.png"
  fi
  env -u KURASHI_SOCKET qs -p "$ROOT/frontend" >> "$QS_LOG" 2>&1 &
  PIDS+=("$!")
  for _ in $(seq 100); do grep -q 'hello.*frontend' "$R/server.log" && break; sleep 0.1; done
  sleep 3
}
stop_session() {
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${PIDS[@]}"; do wait "$p" 2>/dev/null || true; done
  PIDS=()
  "$ROOT/tools/bench/sandbox.sh" stop "$SB" >/dev/null 2>&1 || true
  unset LD_PRELOAD KURASHI_SANDBOX_NETNS_PID KURASHI_SANDBOX_NETNS_ID
}
shot() { sleep "${2:-1.2}"; grim "$OUT/$1.png"; }
ctl() { timeout 10 "$W_DIR/kurashi" "$@" >/dev/null 2>&1 || true; }

GRID='theme.texture.kind = "paper_grid"'
# The text tests need relief under every glyph: the grid's paper is flat between its rules.
TXT='theme.texture.kind = "paper"'

# ---- 1. the reference (no texture), then the sheet, checked on plain fill of the bar and of the island card ----
say "reference without texture"
session none no 'theme.texture.kind = "none"'
shot none-bar 0.5
ctl act island.expand
shot none-island 1.5
cp "$OUT/none-bar.png" "$TMP/notex-bar.png"
cp "$OUT/none-island.png" "$TMP/notex-island.png"
NONE_SHEETS=$("${TEX[@]}" count "$QS_LOG" "texture: tile sheet made")
[ "$NONE_SHEETS" = 0 ] || fail "none: $NONE_SHEETS tile sheet(s) made without a texture"
stop_session

say "sheet continuity (paper_grid, shell scope): the bar, then the island card"
session grid yes "$GRID" 'theme.texture.strength = 0.8'
shot grid-bar 0.5
ctl act island.expand
shot grid-island 1.5
"${TEX[@]}" pick "$TMP/notex-bar.png" 14 4 110 30 12 > "$TMP/bar-points.txt" || true
"${TEX[@]}" check "$TMP/normal-grid.png" "$TMP/tokens-grid.json" "$OUT/grid-bar.png" "$TMP/notex-bar.png" "$TMP/bar-points.txt" \
  || fail "bar: the relief is not the formula of the tile"
"${TEX[@]}" meanerr "$TMP/normal-grid.png" "$TMP/tokens-grid.json" "$TMP/notex-island.png" "$OUT/grid-island.png" 1100 40 1460 300 \
  || fail "island card: the relief does not match the formula of the tile over the card (the sheet is not continuous)"
# K61 (I168): the relief fills the island's whole shape — its centre, its corners and the neck's fillets, not a disc.
mkdir -p "$W32"
cp "$OUT/grid-island.png" "$W32/island-fixed.png"
"${TEX[@]}" island "$TMP/notex-island.png" > "$TMP/island-boxes.txt" || fail "island: the card's boxes were not found"
while read -r name x0 y0 x1 y1 fx fy; do
  # shellcheck disable=SC2086 # fx fy: absent for the boxes with plain pixels
  "${TEX[@]}" region "$TMP/normal-grid.png" "$TMP/tokens-grid.json" "$TMP/notex-island.png" "$OUT/grid-island.png" \
    "$name" "$x0" "$y0" "$x1" "$y1" $fx $fy || fail "island: the relief does not fill the shape at its $name"
done < "$TMP/island-boxes.txt"
# I172: the quick settings phone's screen is a material area too.
ctl act ui.close
sleep 1
ctl act quick.toggle
shot grid-phone 1.8
cp "$OUT/grid-phone.png" "$W32/phone-frame.png"
stop_session

# ---- 2. text: untextured by default, shaded when asked (the glyph pixels of the reference, same layout) ----
say "text off, then on (the session menu: a static card, not the island's morph)"
session none-menu no 'theme.texture.kind = "none"'
ctl act session.menu
shot none-menu 1.5
cp "$OUT/none-menu.png" "$TMP/notex-menu.png"
stop_session
"${TEX[@]}" glyphs "$TMP/notex-menu.png" 1090 40 1470 300 40 > "$TMP/glyphs.txt" || true
[ -s "$TMP/glyphs.txt" ] || fail "text: no glyph pixels in the reference"
session text-off yes "$TXT" 'theme.texture.text = false'
ctl act session.menu
shot text-off-menu 1.5
stop_session
"${TEX[@]}" same "$TMP/notex-menu.png" "$OUT/text-off-menu.png" "$TMP/glyphs.txt" | grep -q 'differ 0' \
  || fail "text: with texture.text off a glyph pixel differs from the untextured run"
session text-on yes "$TXT" 'theme.texture.text = true'
ctl act session.menu
shot text-on-menu 1.5
stop_session
"${TEX[@]}" glyphcheck "$TMP/normal-text-on.png" "$TMP/tokens-text-on.json" "$TMP/notex-menu.png" "$OUT/text-on-menu.png" \
  "$TMP/glyphs.txt" || fail "text: with texture.text on the glyphs do not carry the formula's shade (the relief does not lie over the text)"

# ---- 3. the everything scope: clicks pass through the overlay, and no shell surface shades twice under it ----
say "everything scope: click-through, and the bar shows the sheet once"
session everything yes "$GRID" 'theme.texture.scope = "everything"'
shot everything 1.5
"${TEX[@]}" check "$TMP/normal-everything.png" "$TMP/tokens-everything.json" "$OUT/everything.png" "$TMP/notex-bar.png" \
  "$TMP/bar-points.txt" || fail "everything: the bar does not show the sheet exactly once (the overlay's relief, no shell relief on top)"
timeout 10 python3 "$ROOT/tools/bench/wl_pointer.py" click 1280 15 left >/dev/null 2>&1 || true
sleep 1.5
timeout 10 "$W_DIR/kurashi" sub runtime.ui --count 0 --json 2>/dev/null | head -1 > "$TMP/ui.json" || true
[ "$("${TEX[@]}" panel "$TMP/ui.json")" = "island" ] \
  || fail "everything: a click on the bar did not reach it through the overlay"
stop_session

# ---- 4. the light: four static angles, the pointer at two places, daytime ----
say "light: static angles"
for ang in 0 90 180 270; do
  session "ang$ang" yes "$GRID" "theme.light.angle = $ang" 'theme.light.mode = "static"'
  shot "light-static-$ang" 0.8
  stop_session
done
D=$("${TEX[@]}" diff "$OUT/light-static-0.png" "$OUT/light-static-180.png" 0 0 2559 35)
awk -v d="$D" 'BEGIN { exit !(d > 0.05) }' || fail "light: a static light at 0 and at 180 degrees gives the same relief ($D)"
say "light: the pointer"
session pointer yes "$GRID" 'theme.light.mode = "pointer"'
# One virtual pointer for the whole step, and it stays where it is put: a pointer that leaves glides the light back.
PTR_FIFO=$TMP/pointer.fifo
rm -f "$PTR_FIFO"
mkfifo "$PTR_FIFO"
python3 "$ROOT/tools/bench/wl_pointer.py" --serve < "$PTR_FIFO" >/dev/null 2>&1 &
PTR_PID=$!
exec 3> "$PTR_FIFO"
echo "move 300 18" >&3
shot light-pointer-a 1.5
echo "move 2200 18" >&3
shot light-pointer-b 1.5
exec 3>&-
wait "$PTR_PID" 2>/dev/null || true
stop_session
D=$("${TEX[@]}" diff "$OUT/light-pointer-a.png" "$OUT/light-pointer-b.png" 0 0 2559 35)
awk -v d="$D" 'BEGIN { exit !(d > 0.05) }' || fail "light: the pointer's lamp does not move the relief ($D)"
say "light: daytime"
session daytime yes "$GRID" 'theme.light.mode = "daytime"'
shot light-daytime 0.8
stop_session

# ---- 4b. K61: depth, relief shadows, the light half on a dark ground, the spotlight and a warm light — shade_at exactly ----
# wait_height: the theme names its height map once generated (shading without shadows meanwhile); fresh tokens then.
wait_height() {
  local name=$1
  for _ in $(seq 100); do
    timeout 10 "$W_DIR/kurashi" sub theme --count 0 --json 2>/dev/null | head -1 > "$TMP/tokens-$name.json" || true
    [ "$("${TEX[@]}" tok "$TMP/tokens-$name.json" texture.height_map)" != '""' ] && break
    [ "$("${TEX[@]}" tok "$TMP/tokens-$name.json" texture.shadow)" = "0.0" ] && break
    sleep 0.2
  done
  sleep 1.5
}
K61=('theme.texture.depth = 2' 'theme.texture.shadows = "on"' 'theme.colors.scheme = "dark"' 'theme.light.mode = "spotlight"'
  'theme.light.color = "warm"')
say "K61 formula: depth 2, shadows, lit 0.6 (dark), the spotlight at rest, a warm light"
session none-dark no 'theme.texture.kind = "none"' 'theme.colors.scheme = "dark"'
shot none-dark-bar 0.5
cp "$OUT/none-dark-bar.png" "$TMP/notex-dark-bar.png"
stop_session
session k61 yes "$GRID" 'theme.texture.strength = 0.8' "${K61[@]}"
wait_height k61
[ "$("${TEX[@]}" tok "$TMP/tokens-k61.json" texture.lit)" = "0.6" ] || fail "k61: texture.lit is not 0.6 on the dark ground"
"${TEX[@]}" warm "$TMP/tokens-k61.json" || fail "k61: light.color warm is not warm"
ctl act island.expand
shot k61-rest 1.5
cp "$OUT/k61-rest.png" "$W32/spotlight-rest.png"
# The bar beside the open island (its card covers the middle of the strip), short of the clock (a minute may pass).
"${TEX[@]}" pick "$TMP/notex-dark-bar.png" 14 4 1000 30 30 > "$TMP/dark-points.txt" || true
"${TEX[@]}" pick "$TMP/notex-dark-bar.png" 1560 4 2200 30 30 >> "$TMP/dark-points.txt" || true
"${TEX[@]}" check "$TMP/normal-k61.png" "$TMP/tokens-k61.json" "$OUT/k61-rest.png" "$TMP/notex-dark-bar.png" \
  "$TMP/dark-points.txt" || fail "k61: the relief is not shade_at (depth, shadows, lit, spotlight, light colour)"
"${TEX[@]}" meanerr "$TMP/normal-k61.png" "$TMP/tokens-k61.json" "$TMP/notex-dark-bar.png" "$OUT/k61-rest.png" 0 0 1000 33 \
  || fail "k61: the bar's relief does not match shade_at"
say "the spotlight: the beam follows the pointer and glides back to the middle"
PTR_FIFO=$TMP/pointer-spot.fifo
rm -f "$PTR_FIFO"
mkfifo "$PTR_FIFO"
python3 "$ROOT/tools/bench/wl_pointer.py" --serve < "$PTR_FIFO" >/dev/null 2>&1 &
PTR_PID=$!
exec 3> "$PTR_FIFO"
echo "move 300 18" >&3
shot k61-spot-a 1.5
cp "$OUT/k61-spot-a.png" "$W32/spotlight-a.png"
echo "move 1300 300" >&3
shot k61-spot-b 1.5
cp "$OUT/k61-spot-b.png" "$W32/spotlight-b.png"
echo "move 1280 900" >&3
shot k61-spot-back 1.8
exec 3>&-
wait "$PTR_PID" 2>/dev/null || true
stop_session
D=$("${TEX[@]}" diff "$OUT/k61-rest.png" "$OUT/k61-spot-a.png" 0 0 2559 33)
awk -v d="$D" 'BEGIN { exit !(d > 0.05) }' || fail "spotlight: the beam does not follow the pointer ($D)"
D=$("${TEX[@]}" diff "$OUT/k61-spot-a.png" "$OUT/k61-spot-b.png" 0 0 2559 33)
awk -v d="$D" 'BEGIN { exit !(d > 0.05) }' || fail "spotlight: two pointer places light the bar alike ($D)"
D=$("${TEX[@]}" diff "$OUT/k61-rest.png" "$OUT/k61-spot-back.png" 0 0 1000 33)
awk -v d="$D" 'BEGIN { exit !(d < 0.02) }' || fail "spotlight: the beam did not glide back to the middle ($D)"

# ---- 4c. K61: the carried sheet — a sidebar held mid-slide carries its material; at rest it is the continuous sheet ----
# The right sidebar (420 px, flush) held at half its slide is 210 px out of place: carried, its material is the one it
# has at rest, moved by 210 px; fixed, the material stays where the output's sheet is. At rest both are identical.
say "carried and fixed sheets: a sidebar mid-slide and at rest"
for mode in carried fixed; do
  for hold in rest mid; do
    if [ "$hold" = mid ]; then export KURASHI_SIDEBAR_HOLD=0.5; else unset KURASHI_SIDEBAR_HOLD; fi
    session "sheet-$mode-$hold" yes "$GRID" 'theme.texture.strength = 0.8' "theme.texture.sheet = \"$mode\""
    ctl act sidebar.toggle '{"side":"right"}'
    shot "sheet-$mode-$hold" 1.8
    stop_session
  done
done
unset KURASHI_SIDEBAR_HOLD
cp "$OUT/sheet-carried-mid.png" "$W32/carried-mid-slide.png"
cp "$OUT/sheet-fixed-mid.png" "$W32/fixed-mid-slide.png"
# A box of the column's empty middle (the notifications' room), at rest and 210 px further right mid-slide.
D=$("${TEX[@]}" shifted "$OUT/sheet-carried-mid.png" "$OUT/sheet-carried-rest.png" 210 2160 700 2340 1000)
awk -v d="$D" 'BEGIN { exit !(d < 0.05) }' || fail "carried: the sidebar mid-slide does not carry its material ($D)"
D=$("${TEX[@]}" shifted "$OUT/sheet-fixed-mid.png" "$OUT/sheet-fixed-rest.png" 210 2160 700 2340 1000)
awk -v d="$D" 'BEGIN { exit !(d > 0.3) }' || fail "fixed: the sidebar mid-slide carried its material ($D)"
D=$("${TEX[@]}" diff "$OUT/sheet-carried-rest.png" "$OUT/sheet-fixed-rest.png" 2140 40 2559 1400)
awk -v d="$D" 'BEGIN { exit !(d < 0.02) }' || fail "carried at rest is not the continuous sheet ($D)"

# ---- 4d. the W32 look shots: kami with shadows, light and dark; paint with the spotlight ----
say "w32 shots"
for scheme in light dark; do
  session "kami-sh-$scheme" yes 'theme.style = "kami"' "theme.colors.scheme = \"$scheme\"" 'theme.texture.shadows = "on"'
  wait_height "kami-sh-$scheme"
  ctl act island.expand
  shot "kami-shadows-$scheme" 1.5
  cp "$OUT/kami-shadows-$scheme.png" "$W32/kami-shadows-$scheme.png"
  stop_session
done
session paint-spot yes 'theme.texture.kind = "paint"' 'theme.texture.strength = 1.2' 'theme.texture.depth = 1.8' \
  'theme.light.mode = "spotlight"'
wait_height paint-spot
ctl act island.expand
shot paint-spotlight 1.5
cp "$OUT/paint-spotlight.png" "$W32/paint-spotlight.png"
stop_session

# ---- 5. the kami look, light and dark (the frontend's own look, with the fixture tile) ----
say "kami look"
mkdir -p "$ROOT/frontend/shots/look/kami" "$ROOT/frontend/shots/look/kami-dark"
session kami yes 'theme.style = "kami"'
ctl act island.expand
shot kami-bar 0.5
cp "$OUT/kami-bar.png" "$ROOT/frontend/shots/look/kami/bar.png"
shot kami-island 1.5
cp "$OUT/kami-island.png" "$ROOT/frontend/shots/look/kami/island.png"
stop_session
session kami-dark yes 'theme.style = "kami"' 'theme.colors.scheme = "dark"'
ctl act island.expand
shot kami-dark-bar 0.5
cp "$OUT/kami-dark-bar.png" "$ROOT/frontend/shots/look/kami-dark/bar.png"
shot kami-dark-island 1.5
cp "$OUT/kami-dark-island.png" "$ROOT/frontend/shots/look/kami-dark/island.png"
stop_session

if [ "$FAILS" -gt 0 ]; then
  echo "test-texture: $FAILS check(s) failed" >&2
  exit 1
fi
echo "test-texture: ok ($OUT)"
