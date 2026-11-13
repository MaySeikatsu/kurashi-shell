#!/usr/bin/env bash
# The appearance menu (W84, docs/ux/appearance-menu.md) on nested niri (tools/bench/niri-sandbox.sh): the REAL kurashid
# and frontend, a FAKE awww first on the daemon's PATH (it logs its argv; no real backend runs), a folder of generated
# pictures. Checks (ok / FAIL; any FAIL or QML error exits 1):
#   1. launcher: typing "wallpaper" offers the menu's row; Enter shows the menu on the Wallpaper pane (the rows give way);
#   2. wallpaper: a picture chosen in the grid and Enter is set (`awww img <path>` and the mod's document); a folder added
#      through the path field lands in `mods.wallpaper.folders`, Delete on its chip removes it again;
#   3. colours: Ctrl+2, Tab into the pane, Right on the mode previews light live (the `theme` document's scheme_effective),
#      Esc puts it back (the user's own dark again); after a marker change to another key, three moves kept with Enter are
#      ONE undo step (one undo: the starting mode, the marker kept; a second undo: the marker gone);
#   4. the eye on the preview hides it (`launcher.appearance_preview`), the heading's "Show the preview" brings it back;
#   5. closing the launcher while previewing puts back; Esc with nothing previewed goes back to the search, Esc again
#      closes; "tex" (a word's start) offers Material after the apps, not first;
#   6. the card host: `appearance.open` (CONTRACT-CHANGE row 791) — skipped with a note while the daemon lacks it;
#   7. shots: each pane, light and dark in two looks (kami, sekai), the states (no mod, empty folder, missing folder,
#      previewing, preview off), placements (opened by a click, out of the island) and start-menu looks (win95, aqua)
#      → frontend/shots/appearance-menu/shots/.
#   nix develop -c frontend/test-appearance-menu.sh        (KURASHI_BIN_DIR=<dir with kurashid, kurashi>)
#   APPEARANCE_SHOTS=0 skips the per-look shots (7).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KURASHI_NIRI_SB_NAME=${KURASHI_SB_PREFIX:-}w84-app
export KURASHI_NIRI_SB_OUT=${APPEARANCE_OUT:-$ROOT/frontend/shots/appearance-menu}
OUT=$KURASHI_NIRI_SB_OUT
SB="$ROOT/tools/bench/niri-sandbox.sh"
BIN=${KURASHI_BIN_DIR:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
mkdir -p "$OUT"
FAILS=0
CHECKS=0
fail() { echo "test-appearance-menu: $*" >&2; "$SB" stop >/dev/null 2>&1; exit 1; }
check() { CHECKS=$((CHECKS + 1)); if [ "$1" = 1 ]; then echo "ok: $2"; else echo "FAIL: $2"; FAILS=$((FAILS + 1)); fi; }
trap '"$SB" stop >/dev/null 2>&1' EXIT

# ---- the pictures and the fake backend (outside the sandbox's runtime dir: it is made by start) --------------------
WORK=$OUT/work
rm -rf "$WORK"
mkdir -p "$WORK/pics" "$WORK/more" "$WORK/empty" "$WORK/fakebin" "$WORK/wpstate"
i=0
for c in "#c94f4f" "#4f7fc9" "#5fa36a" "#d6a64a" "#8a5fc9" "#3f3f46" "#e7dccb" "#2f6f73"; do
  i=$((i + 1))
  magick -size 640x360 "gradient:$c-#101014" -fill "#ffffff30" -draw "circle 420,150 420,60" "$WORK/pics/pic-$i.jpg"
done
magick -size 640x360 "plasma:#f0a0b0-#203050" -seed 7 "$WORK/more/plasma.png" 2>/dev/null || magick -size 640x360 xc:"#a05050" "$WORK/more/plasma.png"
export WP_LOG=$WORK/awww.log WP_STATE=$WORK/wpstate
: > "$WP_LOG"
cat > "$WORK/fakebin/awww" <<'EOF'
#!/bin/sh
echo "awww $*" >> "$WP_LOG"
case "$1" in
  --version) echo "awww 0.12.1" ;;
  query)
    if [ -f "$WP_STATE/daemon" ]; then
      printf '%s\n' '{"": [{"name": "WINIT-1", "width": 1920, "height": 1080, "scale": 1, "displaying": {"color": "000000"}}]}'
    else echo "Failed to connect to the awww-daemon socket" >&2; exit 1; fi ;;
  img) exit 0 ;;
  kill) rm -f "$WP_STATE/daemon" ;;
esac
exit 0
EOF
cat > "$WORK/fakebin/awww-daemon" <<'EOF'
#!/bin/sh
echo "awww-daemon $*" >> "$WP_LOG"
touch "$WP_STATE/daemon"
EOF
chmod +x "$WORK/fakebin/awww" "$WORK/fakebin/awww-daemon"
export PATH="$WORK/fakebin:$PATH"

CFG=$OUT/config.toml
conf() { # conf <style> <scheme> <folders toml list> [mods loaded: "" for none]
  local mods=${4-'"wallpaper"'}
  cat > "$CFG" <<TOML
[idle]
enabled = false
[theme]
style = "$1"
[theme.colors]
scheme = "$2"
[theme.motion]
profile = "none"
[modules.windows]
previews = false
[modules.workspaces]
previews = false
[edges.top]
start = ["launcher"]
center = ["island"]
end = ["clock"]
[mods]
loaded = [$mods]
enabled = [$mods]
[mods.wallpaper]
folders = $3
backend = "awww"
wallhaven = false
${5:-}
TOML
}
conf kami dark "[\"$WORK/pics\"]"
export KURASHI_LAUNCHER_LOG=1
"$SB" start "$CFG" > /dev/null || fail "the sandbox did not start"
. "$OUT/niri-env.sh"
K() { timeout 15 "$BIN/kurashi" "$@"; }
# Keys through sway's seat to the nested niri (one virtual keyboard per call).
keys() { (. "$OUT/sway-env.sh"; timeout 30 python3 -I "$ROOT/tools/bench/wl_keys.py" "$@") >/dev/null 2>&1; }
# Typing: one token per character (wl_keys' names for `/`, `-`, `.`).
typed() { local s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}
    case "$c" in /) out+=" slash" ;; -) out+=" minus" ;; .) out+=" period" ;; _) out+=" underscore" ;; *) out+=" $c" ;; esac
  done; keys $out; }
doc() { K sub "$1" --count 0 2>/dev/null | head -1; }
cfgval() { doc config | python3 -c "import json,sys; v=json.load(sys.stdin)['data']['values'].get('$1'); print(json.dumps(v['value'] if v else None))"; }
cfgsrc() { doc config | python3 -c "import json,sys; v=json.load(sys.stdin)['data']['values'].get('$1'); print(v['source']['kind'] if v else '')"; }
hist() { doc config | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['history']['rev'])"; }
scheme_eff() { doc theme | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['appearance']['scheme_effective'])"; }
ui_launcher() { doc runtime.ui | python3 -c "import json,sys; print(str(json.load(sys.stdin)['data'].get('launcher', False)).lower())"; }
wall_path() { doc mod.wallpaper | python3 -c "import json,sys; o=json.load(sys.stdin)['data'].get('outputs',{}); print(next((v.get('path','') for v in o.values() if v.get('path')), ''))"; }
until_eq() { local want=$1; shift; for _ in $(seq 80); do [ "$("$@")" = "$want" ] && return 0; sleep 0.1; done; return 1; }
qlog() { cat "$XDG_RUNTIME_DIR/qs.log" 2>/dev/null; }
# The launcher card, opened by its key, stands in the middle of the 1920 x 1080 output.
CARD="560,150 800x780"
shot() { "$SB" shot "$1" "${2:-$CARD}" 1 > /dev/null; }
thumbs_ready() { [ "$(ls "$XDG_CACHE_HOME/kurashi/wallpaper/thumbs/"*.json 2>/dev/null | wc -l)" -ge "$1" ]; }
wait_thumbs() { for _ in $(seq 150); do thumbs_ready "$1" && { sleep 1; return 0; }; sleep 0.1; done; return 1; }

for _ in $(seq 100); do doc mod.wallpaper | grep -q '"available":true' && break; sleep 0.2; done

open_menu() { # open_menu <query>
  K act launcher.toggle > /dev/null 2>&1
  until_eq true ui_launcher || true
  sleep 0.4
  typed "$1"
  sleep 0.8
  keys return
  sleep 1
}
close_launcher() { K act ui.close > /dev/null 2>&1; until_eq false ui_launcher || true; sleep 0.4; }

# ---- 1. launcher → menu --------------------------------------------------------------------------------------------
open_menu wallpaper
check "$(qlog | grep -a 'launcher-rows' | grep -a '"q":"wallpaper"' | grep -c 'appearance:appearance:wallpaper' | awk '{print ($1 > 0)}')" \
  "\"wallpaper\" offers the menu's row"
check "$(qlog | grep -ac 'launcher-menu wallpaper' | awk '{print ($1 > 0)}')" "Enter shows the menu on the Wallpaper pane"
wait_thumbs 8 || echo "note: the thumbnails took long"
shot wallpaper-kami-dark

# ---- 2. wallpaper: a picture, then the folders ----------------------------------------------------------------------
# From the rail: Right enters the pane (Local), Tab: the folder, + Add folder, search, the grid.
keys right tab tab tab tab
sleep 0.3
keys right
sleep 0.5
shot wallpaper-selected
keys return
for _ in $(seq 50); do grep -q "awww img .*pic-2.jpg" "$WP_LOG" && break; sleep 0.1; done
check "$(grep -c "awww img .*pic-2.jpg" "$WP_LOG" | awk '{print ($1 > 0)}')" "Enter in the grid sets the picture (awww img pic-2.jpg)"
until_eq "$WORK/pics/pic-2.jpg" wall_path || true
check "$([ "$(wall_path)" = "$WORK/pics/pic-2.jpg" ] && echo 1 || echo 0)" "the mod's document shows the picture ($(wall_path))"
# Add a folder: back to + Add folder (search, then the button), Return opens the path field.
MORE=$XDG_RUNTIME_DIR/more
mkdir -p "$MORE" && cp "$WORK/more/plasma.png" "$MORE/"
keys shift+tab shift+tab
sleep 0.2
keys return
sleep 0.4
typed "$MORE"
keys return
until_eq "[\"$WORK/pics\", \"$MORE\"]" cfgval mods.wallpaper.folders || true
check "$([ "$(cfgval mods.wallpaper.folders)" = "[\"$WORK/pics\", \"$MORE\"]" ] && echo 1 || echo 0)" \
  "a folder added in the path field is in mods.wallpaper.folders ($(cfgval mods.wallpaper.folders))"
sleep 1
shot wallpaper-two-folders
# Remove it: Shift+Tab from + Add folder is its chip; Delete removes it.
keys shift+tab
sleep 0.2
keys delete
until_eq "[\"$WORK/pics\"]" cfgval mods.wallpaper.folders || true
check "$([ "$(cfgval mods.wallpaper.folders)" = "[\"$WORK/pics\"]" ] && echo 1 || echo 0)" "Delete on a folder's chip removes it"

# ---- 3. colours: live preview, Esc puts back, Enter keeps as one step ------------------------------------------------
keys ctrl+2
sleep 0.8
shot colours-kami-dark
# The rail → More in Settings → hide the preview → the palettes → the mode: Right previews the next mode (dark → light).
keys tab tab tab tab
sleep 0.2
keys right
until_eq light scheme_eff || true
check "$([ "$(scheme_eff)" = light ] && echo 1 || echo 0)" "Right on the mode previews light live (theme: $(scheme_eff))"
sleep 0.8
shot colours-previewing
keys escape
until_eq dark scheme_eff || true
check "$([ "$(scheme_eff)" = dark ] && [ "$(cfgval theme.colors.scheme)" = '"dark"' ] && [ "$(cfgsrc theme.colors.scheme)" = user ] && echo 1 || echo 0)" \
  "Esc puts it back (dark, the user's own: $(cfgval theme.colors.scheme) $(cfgsrc theme.colors.scheme))"
# One undo step for the visit: a marker change first (another key, outside the menu), then three moves kept with Enter.
# One undo must give the starting mode with the marker still there; a second undo takes the marker.
K raw '{"t":"apply","id":"m1","ops":[{"set":"launcher.place_x","value":55}]}' > /dev/null
until_eq 55 cfgval launcher.place_x || true
R0=$(hist)
keys left
until_eq '"wallpaper"' cfgval theme.colors.scheme || true
sleep 0.4
keys left
until_eq '"auto"' cfgval theme.colors.scheme || true
sleep 0.4
keys right
until_eq '"wallpaper"' cfgval theme.colors.scheme || true
sleep 0.8
keys return
sleep 0.8
check "$([ "$(cfgval theme.colors.scheme)" = '"wallpaper"' ] && echo 1 || echo 0)" "Enter keeps the previewed mode ($(cfgval theme.colors.scheme))"
R1=$(hist)
K raw '{"t":"undo","id":"u1"}' > /dev/null
until_eq '"dark"' cfgval theme.colors.scheme || true
check "$([ "$(cfgval theme.colors.scheme)" = '"dark"' ] && [ "$(cfgval launcher.place_x)" = 55 ] && echo 1 || echo 0)" \
  "three moves kept are one undo step: one undo → $(cfgval theme.colors.scheme), the marker kept ($(cfgval launcher.place_x)); revisions $R0 → $R1"
K raw '{"t":"undo","id":"u2"}' > /dev/null
until_eq 50 cfgval launcher.place_x || true
check "$([ "$(cfgval launcher.place_x)" = 50 ] && [ "$(cfgval theme.colors.scheme)" = '"dark"' ] && echo 1 || echo 0)" \
  "a second undo takes the marker, nothing of the session's is left ($(cfgval launcher.place_x), $(cfgval theme.colors.scheme))"

# ---- 4. the preview section toggles (the eye on the preview, then the heading's "Show the preview") -------------------
keys ctrl+2 tab tab return
until_eq false cfgval launcher.appearance_preview || true
check "$([ "$(cfgval launcher.appearance_preview)" = false ] && echo 1 || echo 0)" "the eye on the preview hides it (launcher.appearance_preview false)"
sleep 0.8
shot colours-preview-off
keys ctrl+2 tab return
until_eq true cfgval launcher.appearance_preview || true
check "$([ "$(cfgval launcher.appearance_preview)" = true ] && echo 1 || echo 0)" "\"Show the preview\" brings it back"

# ---- 5. a close while previewing puts back; Esc with nothing previewed goes back to the search ------------------------
keys ctrl+2 tab tab tab tab
sleep 0.2
keys right
until_eq light scheme_eff || true
close_launcher
until_eq dark scheme_eff || true
check "$([ "$(scheme_eff)" = dark ] && [ "$(cfgval theme.colors.scheme)" = '"dark"' ] && [ "$(cfgsrc theme.colors.scheme)" = user ] && echo 1 || echo 0)" \
  "closing the launcher while previewing puts the mode back ($(cfgval theme.colors.scheme) $(cfgsrc theme.colors.scheme))"
open_menu wallpaper
keys escape
sleep 0.6
check "$([ "$(ui_launcher)" = true ] && echo 1 || echo 0)" "Esc goes back to the search (the launcher stays open)"
shot back-to-search
keys escape
until_eq false ui_launcher || true
check "$([ "$(ui_launcher)" = false ] && echo 1 || echo 0)" "Esc again closes the launcher"
# "tex" finds Material by a word's start: after the apps, so Enter still opens the best app hit
K act launcher.toggle > /dev/null 2>&1; until_eq true ui_launcher || true; sleep 0.4
typed tex
sleep 0.8
check "$(qlog | grep -a 'launcher-rows' | grep -a '"q":"tex"' | tail -1 | python3 -c "import json,sys,re; l=sys.stdin.read(); m=re.search(r'launcher-rows (\{.*\})', l); d=json.loads(m.group(1)) if m else {'keys':[]}; k=d['keys']; print(1 if 'appearance:appearance:material' in k and (k.index('appearance:appearance:material') > 0 or len(k) == 1) else 0)")" \
  "a word's start (\"tex\") offers Material after the apps"
close_launcher

# ---- 6. the card host ---------------------------------------------------------------------------------------------------
if K act appearance.open '{"pane":"colours"}' 2>&1 | grep -q '"t":"done"'; then
  sleep 1.5
  shot card-colours "460,0 1000x760"
  check "$(doc runtime.ui | grep -c '"panel":"appearance:colours"' | awk '{print ($1 > 0)}')" "appearance.open shows the card"
  K act ui.close > /dev/null 2>&1
else
  echo "skip: the card host — kurashid has no appearance.open yet (CONTRACT-CHANGE row 791)"
fi

# ---- 7. panes, looks, schemes and states (shots) -------------------------------------------------------------------------
if [ "${APPEARANCE_SHOTS:-1}" = 1 ]; then
  open_menu wallpaper
  for n in 3 4 5 6 7; do
    keys ctrl+$n
    sleep 0.9
    shot "pane-$n-kami-dark"
  done
  close_launcher
  for look in kami sekai; do
    for scheme in light dark; do
      conf "$look" "$scheme" "[\"$WORK/pics\"]"
      "$SB" config "$CFG" > /dev/null
      sleep 1.5
      open_menu colours
      sleep 0.6
      shot "colours-$look-$scheme"
      keys ctrl+1
      sleep 1.5
      shot "wallpaper-$look-$scheme"
      close_launcher
    done
  done
  # states: an empty folder, a missing one, no wallpaper mod
  conf kami dark "[\"$WORK/empty\"]"; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu wallpaper; sleep 0.8; shot state-empty-folder; close_launcher
  conf kami dark "[\"$WORK/nope\"]"; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu wallpaper; sleep 0.8; shot state-missing-folder; close_launcher
  conf kami dark "[\"$WORK/pics\"]" ""; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu wallpaper; sleep 0.8; shot state-no-mod; close_launcher
  # placements (whole screen): opened by a click on the bar's launcher button (it hangs from it), out of the island, and
  # in a look whose launcher is a start menu (win95: the start-menu skin's chrome round the menu)
  conf kami dark "[\"$WORK/pics\"]"; "$SB" config "$CFG" > /dev/null; sleep 2
  "$SB" click 22 18 > /dev/null
  if until_eq true ui_launcher; then
    sleep 0.6; typed colours; sleep 0.8; keys return; sleep 1.2; "$SB" shot place-at > /dev/null; close_launcher
  else echo "note: the click at the launcher button did not open it (no place-at shot)"; fi
  conf kami dark "[\"$WORK/pics\"]" '"wallpaper"' $'[launcher]\nplace = "island"'; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu colours; "$SB" shot place-island > /dev/null; close_launcher
  conf win95 light "[\"$WORK/pics\"]"; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu colours; "$SB" shot look-win95 > /dev/null; close_launcher
  conf aqua light "[\"$WORK/pics\"]"; "$SB" config "$CFG" > /dev/null; sleep 2
  open_menu wallpaper; "$SB" shot look-aqua > /dev/null; close_launcher
fi

bad=$(qlog | grep -a -E 'appearance/|Picker\.qml|Launcher\.qml|Stage\.qml' | grep -a -E 'TypeError|ReferenceError|Unable to assign|Cannot|binding loop' | sort -u)
[ -z "$bad" ] || echo "$bad"
check "$([ -z "$bad" ] && echo 1 || echo 0)" "no QML errors from the menu, the picker, the launcher or the Stage"
echo "test-appearance-menu: $CHECKS checks, $FAILS failed"
[ "$FAILS" = 0 ]
