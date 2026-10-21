#!/usr/bin/env bash
# The material texture (K59, docs/ux/texture.md), headless, against the real kurashid: the committed relief.frag.qsb is
# the build of its source; the relief on the screen is kurashi_texture::shade, checked pixel by pixel (the tile and the
# daemon's own tokens give the colour every plain pixel must have); the sheet is continuous across the bar and the island
# card; text stays crisp unless asked, and shades when asked; the everything overlay lets clicks through and no shell
# surface shades twice under it; the light moves the relief (four static angles, the pointer, daytime); no texture, no
# relief. Shots go to frontend/shots/texture/shell/ and frontend/shots/look/kami{,-dark}/ (evidence to look at); the pixel
# checks decide the exit code.
#   nix develop -c frontend/test-texture.sh
#   Machine B: export KURASHI_RENDER_NODE=/dev/dri/renderD129 first (the sandbox's gles2 renderer).
# Fixture (contract rows 280-281): the daemon's tile is an RGBA PNG, and Qt Quick premultiplies textures, which drops the
# RGB of alpha-0 texels, the normal map. Until the daemon publishes the opaque normal map and `texture.ink_map`, each
# session with a texture copies the tile's RGB, alpha 255, into the sandbox's cache before the frontend starts. No ink
# is drawn in these shots.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/texture/shell
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
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


def rgb_of(hexstr):
    s = hexstr.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def normalize(v):
    l = max(math.sqrt(dot(v, v)), 1e-6)
    return [v[0] / l, v[1] / l, v[2] / l]


def params(tokens_path, ink_on):
    t = json.load(open(tokens_path))
    tok = t.get("data", t).get("tokens", {})
    ink = [c / 255.0 for c in rgb_of(tok["texture.ink"])]
    lc = [c / 255.0 for c in rgb_of(tok["light.color"])]
    return dict(size=int(tok["texture.tile_px"]), logical=float(tok["texture.tile_logical"]),
                scale=float(tok["texture.scale"]), amp=float(tok["texture.amp"]),
                gloss=float(tok["texture.gloss"]), shin=float(tok["texture.shininess"]),
                ink=ink, ink_alpha=float(tok["texture.ink_alpha"]) if ink_on else 0.0,
                L=[float(v) for v in tok["light.dir"]], Lc=lc)


def sample(tile, p, x, y):
    # Tile::sample: bilinear over the wrapped tile, at the sheet position of the pixel centre (output coordinates).
    size = p["size"]
    k = size / (p["logical"] * max(p["scale"], 0.01))
    fx, fy = (x + 0.5) * k - 0.5, (y + 0.5) * k - 0.5
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0

    def texel(ix, iy):
        return px(tile, ix % size, iy % size)
    a, b = texel(x0, y0), texel(x0 + 1, y0)
    c, d = texel(x0, y0 + 1), texel(x0 + 1, y0 + 1)
    return [((a[i] * (1 - tx) + b[i] * tx) * (1 - ty) + (c[i] * (1 - tx) + d[i] * tx) * ty) / 255.0
            for i in range(4)]


def shade(t, p):
    # kurashi_texture::shade, line for line.
    nx, ny = 2 * t[0] - 1, 2 * t[1] - 1
    n = normalize([nx, ny, math.sqrt(max(0.0, 1 - nx * nx - ny * ny))])
    cav = 2 * t[2] - 1
    L = p["L"]
    diff = dot(n, L) - L[2]
    h = normalize([L[0], L[1], L[2] + 1])
    spec = p["gloss"] * (max(dot(n, h), 0) ** p["shin"] - max(h[2], 0) ** p["shin"])
    amp = p["amp"]
    v = min(max(amp * (2 * diff + 0.5 * cav + spec), -amp), amp)
    sh = [0.0, 0.0, 0.0, -v] if v < 0 else [p["Lc"][0] * v, p["Lc"][1] * v, p["Lc"][2] * v, v]
    a = t[3] * p["ink_alpha"]
    ink = [p["ink"][0] * a, p["ink"][1] * a, p["ink"][2] * a, a]
    return [sh[i] + ink[i] * (1 - sh[3]) for i in range(4)]


def expected(tile, p, bg, x, y):
    o = shade(sample(tile, p, x, y), p)
    return [o[i] * 255 + bg[i] * (1 - o[3]) for i in range(3)]


def plain(img, x, y):
    # A pixel whose 3x3 neighbourhood is one colour: fill, not an edge or a glyph.
    c = px(img, x, y)[:3]
    return all(px(img, x + dx, y + dy)[:3] == c for dx in (-1, 0, 1) for dy in (-1, 0, 1))


def interior(img, x, y, colour):
    return all(px(img, x + dx, y + dy)[:3] == colour for dx in (-1, 0, 1) for dy in (-1, 0, 1))


def main():
    cmd = sys.argv[1]
    if cmd == "rgb":                       # rgb SRC DST: the tile as an opaque RGB normal map
        write_rgb_png(sys.argv[3], read_png(sys.argv[2]))
    elif cmd == "pick":                    # pick NOTEX X0 Y0 X1 Y1 N: plain fill points of a box
        img = read_png(sys.argv[2])
        x0, y0, x1, y1, n = map(int, sys.argv[3:8])
        pts = [(x, y) for y in range(y0, y1 + 1, 2) for x in range(x0, x1 + 1, 2) if plain(img, x, y)]
        step = max(1, len(pts) // n)
        for x, y in pts[::step][:n]:
            print(x, y)
    elif cmd == "check":                   # check NORMAL TOKENS SHOT NOTEX POINTS: the formula on the plain points
        tile = read_png(sys.argv[2])
        p = params(sys.argv[3], ink_on=False)
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
        p = params(sys.argv[3], ink_on=False)
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
        p = params(sys.argv[3], ink_on=False)
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
        sys.exit(0 if n >= 4 and mean <= 2.0 and shift >= 2.0 else 1)
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
  SB=w31-tex-$name
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
      tile=$(ls "$XDG_CACHE_HOME"/kurashi/texture/*.png 2>/dev/null | head -1 || true)
      [ -n "$tile" ] && break
      sleep 0.2
    done
    [ -n "$tile" ] || { echo "test-texture: no tile was generated ($name)" >&2; exit 1; }
    sleep 0.5
    "${TEX[@]}" rgb "$tile" "$TMP/normal-$name.png"
    cp "$TMP/normal-$name.png" "$tile"
  fi
  timeout 10 "$W_DIR/kurashi" sub theme --count 0 --json 2>/dev/null | head -1 > "$TMP/tokens-$name.json" || true
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
