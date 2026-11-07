#!/usr/bin/env bash
# What a strong shadow and a translucent look ask of the sheet and the cards on it (I435, docs/ux/shadows.md), on nested niri, by
# the pixels over a flat wallpaper at strength 2: the sheet's shadow runs on with no step where two of its windows meet, under a
# held lamp too; a Stage card's and the launcher's shadow fade out instead of ending in a straight line; a translucent card that
# hangs from the bar leaves no line along the connecting edge.
#   nix develop -c frontend/test-card-edges.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}cardedges
OUT=${CARD_EDGES_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/card-edges}
export KURASHI_NIRI_SB_OUT=$OUT
mkdir -p "$OUT"
SB="$ROOT/tools/bench/niri-sandbox.sh"
fail() { echo "test-card-edges: FAIL: $*" >&2; "$SB" stop > /dev/null 2>&1; exit 1; }
trap '"$SB" stop > /dev/null 2>&1' EXIT
CFG=$OUT/config.toml
magick -size 1920x1080 xc:'#8fb8c8' "$OUT/flat.png"
conf() { # conf <light mode>
cat > "$CFG" <<T
[idle]
enabled = false
[theme]
style = "kami"
[theme.colors]
scheme = "light"
[theme.motion]
profile = "none"
[theme.material]
kind = "translucent"
elevation = "follow"
sheet_shadow = "auto"
elevation_strength = 2.0
[theme.light]
mode = "$1"
[modules.windows]
previews = false
[modules.workspaces]
previews = false
[mods]
enabled = ["sysmon"]
[edges.top]
bar = true
start = ["launcher"]
center = ["island"]
end = ["clock"]
[layout]
draw = "dynamic"
[layout.frame]
enabled = true
thickness = 10
T
}
conf spotlight
"$SB" start "$CFG" "$OUT/flat.png" > /dev/null || fail "the sandbox did not start"
sleep 4
shot() { (. "$OUT/sway-env.sh"; timeout 8 grim "$OUT/$1.png"); }
# step <shot> <h|v> <fixed> <from> <to> <limit>: the largest step between neighbouring pixels along that line, red channel.
step() {
  python3 -I - "$OUT/$1.png" "$2" "$3" "$4" "$5" "$6" "$1" <<'PY'
import subprocess, sys
png, axis, fixed, a, b, limit, name = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), sys.argv[7]
geo = f"{b - a}x1+{a}+{fixed}" if axis == "h" else f"1x{b - a}+{fixed}+{a}"
raw = subprocess.run(["magick", png, "-crop", geo, "+repage", "-depth", "8", "gray:-"], capture_output=True, check=True).stdout
worst = max(abs(raw[i + 1] - raw[i]) for i in range(len(raw) - 1))
print(f"{name} {axis}{fixed} {a}..{b}: largest step {worst}")
sys.exit(0 if worst <= limit else 1)
PY
}
px() { magick "$OUT/$1.png" -format "%[fx:int(255*p{$2,$3}.r)]" info:; }

# ---- the sheet's shadow: the top window owns the hole down to its room, the side windows below it ----
shot sheet
step sheet v 1880 60 700 6 || fail "a step in the sheet's shadow down the right side"
step sheet v 40 60 700 6 || fail "a step in the sheet's shadow down the left side"

# ---- a Stage card's shadow ends softly ----
"$SB" act act mod.panel.open '{"id":"sysmon","panel":"sysmon"}' > /dev/null; sleep 3
shot stage
# (the card's box from the shape's own log would do; the first paper to the left of the middle along a row)
Y=300; L=0
for x in $(seq 960 -4 200); do [ "$(px stage "$x" $Y)" -ge 180 ] && L=$x; done
[ "$L" -gt 200 ] || fail "no Stage card at row $Y"
step stage h $Y $(( L - 170 )) $(( L - 6 )) 8 || fail "the Stage card's shadow ends in a line"
# ---- no line along the connecting edge: the strip, the seam and the card read alike under the card's middle ----
# (row by row over 60 px past the island's pill: the look's dots and grain average out, a line along the edge does not)
magick "$OUT/stage.png" -crop "60x16+$(( L + 20 ))+28" +repage -filter box -resize '1x16!' "$OUT/seam.png"
step seam v 0 0 16 4 || fail "a line along the card's connecting edge"
"$SB" act act ui.close > /dev/null; sleep 2

# ---- the launcher's shadow has room ----
"$SB" act act launcher.toggle > /dev/null; sleep 3
shot launcher
Y=400; L=0
for x in $(seq 960 -4 100); do [ "$(px launcher "$x" $Y)" -ge 180 ] && L=$x; done
[ "$L" -gt 100 ] || fail "no launcher at row $Y"
[ "$(px launcher $(( L - 12 )) $Y)" -lt "$(px sheet 400 400)" ] || fail "no shadow beside the launcher"
step launcher h $Y $(( L - 130 )) $(( L - 6 )) 8 || fail "the launcher's shadow ends in a line"
"$SB" act act ui.close > /dev/null
echo "test-card-edges: ok"
