#!/usr/bin/env bash
# The bar's widgets on a side edge (I85, W19-side-bars), invisibly (headless sway sandbox) on the real daemon. Each scene has
# its own daemon and frontend: the bar's edge, the output's height (1080 or 720 px, by swaymsg), the mod widgets (sysmon,
# weather with a fixture place, and the test mod hello: kurashid must be built with --features test-mods), twelve fake
# StatusNotifierItems for a long tray (a Python helper on the sandbox's bus, embedded below) and the locale:
#   left-default   left bar, 1080 px, no mods, no tray: every default widget fits, nothing is hidden;
#   left-long      left bar, 1080 px, the mods and twelve tray icons: the column hides from the end, with a count;
#   left-720       the same on a 720 px output;
#   right-long     right bar, 1080 px, the same;
#   right-default  right bar, 1080 px, no mods, no tray;
#   left-ja        left bar, 1080 px, the mods and the tray with the Japanese copy.
# Asserted from the QML item geometry the frontend logs (KURASHI_BAR_GEOMETRY=1; Bar.qml's logGeometry, read by geo.py): every
# item's box lies inside the bar, the bottom column is in order and does not overlap the island, and the mod slots and tray
# icons drawn are the ones the column's fit gives, with the count of the rest. The frontend logs no QML error or warning.
# Shots: frontend/shots/sidebars/<scene>.png (the output) and <scene>-bar.png (the bar's strip): read them, not just the exit code.
#   KURASHI_BIN_DIR=<dir with kurashid (--features test-mods) and kurashi> \
#     timeout 900 nix develop -c frontend/test-sidebars.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-w19-side-bars-$$}   # the w19-side-bars prefix: other runs never stop this sandbox
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
OUT=$ROOT/frontend/shots/sidebars
FX=$ROOT/crates/kurashi-mod-weather/tests/fixtures
HELLO=$ROOT/crates/kurashid/tests/data/mods/hello
mkdir -p "$OUT"
fail() { echo "test-sidebars: $*" >&2; exit 1; }
[ -x "$BIN/kurashid" ] && [ -x "$BIN/kurashi" ] || fail "no kurashid and kurashi in $BIN (KURASHI_BIN_DIR)"
TEST_MODS=0; grep -aq 'hello.raise' "$BIN/kurashid" && TEST_MODS=1   # the side-bar scenes need the test mod (--features test-mods)
WEATHER_TOKYO='{"place":{"id":"1850147","name":"Tokyo","country_code":"JP","lat":35.6895,"lon":139.69171,"tz":"Asia/Tokyo"}}'

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
mkdir -p "$W" "$R/kurashi" "$R/weather/v1"
cp "$BIN/kurashid" "$BIN/kurashi" "$W/"
cp "$FX/forecast_tokyo.json" "$R/weather/v1/forecast"
cp "$FX/geocode_tokyo_ja.json" "$R/weather/v1/search"
# Hermetic daemon and frontend: isolated XDG dirs, no system bus (the sandbox's own session bus only), strings from this checkout.
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache \
       KURASHI_DATA_DIR=$ROOT

# `ipc.py <doc>` prints the first snapshot's data of a document (stdlib only, as in test-peek.sh).
cat > "$W/ipc.py" <<'PY'
import json, os, socket, sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(os.environ["KURASHI_SOCKET"])
f = sock.makefile("rwb")


def send(msg):
    f.write((json.dumps(msg) + "\n").encode())
    f.flush()


send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
if json.loads(f.readline())["t"] != "welcome":
    sys.exit("ipc: no welcome")
send({"t": "sub", "id": "s", "doc": sys.argv[1]})
while True:
    line = f.readline()
    if not line:
        sys.exit("ipc: connection closed")
    m = json.loads(line)
    if m.get("id") == "s" and m["t"] in ("snap", "err"):
        if m["t"] == "err":
            sys.exit("ipc: " + json.dumps(m))
        print(json.dumps(m.get("data")))
        break
PY
cat > "$W/geo.py" <<'PY'
# geo.py LOG HEIGHT MODS TRAY HIDDEN: the asserts on the last geometry dump of the frontend's bar (Bar.qml, KURASHI_BAR_GEOMETRY=1).
# Prints "ok <what>" and "FAIL <what>" lines; the exit status is 1 when any check fails.
#   LOG     the frontend's log (qs.log)
#   HEIGHT  the output's height the bar must span
#   MODS    how many mod widgets the bar has (sysmon, weather, hello: 3)
#   TRAY    how many tray items the host lists
#   HIDDEN  1 when the column must hide something (a count is shown), 0 when everything must fit
import re
import sys

log, height, mods, tray, hidden_expect = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
out = []
failed = []


def ok(what):
    out.append("ok " + what)


def bad(what):
    out.append("FAIL " + what)
    failed.append(what)


starts = [i for i, line in enumerate(lines) if "BARGEO bar " in line]
if not starts:
    bad("the frontend logged no geometry (KURASHI_BAR_GEOMETRY)")
else:
    block = []
    for line in lines[starts[-1]:]:
        if "BARGEO " not in line:
            if block:
                break
            continue
        block.append(line.split("BARGEO ", 1)[1].strip())
    items, fit, bar_w, bar_h = {}, None, None, None
    for line in block:
        name, _, rest = line.partition(" ")
        if name == "bar":
            nums = [int(v) for v in rest.split()]
            bar_w, bar_h = nums[2], nums[3]
        elif name == "fit":
            m = re.match(r"(\d+) hidden (\d+) trays (\d+) shown (\d+)", rest)
            fit = tuple(int(v) for v in m.groups())
        else:
            items[name] = [int(v) for v in rest.split()]
    if bar_h != height:
        bad("the bar spans %s px, the output is %d px tall" % (bar_h, height))
    else:
        ok("the bar spans the output's %d px (bar %d px wide)" % (height, bar_w))
    if fit is None:
        bad("no fit line in the dump")
        fit = (0, 0, 0, 0)
    fit_n, hidden, trays_n, shown = fit

    # Every item's box lies inside the bar (the boxes are the drawn ones: a rotated slider is measured by its corners).
    outside = [n + str(b) for n, b in items.items() if not (b[0] >= 0 and b[1] >= 0 and b[2] <= bar_w and b[3] <= bar_h)]
    if outside:
        bad("items outside the bar: " + ", ".join(outside))
    else:
        ok("%d items inside the bar's %d x %d px" % (len(items), bar_w, bar_h))

    if "island" not in items:
        bad("the island is not drawn")
    else:
        isl = items["island"]
        above_ws = items.get("workspaces")
        if above_ws is not None and above_ws[3] > isl[1]:
            bad("the workspaces reach into the island")
        else:
            ok("the workspaces stay above the island")
        column = sorted(((b[1], n, b) for n, b in items.items() if n == "slider" or n in ("clock", "quick", "more") or n.startswith("slot-") or re.match(r"tray\d+$", n)), key=lambda t: t[0])
        overlap = [(a[1], c[1]) for a, c in zip(column, column[1:]) if c[0] < a[2][3] - 0.5]
        if overlap:
            bad("column items overlap: %s" % overlap)
        else:
            ok("the bottom column is in order, its items do not overlap")
        if any(b[1] < isl[3] - 0.5 for n, b in items.items() if n in ("slider", "clock", "quick", "more") or n.startswith(("slot-", "tray"))):
            bad("column items start above the island's lower edge")
        else:
            ok("the bottom column starts below the island")

    # The column's count: the slots are the slider, the mods, the clock, the quick button and the tray icons, in that order.
    slot_names = [n for n in items if n.startswith("slot-")]
    tray_names = [n for n in items if re.match(r"tray\d+$", n)]
    total = 3 + mods + tray
    if hidden != total - fit_n:
        bad("the fit says %d of %d slots, hidden %d" % (fit_n, total, hidden))
    else:
        ok("the fit holds %d of %d slots (%d hidden)" % (fit_n, total, hidden))
    want_mods = min(mods, max(0, fit_n - 1))
    if len(slot_names) != want_mods:
        bad("%d mod slots drawn, the fit gives %d" % (len(slot_names), want_mods))
    else:
        ok("%d mod slots drawn" % want_mods)
    want_trays = max(0, min(tray, fit_n - 3 - mods))
    if len(tray_names) != want_trays or shown != want_trays or trays_n != tray:
        bad("%d tray icons drawn (shown %d, the fit gives %d of %d)" % (len(tray_names), shown, want_trays, tray))
    else:
        ok("%d of %d tray icons drawn" % (want_trays, tray))
    if (fit_n >= 1) != ("slider" in items) or (fit_n >= 2 + mods) != ("clock" in items) or (fit_n >= 3 + mods) != ("quick" in items):
        bad("the slider, clock and quick button do not follow the fit")
    else:
        ok("the slider, clock and quick button follow the fit")
    if hidden_expect == 1:
        if hidden > 0 and "more" in items:
            ok("a count of %d hidden items is drawn at the column's end" % hidden)
        else:
            bad("the column should hide items with a count (hidden %d, marker %s)" % (hidden, "more" in items))
    else:
        if hidden == 0 and "more" not in items:
            ok("nothing is hidden: every default item fits")
        else:
            bad("the column hides %d items it should not" % hidden)

for line in out:
    print(line)
sys.exit(1 if failed else 0)
PY
cat > "$W/sni.py" <<'PY'
# sni.py N — N fake StatusNotifierItems on the session bus, registered with the tray host (kurashid's watcher). Each answers
# the properties the tray reads (GetAll / Get on org.kde.StatusNotifierItem at /StatusNotifierItem). Stdlib only: a raw
# D-Bus client, since the dev shell has no D-Bus bindings. Method calls that are not for a property get an empty reply.
import os
import selectors
import socket
import struct
import sys


def pad_to(buf, n):
    buf.extend(b"\0" * ((-len(buf)) % n))


def w_str(buf, s):
    pad_to(buf, 4)
    b = s.encode()
    buf.extend(struct.pack("<I", len(b)) + b + b"\0")


def w_sig(buf, s):
    b = s.encode()
    buf.extend(bytes([len(b)]) + b + b"\0")


def put(buf, sig, v):
    if sig in ("s", "o"):
        w_str(buf, v)
    elif sig == "g":
        w_sig(buf, v)
    elif sig in ("b", "u"):
        pad_to(buf, 4)
        buf.extend(struct.pack("<I", 1 if v is True else (0 if v is False else v)))
    elif sig == "v":
        w_sig(buf, v[0])
        put(buf, v[0], v[1])
    elif sig == "a{sv}":
        pad_to(buf, 4)
        at = len(buf)
        buf.extend(b"\0\0\0\0")
        pad_to(buf, 8)
        start = len(buf)
        for key, value in v.items():
            pad_to(buf, 8)
            w_str(buf, key)
            w_sig(buf, value[0])
            put(buf, value[0], value[1])
        struct.pack_into("<I", buf, at, len(buf) - start)
    else:
        raise ValueError("unsupported signature " + sig)


def message(mtype, flags, serial, fields, body):
    m = bytearray(b"l" + bytes([mtype, flags, 1]))
    m.extend(struct.pack("<II", len(body), serial))
    at = len(m)
    m.extend(b"\0\0\0\0")
    pad_to(m, 8)
    start = len(m)
    for code, sig, value in fields:
        pad_to(m, 8)
        m.append(code)
        w_sig(m, sig)
        put(m, sig, value)
    struct.pack_into("<I", m, at, len(m) - start)
    pad_to(m, 8)
    return bytes(m) + body


def args_bytes(types, args):
    body = bytearray()
    for t, a in zip(types, args):
        put(body, t, a)
    return bytes(body)


def call(serial, dest, path, iface, member, types=(), args=(), flags=0):
    fields = [(1, "o", path), (2, "s", iface), (3, "s", member), (6, "s", dest)]
    sig = "".join(types)
    if sig:
        fields.append((8, "g", sig))
    return message(1, flags, serial, fields, args_bytes(types, args))


def reply(serial, reply_serial, dest, types=(), args=()):
    fields = [(5, "u", reply_serial), (6, "s", dest)]
    sig = "".join(types)
    if sig:
        fields.append((8, "g", sig))
    return message(2, 1, serial, fields, args_bytes(types, args))


def recv_exact(sock, n):
    data = bytearray()
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError("bus closed")
        data.extend(chunk)
    return bytes(data)


def get(data, off, sig):
    if sig in ("s", "o"):
        off += (-off) % 4
        n = struct.unpack_from("<I", data, off)[0]
        off += 4
        return data[off:off + n].decode(), off + n + 1
    if sig == "g":
        n = data[off]
        return data[off + 1:off + 1 + n].decode(), off + n + 2
    if sig in ("b", "u"):
        off += (-off) % 4
        return struct.unpack_from("<I", data, off)[0], off + 4
    raise ValueError("unsupported signature " + sig)


def parse_fields(data):
    out = {}
    off = 0
    while off < len(data):
        off += (-off) % 8
        code = data[off]
        off += 1
        n = data[off]
        sig = data[off + 1:off + 1 + n].decode()
        off += n + 2
        out[code], off = get(data, off, sig)
    return out


def parse_args(body, sig):
    out, off = [], 0
    for c in sig:
        v, off = get(body, off, c)
        out.append(v)
    return out


def read_msg(sock):
    fixed = recv_exact(sock, 16)
    mtype, flags = fixed[1], fixed[2]
    body_len, serial = struct.unpack("<II", fixed[4:12])
    fields_len = struct.unpack("<I", fixed[12:16])[0]
    fields = parse_fields(recv_exact(sock, fields_len))
    recv_exact(sock, (-(16 + fields_len)) % 8)
    body = recv_exact(sock, body_len)
    return mtype, flags, serial, fields, body


def props(i):
    return {
        "Id": ("s", "kurashi-test-%d" % i),
        "Category": ("s", "ApplicationStatus"),
        "Title": ("s", "Test item %d" % i),
        "Status": ("s", "Active"),
        "IconName": ("s", "kurashi-test-missing-icon"),
        "ItemIsMenu": ("b", False),
        "Menu": ("o", "/NO_DBUSMENU"),
    }


class Item:
    def __init__(self, bus_path, i):
        self.i = i
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(bus_path)
        self.sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        line = b""
        while not line.endswith(b"\r\n"):
            line += self.sock.recv(1)
        if not line.startswith(b"OK"):
            raise RuntimeError("auth refused: " + line.decode(errors="replace"))
        self.sock.sendall(b"BEGIN\r\n")
        self.serial = 0
        self.sock.sendall(call(self.next(), "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello"))
        while True:
            mtype, _, rs, fields, body = read_msg(self.sock)
            if mtype == 2 and fields.get(5) == self.serial:
                self.name = parse_args(body, "s")[0]
                break

    def next(self):
        self.serial += 1
        return self.serial

    def register(self):
        self.sock.sendall(call(self.next(), "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                               "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem", ["s"], [self.name], flags=1))

    def serve(self):
        mtype, flags, serial, fields, body = read_msg(self.sock)
        if mtype != 1:
            return
        iface, member, path, sender = fields.get(2), fields.get(3), fields.get(1), fields.get(7)
        expects_reply = not (flags & 1)
        out = None
        if path == "/StatusNotifierItem" and iface == "org.freedesktop.DBus.Properties" and member == "GetAll":
            name = parse_args(body, "s")[0]
            out = reply(self.next(), serial, sender, ["a{sv}"], [props(self.i) if name == "org.kde.StatusNotifierItem" else {}])
        elif path == "/StatusNotifierItem" and iface == "org.freedesktop.DBus.Properties" and member == "Get":
            name, prop = parse_args(body, "ss")
            value = props(self.i).get(prop)
            out = reply(self.next(), serial, sender, ["v"], [value]) if value else None
        elif expects_reply:
            out = reply(self.next(), serial, sender)
        if out is not None and expects_reply:
            self.sock.sendall(out)


def main():
    count = int(sys.argv[1])
    bus = os.environ["DBUS_SESSION_BUS_ADDRESS"]
    bus_path = bus.split("path=", 1)[1].split(",", 1)[0]
    items = [Item(bus_path, i) for i in range(count)]
    sel = selectors.DefaultSelector()
    for item in items:
        item.register()
        sel.register(item.sock, selectors.EVENT_READ, item)
    print("sni: %d items registered" % count, flush=True)
    while True:
        for key, _ in sel.select():
            key.data.serve()


if __name__ == "__main__":
    main()
PY
ipc() { timeout 10 python3 -I "$W/ipc.py" "$@"; }
K() { timeout 10 "$W/kurashi" "$@"; }

FAILS=0
check() { # check <0|1> <label>
  if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi
}
qs_problems() { # the frontend's errors and warnings, the known ones aside (the background effect, the portal, and GTK's notice that a locale
  # is not installed in the sandbox)
  grep -E "WARN|ERROR|TypeError|ReferenceError|Binding loop|not a type|is not defined|cannot assign|Unable to assign|non-existent" \
    "$R/qs.log" | grep -v "background effect\|host portal\|Gtk-WARNING\|Locale not supported" || true
}
tray_count() { ipc svc.tray | python3 -c 'import json, sys; d = json.load(sys.stdin) or {}; print(len(d.get("items") or []))' 2>/dev/null || echo 0; }

SCENE_PIDS=()
FIX_PID=""
stop_scene() { # stops the scene's daemon, frontend and fake items (the fixture server stays up for the whole run)
  local p
  for p in ${SCENE_PIDS[@]+"${SCENE_PIDS[@]}"}; do kill "$p" 2>/dev/null || true; done
  for p in ${SCENE_PIDS[@]+"${SCENE_PIDS[@]}"}; do wait "$p" 2>/dev/null || true; done
  SCENE_PIDS=()
  rm -f "$KURASHI_SOCKET"
}
cleanup() {
  stop_scene
  [ -n "$FIX_PID" ] && kill "$FIX_PID" 2>/dev/null || true
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# start_daemon <locale>: a fresh daemon (no config, no mods, no saved places); the hello test mod's files in its data dir.
start_daemon() {
  rm -rf "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME/kurashi/mods/hello"
  cp -r "$HELLO/qml" "$XDG_DATA_HOME/kurashi/mods/hello/"
  cp "$HELLO/live.mod.toml" "$XDG_DATA_HOME/kurashi/mods/hello/mod.toml"
  rm -f "$KURASHI_SOCKET"
  env LC_ALL="$1" KURASHI_WEATHER_API=http://127.0.0.1:8099 DBUS_SYSTEM_BUS_ADDRESS="unix:path=$R/no-system-bus" \
    "$W/kurashid" >> "$R/kurashid.log" 2>&1 &
  SCENE_PIDS+=("$!")
  for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && K ping >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "kurashid did not come up (see $R/kurashid.log)"
}
# enable_mods: the three mod widgets, sysmon, weather (with the fixture's place) and hello.
enable_mods() {
  K act mod.enable '{"id":"sysmon"}' >/dev/null || fail "mod.enable sysmon failed"
  K act mod.enable '{"id":"weather"}' >/dev/null || fail "mod.enable weather failed"
  K act weather.place.add "$WEATHER_TOKYO" >/dev/null || fail "weather.place.add failed"
  K act mod.enable '{"id":"hello"}' >/dev/null || fail "mod.enable hello failed"
}
# start_tray <count>: fake StatusNotifierItems on the sandbox's bus, registered with the tray host; the host must list them.
start_tray() {
  : > "$R/sni.log"
  python3 -I "$W/sni.py" "$1" >> "$R/sni.log" 2>&1 &
  SCENE_PIDS+=("$!")
  for _ in $(seq 100); do grep -q "items registered" "$R/sni.log" && break; sleep 0.1; done
  grep -q "items registered" "$R/sni.log" || fail "the fake items did not register (see $R/sni.log)"
  for _ in $(seq 50); do [ "$(tray_count)" -ge "$1" ] && return 0; sleep 0.2; done
  fail "the tray host lists $(tray_count) items, not $1 (see $R/kurashid.log)"
}

# scene <name> <edge> <height> <mods> <tray> <locale> <hidden>: one daemon and frontend; the geometry asserts, the shots, the log.
#   hidden 1: the column must hide items (a count is drawn); 0: every default item fits.
scene() {
  local name=$1 edge=$2 height=$3 mods=$4 tray=$5 locale=$6 hidden=$7 width=1920
  [ "$height" = 720 ] && width=1280
  echo "== scene $name: $edge bar, ${width}x${height}, $mods mod widgets, $tray tray items, locale $locale"
  stop_scene
  : > "$R/qs.log"
  timeout 20 swaymsg output HEADLESS-1 resolution "${width}x${height}" >/dev/null || fail "the output did not take ${width}x${height}"
  start_daemon "$locale"
  K set bar.edge "$edge" >/dev/null || fail "bar.edge $edge was refused"
  # The fit arithmetic below counts the column's own slots; the sidebars' end buttons (I154) are tested in
  # test-sidebar-panel.sh.
  K set sidebar.bar_buttons false >/dev/null || fail "sidebar.bar_buttons was refused"
  [ "$mods" = 0 ] || enable_mods
  env -u KURASHI_SOCKET KURASHI_BAR_GEOMETRY=1 LC_ALL="$locale" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  SCENE_PIDS+=("$!")
  sleep 4
  [ "$tray" = 0 ] || start_tray "$tray"
  sleep 3
  python3 -I "$W/geo.py" "$R/qs.log" "$height" "$mods" "$tray" "$hidden" > "$R/geo.out" 2>&1 || true
  [ -s "$R/geo.out" ] || check 0 "$name: the geometry check printed nothing (see $R/qs.log)"
  while IFS= read -r line; do
    case "$line" in
      "ok "*) check 1 "$name: ${line#ok }" ;;
      "FAIL "*) check 0 "$name: ${line#FAIL }" ;;
    esac
  done < "$R/geo.out"
  timeout 20 grim -o HEADLESS-1 "$OUT/$name.png" || fail "grim failed on $name"
  if [ "$edge" = left ]; then
    timeout 20 grim -g "0,0 96x$height" "$OUT/$name-bar.png" || fail "grim failed on $name's bar"
  else
    timeout 20 grim -g "$((width - 96)),0 96x$height" "$OUT/$name-bar.png" || fail "grim failed on $name's bar"
  fi
  local problems
  problems=$(qs_problems)
  if [ -z "$problems" ]; then
    check 1 "$name: the frontend logs no QML error or warning"
  else
    echo "$problems" | head -5
    check 0 "$name: the frontend logs QML errors or warnings"
  fi
}

want_part() { [[ " ${SIDEBARS_PARTS:-bars morph} " == *" $1 "* ]]; }

if want_part bars; then
  if [ "$TEST_MODS" = 1 ]; then
    # The weather fixture (Tokyo's forecast and search) on 8099 for the whole run.
    python3 -I -m http.server 8099 --bind 127.0.0.1 --directory "$R/weather" > "$R/fixture.log" 2>&1 &
    FIX_PID=$!
    sleep 1

    scene left-default left 1080 0 0 C.UTF-8 0
    scene left-long left 1080 3 12 C.UTF-8 1
    scene left-720 left 720 3 12 C.UTF-8 1
    scene right-long right 1080 3 12 C.UTF-8 1
    scene right-default right 1080 0 0 C.UTF-8 0
    scene left-ja left 1080 3 12 ja_JP.UTF-8 1
    stop_scene
  else
    echo "test-sidebars: SKIP the side-bar scenes: $BIN/kurashid links no test mod (build it with --features test-mods)"
  fi
fi

# ---- W34 (docs/ux/motion.md "the bar reaches out"): the sidebars grow out of the bar and fold back into it ----
# One daemon and frontend (KURASHI_SIDEBAR_FREEZE: the morph holds still N ms after it starts, for a shot; the frontend
# logs it). For each bar edge (top, bottom), look (washi, sekai, kami), profile (calm, lively) and side (left, right):
# frames at 40/120/250 ms of the opening, the column at rest and 40/120/250 ms of the closing, as one sheet
# frontend/shots/sidebar/morph/<edge>-<look>-<profile>-<side>.png (half size; read them). Asserted: every frozen frame
# is mid-morph (opening: the shape has not reached rest at 40 ms; closing: it has left it) and the window comes and goes;
# at rest the fillet's pixels at the column's inner top corner are the column's colour and, where the bar draws a strip,
# the bar's (one sheet); `none` cuts (the column is whole the frame after its window maps); a click outside the column
# closes it and one on the column does not (I152); 20 open/close cycles leave the frontend's USS where it was (K16);
# an open sidebar at rest commits no frame (Ma). MORPH_EDGES / MORPH_LOOKS / MORPH_PROFILES / MORPH_SIDES narrow it.
MOUT=$ROOT/frontend/shots/sidebar/morph
MBG='#8fb8c8'
nlines() { grep -c -- "$1" "$R/qs.log" || true; }
wait_more() { # wait_more <pattern> <count before> [tries of 50 ms]
  local i
  for i in $(seq "${3:-100}"); do [ "$(nlines "$1")" -gt "$2" ] && return 0; sleep 0.05; done
  return 1
}
last_window_of() { grep -oE "sidebar-window (up|down) $1" "$R/qs.log" | tail -1 | awk '{print $2}'; }
toggle() { K act sidebar.toggle "{\"side\":\"$1\",\"output\":\"HEADLESS-1\"}" >/dev/null; }
uidoc() { ipc runtime.ui; }
morph_frontend() { # morph_frontend [env assignments…]: a fresh frontend with the sidebar's test hooks
  local p
  for p in ${QS_PID:-}; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  : > "$R/qs.log"
  : > "$W/freeze"
  env -u KURASHI_SOCKET KURASHI_SIDEBAR_GEOMETRY=1 KURASHI_SIDEBAR_FREEZE="$W/freeze" "$@" qs -p "$ROOT/frontend" >> "$R/qs.log" 2>&1 &
  QS_PID=$!
  SCENE_PIDS+=("$QS_PID")
  sleep 4
}
# open_rest <side> / close_down <side>: one toggle, waiting for the column at rest or the window gone.
open_rest() {
  local n; n=$(nlines "sidebar-rest $1 ")
  toggle "$1"
  wait_more "sidebar-rest $1 " "$n" 80 || { check 0 "$TAG: the $1 sidebar did not come to rest"; return 1; }
  sleep 0.35   # the content's fade (160 ms) and a frame
}
close_down() {
  local n; n=$(nlines "sidebar-window down $1")
  toggle "$1"
  wait_more "sidebar-window down $1" "$n" 80 || { check 0 "$TAG: the $1 sidebar's window did not go"; return 1; }
}
# frozen <side> <open|close> <ms> <file>: the toggle with a freeze at <ms>; the frame half size into <file>.
FROZEN=""
frozen() {
  local n x=0; n=$(nlines "sidebar-frozen $1 ")
  [ "$1" = right ] && x=$((SW - 600))
  echo "$2 $3 900" > "$W/freeze"
  toggle "$1"
  if ! wait_more "sidebar-frozen $1 " "$n" 60; then
    : > "$W/freeze"
    # A lively fold can be over before a late freeze: then the window must be gone.
    if [ "$2" = close ] && [ "$(last_window_of "$1")" = down ]; then
      check 1 "$TAG: folded before $3 ms (its window is gone)"
      timeout 20 grim -s 0.5 -g "$x,0 600x$SH" "$4" || fail "grim failed"
    else
      check 0 "$TAG: no frozen frame at $2 $3 ms"
    fi
    return 1
  fi
  timeout 20 grim -s 0.5 -g "$x,0 600x$SH" "$4" || fail "grim failed"
  : > "$W/freeze"
  FROZEN=$(grep "sidebar-frozen $1 " "$R/qs.log" | tail -1 | sed 's/.*sidebar-frozen //')
}
# The column at rest: its rect in the window (geometry log) and where the window sits on the output.
geom_rest() { grep "sidebar-geom HEADLESS-1 $1 " "$R/qs.log" | tail -1 | sed 's/.*sidebar-geom //'; }
cat > "$W/join.py" <<'PY'
# join.py PPM EDGE SIDE X Y W H WINY BARH OW STRIP: the join of a column at rest. PPM is the whole output. The column's
# rect (X, Y, W, H) is in its window, whose top lies at WINY on the output. The fillet's pixels (just outside the column's
# inner top corner, on the bar's edge), the column's own (just inside its edge) and, with STRIP 1, the bar strip's (just
# past its rule): medians of three, compared channel by channel. Prints "ok …" / "FAIL …".
import sys
ppm, edge, side = sys.argv[1], sys.argv[2], sys.argv[3]
X, Y, W, H, winy, barh, ow, strip = (int(v) for v in sys.argv[4:12])
data = open(ppm, "rb").read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace():
        i += 1
    j = i
    while not data[j:j + 1].isspace():
        j += 1
    fields.append(data[i:j])
    i = j
sw, sh = int(fields[1]), int(fields[2])
px = data[i + 1:]
def at(x, y):
    o = (y * sw + x) * 3
    return tuple(px[o:o + 3])
def med(pts):
    cs = [at(x, y) for x, y in pts]
    return tuple(sorted(c[k] for c in cs)[len(cs) // 2] for k in range(3))
# The bar's edge on the output and the direction into the column (down under a top bar, up over a bottom one).
if edge == "top":
    e, d = winy, 1
else:
    e, d = winy + Y + H, -1
# Into the column from its inner side: right sidebar's inner side is its left edge.
if side == "right":
    xi, s = X, -1
else:
    xi, s = X + W - 1, 1
fil = med([(xi + s * 1, e + d * 1 if d > 0 else e - 2), (xi + s * 2, e + d * 1 if d > 0 else e - 2), (xi + s * 1, e + d * 2 if d > 0 else e - 3)])
col = med([(xi - s * k, e + (1 if d > 0 else -2)) for k in (8, 9, 10)])
bar = med([(xi + s * k, e - (ow + 3) if d > 0 else e + ow + 2) for k in (40, 41, 42)])
def close(a, b, tol=14):
    return max(abs(a[k] - b[k]) for k in range(3)) <= tol
bad = False
print(("ok" if close(fil, col) else "FAIL") + " the fillet %s is the column's colour %s" % (fil, col))
bad |= not close(fil, col)
if strip:
    print(("ok" if close(fil, bar) else "FAIL") + " the fillet %s is the bar strip's colour %s" % (fil, bar))
    bad |= not close(fil, bar)
sys.exit(1 if bad else 0)
PY
cat > "$W/mid.py" <<'PY'
# mid.py PHASE MS LINE: whether a frozen frame (the frontend's "sidebar-frozen" line: side, phase, ms, mw=…, mh=…) is
# mid-morph: opening at 40 ms both springs are short of rest; closing, the shape has left its rest.
import re, sys
phase, ms, line = sys.argv[1], int(sys.argv[2]), sys.argv[3]
mw = float(re.search(r"mw=(-?[0-9.]+)", line).group(1))
mh = float(re.search(r"mh=(-?[0-9.]+)", line).group(1))
if phase == "open":
    ok = (mw < 0.95 and mh < 0.95) if ms <= 40 else (mw > 0.05 and mh > 0.05)
else:
    ok = mw < 0.999 or mh < 0.999
print(("ok" if ok else "FAIL") + " %s %d ms: mw=%.3f mh=%.3f" % (phase, ms, mw, mh))
sys.exit(0 if ok else 1)
PY
morph_config() { # morph_config <edge> <look> <profile>
  K set bar.edge="$1" theme.style="$2" theme.motion.profile="$3" >/dev/null || fail "config $1 $2 $3 was refused"
  sleep 1.5
}
if want_part morph; then
  echo "== morph: the sidebars grow out of the bar"
  stop_scene
  mkdir -p "$MOUT"
  timeout 20 swaymsg output HEADLESS-1 resolution 1920x1080 >/dev/null || fail "the output did not take 1920x1080"
  swaymsg output '*' bg "$MBG" solid_color >/dev/null 2>&1 || true
  SW=1920 SH=1080
  start_daemon C.UTF-8
  morph_frontend
  HAVE_MAGICK=0; command -v magick >/dev/null && HAVE_MAGICK=1
  for edge in ${MORPH_EDGES-top bottom}; do
    for look in ${MORPH_LOOKS:-washi sekai kami}; do
      for prof in ${MORPH_PROFILES:-calm lively}; do
        morph_config "$edge" "$look" "$prof"
        for side in ${MORPH_SIDES:-right left}; do
          TAG="$edge-$look-$prof-$side"
          frames=()
          for t in 40 120 250; do
            f="$R/m-$TAG-open-$t.png"
            n=$(nlines "sidebar-rest $side ")
            if frozen "$side" open "$t" "$f"; then
              frames+=("$f")
              line=$(python3 -I "$W/mid.py" open "$t" "$FROZEN") && check 1 "$TAG: $line" || check 0 "$TAG: $line"
            fi
            wait_more "sidebar-rest $side " "$n" 80 || check 0 "$TAG: the opening did not come to rest after its freeze"
            sleep 0.2
            close_down "$side" || true
          done
          open_rest "$side" || continue
          f="$R/m-$TAG-rest.png"
          timeout 20 grim -s 0.5 -g "$([ "$side" = right ] && echo $((SW - 600)) || echo 0),0 600x$SH" "$f" && frames+=("$f")
          # The join at rest: the fillet's pixels against the column's and the bar strip's.
          read -r _ _ _ _ WW WH _ FR _ BEDGE BARH _ <<< "$(geom_rest "$side")"
          IFS=, read -r FX FY FW FH <<< "$FR"
          WINY=0; [ "$BEDGE" = top ] && WINY=$((SH - WH))
          STRIP=1; [ "$look" = sekai ] && STRIP=0   # keycap groups float on the desk: no strip
          timeout 20 grim -t ppm "$R/rest.ppm" || fail "grim failed"
          while IFS= read -r line; do
            case "$line" in ok*) check 1 "$TAG: ${line#ok }" ;; FAIL*) check 0 "$TAG: ${line#FAIL }" ;; esac
          done < <(python3 -I "$W/join.py" "$R/rest.ppm" "$BEDGE" "$side" "$FX" "$FY" "$FW" "$FH" "$WINY" "$BARH" 3 "$STRIP" || true)
          [ "$look" = washi ] && [ "$prof" = calm ] && cp "$R/rest.ppm" "$R/rest-$TAG.ppm"
          close_down "$side" || true
          for t in 40 120 250; do
            open_rest "$side" || break
            f="$R/m-$TAG-close-$t.png"
            n=$(nlines "sidebar-window down $side")
            rm -f "$f"
            rc=0; frozen "$side" close "$t" "$f" || rc=$?
            [ -f "$f" ] && frames+=("$f")
            if [ "$rc" = 0 ]; then
              line=$(python3 -I "$W/mid.py" close "$t" "$FROZEN") && check 1 "$TAG: $line" || check 0 "$TAG: $line"
            fi
            wait_more "sidebar-window down $side" "$n" 80 || check 0 "$TAG: the window stayed after the fold"
            sleep 0.2
          done
          if [ "$HAVE_MAGICK" = 1 ] && [ "${#frames[@]}" -gt 0 ]; then
            magick "${frames[@]}" +append "$MOUT/$TAG.png" && echo "shot $MOUT/$TAG.png"
          else
            for f in "${frames[@]}"; do cp "$f" "$MOUT/$(basename "${f#"$R"/m-}")"; done
          fi
        done
      done
    done
  done

  # `none` cuts: the column is whole on the first frames after its window maps, and goes with its window.
  TAG=none
  morph_config top washi none
  n=$(nlines "sidebar-window up right")
  toggle right
  wait_more "sidebar-window up right" "$n" 60 || check 0 "none: no window"
  sleep 0.12
  timeout 20 grim -s 0.5 -g "$((SW - 600)),0 600x$SH" "$MOUT/none-right-open.png"
  timeout 20 grim -g "$((SW - 410)),$((SH - 2)) 1x1" -t ppm "$R/px.ppm"
  [ "$(python3 -I - "$R/px.ppm" "$MBG" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
p = data[-3:]
B = tuple(int(sys.argv[2].lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
print("desk" if max(abs(p[k] - B[k]) for k in range(3)) <= 24 else "ink")
PY
)" = ink ] && check 1 "none: the column reaches the screen's bottom at once" || check 0 "none: the column is not whole at once"
  close_down right && check 1 "none: the window goes with the close" || true

  # I152: a click outside closes, one on the column does not.
  morph_config top washi calm
  rm -f "$W/ptr"; mkfifo "$W/ptr"
  python3 -I "$ROOT/tools/bench/wl_pointer.py" --serve < "$W/ptr" >> "$W/ptr.log" 2>&1 &
  SCENE_PIDS+=("$!")
  exec 7> "$W/ptr"
  open_rest right
  echo "click $((SW - 420 + 4)) $((SH / 2)) left" >&7; sleep 0.8
  uidoc | jq -e '.sidebar == "right"' >/dev/null && check 1 "a click on the column keeps it open" \
    || check 0 "a click on the column closed it ($(uidoc))"
  n=$(nlines "sidebar-window down right")
  echo "click 400 $((SH / 2)) left" >&7; sleep 0.8
  uidoc | jq -e 'has("sidebar") | not' >/dev/null && check 1 "a click outside the column closes it" \
    || check 0 "a click outside did not close it ($(uidoc))"
  wait_more "sidebar-window down right" "$n" 40 && check 1 "… and its window goes" || check 0 "the window stayed after a click outside"
  open_rest left
  echo "click $((SW - 300)) $((SH / 2)) left" >&7; sleep 0.8
  uidoc | jq -e 'has("sidebar") | not' >/dev/null && check 1 "a click outside the left sidebar closes it" \
    || check 0 "a click outside the left sidebar did not close it ($(uidoc))"
  exec 7>&-

  # K16: 20 open/close cycles; the frontend's USS after them against after the first.
  uss() { awk '/^Private_(Clean|Dirty):/ { s += $2 } END { print s }' "/proc/$QS_PID/smaps_rollup"; }
  open_rest right; close_down right
  sleep 1; U0=$(uss)
  for i in $(seq 20); do open_rest right || break; close_down right || break; done
  sleep 2; U1=$(uss)
  echo "test-sidebars: USS after 1 cycle $((U0 / 1024)) MiB, after 21 cycles $((U1 / 1024)) MiB ($(( (U1 - U0) / 1024 )) MiB)"
  [ $((U1 - U0)) -le $((6 * 1024)) ] && check 1 "20 open/close cycles: USS $(( (U1 - U0) / 1024 )) MiB (≤ 6 MiB)" \
    || check 0 "20 open/close cycles grew the USS by $(( (U1 - U0) / 1024 )) MiB"

  # Ma: an open sidebar at rest commits no frame.
  morph_frontend WAYLAND_DEBUG=1
  open_rest right
  sleep 1
  s=$(stat -c %s "$R/qs.log"); sleep 5
  c=$(tail -c +"$((s + 1))" "$R/qs.log" | grep -c 'wl_surface#[0-9]*\.commit(' || true)
  [ "$c" = 0 ] && check 1 "the open sidebar at rest commits no frame in 5 s" || {
    tail -c +"$((s + 1))" "$R/qs.log" | grep -oE 'wl_surface#[0-9]+\.commit\(' | sort | uniq -c | head
    grep -E "sidebar-|kurashi-" "$R/qs.log" | tail -5
    check 0 "the open sidebar at rest committed $c frames in 5 s"; }
  close_down right

  problems=$(qs_problems | grep -v "wl_\|zwlr\|xdg_\|wp_\|ext_" || true)
  [ -z "$problems" ] && check 1 "morph: the frontend logs no QML error or warning" \
    || { echo "$problems" | head -5; check 0 "morph: the frontend logs QML errors or warnings"; }
  stop_scene
fi
[ "$FAILS" = 0 ] || fail "$FAILS check(s) failed"
echo "test-sidebars: all checks passed"
