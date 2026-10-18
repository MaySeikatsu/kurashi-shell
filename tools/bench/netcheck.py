#!/usr/bin/env python3
# Probes the network from inside the sandbox (I58; sandbox.sh netcheck, and sandbox.sh start, which refuses a sandbox
# that reaches one). It runs joined to the sandbox's namespace (the env lines do that). It prints the interfaces the
# namespace shows, then tries a TCP connect to a public address and an HTTPS fetch: both must fail. Exit 0 when the
# network is out of reach, 1 when one of them got through.
# A name lookup is printed, not counted: glibc asks the host's nscd over its unix socket, which the namespace shares,
# so a name can resolve. No packet leaves the namespace (it has no route), and that is what the probes test.
import socket
import sys
import urllib.request

TARGET = ("93.184.215.14", 443)  # example.com; any public address would do


def interfaces():
    with open("/proc/net/dev", encoding="utf-8") as f:
        return [line.split(":")[0].strip() for line in f.readlines()[2:]]


def connect():
    socket.create_connection(TARGET, timeout=3).close()


def https():
    urllib.request.urlopen("https://example.com", timeout=5).close()


PROBES = [
    ("connect 93.184.215.14:443", connect),
    ("https://example.com", https),
]


def main():
    print(f"netcheck: interfaces {', '.join(interfaces())}")
    try:
        socket.getaddrinfo("example.com", 443)
        print("netcheck: name lookup answered (by the host's nscd, not counted; no route for the answer)")
    except OSError as e:
        print(f"netcheck: name lookup failed: {e}")
    reached = []
    for label, probe in PROBES:
        try:
            probe()
            reached.append(label)
        except OSError as e:
            print(f"netcheck: {label} failed: {e}")
    if reached:
        print(f"netcheck: REACHED {', '.join(reached)}")
        return 1
    print("netcheck: offline (every connection failed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
