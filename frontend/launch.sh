#!/bin/sh
# Launch the shell with the GL vendor pinned to the GPU it renders on (Kaizen, K16; card K-hybrid-egl).
# glvnd dlopens every installed EGL vendor, so with the NVIDIA driver active the other vendor's stack is
# loaded for nothing: ~13 MiB PSS with one NVIDIA render node, ~10 MiB on hybrid laptops where niri
# renders on the Radeon 680M (114.4 vs 123.5-126.9 MiB, docs/BENCH.md "quiet machine B"). Rendering on
# the RTX 3070 costs more than memory: every runtime-PM resume stalls the UI thread ~2 s.
# Only with the NVIDIA driver loaded (/proc/driver/nvidia):
#   one DRM render node   -> NVIDIA (unchanged rule)
#   several               -> the driver of the compositor's main device: wayland-info's linux-dmabuf
#                            "main device", else the one card with boot_vga=1.
#                            nvidia -> NVIDIA; amdgpu, i915, xe, ... -> Mesa
#   anything unclear      -> no pin
# A user's __EGL_VENDOR_LIBRARY_FILENAMES or __NV_PRIME_RENDER_OFFLOAD always wins.
# Env: KURASHI_QS (quickshell) and KURASHI_WAYLAND_INFO override the binaries; the HM service sets both,
# so no PATH is needed. KURASHI_ROOT re-roots /dev, /proc, /sys and the glvnd dirs for test-launch.sh.
# Only sysfs reads and one wayland-info run (it exits before we exec); POSIX sh, no bashisms.
#
# Image format plugins (W42, K16 Kaizen): Qt maps every image format plugin it finds when it probes an image by its
# content, and a NixOS session hands it the system profile's: kimageformats (libheif, x265, libde265, OpenEXR, libraw,
# libjxl, libavif, libaom, dav1d, ...) and qtimageformats (tiff, jasper, mng, ...), libraries the shell never decodes
# with. Qt finds them two ways: QT_PLUGIN_PATH, and nixpkgs' Qt patch that adds <entry>/../lib/qt-6/plugins for every
# PATH entry (so /run/current-system/sw/bin brings /run/current-system/sw/lib/qt-6/plugins). Every such dir that has
# an imageformats/ is replaced by a copy made of symlinks under $XDG_RUNTIME_DIR/kurashi/qt-plugins-<pid> (its other
# plugin kinds linked as they are) whose imageformats/ holds only the formats the shell draws: SVG, JPEG, WebP and GIF
# (PNG, BMP and XPM are built into Qt). Those are what the icon themes (tray, launcher), the wallpaper library (png jpg
# webp gif bmp: kurashi-mod-wallpaper's EXTENSIONS) and the clipboard thumbnails (PNG, decoded by kurashid) need;
# quickshell's own plugin dirs (its wrapper's QT_PLUGIN_PATH prefix) are left alone. A PATH entry is replaced by
# <farm>/b<n>/bin, a symlink to the same dir, so commands resolve as before and the patch's lexical
# <entry>/../lib/qt-6/plugins lands in the farm. KURASHI_IMAGE_FORMATS (space-separated, e.g. "gif jpeg svg webp avif")
# names the kept formats, matched as libq<format>.so or kimg_<format>.so; "all" leaves both variables as they are.
case $0 in */*) dir=${0%/*} ;; *) dir=. ;; esac
root=${KURASHI_ROOT-}

# shadow_plugins <plugin dir> <copy>: the copy links every entry of the dir but imageformats/, which gets the kept
# formats only. A dir met before (PATH and QT_PLUGIN_PATH name the same profiles, some twice) gets a link to its first
# copy. A handful of processes per dir, not one per entry: the start-up of the shell waits on this.
shadow_plugins() {
    case $seen in
        *"|$1>"*)
            first=${seen#*"|$1>"}
            ln -s "${first%%|*}" "$2"
            return
            ;;
    esac
    seen="$seen|$1>$2|"
    src=$1 dst=$2
    mkdir -p "$dst/imageformats" || return 1
    set --
    for e in "$src"/*; do
        [ -e "$e" ] && [ "${e##*/}" != imageformats ] && set -- "$@" "$e"
    done
    [ $# -eq 0 ] || ln -s "$@" "$dst/"
    set --
    for f in $keep; do
        for p in "$src/imageformats/libq$f.so" "$src/imageformats/kimg_$f.so"; do
            [ -e "$p" ] && set -- "$@" "$p"
        done
    done
    [ $# -eq 0 ] || ln -s "$@" "$dst/imageformats/"
}

# Rewrites QT_PLUGIN_PATH and PATH as described above. A farm whose shell is gone (its pid is not ours) is removed.
filter_image_plugins() {
    keep=${KURASHI_IMAGE_FORMATS-gif jpeg svg webp}
    [ "$keep" != all ] && [ -d "${XDG_RUNTIME_DIR-}" ] || return 0
    base=$XDG_RUNTIME_DIR/kurashi
    for old in "$base"/qt-plugins-*; do
        [ -d "$old" ] || continue
        kill -0 "${old##*-}" 2>/dev/null || rm -rf "$old"
    done
    farm=$base/qt-plugins-$$ # exec keeps the pid: the farm is named after the shell that uses it
    [ ! -e "$farm" ] || rm -rf "$farm"
    mkdir -p "$farm" || return 0
    old_ifs=$IFS
    i=0
    seen=
    if [ -n "${QT_PLUGIN_PATH-}" ]; then
        set -f
        IFS=:
        # shellcheck disable=SC2086 # split on ':' on purpose (globbing is off)
        set -- $QT_PLUGIN_PATH
        IFS=$old_ifs
        set +f
        new=
        for d in "$@"; do
            [ -n "$d" ] || continue
            if [ -d "$d/imageformats" ]; then
                i=$((i + 1))
                shadow_plugins "$d" "$farm/$i" || return 0
                d=$farm/$i
            fi
            new=${new:+$new:}$d
        done
        export QT_PLUGIN_PATH="$new"
    fi
    if [ -n "${PATH-}" ]; then
        set -f
        IFS=:
        # shellcheck disable=SC2086 # as above
        set -- $PATH
        IFS=$old_ifs
        set +f
        new=
        bins=
        for d in "$@"; do
            case $bins in
                *"|$d>"*)
                    # The same entry again (session PATHs repeat profiles): its link from before.
                    d=${bins#*"|$d>"}
                    d=${d%%|*}
                    new=${new:+$new:}$d
                    continue
                    ;;
            esac
            case $d in
                /*)
                    up=${d%/}
                    up=${up%/*}
                    if [ -d "$up/lib/qt-6/plugins/imageformats" ]; then
                        i=$((i + 1))
                        mkdir -p "$farm/b$i/lib/qt-6" && ln -s "$d" "$farm/b$i/bin" || return 0
                        shadow_plugins "$up/lib/qt-6/plugins" "$farm/b$i/lib/qt-6/plugins" || return 0
                        bins="$bins|$d>$farm/b$i/bin|"
                        d=$farm/b$i/bin
                    fi
                    ;;
            esac
            new=${new:+$new:}$d
        done
        export PATH="$new"
    fi
}
filter_image_plugins

# Sets $vendor to the installed glvnd vendor file named $1 (e.g. 10_nvidia.json), empty if none.
vendor_file() {
    vendor=
    for d in "$root/run/opengl-driver/share/glvnd/egl_vendor.d" "$root/usr/share/glvnd/egl_vendor.d"; do
        if [ -f "$d/$1" ]; then
            vendor=$d/$1
            return
        fi
    done
}

# Sets $drv to the driver bound to the device whose uevent file is $1 (its DRIVER= line), empty if none.
driver_of() {
    drv=
    [ -r "$1" ] || return
    while IFS= read -r line; do
        case $line in DRIVER=?*) drv=${line#DRIVER=} ;; esac
    done < "$1"
}

# Sets $drv to the driver of the one card with boot_vga=1 (the firmware's display GPU), empty if none or several.
boot_vga_driver() {
    drv=
    hits=0
    for c in "$root/sys/class/drm/card"*; do
        case ${c##*/} in *-*) continue ;; esac # connectors (card1-eDP-1) share their card's device
        [ -r "$c/device/boot_vga" ] || continue
        read -r vga < "$c/device/boot_vga"
        [ "$vga" = 1 ] || continue
        hits=$((hits + 1))
        driver_of "$c/device/uevent"
    done
    [ "$hits" -eq 1 ] || drv=
}

# Sets $main to the compositor's linux-dmabuf main device as hex dev_t (wayland-info prints
# "main device: 0xE281 (/dev/dri/card2 or /dev/dri/renderD129)"), empty if none is reported.
main_device() {
    main=
    [ -n "${WAYLAND_DISPLAY-}" ] || return
    wi=${KURASHI_WAYLAND_INFO:-wayland-info}
    command -v "$wi" >/dev/null 2>&1 || return
    info=$("$wi" 2>/dev/null) || return
    case $info in *"main device: 0x"*) ;; *) return ;; esac
    rest=${info#*"main device: 0x"}
    main=${rest%%[!0-9A-Fa-f]*}
}

if [ -z "$__EGL_VENDOR_LIBRARY_FILENAMES" ] && [ -z "$__NV_PRIME_RENDER_OFFLOAD" ] && [ -d "$root/proc/driver/nvidia" ]; then
    n=0
    for r in "$root/dev/dri/renderD"*; do [ -e "$r" ] && n=$((n + 1)); done
    drv=
    if [ "$n" -eq 1 ]; then
        drv=nvidia
    elif [ "$n" -gt 1 ]; then
        main_device
        if [ -n "$main" ]; then
            devt=$((0x$main)) # dev_t = major << 8 | minor; DRM minors stay below 256
            driver_of "$root/sys/dev/char/$(((devt >> 8) & 4095)):$((devt & 255))/device/uevent"
        else
            boot_vga_driver
        fi
    fi
    case $drv in
        '') vendor= ;;
        nvidia) vendor_file 10_nvidia.json ;;
        *) vendor_file 50_mesa.json ;;
    esac
    [ -z "$vendor" ] || export __EGL_VENDOR_LIBRARY_FILENAMES="$vendor"
fi
# Quickshell links jemalloc, whose default is 4 arenas per CPU (48 on 12 cores) and no background purging: a thread's
# arena (each window has a render thread, I11) keeps its freed pages until that arena allocates again, which an idle
# window never does. Two arenas hold the shell's heap with ~15 MiB less resident memory at one output (W42, BENCH). A
# user's own MALLOC_CONF wins (it replaces this one whole).
export MALLOC_CONF="${MALLOC_CONF:-narenas:2}"
exec "${KURASHI_QS:-qs}" -p "$dir" "$@"
