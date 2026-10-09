#!/bin/sh
# Launch the shell with the GL vendor pinned when it is unambiguous (Kaizen, K16).
# glvnd dlopens every installed EGL vendor; with the NVIDIA driver active the Mesa vendor
# (libgallium + libLLVM) is loaded for nothing: ~13 MiB PSS measured. Pins only with exactly one
# DRM render node: on hybrid laptops (iGPU + NVIDIA) Mesa may be the right driver. Respects a
# user setting and does nothing without NVIDIA (AMD/Intel need Mesa).
# `$KURASHI_QS` overrides the quickshell binary (the HM service sets it; no PATH needed).
case $0 in */*) dir=${0%/*} ;; *) dir=. ;; esac
if [ -z "$__EGL_VENDOR_LIBRARY_FILENAMES" ] && [ -d /proc/driver/nvidia ]; then
    n=0
    for r in /dev/dri/renderD*; do [ -e "$r" ] && n=$((n + 1)); done
    if [ "$n" -eq 1 ]; then
        for d in /run/opengl-driver/share/glvnd/egl_vendor.d /usr/share/glvnd/egl_vendor.d; do
            if [ -f "$d/10_nvidia.json" ]; then
                export __EGL_VENDOR_LIBRARY_FILENAMES="$d/10_nvidia.json"
                break
            fi
        done
    fi
fi
exec "${KURASHI_QS:-qs}" -p "$dir" "$@"
