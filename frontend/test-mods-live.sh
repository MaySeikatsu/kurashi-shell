#!/usr/bin/env bash
# Every bundled mod and the test mod `hello` through the real shell (W14, BACKLOG I21, I34), invisibly: the real kurashid
# built with `--features test-mods` (it links `hello`), an isolated XDG and data dir holding a copy of the checkout's
# frontend, i18n and mods, and the frontend in the headless sway sandbox. Per mod, in turn: `mod.enable`; the `qml` the
# daemon lists is exactly the files its manifest provides; the widget loads in the bar; the panel opens with
# `mod.panel.open` and is drawn as a card; each slot loads in its host view iff runtime.slots says it is ready; the face
# is raised by the mod's test action where it has one (hello); `mod.disable`; every component the mod loaded is released.
# Two mods (media, easter-eggs) have no native crate: enabling them must load nothing. Checks for the whole run: no QML
# warning, binding loop or error in qs.log; no raw i18n key drawn in the window of a mod component (MODRAW); the static
# guard: every relative import in a mod stays inside the mod (a mod that imports the shell core by path gets a second,
# empty Store/Theme/I18n: its keys show raw, and the MODRAW walk catches that).
#
# The frontend that runs is a copy in the sandbox data dir with log lines added and nothing else changed:
#   I18n.tr    logs `I18N MISS <key>` for a key the daemon's i18n document lacks (once it arrived; informational only,
#              a missing key is not always drawn: weather's panel asks for keys it does not show without a place);
#   ModLoader  logs `MODLOAD <url>`, `MODUNLOAD <url>` (also when its item is destroyed with its view) and, from the
#              window of the mod component, `MODRAW <url> "<text>"` for every visible text that is a raw i18n key of a
#              known domain or shows undefined/NaN/null.
# Screenshots: frontend/shots/modslive/. Usage (machine B):
#   KURASHI_RENDER_NODE=/dev/dri/renderD129 KURASHI_BIN_DIR=<dir with kurashid (test-mods) and kurashi> \
#     timeout 1500 nix develop -c frontend/test-mods-live.sh [sandbox-name]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-modslive-$$}   # unique per run: other agents' runs stop any sandbox that shares a name
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
HELLO_SRC=$ROOT/crates/kurashid/tests/data/mods/hello
OUT=$ROOT/frontend/shots/modslive
mkdir -p "$OUT"
fail() { echo "test-mods-live: $*" >&2; exit 1; }

eval "$("$ROOT/tools/bench/sandbox.sh" start "$NAME")"
R=$XDG_RUNTIME_DIR
W=$R/work
DATA=$R/data
# The wayland socket can appear before the compositor serves clients (slow under load): wait until sway answers.
for _ in $(seq 150); do timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 && break; sleep 0.2; done
timeout 5 swaymsg -t get_outputs >/dev/null 2>&1 || fail "the headless compositor does not answer (see $R/sway.log)"
# The runtime dir is reused by a later run of the same sandbox: its logs and data copy start empty.
rm -rf "$DATA" "$R/qs.log" "$R/server.log"
mkdir -p "$W" "$R/kurashi" "$DATA"
cp "$BIN/kurashi" "$BIN/kurashid" "$W/"
grep -aq 'hello.raise' "$W/kurashid" || fail "$BIN/kurashid links no test mod: build it with --features test-mods"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
  "$ROOT/tools/bench/sandbox.sh" stop "$NAME" >/dev/null || true
}
trap cleanup EXIT

# Hermetic: no config, state or cache from an earlier run; the system bus is not reachable (only the sandbox's session bus).
rm -rf "$R/xdg"
export XDG_CONFIG_HOME=$R/xdg/config XDG_STATE_HOME=$R/xdg/state XDG_DATA_HOME=$R/xdg/data XDG_CACHE_HOME=$R/xdg/cache
export KURASHI_DATA_DIR=$DATA LC_ALL=C.UTF-8 DBUS_SYSTEM_BUS_ADDRESS=unix:path=$R/no-system-bus
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME/kurashi/mods/hello" "$XDG_CACHE_HOME"
tar -C "$ROOT" --exclude=frontend/shots -cf - frontend i18n mods palettes | tar -C "$DATA" -xf -
# The test mod: the checkout's qml with the live manifest (mod.toml stays footer-only for tests/native_mods.rs).
cp -r "$HELLO_SRC/qml" "$XDG_DATA_HOME/kurashi/mods/hello/"
cp "$HELLO_SRC/live.mod.toml" "$XDG_DATA_HOME/kurashi/mods/hello/mod.toml"

# ---- helpers written into the sandbox: the static guard, the log and PPM analysis, and the instrumentation.
cat > "$W/tool.py" <<'PY'
"""Helpers for frontend/test-mods-live.sh (stdlib only; run with python3 -I)."""
import json
import os
import pathlib
import re
import sys
import tomllib

ANSI = re.compile(r"\x1b\[[0-9;]*m")
MOD_LOG = re.compile(r"MOD(LOAD|UNLOAD) (file://\S+)")


def guard(mods_root, hello_dir):
    imp = re.compile(r'^\s*import\s+"([^"]+)"', re.M)
    roots = [p for p in sorted(pathlib.Path(mods_root).iterdir()) if p.is_dir()]
    roots.append(pathlib.Path(hello_dir))
    bad, files = [], 0
    for root in roots:
        base = root.resolve()
        qml = base / "qml"
        if not qml.is_dir():
            continue
        for f in sorted(qml.rglob("*.qml")):
            files += 1
            for m in imp.finditer(f.read_text(encoding="utf-8")):
                target = m.group(1)
                if "://" in target or target.startswith("/"):
                    bad.append(f'{f}: import "{target}" is not a path inside the mod')
                    continue
                res = os.path.normpath(os.path.join(str(f.parent), target))
                if res != str(base) and not res.startswith(str(base) + os.sep):
                    bad.append(f'{f}: import "{target}" leaves {base.name}/ '
                               "(the shell core is imported as qs.core / qs.components)")
    if bad:
        print("\n".join(bad))
        return 1
    print(f"static guard: {files} mod QML files; every relative import stays inside its mod")
    return 0


# The provide kinds that become `qml` keys (the daemon's qml_of, native.rs): each kind's component files under the mod's
# qml/, the key taking the suffix. Every other kind is no component: a service, an action, a palette, a decor, a launcher,
# choices, a job, a host, the i18n block. The kinds the daemon parses are read from its source (kurashi-mods manifest.rs),
# so a kind it gains fails this run until it is classified here (I67).
QML_FILES = {
    "widget": [("", "Widget.qml")],
    "panel": [("", "Panel.qml")],
    "peek": [("", "Peek.qml")],
    "island-face": [("", "Face.qml"), (":expanded", "FaceExpanded.qml")],
    "slot": [("", "slots/{name}.qml")],
    # K38 row 88: a mod's own per-output surface (the web dock).
    "surface": [("", "surfaces/{name}.qml")],
    # K46 row 120: a card on the desktop widget column.
    "desk": [("", "desk/{name}.qml")],
}
NO_QML = {"service", "action", "palette", "decor", "launcher", "choices", "job", "host", "i18n"}


def daemon_kinds(manifest_rs):
    """The kinds `Provide::parse` maps in the daemon's source."""
    text = pathlib.Path(manifest_rs).read_text(encoding="utf-8")
    return set(re.findall(r'"([a-z-]+)" => Self::', text)) | {"i18n"}


def expect(moddir, manifest, manifest_rs):
    """The `qml` keys the daemon must list, from the mod's manifest (its provides, read from mod.toml rather than from the
    daemon's document), and the slots the mod contributes."""
    unclassified = daemon_kinds(manifest_rs) - set(QML_FILES) - NO_QML
    if unclassified:
        raise SystemExit(f"the daemon maps provide kinds this test does not classify: {sorted(unclassified)}")
    qml = pathlib.Path(moddir) / "qml"
    provides = tomllib.loads(pathlib.Path(manifest).read_text(encoding="utf-8")).get("provides", [])
    keys, slots = [], []
    for p in provides:
        kind, _, name = p.partition(":")
        if kind in NO_QML:
            continue
        if kind not in QML_FILES:
            raise SystemExit(f"provide {p!r} is of a kind this test does not classify")
        for suffix, rel in QML_FILES[kind]:
            if (qml / rel.format(name=name)).is_file():
                keys.append(p + suffix)
        if kind == "slot" and (qml / "slots" / f"{name}.qml").is_file():
            slots.append(name)
    print(json.dumps({"keys": sorted(keys), "slots": slots}))
    return 0


def read_ppm(data):
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P6" or fields[3] != b"255":
        raise SystemExit(f"not an 8-bit P6 image: {fields}")
    return int(fields[1]), int(fields[2]), data[i + 1:]


def card(ppm, surface):
    """Pixels of the surface colour in the band under the bar (where cards are drawn): count and bounding box."""
    t = [int(surface.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    w, h, raster = read_ppm(pathlib.Path(ppm).read_bytes())
    n, x0, y0, x1, y1 = 0, 1 << 30, 1 << 30, -1, -1
    for y in range(40, min(1000, h)):
        row = y * w * 3
        for x in range(640, min(1920, w)):
            o = row + x * 3
            if abs(raster[o] - t[0]) <= 3 and abs(raster[o + 1] - t[1]) <= 3 and abs(raster[o + 2] - t[2]) <= 3:
                n += 1
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, y), max(y1, y)
    print(json.dumps({"surface": n, "bbox": [x0, y0, x1, y1] if n else None, "width": w}))
    return 0


def lines_of(qslog):
    return [ANSI.sub("", ln) for ln in open(qslog, encoding="utf-8", errors="replace").read().splitlines()]


def count(qslog, start, kind, mod_id, rel):
    """Loads or unloads of the mod's components (URLs under mods/<id>/qml/, ending in rel when given) after line start."""
    want = "LOAD" if kind == "load" else "UNLOAD"
    n = 0
    for ln in lines_of(qslog)[int(start):]:
        m = MOD_LOG.search(ln)
        if not m or m.group(1) != want:
            continue
        url = m.group(2)
        if f"/mods/{mod_id}/qml/" in url and (not rel or url.endswith("/qml/" + rel)):
            n += 1
    print(n)
    return 0


def balance(qslog, mod_id):
    """Every component the mod loaded is released: per URL, loads minus unloads is zero."""
    nets, loads, unloads = {}, 0, 0
    for ln in lines_of(qslog):
        m = MOD_LOG.search(ln)
        if not m or f"/mods/{mod_id}/qml/" not in m.group(2):
            continue
        d = 1 if m.group(1) == "LOAD" else -1
        nets[m.group(2)] = nets.get(m.group(2), 0) + d
        loads += d == 1
        unloads += d == -1
    live = {u: n for u, n in nets.items() if n}
    print(json.dumps({"mod": mod_id, "loads": loads, "unloads": unloads, "live": live}))
    return 1 if live else 0


def raw(qslog, start=0):
    hits = [ln for ln in lines_of(qslog)[int(start):] if "MODRAW " in ln]
    print("\n".join(h.rstrip() for h in hits))
    return 1 if hits else 0


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "count":
        sys.exit(count(args[0], args[1], args[2], args[3], args[4] if len(args) > 4 else ""))
    fn = {"guard": guard, "expect": expect, "card": card, "balance": balance, "raw": raw}[cmd]
    sys.exit(fn(*args))
PY

cat > "$W/instrument.py" <<'PY'
"""Adds the log lines the test reads to the copy of the frontend core under the sandbox (behaviour unchanged)."""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def patch(name, old, new):
    p = root / name
    text = p.read_text()
    if text.count(old) != 1:
        sys.exit(f"instrumentation: {name} changed ({text.count(old)} matches): {old[:60]!r}")
    p.write_text(text.replace(old, new))


patch(
    "I18n.qml",
    'function tr(key) { var s = strings[key]; return s === undefined ? key : s }',
    'function tr(key) { var s = strings[key]; if (s === undefined) { if (Object.keys(strings).length > 0) '
    'console.log("I18N MISS " + key); return key } return s }',
)
patch(
    "ModLoader.qml",
    '    function refresh() {\n        var want = shown ? resolved : ""\n        if (want === String(source)) return\n'
    '        if (want === "") { source = ""; return }\n'
    '        setSource(want, { store: Store, theme: Theme, i18n: I18n })\n    }',
    '    function refresh() {\n        var want = shown ? resolved : ""\n        if (want === String(source)) return\n'
    '        if (String(source) !== "") console.log("MODUNLOAD " + String(source))\n'
    '        if (want === "") { source = ""; return }\n'
    '        console.log("MODLOAD " + want)\n'
    '        setSource(want, { store: Store, theme: Theme, i18n: I18n })\n    }',
)
patch(
    "ModLoader.qml",
    '    onStatusChanged: if (status === Loader.Error) console.warn("ModLoader: cannot load " + source)',
    '    onStatusChanged: if (status === Loader.Error) console.warn("ModLoader: cannot load " + source)\n'
    '    // test instrumentation (frontend/test-mods-live.sh)\n'
    '    Component.onDestruction: if (String(source) !== "") console.log("MODUNLOAD " + String(source))\n'
    '    property var probeSeen: ({})\n'
    '    Timer {\n        interval: 800\n        repeat: true\n'
    '        running: String(ml.source) !== "" && ml.status === Loader.Ready\n'
    '        onTriggered: ml.probeText()\n    }\n'
    '    function probeText() {\n'
    '        var win = ml.Window ? ml.Window.window : null\n'
    '        var top = (win && win.contentItem) ? win.contentItem : ml.item\n'
    '        if (!top) return\n'
    '        var domains = {}\n'
    '        var keys = Object.keys(I18n.strings)\n'
    '        for (var k = 0; k < keys.length; k++) domains[keys[k].split(".")[0]] = true\n'
    '        var stack = [{ item: top, vis: true }]\n'
    '        while (stack.length) {\n'
    '            var n = stack.pop()\n'
    '            var it = n.item\n'
    '            var vis = n.vis && it.visible\n'
    '            if (vis && typeof it.text === "string" && it.text !== "" && it.width > 0 && it.height > 0) {\n'
    '                var t = it.text\n'
    '                var raw = /undefined|NaN|\\bnull\\b/.test(t)\n'
    '                    || (/^[a-z][a-z0-9_-]*(\\.[a-z0-9_-]*)+$/.test(t) && domains[t.split(".")[0]] === true)\n'
    '                if (raw && !ml.probeSeen[t]) {\n'
    '                    ml.probeSeen[t] = true\n'
    '                    console.log("MODRAW " + String(ml.source) + " " + JSON.stringify(t))\n'
    '                }\n'
    '            }\n'
    '            var kids = it.children\n'
    '            for (var i = 0; kids && i < kids.length; i++) stack.push({ item: kids[i], vis: vis })\n'
    '        }\n    }',
)
PY
python3 -I "$W/instrument.py" "$DATA/frontend/core"

# ---- the static guard: no mod imports the shell core, or anything else, by a path that leaves the mod.
python3 -I "$W/tool.py" guard "$ROOT/mods" "$HELLO_SRC" || fail "static guard: a mod imports outside itself"

# ---- the daemon and the frontend.
RUST_LOG=info "$W/kurashid" >> "$R/server.log" 2>&1 &
pids+=("$!")
for _ in $(seq 100); do [ -S "$KURASHI_SOCKET" ] && break; sleep 0.1; done
[ -S "$KURASHI_SOCKET" ] || fail "kurashid did not come up (see $R/server.log)"
env -u KURASHI_SOCKET qs -p "$DATA/frontend" >> "$R/qs.log" 2>&1 &
pids+=("$!")

K() { timeout 10 "$W/kurashi" "$@"; }
doc() { K sub "$1" --count 0 --json | jq -c '.data'; }
act() { K act "$1" "$2" >/dev/null || fail "action $1 $2 was refused"; }
mark() { wc -l < "$R/qs.log"; }
count() { python3 -I "$W/tool.py" count "$R/qs.log" "$1" "$2" "$3" "${4:-}"; }
settle() { sleep "${1:-1.5}"; }
mod_entry() { doc mods | jq -c --arg id "$1" '.mods[] | select(.id == $id)'; }
shot_full() { timeout 20 grim -o HEADLESS-1 "$OUT/$1.png" || fail "grim failed on $1"; }
bar_shot() { timeout 20 grim -g "0,0 2560x40" "$OUT/$1.png" || fail "grim failed on $1"; }

# Findings are recorded and the run goes on, so one run lists every defect it finds; the run fails at the end.
FINDINGS=()
finding() { echo "FINDING: $*" >&2; FINDINGS+=("$*"); }
CHECKED=0
# check_frontend <label>: the QML warnings, binding loops and errors in qs.log, and the raw i18n keys drawn in a mod's
# window (MODRAW), since the previous check (the windows are contiguous, so every line is checked once).
check_frontend() {
  local from=$CHECKED w r
  CHECKED=$(mark)
  # The QML warnings of test-modqml: any QML warning or error, binding loop, reference or type error.
  w=$(tail -n +"$((from + 1))" "$R/qs.log" | grep -E '(WARN|ERROR)[^:]*(qml|scene)|Binding loop|ReferenceError|TypeError|is not a function|Unable to assign|Expected a qualified' || true)
  if [ -n "$w" ]; then
    echo "$w" | head -10 >&2
    finding "$1: $(echo "$w" | wc -l) QML warning or error line(s), first: $(echo "$w" | head -1 | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-200)"
  fi
  r=$(python3 -I "$W/tool.py" raw "$R/qs.log" "$from") || { echo "$r" >&2; finding "$1: a raw i18n key is drawn in a mod's window"; }
}

sleep 4
# Wait for the frontend's first documents, then the card surface colour of this theme (color.surface_container).
SURFACE=$(doc theme | jq -r '.tokens["color.surface_container"] // "#252329"')
echo "surface colour: $SURFACE"

# A card of the surface colour, centred on the output (the Stage and the expanded Island), cropped as evidence.
card() {  # card <name>
  local res x0 y0 x1 y1
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
  res=$(python3 -I "$W/tool.py" card "$W/$1.ppm" "$SURFACE") || fail "$1: analysis failed"
  echo "  card $1: $res"
  jq -e '.surface >= 15000 and .bbox != null and (((.bbox[0] + .bbox[2]) / 2 - (.width / 2)) | fabs) <= 4' \
    <<<"$res" >/dev/null || fail "$1: no card centred on the output ($res)"
  read -r x0 y0 x1 y1 < <(jq -r '.bbox | "\(.[0]) \(.[1]) \(.[2]) \(.[3])"' <<<"$res")
  local cx=$((x0 - 24)) cy=$((y0 - 24))
  ((cx < 0)) && cx=0
  ((cy < 0)) && cy=0
  timeout 20 grim -g "$cx,$cy $((x1 - x0 + 49))x$((y1 - y0 + 49))" "$OUT/$1.png" || fail "grim failed on $1"
}
closed() {  # closed <name>: nothing of the surface colour is drawn under the bar (Ma)
  local res
  timeout 20 grim -o HEADLESS-1 -t ppm "$W/$1.ppm" || fail "grim failed on $1"
  res=$(python3 -I "$W/tool.py" card "$W/$1.ppm" "$SURFACE") || fail "$1: analysis failed"
  jq -e '.surface < 500' <<<"$res" >/dev/null || fail "$1: a card is still drawn ($res)"
}

# island_face <face>: cycles the island's main face (island.next) until it shows <face>; faces: runtime.island.main.
island_face() {
  local i
  for i in $(seq 12); do
    [ "$(doc runtime.island.main | jq -r .face)" = "$1" ] && return 0
    act island.next '{}'
    settle 0.8
  done
  fail "the island does not show $1 (main face: $(doc runtime.island.main | jq -r .face))"
}

# open_host <host>: the view that hosts a slot of this kind (clock, quick, media, notifications).
open_host() {
  case "$1" in
    clock) island_face clock; act island.expand '{}' ;;
    media) island_face media; act island.expand '{}' ;;
    notifications) island_face notifications; act island.expand '{}' ;;
    quick) act quick.toggle '{}' ;;
    *) fail "no host view for $1" ;;
  esac
  settle 2
}
close_host() { act ui.close '{}'; settle 1.5; }

# check_slots <id>: for each slot the mod contributes: loaded in its host iff the daemon says ready.
check_slots() {
  local id=$1 entries h hs slot ready m n
  entries=$(doc runtime.slots | jq -c --arg id "$id" '[to_entries[] | .key as $s | .value[] | select(.mod == $id) | {slot: $s, ready}]')
  for h in clock quick media notifications; do
    if [ "$h" = quick ]; then
      hs=$(jq -c '[.[] | select(.slot == "quick.tiles")]' <<<"$entries")
    else
      hs=$(jq -c --arg h "$h" '[.[] | select(.slot | startswith($h + "."))]' <<<"$entries")
    fi
    [ "$(jq length <<<"$hs")" -gt 0 ] || continue
    m=$(mark)
    open_host "$h"
    shot_full "$id-host-$h"
    while read -r slot ready; do
      n=$(count "$m" load "$id" "slots/$slot.qml")
      if [ "$ready" = true ]; then
        [ "$n" -ge 1 ] || fail "$id: slot $slot is ready but did not load in the $h view"
      else
        [ "$n" -eq 0 ] || fail "$id: slot $slot is not ready but loaded"
      fi
      echo "  slot $slot in $h: ready=$ready loads=$n"
    done < <(jq -r '.[] | "\(.slot) \(.ready)"' <<<"$hs")
    close_host
  done
}

# check_face <id> <raise action> <clear action>: the face the mod's test action raises shows and expands in the island.
check_face() {
  local id=$1 raise=$2 clear=$3 m n
  m=$(mark)
  act "$raise" '{"relevance":90}'
  settle 2
  [ "$(doc runtime.island.main | jq -r .face)" = "$id" ] || fail "$id: raised, the island does not show the face ($(doc runtime.island.main | jq -c '{face}'))"
  n=$(count "$m" load "$id" Face.qml); [ "$n" -ge 1 ] || fail "$id: the face did not load"
  shot_full "$id-face"
  m=$(mark)
  act island.expand '{}'
  settle 2
  n=$(count "$m" load "$id" FaceExpanded.qml); [ "$n" -ge 1 ] || fail "$id: the expanded face did not load"
  shot_full "$id-face-expanded"
  close_host
  m=$(mark)
  act "$clear" '{}'
  settle 2
  n=$(count "$m" unload "$id" Face.qml); [ "$n" -ge 1 ] || fail "$id: the cleared face was not released"
  echo "  face $id: raised, expanded, cleared"
}

disable_mod() {  # disable_mod <id>: off, nothing of it in the daemon's documents, every component released
  local id=$1 state
  act mod.disable "{\"id\":\"$id\"}"
  settle 2
  state=$(mod_entry "$id" | jq -r .state)
  [ "$state" != enabled ] || fail "$id: still enabled after mod.disable"
  [ "$(mod_entry "$id" | jq '(.qml // {}) | length')" = 0 ] || fail "$id: after mod.disable the mods document still lists qml"
  [ "$(doc runtime.slots | jq --arg id "$id" '[.. | objects | select(.mod? == $id)] | length')" = 0 ] \
    || fail "$id: after mod.disable runtime.slots still lists it"
  case "$(doc runtime.ui | jq -r .panel)" in
    "mod:$id:"*) fail "$id: its panel is still open" ;;
  esac
  python3 -I "$W/tool.py" balance "$R/qs.log" "$id" >&2 || finding "$id: a loaded component was not released"
  bar_shot "$id-off"
}

# mod_block <id> <mod dir> [raise clear]: enable, exercise every provide, disable.
mod_block() {
  local id=$1 dir=$2 entry provides exp got panel m n manifest
  echo "== $id"
  entry=$(mod_entry "$id")
  [ "$(jq -r .state <<<"$entry")" != enabled ] || fail "$id: on before the test ($(jq -c '{state,errors}' <<<"$entry"))"
  provides=$(jq -c .provides <<<"$entry")
  # The expected keys come from the manifest the daemon reads (the test mod's live one), not from the daemon's document.
  if [ -f "$dir/live.mod.toml" ]; then manifest=$dir/live.mod.toml; else manifest=$dir/mod.toml; fi
  exp=$(python3 -I "$W/tool.py" expect "$dir" "$manifest" "$ROOT/crates/kurashi-mods/src/manifest.rs")
  m=$(mark)
  act mod.enable "{\"id\":\"$id\"}"
  settle 2
  entry=$(mod_entry "$id")
  [ "$(jq -r .state <<<"$entry")" = enabled ] || fail "$id: not enabled ($(jq -c '{state,errors}' <<<"$entry"))"
  [ "$(jq -c .errors <<<"$entry")" = "[]" ] || fail "$id: errors $(jq -c .errors <<<"$entry")"
  got=$(jq -c '[.qml // {} | keys[]] | sort' <<<"$entry")
  [ "$got" = "$(jq -c .keys <<<"$exp")" ] || fail "$id: qml $got, the manifest and its files say $(jq -c .keys <<<"$exp")"
  echo "  qml: $got"
  if jq -e 'any(startswith("widget:"))' <<<"$provides" >/dev/null; then
    n=$(count "$m" load "$id" Widget.qml)
    [ "$n" -ge 1 ] || fail "$id: the bar widget did not load"
    echo "  widget: loads=$n"
    bar_shot "$id-widget"
  fi
  panel=$(jq -r '[.[] | select(startswith("panel:")) | sub("panel:"; "")][0] // empty' <<<"$provides")
  if [ -n "$panel" ]; then
    m=$(mark)
    act mod.panel.open "{\"id\":\"$id\",\"panel\":\"$panel\"}"
    settle 2.5
    [ "$(doc runtime.ui | jq -r .panel)" = "mod:$id:$panel" ] || fail "$id: the panel is not open ($(doc runtime.ui | jq -c .))"
    n=$(count "$m" load "$id" Panel.qml); [ "$n" -ge 1 ] || fail "$id: Panel.qml did not load"
    card "$id-panel"
    act ui.close '{}'
    settle 1.5
    closed "$id-panel-closed"
    n=$(count "$m" unload "$id" Panel.qml); [ "$n" -ge 1 ] || fail "$id: the closed panel was not released"
    echo "  panel $panel: loads=$(count "$m" load "$id" Panel.qml) released"
  fi
  # The face first: a manual choice of the island (island.next, as the host views use) is not displaced by a raised face.
  if [ "${3:-}" != "" ]; then
    check_face "$id" "$3" "$4"
  fi
  check_slots "$id"
  disable_mod "$id"
  check_frontend "$id"
}

# unlinked_block <id>: no native crate is linked for it. Enabling must load nothing: no qml, no slot, no component.
unlinked_block() {
  local id=$1 entry m state
  echo "== $id (no native crate linked)"
  m=$(mark)
  entry=$(mod_entry "$id")
  if [ "$(jq -r .state <<<"$entry")" != enabled ]; then
    act mod.enable "{\"id\":\"$id\"}"
    settle 2
  fi
  entry=$(mod_entry "$id")
  state=$(jq -r .state <<<"$entry")
  [ "$(jq '(.qml // {}) | length' <<<"$entry")" = 0 ] || fail "$id: lists qml without a linked crate"
  [ "$(doc runtime.slots | jq --arg id "$id" '[.. | objects | select(.mod? == $id)] | length')" = 0 ] \
    || fail "$id: lists slots without a linked crate"
  [ "$(count "$m" load "$id" "")" = 0 ] || fail "$id: a component loaded without a linked crate"
  echo "  state $state, qml none, slots none, loads 0"
  [ "$state" != enabled ] || finding "$id: state enabled while no native crate is linked (nothing runs; the mods page would show it on)"
  if [ "$id" != easter-eggs ]; then
    act mod.disable "{\"id\":\"$id\"}"
    settle 1
  fi
  check_frontend "$id"
}

# The mods with a native crate linked into this build (the test-mods feature); phases 1 and 3 use the list.
LINKED="weather sysmon wallpaper hello"
# Phase 1: each linked mod, one at a time.
echo "--- phase 1: the linked mods, one at a time"
shot_full start
mod_block weather "$ROOT/mods/weather"
mod_block sysmon "$ROOT/mods/sysmon"
mod_block wallpaper "$ROOT/mods/wallpaper"
mod_block hello "$HELLO_SRC" hello.raise hello.clear
# Phase 2: the mods that have no crate.
echo "--- phase 2: the mods without a native crate"
unlinked_block media
unlinked_block easter-eggs
# Phase 3: every linked mod on at once: the views with several contributions.
echo "--- phase 3: all linked mods on"
for id in $LINKED; do act mod.enable "{\"id\":\"$id\"}"; done
settle 3
island_face clock; act island.expand '{}'; settle 2; shot_full all-clock; close_host
act quick.toggle '{}'; settle 2; shot_full all-quick; close_host
island_face notifications; act island.expand '{}'; settle 2; shot_full all-notifications; close_host
island_face media; act island.expand '{}'; settle 2; shot_full all-media; close_host
island_face clock
for id in $LINKED; do disable_mod "$id"; done
check_frontend "all linked mods"

# The whole run: no panic in the daemon, and the i18n misses for the record (a missing key is not always drawn).
grep -q panicked "$R/server.log" && finding "kurashid panicked (see $R/server.log)"
misses=$(grep -o 'I18N MISS [^ ]*' "$R/qs.log" | sort | uniq -c | tr -s ' ' | tr '\n' ';' || true)
echo "note: i18n misses (keys asked for and not in the daemon's document; drawn or not): ${misses:-none}"
if [ "${#FINDINGS[@]}" -gt 0 ]; then
  printf 'finding: %s\n' "${FINDINGS[@]}" >&2
  fail "${#FINDINGS[@]} finding(s); screenshots in $OUT"
fi
echo "ok: screenshots in $OUT"
