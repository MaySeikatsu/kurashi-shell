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
case $0 in */*) dir=${0%/*} ;; *) dir=. ;; esac
root=${KURASHI_ROOT-}

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
exec "${KURASHI_QS:-qs}" -p "$dir" "$@"
