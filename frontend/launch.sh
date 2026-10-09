#!/bin/sh
# Launch the shell with the GL vendor pinned when it is unambiguous (Kaizen, K16).
# glvnd dlopens every installed EGL vendor; with the NVIDIA driver active the Mesa vendor
# (libgallium + libLLVM) is loaded for nothing: ~13 MiB PSS measured. Respects a user setting
# and does nothing without NVIDIA (AMD/Intel need Mesa).
dir=$(dirname "$0")
if [ -z "$__EGL_VENDOR_LIBRARY_FILENAMES" ] && [ -d /proc/driver/nvidia ]; then
    for d in /run/opengl-driver/share/glvnd/egl_vendor.d /usr/share/glvnd/egl_vendor.d; do
        if [ -f "$d/10_nvidia.json" ]; then
            export __EGL_VENDOR_LIBRARY_FILENAMES="$d/10_nvidia.json"
            break
        fi
    done
fi
exec qs -p "$dir" "$@"
