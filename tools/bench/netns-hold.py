#!/usr/bin/env python3
# The sandbox's network namespace holder (I58, tools/bench/sandbox.sh). Run as:
#   python3 -I netns-hold.py <id-file> <command> [args...]
# It unshares a user and a network namespace for itself. The namespace holds loopback only: no route, no resolver,
# so nothing in it reaches a host or the internet. The caller's uid and gid map to themselves, so the peer
# credentials that D-Bus and Wayland check agree on both sides of the namespace. It writes the namespace's id
# ("net:[inode]") to <id-file>, which sandbox.sh waits for and netjoin.c joins by, then execs the command: that
# command (the sandbox's sway) keeps the namespace alive. Rootless: needs unprivileged user namespaces (NixOS: on).
import fcntl
import os
import socket
import struct
import sys

SIOCGIFFLAGS = 0x8913
SIOCSIFFLAGS = 0x8914
IFF_UP = 0x1
IFREQ = "16sH22x"  # struct ifreq (40 bytes): the name, then the union; the flags sit at offset 16


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: netns-hold.py <id-file> <command> [args...]")
    id_file, command = argv[1], argv[2:]
    uid, gid = os.getuid(), os.getgid()
    try:
        os.unshare(os.CLONE_NEWUSER | os.CLONE_NEWNET)
    except OSError as e:
        sys.exit(f"netns-hold: cannot unshare user and network namespaces: {e}")
    # setgroups must be denied before gid_map may be written by an unprivileged process.
    with open("/proc/self/setgroups", "w") as f:
        f.write("deny")
    with open("/proc/self/uid_map", "w") as f:
        f.write(f"{uid} {uid} 1")
    with open("/proc/self/gid_map", "w") as f:
        f.write(f"{gid} {gid} 1")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        flags = struct.unpack(IFREQ, fcntl.ioctl(s, SIOCGIFFLAGS, struct.pack(IFREQ, b"lo", 0)))[1]
        fcntl.ioctl(s, SIOCSIFFLAGS, struct.pack(IFREQ, b"lo", flags | IFF_UP))
    tmp = id_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(os.readlink("/proc/self/ns/net"))
    os.replace(tmp, id_file)
    os.execvp(command[0], command)


if __name__ == "__main__":
    main(sys.argv)
