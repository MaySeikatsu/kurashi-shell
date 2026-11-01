#!/usr/bin/env bash
# The open island meets a ruled bar (W30, docs/ux/island.md "Session 12: the join under line chrome"), invisibly
# (headless sway sandbox, through frontend/test-island-morph.sh), against the REAL kurashid. Under line chrome the bar
# rules its strip's inner edge; the open card must hang from that rule: the rule runs round the card's fillet (or its
# mitred corner when square) into the card's side as one line. For each case the morph test runs, then a pixel check
# reads the shots (top bar as is, bottom bar flipped; left side, then mirrored for the right):
#   - the rule is found down the crop's left column (its row R, its colour = the outline);
#   - the outline is one connected line (8-neighbours, a 1 px gap bridged, no more) from the rule at the crop's edge to
#     the card's side 50 px below the rule — in the card at rest and in every morph frame whose card is past the rule
#     (a card shorter than that: half way down it; a pill not yet 8 px past the rule is skipped);
#   - no rule left under the card, at rest and in every morph frame;
#   - at rest, walking from the crop's edge to the side, the outline's topmost pixel never rises above the rule (no
#     side running on into the bar, no step up, no tab outline round the head) and the rule is open between the sides.
# The -mid cases run the springs at a quarter speed with dense grabs and fail unless a checked frame caught the card
# mid-morph (0 < opened < 1, from the shape's KURASHI_ISLAND_DEBUG log matched to the card's foot in the frame).
# Shots: washi and terminal into frontend/shots/island/morph-<tag>-*.png, the other cases into
# target/island-join/ (MORPH_OUT). Fails on a gap, a step or an overshoot, or where the morph test fails.
#   nix develop -c frontend/test-island-join.sh            # all cases
#   JOIN_CASES="washi terminal" nix develop -c frontend/test-island-join.sh
# Machine B: export KURASHI_RENDER_NODE first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXTRA=${JOIN_OUT:-${CARGO_TARGET_DIR:-$ROOT/target}/island-join}
mkdir -p "$EXTRA"
fail() { echo "test-island-join: $*" >&2; exit 1; }
CHECK=$EXTRA/check.py

cat > "$CHECK" <<'PY'
import struct, sys, zlib

def load(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    i, idat, w = 8, b"", 0
    while i < len(data):
        n, = struct.unpack(">I", data[i:i + 4]); kind = data[i + 4:i + 8]; body = data[i + 8:i + 8 + n]; i += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and ctype in (2, 6) and inter == 0, "unsupported PNG"
            bpp = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ft == 1: line[x] = (line[x] + a) & 255
            elif ft == 2: line[x] = (line[x] + b) & 255
            elif ft == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(w)])
        prev = line
    return w, h, rows

def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5

def side(rows, w, rest, name):
    """Checks the left half of a top-bar image; returns an error string or None."""
    px = lambda x, y: rows[y][x]
    bar = px(4, 2)
    R = next((y for y in range(3, 120) if dist(px(4, y), bar) > 40), None)
    if R is None: return "no rule under the bar (is this line chrome?)"
    ref = px(4, R)
    R2 = R
    while dist(px(4, R2 + 1), ref) < 30: R2 += 1
    desk = px(4, R2 + 4)
    # The card's bottom down its centre (the first desk row past the rule); a card that is not 8 px past the rule yet is
    # a pill (no join to check). The side is checked 50 px below the rule, or half way down a card shorter than that.
    E = R2 + 1
    B = next((y for y in range(E, len(rows)) if dist(px(w // 2, y), desk) < 12), len(rows))
    depth = B - E
    if depth < 8:
        return "no card side below the rule" if rest else None
    CHECKED.append(B)
    card = px(w // 2, E + min(5, depth // 2 - 1))
    contrast = min(dist(ref, c) for c in (bar, desk, card) if dist(ref, c) > 1)
    if contrast < 40: return "the rule hardly differs from its grounds (%.0f)" % contrast
    thr = 0.5 * contrast
    # The grounds an outline pixel may blend with: the bar, the desk, the card over the desk and over the bar (its head).
    grounds = [c for c in (bar, desk, card, px(w // 2, R)) if dist(ref, c) > 20]
    def cover(p):
        # How much of the pixel is the outline: p as a blend of the outline and one of its grounds (anti-aliasing).
        best = 0.0
        for g in grounds:
            v = [r - c for r, c in zip(ref, g)]; d = [q - c for q, c in zip(p, g)]
            vv = sum(a * a for a in v)
            a = sum(x * y for x, y in zip(v, d)) / vv
            off = dist(d, [a * x for x in v])
            if off < 0.2 * vv ** 0.5: best = max(best, a)
        return best
    # A flat arc spreads a 1 px line over two rows (two pixels of about half each).
    on = lambda x, y: cover(px(x, y)) >= 0.3
    ys = R2 + min(50, max(4, depth // 2))
    if ys >= len(rows): return "crop too short"
    xs = next((x for x in range(4, w // 2) if on(x, ys)), None)
    if xs is None: return "no outline at the card's side %d px below the rule" % (ys - R)
    # One line from the rule at the edge to the side: flood the outline, a 1 px gap bridged.
    seen, todo = set(), [(x, y) for x in range(4, 9) for y in range(R, R2 + 1) if on(x, y)]
    seen.update(todo)
    while todo:
        x, y = todo.pop()
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                q = (x + dx, y + dy)
                if q in seen or not (0 <= q[0] <= w // 2 and 0 <= q[1] <= ys): continue
                if on(*q):
                    seen.add(q); todo.append(q)
    if (xs, ys) not in seen:
        reach = max((p for p in seen), key=lambda p: (p[1], p[0]))
        return "gap: the rule's outline stops at %s and never reaches the card's side at (%d, %d)" % (reach, xs, ys)
    # No rule left under the card (a mid-morph frame too: the bar's rule lagging the card would show here).
    for x in range(xs + 4, w // 2):
        if any(on(x, y) for y in range(R, R2 + 1)): return "double line: the rule runs on under the card at x=%d" % x
    if not rest: return None
    # The topmost outline pixel, column by column from the edge to the side: never above the rule, never back up.
    top_prev, missing = R, 0
    for x in range(4, xs + 1):
        top = next((y for y in range(2, ys + 1) if on(x, y)), None)
        if top is None:
            missing += 1
            if missing > 1: return "gap: columns %d-%d have no outline between the bar and the side" % (x - 1, x)
            continue
        missing = 0
        if top < R: return "overshoot: the outline rises into the bar at x=%d (row %d, rule at %d)" % (x, top, R)
        if top < top_prev - 1: return "step: the outline steps up at x=%d (%d -> %d)" % (x, top_prev, top)
        top_prev = max(top_prev, top)
    return None

CHECKED = []

def main():
    # check.py <edge> <shape log or -> <rest.png> <frames...>
    edge, log, rest_name = sys.argv[1], sys.argv[2], sys.argv[3]
    bad, mid = [], []
    # The shape's log (KURASHI_ISLAND_DEBUG=1): "island-shape opened=<o> y1=<y>" on every change of `opened`.
    states = []
    if log != "-":
        for line in open(log, errors="replace"):
            i = line.find("island-shape opened=")
            if i < 0: continue
            kv = dict(p.split("=", 1) for p in line[i:].split()[1:] if "=" in p)
            states.append((float(kv["opened"]), float(kv["y1"])))
    for path in sys.argv[3:]:
        w, h, rows = load(path)
        if edge == "bottom": rows = rows[::-1]
        rest = path == rest_name
        del CHECKED[:]
        errs = []
        for label, rr in (("left", rows), ("right", [r[::-1] for r in rows])):
            err = side(rr, w, rest, path)
            if err: errs.append("%s (%s): %s" % (path, label, err))
        bad += errs
        # A checked frame whose card's bottom (B) matches a logged state with 0 < opened < 1 is a mid-morph frame.
        if CHECKED and not errs and states:
            B = CHECKED[0]
            near = [o for o, y in states if abs(y - B) <= 1.5]
            if near and all(0 < o < 1 for o in near):
                mid.append(path)
    for b in bad: print("test-island-join: " + b)
    if log != "-":
        print("test-island-join: mid-morph frames checked (0 < opened < 1): %d %s" % (len(mid), " ".join(p.rsplit("/", 1)[-1] for p in mid)))
        if not bad and not mid:
            print("test-island-join: no checked frame caught the card mid-morph (0 < opened < 1)")
            sys.exit(1)
    sys.exit(1 if bad else 0)

main()
PY

# case <tag> <edge> <into-repo 0|1> <config lines...>
run_case() {
  local tag=$1 edge=$2 keep=$3; shift 3
  local out=$EXTRA crop="860,0 840x520"
  [ "$keep" = 1 ] && out=$ROOT/frontend/shots/island
  [ "$edge" = bottom ] && crop="860,920 840x520"
  local at=${MID_AT[$tag]:-} log=- qslog=$EXTRA/$tag.qs.log
  echo "test-island-join: case $tag ($edge): $*"
  rm -f "$out/morph-$tag"-open-*.png "$out/morph-$tag"-close-*.png "$qslog"
  if [ -n "$at" ]; then
    log=$qslog
    KURASHI_ISLAND_DEBUG=1 MORPH_LOG=$qslog MORPH_AT=$at MORPH_OUT=$out MORPH_CROP=$crop MORPH_SANDBOX=${KURASHI_SB_PREFIX:-}w30-join \
      "$ROOT/frontend/test-island-morph.sh" "$tag" "$@" > "$EXTRA/$tag.log" 2>&1 \
      || { tail -5 "$EXTRA/$tag.log" >&2; fail "morph test failed for $tag"; }
  else
    MORPH_OUT=$out MORPH_CROP=$crop MORPH_SANDBOX=${KURASHI_SB_PREFIX:-}w30-join "$ROOT/frontend/test-island-morph.sh" "$tag" "$@" \
      > "$EXTRA/$tag.log" 2>&1 || { tail -5 "$EXTRA/$tag.log" >&2; fail "morph test failed for $tag"; }
  fi
  local shots=("$out/morph-$tag-rest.png")
  for f in "$out/morph-$tag"-open-*.png "$out/morph-$tag"-close-*.png; do shots+=("$f"); done
  timeout 300 python3 -I "$CHECK" "$edge" "$log" "${shots[@]}" || fail "the join is broken for $tag"
  echo "test-island-join: $tag ok"
}

# K71: a bottom bar with today's modules, none on top (what `layout.bar.move` writes).
BOTTOM_BAR="edges.top.bar = false|edges.top.start = []|edges.top.center = []|edges.top.end = []|edges.bottom.bar = true|edges.bottom.start = [\"sidebar_left\", \"workspaces\", \"windows\"]|edges.bottom.center = [\"island\"]|edges.bottom.end = [\"volume\", \"mods\", \"recorder\", \"keyboard\", \"clock\", \"quick\", \"tray\", \"sidebar_right\"]"
# The "terminal" cases are the square line join on the quick timed motion terminal had before W53.8. The terminal look
# itself now stands its launcher and island card apart from the bar (`[decor] surface.join = false`: boxed TUI windows),
# so they pin those axes on no style instead of naming it.
SQUARE_BASE="theme.style = \"none\"|theme.chrome = \"line\"|theme.shape.corners = \"none\"|theme.motion.profile = \"expressive\""
SQUARE="$SQUARE_BASE|theme.motion.speed = 1.6"
declare -A CASES=(
  [washi]='top 1 theme.style = "washi"'
  [terminal]="top 1 $SQUARE"
  [washi-dark]='top 0 theme.style = "washi"|theme.colors.scheme = "dark"'
  [line-none]='top 0 theme.style = "none"|theme.chrome = "line"'
  [line-square]='top 0 theme.style = "washi"|theme.shape.corners = "none"'
  [line-squircle]='top 0 theme.style = "washi"|theme.shape.corners = "squircle"'
  [line-r05]='top 0 theme.style = "none"|theme.chrome = "line"|theme.shape.radius = 9'
  [line-r2]='top 0 theme.style = "none"|theme.chrome = "line"|theme.shape.radius = 36'
  [washi-bottom]="bottom 0 theme.style = \"washi\"|$BOTTOM_BAR"
  [terminal-bottom]="bottom 0 $SQUARE|$BOTTOM_BAR"
  [washi-mid]='top 0 theme.style = "washi"|theme.motion.speed = 0.25'
  [terminal-bottom-mid]="bottom 0 $SQUARE_BASE|$BOTTOM_BAR|theme.motion.speed = 0.25"
)
# Mid-morph cases: the springs at a quarter speed and dense grabs, so frames land while the card is still short (the
# shape logs `opened`, KURASHI_ISLAND_DEBUG); the check fails unless one checked frame has 0 < opened < 1.
DENSE="60 80 100 115 130 145 160 175 190 205 220 240 260 290 330 400 500 600 700 800 900 1100"
declare -A MID_AT=([washi-mid]=$DENSE [terminal-bottom-mid]=$DENSE)
ORDER="washi terminal washi-dark line-none line-square line-squircle line-r05 line-r2 washi-bottom terminal-bottom washi-mid terminal-bottom-mid"
for c in ${JOIN_CASES:-$ORDER}; do
  spec=${CASES[$c]:-}
  [ -n "$spec" ] || fail "unknown case $c"
  read -r edge keep rest <<<"$spec"
  IFS='|' read -r -a lines <<<"$rest"
  run_case "$c" "$edge" "$keep" "${lines[@]}"
done
echo "test-island-join: ok"
