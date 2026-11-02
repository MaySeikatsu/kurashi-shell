#!/usr/bin/env bash
# Animated previews of the motion forms for the README and the PR (W59, K83): each form opens and closes one card on
# nested niri, filmed with grim, played back at real speed as an animated WebP in docs/media/motion/<form>.webp.
#
#   nix develop -c tools/motion-previews.sh [form …]          default: every form below
#   MOTION_SURFACE=session|island|sidebar|toast  (session)    the card that opens: the session menu (no data at all),
#                                                             the island's clock card, the right sidebar, a toast
#   MOTION_STYLE=washi (any style)   MOTION_SLOW=4 (1–4)      the shell runs the motion this many times slower so grim
#                                                             (~30–60 ms a shot) catches enough frames; playback undoes it
#
# Privacy (I345): the sandbox still sees the real HOME until card W60 lands, so this films only cards that carry no
# personal data (the session menu, the clock, an empty sidebar, a toast with fixed text) over a generated wallpaper,
# with no launcher and no terminal. It writes a contact sheet of every frame (OUT/review/<form>.png): look at each one
# before committing a preview. Previews are the one place images are tracked on purpose (docs/media/, not a shots/ dir).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SB="$ROOT/tools/bench/niri-sandbox.sh"
OUT=${KURASHI_NIRI_SB_OUT:-/tmp/kurashi-motion-previews}
export KURASHI_NIRI_SB_OUT=$OUT KURASHI_NIRI_SB_NAME=motion-previews
DEST="$ROOT/docs/media/motion"
SURFACE=${MOTION_SURFACE:-session}
STYLE=${MOTION_STYLE:-washi}
SLOW=${MOTION_SLOW:-4}
FORMS=("$@")
[ ${#FORMS[@]} -gt 0 ] || FORMS=(grow expand liquid iris drop stamp outline slide zoom fade flip bleed stepped
  fold book roll crumple genie crt fan noren pixelate glitch dissolve)

mkdir -p "$OUT/frames" "$OUT/review" "$DEST"

# A generated wallpaper with structure, so blur and refraction show (no picture of anyone's).
WALL="$OUT/wall.png"
[ -f "$WALL" ] || magick -size 1920x1080 xc: -sparse-color Shepards \
  '0,0 #d9cbb4 1920,0 #8fa9a0 0,1080 #b98a7a 1920,1080 #4f6b7a 960,540 #e8dfcf' \
  \( -size 1920x1080 pattern:checkerboard -blur 0x2 -evaluate multiply 0.08 \) -compose plus -composite "$WALL"

case "$SURFACE" in
  session) OPEN=(session.menu); CLOSE=(ui.close); CROP="560,0 800x420" ;;
  island) OPEN=(island.expand); CLOSE=(ui.close); CROP="560,0 800x560" ;;
  sidebar) OPEN=(sidebar.toggle '{"side":"right"}'); CLOSE=(sidebar.toggle '{"side":"right"}'); CROP="1340,0 580x1080" ;;
  # A toast: a Notify on the sandbox's own session bus (as test-morph.sh), fixed text; dismissed by the shell.
  toast) OPEN=(); CLOSE=(notify.dismiss '{}'); CROP="1280,0 640x360" ;;
  *) echo "motion-previews: unknown MOTION_SURFACE $SURFACE" >&2; exit 2 ;;
esac

config() {  # config <form> → the sandbox's config.toml
  cat > "$OUT/config.toml" <<EOF
schema_version = 7
[theme]
style = "$STYLE"
[theme.motion]
speed = $(python3 -c "print(round(1/$SLOW, 2))")
[theme.motion.form]
open = "$1"
close = "$1"
[theme.motion.form.island]
follow = true
[idle]
enabled = false
EOF
}

now_ms() { date +%s%3N; }
# film <form>: grim as fast as it goes for the whole open → hold → close, each frame named by its time.
film() {
  local form=$1 dir="$OUT/frames/$form" t0 stop
  rm -rf "$dir"; mkdir -p "$dir"
  . "$OUT/sway-env.sh"
  t0=$(now_ms)
  # open at 0.3 s, close when the open has run its slowed course and rested a moment, film until it has gone.
  ( sleep 0.3
    if [ ${#OPEN[@]} -gt 0 ]; then "$SB" act act "${OPEN[@]}" >/dev/null
    else ( . "$OUT/niri-env.sh"; timeout 10 gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
        kurashi 0 '' 'お茶の時間' 'The kettle has boiled.' '[]' '{}' 5000 >/dev/null ); fi
    sleep "$(python3 -c "print(0.7 * $SLOW + 0.6)")"; "$SB" act act "${CLOSE[@]}" >/dev/null ) &
  # open at 0.3 s, close after 0.7 s × SLOW + 0.6 s, the close runs ≤ 0.45 s × SLOW; a short tail at rest.
  stop=$(( t0 + 300 + 700 * SLOW + 600 + 450 * SLOW + 400 ))
  # PPM: no PNG encoding between grabs (≈ 3× the frames).
  while [ "$(now_ms)" -lt "$stop" ]; do
    timeout 5 grim -t ppm -s 1 -g "$CROP" "$dir/$(( $(now_ms) - t0 )).ppm" || true
  done
  wait
}
# assemble <form>: real-time playback (each frame held as long as it lasted, ÷ SLOW), half size, looped.
assemble() {
  local form=$1 dir="$OUT/frames/$form" args=() prev="" t f
  mapfile -t files < <(ls "$dir" | sort -n)
  for f in "${files[@]}"; do
    t=${f%.ppm}
    if [ -n "$prev" ]; then args+=(-delay "$(( (t - ${prev%.ppm}) / SLOW / 10 + 1 ))" "$dir/$prev"); fi
    prev=$f
  done
  args+=(-delay 120 "$dir/$prev")
  magick "${args[@]}" -resize 50% -loop 0 -quality 78 -define webp:method=6 "$DEST/$form.webp"
  # In time order, labelled with each frame's ms, for the privacy review.
  magick montage -label '%t' "${files[@]/#/$dir/}" -tile 12x -geometry 240x+2+2 -background '#333' \
    "$OUT/review/$form.png"
  echo "motion-previews: $DEST/$form.webp ($(du -h "$DEST/$form.webp" | cut -f1)); review: $OUT/review/$form.png"
}

config "${FORMS[0]}"
"$SB" start "$OUT/config.toml" "$WALL" >/dev/null
trap '"$SB" stop >/dev/null 2>&1 || true' EXIT
# The pointer out of every crop (bottom-left corner, under no card).
"$SB" move 4 1076 >/dev/null 2>&1 || true
for form in "${FORMS[@]}"; do
  config "$form"; "$SB" config "$OUT/config.toml"
  film "$form"; assemble "$form"
done
