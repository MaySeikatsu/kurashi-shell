#!/bin/sh
# Tests for frontend/launch.sh's EGL vendor pin (card K-hybrid-egl), with fake inputs only: KURASHI_ROOT
# re-roots /dev, /proc, /sys and the glvnd dirs to a temp tree, KURASHI_WAYLAND_INFO is a stub that prints
# a canned report, KURASHI_QS a stub that records what launch.sh exported. Each case runs under `env -i`,
# so no compositor, driver or session of the machine running the test can leak in.
# Run: sh frontend/test-launch.sh
set -u
case $0 in */*) here=${0%/*} ;; *) here=. ;; esac
launch=$(cd "$here" && pwd)/launch.sh
t=$(mktemp -d) || exit 1
trap 'rm -rf "$t"' EXIT
root=$t/root
glvnd=$root/run/opengl-driver/share/glvnd/egl_vendor.d
nv=$glvnd/10_nvidia.json
mesa=$glvnd/50_mesa.json
fails=0
quiet=no

cat > "$t/qs" <<'EOF'
#!/bin/sh
env > "$FAKE_OUT"
printf 'ARGS=%s\n' "$*" >> "$FAKE_OUT"
EOF
cat > "$t/wayland-info" <<'EOF'
#!/bin/sh
: > "$FAKE_PROBED"
cat "$FAKE_INFO"
EOF
chmod +x "$t/qs" "$t/wayland-info"

# Canned wayland-info reports, in the format wayland-info prints on sway (dmabuf main device as hex dev_t).
cat > "$t/info-amd" <<'EOF'
interface: 'zwp_linux_dmabuf_v1', version: 5, name: 3
  main device: 0xE281 (/dev/dri/card2 or /dev/dri/renderD129)
    target device: 0xE281 (/dev/dri/card2 or /dev/dri/renderD129)
EOF
cat > "$t/info-nv" <<'EOF'
interface: 'zwp_linux_dmabuf_v1', version: 5, name: 3
  main device: 0xE280 (/dev/dri/card1 or /dev/dri/renderD128)
    target device: 0xE280 (/dev/dri/card1 or /dev/dri/renderD128)
EOF
cat > "$t/info-card" <<'EOF'
interface: 'zwp_linux_dmabuf_v1', version: 5, name: 3
  main device: 0xE202 (/dev/dri/card2)
EOF
cat > "$t/info-unknown" <<'EOF'
interface: 'zwp_linux_dmabuf_v1', version: 5, name: 3
  main device: 0x1234 (/dev/dri/card9)
EOF
cat > "$t/info-v3" <<'EOF'
interface: 'zwp_linux_dmabuf_v1', version: 3, name: 3
EOF

# machine <yes|no>: an empty fake machine with both glvnd vendor files; yes = NVIDIA driver loaded.
machine() {
    rm -rf "$root"
    mkdir -p "$root/dev/dri" "$root/sys/dev/char" "$root/sys/class/drm" "$root/sys/devices" "$glvnd"
    touch "$nv" "$mesa"
    if [ "$1" = yes ]; then
        mkdir -p "$root/proc/driver/nvidia"
    fi
}

# gpu <pci address> <driver> <boot_vga> <renderD minor> <card minor>: one GPU laid out as the kernel does:
# /sys/dev/char/226:N -> .../drm/renderDN, whose device/ -> the PCI device (uevent, boot_vga).
gpu() {
    g=$root/sys/devices/$1
    mkdir -p "$g/drm/renderD$4" "$g/drm/card$5"
    printf 'DRIVER=%s\n' "$2" > "$g/uevent"
    printf '%s\n' "$3" > "$g/boot_vga"
    ln -s "../../devices/$1/drm/renderD$4" "$root/sys/dev/char/226:$4"
    ln -s "../../devices/$1/drm/card$5" "$root/sys/dev/char/226:$5"
    ln -s "../../devices/$1/drm/card$5" "$root/sys/class/drm/card$5"
    ln -s ../.. "$g/drm/renderD$4/device"
    ln -s ../.. "$g/drm/card$5/device"
    : > "$root/dev/dri/renderD$4"
}

# hybrid <NVIDIA boot_vga> <Radeon boot_vga>: machine B's layout (renderD128 = RTX 3070, renderD129 = 680M).
hybrid() {
    machine yes
    gpu 0000:01:00.0 nvidia "$1" 128 1
    gpu 0000:35:00.0 amdgpu "$2" 129 2
}

# check <name> <wanted EGL, empty = no pin> <report: none|missing|amd|nv|card|unknown|v3> [VAR=value ...]
# report none: no WAYLAND_DISPLAY; missing: WAYLAND_DISPLAY but no wayland-info binary; else the canned report.
# quiet=yes: wayland-info must not have run (user override).
check() {
    name=$1 want=$2 report=$3
    shift 3
    case $report in
        none) probe= ;;
        missing) probe="WAYLAND_DISPLAY=test-0 KURASHI_WAYLAND_INFO=$t/missing" ;;
        *) probe="WAYLAND_DISPLAY=test-0 KURASHI_WAYLAND_INFO=$t/wayland-info FAKE_INFO=$t/info-$report" ;;
    esac
    rm -f "$t/out" "$t/probed"
    # $probe is a list of VAR=value words without spaces, so it is split on purpose.
    # shellcheck disable=SC2086
    env -i PATH="$PATH" KURASHI_ROOT="$root" KURASHI_QS="$t/qs" FAKE_OUT="$t/out" \
        FAKE_PROBED="$t/probed" $probe "$@" sh "$launch" --marker
    got=$(sed -n 's/^__EGL_VENDOR_LIBRARY_FILENAMES=//p' "$t/out" 2>/dev/null)
    args=$(sed -n 's/^ARGS=//p' "$t/out" 2>/dev/null)
    probed=no
    [ -e "$t/probed" ] && probed=yes
    if [ "$got" = "$want" ] && [ "$args" = "-p ${launch%/*} --marker" ] && { [ "$quiet" = no ] || [ "$probed" = no ]; }; then
        echo "ok    $name"
    else
        echo "FAIL  $name: EGL='$got' (want '$want'), ARGS='$args', wayland-info ran: $probed"
        fails=$((fails + 1))
    fi
}

machine yes
gpu 0000:01:00.0 nvidia 0 128 1
check "one render node: NVIDIA (unchanged)" "$nv" none

machine yes
check "no render node: nothing" "" none

machine no
gpu 0000:35:00.0 amdgpu 1 129 2
check "one AMD node, no NVIDIA driver: nothing" "" none

machine no
gpu 0000:00:02.0 i915 0 130 3
gpu 0000:35:00.0 amdgpu 1 129 2
check "two nodes, no NVIDIA driver: nothing" "" amd

hybrid 0 1
check "AMD main + NVIDIA: Mesa" "$mesa" amd
check "NVIDIA main + AMD: NVIDIA" "$nv" nv
check "card node as main device (card2): Mesa" "$mesa" card

quiet=yes
check "user __EGL_VENDOR_LIBRARY_FILENAMES wins" "/my/egl.json" amd __EGL_VENDOR_LIBRARY_FILENAMES=/my/egl.json
check "user __NV_PRIME_RENDER_OFFLOAD wins" "" amd __NV_PRIME_RENDER_OFFLOAD=1
quiet=no

hybrid 0 1
check "unknown main device (0x1234): nothing, no boot_vga fallback" "" unknown
check "no wayland-info binary: boot_vga fallback (Radeon)" "$mesa" missing
check "dmabuf v3, no main device: boot_vga fallback (Radeon)" "$mesa" v3
check "no WAYLAND_DISPLAY: boot_vga fallback (Radeon)" "$mesa" none

hybrid 1 0
check "no WAYLAND_DISPLAY: boot_vga=1 is the NVIDIA card: NVIDIA" "$nv" none

hybrid 0 0
check "no WAYLAND_DISPLAY, no boot_vga=1 card: nothing" "" none

hybrid 1 1
check "two boot_vga=1 cards: nothing" "" none

hybrid 0 1
rm -f "$mesa"
check "pinned vendor file not installed: nothing" "" amd

# W42: the image format plugin filter. Fake plugin dirs: sys has imageformats (Qt's and kimageformats') beside other
# plugin kinds, plain has none, qt5 another imageformats dir. Each case runs under `env -i` with its own runtime dir.
machine no
pl=$t/plugins
mkdir -p "$pl/sys/imageformats" "$pl/sys/platformthemes" "$pl/sys/platforminputcontexts" "$pl/plain/platforms" \
    "$pl/qt5/imageformats"
for f in libqgif libqico libqjpeg libqsvg libqwebp libqtiff kimg_avif kimg_heif kimg_exr kimg_jxl kimg_raw; do
    : > "$pl/sys/imageformats/$f.so"
done
: > "$pl/sys/top_level_plugin.so"
: > "$pl/qt5/imageformats/libqjpeg.so"
: > "$pl/qt5/imageformats/libqtga.so"
qpp=$pl/sys:$pl/plain::$pl/qt5

# plugins <name> <wanted QT_PLUGIN_PATH, with @F for the farm> <wanted: entry=listing;...> [VAR=value ...]
# A listing is the sorted names in that farm entry's imageformats/ (or "-" for an entry the farm must not have).
plugins() {
    name=$1 want=$2 lists=$3
    shift 3
    rm -f "$t/out"
    env -i PATH="$PATH" KURASHI_ROOT="$root" KURASHI_QS="$t/qs" FAKE_OUT="$t/out" "$@" sh "$launch" --marker
    got=$(sed -n 's/^QT_PLUGIN_PATH=//p' "$t/out" 2>/dev/null)
    rt=$(sed -n 's/^XDG_RUNTIME_DIR=//p' "$t/out" 2>/dev/null)
    farm=$(ls -d "$rt"/kurashi/qt-plugins-* 2>/dev/null | head -n 1)
    ok=yes
    [ "$got" = "$(printf '%s' "$want" | sed "s|@F|$farm|g")" ] || ok=no
    detail=
    old_ifs=$IFS
    IFS=';'
    for l in $lists; do
        IFS=$old_ifs
        e=${l%%=*} wantl=${l#*=}
        if [ "$wantl" = - ]; then
            gotl=-
            [ -e "$farm/$e" ] && gotl=present
        else
            gotl=$(ls "$farm/$e/imageformats" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        fi
        [ "$gotl" = "$wantl" ] || { ok=no; detail="$detail [$e: '$gotl' want '$wantl']"; }
    done
    IFS=$old_ifs
    if [ "$ok" = yes ]; then
        echo "ok    $name"
    else
        echo "FAIL  $name: QT_PLUGIN_PATH='$got' (want '$want', farm '$farm')$detail"
        fails=$((fails + 1))
    fi
}

rt1=$t/rt1
mkdir -p "$rt1"
plugins "image plugins: the kept four, other kinds linked, order kept" "@F/1:$pl/plain:@F/2" \
    "1=libqgif.so libqjpeg.so libqsvg.so libqwebp.so;2=libqjpeg.so;3=-" XDG_RUNTIME_DIR="$rt1" QT_PLUGIN_PATH="$qpp"
farm1=$(ls -d "$rt1"/kurashi/qt-plugins-*)
plugins "image plugins: other plugin kinds stay reachable" "@F/1:$pl/plain:@F/2" "1=libqgif.so libqjpeg.so libqsvg.so libqwebp.so" \
    XDG_RUNTIME_DIR="$rt1" QT_PLUGIN_PATH="$qpp"
for k in platformthemes platforminputcontexts top_level_plugin.so; do
    farm=$(ls -d "$rt1"/kurashi/qt-plugins-* | head -n 1)
    if [ -L "$farm/1/$k" ] && [ "$(readlink "$farm/1/$k")" = "$pl/sys/$k" ]; then
        echo "ok    image plugins: $k linked"
    else
        echo "FAIL  image plugins: $k not linked in $farm/1"
        fails=$((fails + 1))
    fi
done
if [ -e "$farm1" ]; then
    echo "FAIL  image plugins: the farm of a gone shell ($farm1) was not removed"
    fails=$((fails + 1))
else
    echo "ok    image plugins: the farm of a gone shell is removed"
fi
rm -rf "$rt1"/kurashi
plugins "image plugins: KURASHI_IMAGE_FORMATS adds avif" "@F/1:$pl/plain:@F/2" \
    "1=kimg_avif.so libqgif.so libqjpeg.so libqsvg.so libqwebp.so" XDG_RUNTIME_DIR="$rt1" QT_PLUGIN_PATH="$qpp" \
    KURASHI_IMAGE_FORMATS="gif jpeg svg webp avif"
rm -rf "$rt1"/kurashi
plugins "image plugins: KURASHI_IMAGE_FORMATS=all keeps the path" "$qpp" "1=-" XDG_RUNTIME_DIR="$rt1" \
    QT_PLUGIN_PATH="$qpp" KURASHI_IMAGE_FORMATS=all
plugins "image plugins: no runtime dir keeps the path" "$qpp" "" QT_PLUGIN_PATH="$qpp"
plugins "image plugins: no QT_PLUGIN_PATH stays unset" "" "1=-" XDG_RUNTIME_DIR="$rt1"

# nixpkgs' Qt adds <PATH entry>/../lib/qt-6/plugins: a PATH entry whose prefix has image plugins becomes <farm>/b<n>/bin,
# a link to the same dir (its commands still run), and <farm>/b<n>/lib/qt-6/plugins the filtered copy.
mkdir -p "$pl/prof/bin" "$pl/prof/lib/qt-6/plugins/imageformats" "$pl/prof/lib/qt-6/plugins/platformthemes" "$pl/bare/bin"
printf '#!/bin/sh\necho tool-ran\n' > "$pl/prof/bin/kurashi-test-tool"
chmod +x "$pl/prof/bin/kurashi-test-tool"
for f in libqjpeg libqsvg kimg_heif kimg_jxl; do : > "$pl/prof/lib/qt-6/plugins/imageformats/$f.so"; done
rm -rf "$rt1"/kurashi
rm -f "$t/out"
env -i PATH="$pl/prof/bin/:$pl/bare/bin:relative/bin:$PATH" KURASHI_ROOT="$root" KURASHI_QS="$t/qs" FAKE_OUT="$t/out" \
    XDG_RUNTIME_DIR="$rt1" sh "$launch" --marker
got=$(sed -n 's/^PATH=//p' "$t/out")
farm=$(ls -d "$rt1"/kurashi/qt-plugins-* 2>/dev/null | head -n 1)
fmts=$(ls "$farm/b1/lib/qt-6/plugins/imageformats" 2>/dev/null | tr '\n' ' ')
case $got in
    "$farm/b1/bin:$pl/bare/bin:relative/bin:"*) path_ok=yes ;;
    *) path_ok=no ;;
esac
if [ "$path_ok" = yes ] && [ "$(readlink "$farm/b1/bin")" = "$pl/prof/bin/" ] && [ "$fmts" = "libqjpeg.so libqsvg.so " ] \
    && [ -L "$farm/b1/lib/qt-6/plugins/platformthemes" ] && [ "$(PATH=$got kurashi-test-tool)" = tool-ran ]; then
    echo "ok    image plugins: a PATH prefix's plugins filtered, its commands still found"
else
    echo "FAIL  image plugins: PATH='$got' farm '$farm' formats '$fmts'"
    fails=$((fails + 1))
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "launch.sh tests: all passed"
else
    echo "launch.sh tests: $fails failed"
fi
[ "$fails" -eq 0 ]
