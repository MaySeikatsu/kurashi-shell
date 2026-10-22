#!/usr/bin/env bash
# The material over controls (K61, docs/ux/texture.md "Controls"; card W32-controls), headless, against the real kurashid:
#   1. a gallery of the controls in their states on the material (a layer window at the output's corner, with its own
#      shell.qml written here, in a scratch copy of the frontend): main's frontend (the merge base of this branch) and this
#      branch with theme.texture.controls off (must match main within the renderer's own noise), then on (the relief lies
#      over every filled face and its icon or glyph; labels, transparent faces, pictures and the focus ring stay as they
#      were); leather and kami;
#   2. the bar and the quick card (the real shell): off matches main, on changes the card's controls and nothing on the desk;
#   3. the launcher's calculation row (an accent fallback tile) and the dock. This branch's Launcher and Dock windows do not
#      share a tile sheet yet (CONTRACT-CHANGE), so their reliefs wait for it: the frontend as committed must change nothing
#      and make no sheet there; a scratch copy with a shared sheet on those two windows shows the reliefs working.
# Every session also checks that the tile sheets are not multiplied (a Relief in a window without a shared sheet makes its
# own pair) and that the frontend logs no error. Shots: frontend/shots/texture/controls/ (evidence to read, not just the exit
# code). Sandbox names are w32-ctl-…; sessions run one at a time.
#   nix develop -c frontend/test-controls.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/texture/controls
TMP=${KEEP_TMP:-$(mktemp -d)}; mkdir -p "$TMP"
PIDS=()
SB=""
cleanup() {  # a failed run leaves nothing up: this run's frontend and daemon, then its sandbox, then the scratch files
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  if [ -n "$SB" ]; then "$ROOT/tools/bench/sandbox.sh" stop "$SB" >/dev/null 2>&1 || true; fi
  [ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$OUT"
FAILS=0
fail() { echo "test-controls: FAIL $*" >&2; FAILS=$((FAILS + 1)); }
say() { echo "test-controls: $*"; }

# ---- the checker (stdlib only): PNG in and out, box and outside-box differences ----
cat > "$TMP/ctl.py" <<'PY'
import struct
import sys
import zlib

BAR = (0, 0, 2559, 31)
CARD = (1080, 36, 1480, 600)
LAUNCH = (980, 650, 1580, 790)
CALC_TILE = (1003, 731, 1032, 759)
CALC_LABEL = (1040, 726, 1070, 766)
CLOCKS = [(1100, 36, 1190, 75), (1190, 0, 1370, 31), (2270, 0, 2530, 31)]
# name, box, kind: flat (at most 8 pixels change: a label, a transparent face, the focus ring), relief (at least 60),
# glyph (at least 20: only the icon changes, the face stays what it was)
GALLERY = [
    ("button-label", (24, 24, 84, 53), "flat"),
    ("button-primary", (171, 24, 249, 53), "flat"),
    ("iconbtn-lit", (340, 24, 368, 52), "glyph"),
    ("iconbtn-rest", (380, 24, 408, 52), "flat"),
    ("quickbtn-open", (433, 25, 459, 51), "relief"),
    ("sidebarbtn-open", (473, 25, 499, 51), "relief"),
    ("chip", (520, 28, 556, 47), "relief"),
    ("toggle-on", (24, 103, 63, 125), "relief"),
    ("toggle-off", (110, 103, 150, 125), "relief"),
    ("slider-track", (200, 101, 420, 110), "relief"),
    ("slider-knob", (321, 96, 339, 114), "relief"),
    ("slider-unavail", (540, 96, 560, 116), "flat"),
    ("tray-disc", (30, 166, 50, 186), "relief"),
    ("key-label", (80, 160, 128, 200), "flat"),
    ("key-glyph", (180, 160, 220, 200), "relief"),
    ("quicktile-off", (250, 160, 410, 216), "glyph"),
    ("quicktile-on", (420, 160, 580, 216), "glyph"),
    ("focus-button", (24, 230, 86, 260), "flat"),
]


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


def write_png(path, w, h, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw += row

    def chunk(kind, body):
        c = kind + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def rgb(img, x, y):
    w, h, ch, buf = img
    i = (y * w + x) * ch
    return buf[i], buf[i + 1], buf[i + 2]


def inside(box, x, y):
    return box[0] <= x <= box[2] and box[1] <= y <= box[3]


def box_diff(a, b, box):
    n = mx = 0
    for y in range(box[1], box[3] + 1):
        for x in range(box[0], box[2] + 1):
            pa, pb = rgb(a, x, y), rgb(b, x, y)
            d = max(abs(pa[k] - pb[k]) for k in range(3))
            if d:
                n += 1
                mx = max(mx, d)
    return n, mx


def changed_outside(a, b, boxes):
    # Changed pixels outside every box. Rows that are equal are skipped: the screens are mostly flat.
    w, h = a[0], a[1]
    n = mx = 0
    for y in range(h):
        ia, ib = y * w * a[2], y * w * b[2]
        if a[2] == b[2] and a[3][ia:ia + w * a[2]] == b[3][ib:ib + w * b[2]]:
            continue
        for x in range(w):
            if any(inside(bx, x, y) for bx in boxes):
                continue
            pa, pb = rgb(a, x, y), rgb(b, x, y)
            d = max(abs(pa[k] - pb[k]) for k in range(3))
            if d:
                n += 1
                mx = max(mx, d)
    return n, mx


def crop(img, x0, y0, cw, ch_, out):
    w, h, ch, buf = img
    rows = []
    for y in range(y0, y0 + ch_):
        row = bytearray()
        for x in range(x0, x0 + cw):
            i = (y * w + x) * ch
            row += buf[i:i + 3]
        rows.append(bytes(row))
    write_png(out, cw, ch_, rows)


def gallery(off, on):
    bad = 0
    for name, box, kind in GALLERY:
        n, mx = box_diff(off, on, box)
        ok = n <= 8 if kind == "flat" else (n >= 60 if kind == "relief" else n >= 20)
        print("gallery %-15s %-6s changed %4d max %3d %s" % (name, kind, n, mx, "ok" if ok else "FAIL"))
        bad += 0 if ok else 1
    n, mx = changed_outside(off, on, [b for _, b, _ in GALLERY])
    print("gallery outside every control: changed %d max %d" % (n, mx))
    return bad + (0 if n <= 16 else 1)


def same(a, b, skip):
    n, mx = changed_outside(a, b, skip)
    print("same: changed %d max %d outside %d boxes" % (n, mx, len(skip)))
    return 0 if n <= 16 and mx <= 2 else 1


def within(base, off, base2):
    # Controls off against main, within the renderer's own run-to-run noise: two runs of main differ by that noise.
    n_off, mx_off = changed_outside(base, off, CLOCKS)
    n_noise, mx_noise = changed_outside(base, base2, CLOCKS)
    limit = max(16, n_noise + 16)
    print("controls off vs main: changed %d max %d; main against main: changed %d max %d; limit %d"
          % (n_off, mx_off, n_noise, mx_noise, limit))
    return 0 if n_off <= limit and mx_off <= 2 else 1


def quick(off, on):
    n, mx = box_diff(off, on, CARD)
    desk, dmx = changed_outside(off, on, [BAR, CARD])
    print("quick card: changed %d max %d; the desk (outside bar and card) changed %d max %d" % (n, mx, desk, dmx))
    return (0 if n >= 100 else 1) + (0 if desk <= 16 else 1)


def calc(off, on):
    tile, tmx = box_diff(off, on, CALC_TILE)
    label, lmx = box_diff(off, on, CALC_LABEL)
    rest, rmx = changed_outside(off, on, [BAR, LAUNCH])
    print("calc row: tile changed %d max %d; label changed %d max %d; outside launcher and bar changed %d max %d"
          % (tile, tmx, label, lmx, rest, rmx))
    return (0 if tile >= 100 else 1) + (0 if label <= 8 else 1) + (0 if rest <= 16 else 1)


def main():
    cmd = sys.argv[1]
    if cmd == "gallery":
        return gallery(read_png(sys.argv[2]), read_png(sys.argv[3]))
    if cmd == "same":
        return same(read_png(sys.argv[2]), read_png(sys.argv[3]), CLOCKS if sys.argv[4] == "clock" else [])
    if cmd == "within":
        return within(read_png(sys.argv[2]), read_png(sys.argv[3]), read_png(sys.argv[4]))
    if cmd == "quick":
        return quick(read_png(sys.argv[2]), read_png(sys.argv[3]))
    if cmd == "calc":
        return calc(read_png(sys.argv[2]), read_png(sys.argv[3]))
    if cmd == "crop":
        x0, y0, cw, ch_ = map(int, sys.argv[4:8])
        crop(read_png(sys.argv[2]), x0, y0, cw, ch_, sys.argv[3])
        return 0
    if cmd == "count":
        print(sum(1 for line in open(sys.argv[2], errors="replace") if sys.argv[3] in line))
        return 0
    raise SystemExit("usage: ctl.py gallery|same|quick|calc|crop|count ...")


if __name__ == "__main__":
    sys.exit(main())
PY

# ---- the scratch copy with a tile sheet on the Dock and Launcher windows (what their owners would add) ----
cat > "$TMP/hook.py" <<'PY'
import re
import sys

for path in sys.argv[1:]:
    out = []
    for ln in open(path).read().split("\n"):
        out.append(ln)
        if re.match(r"^\s*PanelWindow \{\s*$", ln):
            ind = re.match(r"^(\s*)", ln).group(1) + "    "
            out.append(ind + "property var tileSheet: tilesLoader.item")
            out.append(ind + "Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }")
    open(path, "w").write("\n".join(out))
PY

# ---- the controls gallery: every control in its states on the material ----
cat > "$TMP/gal-shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"
import "components"
import "components/island"
import "components/quick"

// The controls gallery (frontend/test-controls.sh, a scratch shell): one layer window at the output's top-left corner, so
// its origin is the output's own and the sheet registers as in the shell.
ShellRoot {
    Watch { doc: "theme" }
    Watch { doc: "i18n" }

    PanelWindow {
        id: gal
        anchors { top: true; left: true }
        implicitWidth: 720
        implicitHeight: 300
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "kurashi-gallery"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        property var tileSheet: tilesLoader.item
        Loader {
            id: tilesLoader
            active: Theme.texOn && Theme.texTilePx > 0
            sourceComponent: TileSheet {}
        }
        Rectangle { anchors.fill: parent; color: Theme.surface }
        Relief { anchors.fill: parent }

        Button { x: 24; y: 24; label: "Label" }
        Button { x: 170; y: 24; label: "Primary"; primary: true }
        IconButton { x: 340; y: 24; glyph: "◐"; lit: true; a11y: "lit" }
        IconButton { x: 380; y: 24; glyph: "◐"; a11y: "rest" }
        QuickButton { x: 430; y: 22; open: true }
        SidebarButton { x: 470; y: 22; side: "right"; open: true }
        Chip { x: 520; y: 28; text: "Chip" }

        ToggleSwitch { x: 24; y: 96; checked: true; label: "On" }
        ToggleSwitch { x: 110; y: 96; checked: false; label: "Off" }
        Slider { x: 200; y: 96; width: 220; value: 0.6; a11y: "Level" }
        Slider { x: 450; y: 96; width: 200; unavailable: true; a11y: "Level" }

        TrayIcon { x: 24; y: 160; title: "N" }
        KeyButton { x: 80; y: 160; label: "Key"; a11y: "Key" }
        KeyButton { x: 180; y: 160; glyph: "◐"; a11y: "glyph"; primary: true }
        QuickTile { x: 250; y: 160; label: "Wi-Fi"; subtitle: "Off"; glyph: "◐"; hasPage: false }
        QuickTile { x: 420; y: 160; label: "Focus"; subtitle: "On"; glyph: "◐"; on: true; hasPage: false }

        Button { id: focusBtn; x: 24; y: 230; label: "Focus" }
        Timer { interval: 400; running: true; onTriggered: focusBtn.forceActiveFocus() }
    }
}
QML

# ---- the frontends under test: main's (the merge base of this branch), this branch, and the two scratch variants ----
BASE_REF=${BASE_REF:-$(git -C "$ROOT" merge-base HEAD main)}
mkdir -p "$TMP/base"
git -C "$ROOT" archive --format=tar "$BASE_REF" frontend | tar -x -C "$TMP/base"
BASE_FE=$TMP/base/frontend
CUR_FE=$ROOT/frontend
mkgal() {  # mkgal SRC DST: the components, core and shaders of SRC, with the controls gallery as the shell
  mkdir -p "$2"
  cp -r "$1/components" "$1/core" "$1/shaders" "$2/"
  cp "$TMP/gal-shell.qml" "$2/shell.qml"
}
mkgal "$BASE_FE" "$TMP/gal-base"
mkgal "$CUR_FE" "$TMP/gal-cur"
mkdir -p "$TMP/hook"
cp -r "$CUR_FE/components" "$CUR_FE/core" "$CUR_FE/shaders" "$CUR_FE/surfaces" "$CUR_FE/shell.qml" "$TMP/hook/"
python3 "$TMP/hook.py" "$TMP/hook/surfaces/Dock.qml" "$TMP/hook/surfaces/Launcher.qml"
CTL=(python3 "$TMP/ctl.py")

# ---- a session: a fresh headless sandbox, the real kurashid with CONFIG, the frontend FE (the QML tree to run) ----
PIDS=()
SB=""
W_DIR=""
QS_LOG=""
session() {  # session NAME FRONTEND TEXTURE(yes|no) CONFIG...: leaves the session up (stop_session ends it)
  local name=$1 fe=$2 texture=$3
  shift 3
  SB=w32-ctl-$name
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
  timeout 5 "$W_DIR/kurashi" ping >/dev/null 2>&1 || { echo "test-controls: kurashid did not come up ($name)" >&2; exit 1; }
  swaymsg output '*' bg '#8fb8c8' solid_color >/dev/null 2>&1 || true
  if [ "$texture" = yes ]; then
    local tile=""
    for _ in $(seq 150); do
      tile=$(ls "$XDG_CACHE_HOME"/kurashi/texture/*.png 2>/dev/null | grep -v -- '-ink\.png$' | head -1 || true)
      [ -n "$tile" ] && break
      sleep 0.2
    done
    [ -n "$tile" ] || { echo "test-controls: no tile was generated ($name)" >&2; exit 1; }
    sleep 0.5
  fi
  env -u KURASHI_SOCKET qs -p "$fe" >> "$QS_LOG" 2>&1 &
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
snap() { sleep 2; grim "$TMP/$1.png"; }
ctl() { timeout 10 "$W_DIR/kurashi" "$@" >/dev/null 2>&1 || true; }
keys() { timeout 20 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@" >/dev/null 2>&1 || true; }
declare -A SHEETS=() ERRORS=()
rec() {  # rec NAME: the session's tile sheets made and its QML errors, read before the session ends
  SHEETS[$1]=$(grep -c "texture: tile sheet made" "$QS_LOG" || true)
  ERRORS[$1]=$(grep -c "ERROR" "$QS_LOG" || true)
}

LEATHER=('theme.texture.kind = "leather"' 'theme.texture.strength = 1')
KAMI=('theme.style = "kami"')
DOCKCFG=('[dock]' 'enabled = true' 'autohide = false' 'pinned = ["firefox", "org.gnome.Nautilus"]')

# ---- 1. the gallery: main, then this branch off and on, leather and kami ----
say "the gallery: main, then this branch with the controls off and on (leather, then kami)"
session gal-base "$TMP/gal-base" yes "${LEATHER[@]}"
snap gal-base; rec gal-base; stop_session
session gal-off "$TMP/gal-cur" yes "${LEATHER[@]}" 'theme.texture.controls = false'
snap gal-off; rec gal-off; stop_session
session gal-on "$TMP/gal-cur" yes "${LEATHER[@]}" 'theme.texture.controls = true'
snap gal-on; rec gal-on; stop_session
session kgal-base "$TMP/gal-base" yes "${KAMI[@]}"
snap kgal-base; rec kgal-base; stop_session
session kgal-off "$TMP/gal-cur" yes "${KAMI[@]}" 'theme.texture.controls = false'
snap kgal-off; rec kgal-off; stop_session
session kgal-on "$TMP/gal-cur" yes "${KAMI[@]}" 'theme.texture.controls = true'
snap kgal-on; rec kgal-on; stop_session

# ---- 2. the bar and the quick card (the real shell): main, then this branch off and on, leather and kami ----
say "the bar and the quick card: main, then this branch with the controls off and on (leather, then kami)"
session quick-base "$BASE_FE" yes "${LEATHER[@]}"
ctl act quick.toggle; snap quick-base; rec quick-base; stop_session
session quick-base2 "$BASE_FE" yes "${LEATHER[@]}"
ctl act quick.toggle; snap quick-base2; rec quick-base2; stop_session
session quick-off "$CUR_FE" yes "${LEATHER[@]}" 'theme.texture.controls = false'
ctl act quick.toggle; snap quick-off; rec quick-off; stop_session
session quick-on "$CUR_FE" yes "${LEATHER[@]}" 'theme.texture.controls = true'
ctl act quick.toggle; snap quick-on; rec quick-on; stop_session
session kquick-off "$CUR_FE" yes "${KAMI[@]}" 'theme.texture.controls = false'
ctl act quick.toggle; snap kquick-off; rec kquick-off; stop_session
session kquick-on "$CUR_FE" yes "${KAMI[@]}" 'theme.texture.controls = true'
ctl act quick.toggle; snap kquick-on; rec kquick-on; stop_session

# ---- 3. the launcher's calculation row and the dock ----
say "the launcher: main; this branch as committed (controls on: no sheet, so nothing may change); a scratch copy with a sheet"
session launch-base "$BASE_FE" yes "${LEATHER[@]}"
ctl act launcher.toggle; sleep 1; keys 2 + 2; snap launch-base; rec launch-base; stop_session
session launch-committed "$CUR_FE" yes "${LEATHER[@]}" 'theme.texture.controls = true'
ctl act launcher.toggle; sleep 1; keys 2 + 2; snap launch-committed; rec launch-committed; stop_session
session launch-off "$TMP/hook" yes "${LEATHER[@]}" 'theme.texture.controls = false'
ctl act launcher.toggle; sleep 1; keys 2 + 2; snap launch-off; rec launch-off; stop_session
session launch-on "$TMP/hook" yes "${LEATHER[@]}" 'theme.texture.controls = true'
ctl act launcher.toggle; sleep 1; keys 2 + 2; snap launch-on; rec launch-on; stop_session
say "the dock (kami, a pinned pair): the scratch copy with the sheet, controls off and on"
session dock-off "$TMP/hook" yes "${KAMI[@]}" 'theme.texture.controls = false' "${DOCKCFG[@]}"
snap dock-off; rec dock-off; stop_session
session dock-on "$TMP/hook" yes "${KAMI[@]}" 'theme.texture.controls = true' "${DOCKCFG[@]}"
snap dock-on; rec dock-on; stop_session

# ---- the checks ----
say "checks"
run_check() {  # run_check MESSAGE COMMAND...: a failed command is a failed check, and the output stays visible
  local msg=$1; shift
  if ! "$@"; then fail "$msg"; fi
}
run_check "the gallery (leather): the controls change as the relief says, labels and transparent faces do not" \
  "${CTL[@]}" gallery "$TMP/gal-off.png" "$TMP/gal-on.png"
run_check "the gallery (kami): the controls change as the relief says, labels and transparent faces do not" \
  "${CTL[@]}" gallery "$TMP/kgal-off.png" "$TMP/kgal-on.png"
run_check "controls off, leather: the gallery matches main" "${CTL[@]}" same "$TMP/gal-base.png" "$TMP/gal-off.png" none
run_check "controls off, kami: the gallery matches main" "${CTL[@]}" same "$TMP/kgal-base.png" "$TMP/kgal-off.png" none
run_check "controls off, leather: the bar and the quick card match main, within the noise of two runs of main" \
  "${CTL[@]}" within "$TMP/quick-base.png" "$TMP/quick-off.png" "$TMP/quick-base2.png"
run_check "controls on, leather: the quick card changes, the desk does not" \
  "${CTL[@]}" quick "$TMP/quick-off.png" "$TMP/quick-on.png"
run_check "controls on, kami: the quick card changes, the desk does not" \
  "${CTL[@]}" quick "$TMP/kquick-off.png" "$TMP/kquick-on.png"
run_check "the launcher, controls off: a scratch sheet changes nothing against main (the clocks aside)" \
  "${CTL[@]}" same "$TMP/launch-base.png" "$TMP/launch-off.png" clock
run_check "the launcher, controls on: the calculation tile carries the relief, its label stays flat" \
  "${CTL[@]}" calc "$TMP/launch-off.png" "$TMP/launch-on.png"
run_check "the launcher as committed (no sheet), controls on: nothing changes against main" \
  "${CTL[@]}" same "$TMP/launch-base.png" "$TMP/launch-committed.png" clock
run_check "the dock, controls on: its tiles are transparent at rest, so nothing changes" \
  "${CTL[@]}" same "$TMP/dock-off.png" "$TMP/dock-on.png" clock
for pair in "gal-off gal-on" "kgal-off kgal-on" "quick-off quick-on" "kquick-off kquick-on" "launch-off launch-on" \
    "dock-off dock-on"; do
  set -- $pair
  if [ "${SHEETS[$1]}" != "${SHEETS[$2]}" ]; then
    fail "tile sheets: $1 made ${SHEETS[$1]}, $2 made ${SHEETS[$2]} (a control's relief must share its window's sheet)"
  fi
done
if [ "${SHEETS[launch-base]}" != "${SHEETS[launch-committed]}" ]; then
  fail "tile sheets: the committed launcher made ${SHEETS[launch-committed]} against main's ${SHEETS[launch-base]}"
fi
for name in gal-base gal-off gal-on kgal-base kgal-off kgal-on quick-base quick-base2 quick-off quick-on kquick-off kquick-on \
    launch-base launch-committed launch-off launch-on dock-off dock-on; do
  if [ "${ERRORS[$name]}" != 0 ]; then fail "$name logged ${ERRORS[$name]} ERROR line(s) (see its qs.log)"; fi
done

# ---- the shots: the evidence the review reads ----
cp "$TMP/quick-off.png" "$OUT/quick-leather-off.png"
cp "$TMP/quick-on.png" "$OUT/quick-leather-on.png"
cp "$TMP/kquick-off.png" "$OUT/quick-kami-off.png"
cp "$TMP/kquick-on.png" "$OUT/quick-kami-on.png"
"${CTL[@]}" crop "$TMP/gal-off.png" "$OUT/gallery-leather-off.png" 0 0 720 300
"${CTL[@]}" crop "$TMP/gal-on.png" "$OUT/gallery-leather-on.png" 0 0 720 300
"${CTL[@]}" crop "$TMP/kgal-off.png" "$OUT/gallery-kami-off.png" 0 0 720 300
"${CTL[@]}" crop "$TMP/kgal-on.png" "$OUT/gallery-kami-on.png" 0 0 720 300
"${CTL[@]}" crop "$TMP/launch-off.png" "$OUT/launcher-leather-calc-off.png" 960 640 640 160
"${CTL[@]}" crop "$TMP/launch-on.png" "$OUT/launcher-leather-calc-on.png" 960 640 640 160
"${CTL[@]}" crop "$TMP/launch-committed.png" "$OUT/launcher-leather-calc-committed-on.png" 960 640 640 160
"${CTL[@]}" crop "$TMP/dock-off.png" "$OUT/dock-kami-off.png" 900 1290 480 150
"${CTL[@]}" crop "$TMP/dock-on.png" "$OUT/dock-kami-on.png" 900 1290 480 150

if [ "$FAILS" -gt 0 ]; then
  echo "test-controls: $FAILS check(s) failed (shots in $OUT)" >&2
  exit 1
fi
echo "test-controls: ok ($OUT)"
