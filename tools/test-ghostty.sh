#!/usr/bin/env bash
# W37 (I174): the shell's material in ghostty — the generated custom shader (crates/kurashi-theme/src/ghostty_shader.rs,
# docs/ux/terminal-texture.md). Never the user's session or config: a headless sway sandbox (tools/bench/sandbox.sh,
# name w37-ghostty-shots), ghostty and glslang from nixpkgs, and every XDG dir and HOME in a temp dir.
#
#   1. cargo test -p kurashi-theme: every kind's shader compiles with glslang (ghostty's Shadertoy prefix), the golden.
#   2. cargo test -p kurashid theme_export: the shader is written while the material is on, a pass-through after; then the
#      ghostty export of real themes (kami = paper_dots, stone with cracks; light and dark; each with its plain twin).
#   3. An orientation probe: ghostty's fragCoord counts rows from the bottom (the shader flips y for the light).
#   4. ghostty in the sandbox with `ls --color` and htop-like text, per case textured and plain; shots side by side and a
#      zoomed crop in tools/shots/ghostty/. Checks: the relief is there on the background; every pixel that is not the
#      background is unchanged (text, cursor, reverse-video rows); text contrast against what is round it stays within
#      1 % of the plain theme; ghostty logged no shader error.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "${IN_NIX_SHELL:-}" ]; then exec timeout 3000 nix develop "$ROOT" -c bash "$0" "$@"; fi
NAME=w37-ghostty-shots
SHOTS=$ROOT/tools/shots/ghostty
WORK=$(mktemp -d /tmp/kurashi-w37-ghostty.XXXXXX)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/kurashi-agents-target/w37-ghostty}
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
W=1000 H=620

step() { printf '\n== %s\n' "$*"; }
cleanup() {
  for p in ${GPIDS:-}; do kill "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

step "tools from nixpkgs"
GHOSTTY=$(timeout 900 nix shell nixpkgs#ghostty -c sh -c 'command -v ghostty')
GLSLANG=$(timeout 900 nix shell nixpkgs#glslang -c sh -c 'command -v glslangValidator')
echo "ghostty:  $GHOSTTY ($("$GHOSTTY" --version | sed -n 1p))"
echo "glslang:  $GLSLANG"

step "1. shader generator: compile per kind, golden"
KURASHI_REQUIRE_GLSLANG=1 KURASHI_GLSLANG=$GLSLANG timeout 900 cargo test -q -p kurashi-theme ghostty

step "2. export: shader on/off, real themes"
timeout 1200 cargo test -q -p kurashid theme_export
KURASHI_GHOSTTY_SHOTS=$WORK/exports timeout 900 cargo test -q -p kurashid ghostty_shot_exports -- --ignored

step "sandbox"
eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME" gles2)"
swaymsg output HEADLESS-1 resolution ${W}x${H} scale 1 >/dev/null
swaymsg default_border none >/dev/null
swaymsg gaps inner 0 >/dev/null 2>&1 || true

# What the terminal shows: `ls --color` over a demo tree, then an htop-like view (meters, a reverse-video header and a
# selected row), and a prompt with the cursor.
DEMO=$WORK/demo
mkdir -p "$DEMO/src" "$DEMO/docs" "$DEMO/.config"
: > "$DEMO/README.md"; : > "$DEMO/Cargo.toml"; : > "$DEMO/notes.txt"; : > "$DEMO/shot.png"; : > "$DEMO/backup.tar.gz"
printf '#!/bin/sh\n' > "$DEMO/run.sh"; chmod +x "$DEMO/run.sh"
ln -s README.md "$DEMO/LIESMICH"
touch -d '2026-10-25 09:41' "$DEMO" "$DEMO"/* "$DEMO"/.config
cat > "$WORK/content.sh" <<EOF
cd "$DEMO"
export LS_COLORS='di=01;34:ln=01;36:ex=01;32:*.png=01;35:*.tar.gz=01;31'
printf '\$ ls -l --color\n'
TZ=UTC ls -l --color=always --time-style=+'%b %d %H:%M' | sed 's/ [a-z0-9_]* [a-z0-9_]* / maike users /'
printf '\n\$ htop\n'
printf '  1  [\e[32m||||||||||||\e[31m|||\e[0m                 31.4%%]   Tasks: \e[1m142\e[0m, 1 running\n'
printf '  2  [\e[32m|||||\e[34m||\e[0m                        12.0%%]   Load average: \e[1m0.42\e[0m 0.37 0.31\n'
printf '  Mem[\e[32m||||||||||||||\e[34m||||\e[33m|||\e[0m       6.21G/31.2G]   Uptime: \e[1m03:12:44\e[0m\n\n'
printf '\e[30;42m  PID USER       PRI  NI  VIRT   RES  CPU%% MEM%%   TIME+  Command                       \e[0m\n'
printf ' 1342 maike       20   0 1.2G  210M  12.3  0.7  1:02.11 kurashid\n'
printf '\e[30;46m 2210 maike       20   0 3.4G  880M   8.1  2.8  4:51.07 ghostty                       \e[0m\n'
printf ' 2291 maike       20   0  12M  4.1M   0.0  0.0  0:00.02 \e[2mbash\e[0m\n'
printf '\n\$ '
exec sleep 600
EOF

# One ghostty in the sandbox with the config home `home`: the exported theme (and shader) plus our window settings.
run_ghostty() { # case-dir shot.ppm [extra config line]
  local home=$1 out=$2 extra=${3:-}
  mkdir -p "$home/ghostty" "$home/.state" "$home/.cache" "$home/.data" "$home/.home"
  cat > "$home/ghostty/config" <<EOF
theme = kurashi
font-size = 13
window-decoration = none
window-padding-x = 18
window-padding-y = 14
window-padding-balance = false
gtk-single-instance = false
confirm-close-surface = false
cursor-style-blink = false
shell-integration = none
resize-overlay = never
command = bash --noprofile --norc $WORK/content.sh
$extra
EOF
  env HOME="$home/.home" XDG_CONFIG_HOME="$home" XDG_STATE_HOME="$home/.state" \
    XDG_CACHE_HOME="$home/.cache" XDG_DATA_HOME="$home/.data" "$GHOSTTY" > "$home/ghostty.log" 2>&1 &
  local pid=$!
  GPIDS="${GPIDS:-} $pid"
  for _ in $(seq 100); do
    swaymsg -t get_tree -r | grep -q '"app_id": "com.mitchellh.ghostty"' && break
    sleep 0.1
  done
  swaymsg -t get_tree -r | grep -q '"app_id": "com.mitchellh.ghostty"' || { cat "$home/ghostty.log"; echo "ghostty did not map"; exit 1; }
  sleep 2.5
  grim -t ppm "$out"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  for _ in $(seq 50); do swaymsg -t get_tree -r | grep -q '"app_id": "com.mitchellh.ghostty"' || break; sleep 0.1; done
  if grep -iE 'shader.*(error|fail)|(error|fail).*shader' "$home/ghostty.log"; then
    echo "ghostty reports a shader error ($home/ghostty.log)"; exit 1
  fi
}

step "3. orientation probe"
PROBE=$WORK/probe
cp -r "$WORK/exports/kami-dark-plain" "$PROBE"
printf 'void mainImage(out vec4 c, in vec2 f) {\n    c = f.y < 0.25 * iResolution.y ? vec4(1.0, 0.0, 0.0, 1.0) : texture(iChannel0, f / iResolution.xy);\n}\n' > "$PROBE/probe.glsl"
run_ghostty "$PROBE" "$WORK/probe.ppm" "custom-shader = $PROBE/probe.glsl"

step "4. ghostty shots"
CASES="kami-light kami-dark stone-light stone-dark"
for c in $CASES; do
  for v in textured plain; do
    echo "  $c $v"
    run_ghostty "$WORK/exports/$c-$v" "$WORK/$c-$v.ppm"
  done
  grep -q '^custom-shader = ' "$WORK/exports/$c-textured/ghostty/themes/kurashi" || { echo "$c: no shader line"; exit 1; }
  if grep -q '^custom-shader' "$WORK/exports/$c-plain/ghostty/themes/kurashi"; then echo "$c: plain names a shader"; exit 1; fi
done

step "checks and pictures"
mkdir -p "$SHOTS"
python3 -I - "$WORK" "$SHOTS" $CASES <<'PY'
import json, struct, sys, zlib

work, shots, cases = sys.argv[1], sys.argv[2], sys.argv[3:]

def ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    parts, pos = [], 0
    while len(parts) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        parts.append(data[pos:end]); pos = end
    pos += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[pos:pos + w * h * 3]

def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def lum(c):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])

def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

fails = []

# The orientation probe: red in the bottom quarter means fragCoord counts rows from the bottom.
w, h, px = ppm(f"{work}/probe.ppm")
def at(x, y):
    i = (y * w + x) * 3
    return px[i:i + 3]
bottom, top = at(w // 2, h - 5), at(w // 2, 5)
print(f"probe: bottom {tuple(bottom)} top {tuple(top)}")
if not (bottom[0] > 200 and bottom[1] < 40 and top != bottom):
    fails.append("orientation: fragCoord does not count rows from the bottom; the shader's y flip is wrong")

for case in cases:
    tok = json.load(open(f"{work}/exports/{case}-textured/tokens.json"))
    bg = bytes(int(tok["color.surface"][i:i + 2], 16) for i in (1, 3, 5))
    w, h, plain = ppm(f"{work}/{case}-plain.ppm")
    w2, h2, tex = ppm(f"{work}/{case}-textured.ppm")
    assert (w, h) == (w2, h2)
    n = w * h
    is_bg = bytearray(n)
    for i in range(n):
        p = plain[i * 3:i * 3 + 3]
        if abs(p[0] - bg[0]) <= 2 and abs(p[1] - bg[1]) <= 2 and abs(p[2] - bg[2]) <= 2:
            is_bg[i] = 1
    nbg = sum(is_bg)
    changed_bg, sum_bg, other_changed, other, max_other = 0, 0, 0, 0, 0
    for i in range(n):
        a, b = plain[i * 3:i * 3 + 3], tex[i * 3:i * 3 + 3]
        d = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
        if is_bg[i]:
            sum_bg += d
            changed_bg += d > 0
        else:
            other += 1
            if d > 1:
                other_changed += 1
            max_other = max(max_other, d)
    # Text: pixels far from the background in the plain shot; their contrast against the mean of the background
    # pixels in a 7 × 7 window round them, plain vs textured.
    rel, texts = [], 0
    for y in range(3, h - 3, 1):
        for x in range(3, w - 3, 1):
            i = y * w + x
            p = plain[i * 3:i * 3 + 3]
            if is_bg[i] or max(abs(p[k] - bg[k]) for k in range(3)) < 60:
                continue
            texts += 1
            if texts % 3:
                continue  # every third text pixel is plenty
            sp, st, cnt = [0, 0, 0], [0, 0, 0], 0
            for dy in range(-3, 4):
                for dx in range(-3, 4):
                    j = (y + dy) * w + x + dx
                    if is_bg[j]:
                        cnt += 1
                        for k in range(3):
                            sp[k] += plain[j * 3 + k]; st[k] += tex[j * 3 + k]
            if not cnt:
                continue
            cp = contrast(p, [v / cnt for v in sp])
            ct = contrast(tex[i * 3:i * 3 + 3], [v / cnt for v in st])
            rel.append(abs(ct - cp) / cp)
    rel.sort()
    worst = rel[-1] if rel else 0.0
    p99 = rel[int(len(rel) * 0.99)] if rel else 0.0
    mean = sum(rel) / len(rel) if rel else 0.0
    cover = changed_bg / max(nbg, 1)
    print(f"{case}: background {nbg} px, {cover:.0%} touched (mean |Δ| {sum_bg / max(nbg, 1):.2f}); "
          f"other {other} px, {other_changed} changed (max Δ {max_other}); "
          f"text contrast Δ mean {mean:.4%} p99 {p99:.4%} max {worst:.4%} over {len(rel)} samples")
    if cover < 0.15:
        fails.append(f"{case}: the relief is missing ({cover:.0%} of the background touched)")
    if other_changed:
        fails.append(f"{case}: {other_changed} pixels that are not the background changed")
    if worst > 0.01:
        fails.append(f"{case}: text contrast moved {worst:.3%} (> 1 %)")
    # Side by side: plain | textured, an 8 px seam of the background between.
    gap = 8
    sw = 2 * w + gap
    row_gap = bg * gap
    side = b"".join(plain[y * w * 3:(y + 1) * w * 3] + row_gap + tex[y * w * 3:(y + 1) * w * 3] for y in range(h))
    png(f"{shots}/{case}.png", sw, h, side)
    # Zoom ×4 of the prompt, the cursor and the empty page under them: plain above, textured below.
    zx, zy, zw, zh, k, gap = 10, int(h * 0.76), 200, 90, 4, 24
    def crop(img):
        rows = []
        for y in range(zy, zy + zh):
            r = b"".join(img[(y * w + x) * 3:(y * w + x) * 3 + 3] * k for x in range(zx, zx + zw))
            rows.extend([r] * k)
        return rows
    zoom = crop(plain) + [bg * (zw * k)] * gap + crop(tex)
    png(f"{shots}/{case}-zoom.png", zw * k, len(zoom), b"".join(zoom))

if fails:
    print("\nFAIL:\n  " + "\n  ".join(fails))
    sys.exit(1)
print("\nall checks passed")
PY
echo "shots: $SHOTS"
rm -rf "$WORK"
