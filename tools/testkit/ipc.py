#!/usr/bin/env python3
"""The suites' IPC client (W89): one exchange with kurashid at $KURASHI_SOCKET. Stdlib only.

  ipc.py <doc>                  the first snapshot's data of a document; a daemon error exits 1 with it
  ipc.py <doc> count <seconds>  the patches of that document in that many seconds after its snapshot
  ipc.py sub <doc>              the first snapshot's data; a daemon error prints null (exit 0)
  ipc.py act <action> [json]    act: prints the reply; exit 0 when it is done, 1 otherwise
  ipc.py tokens <key>...        the theme tokens of those keys (null where missing or on an error)

The suites run it as `python3 -I`, through tk_ipc in frontend/test-lib.sh. Import it for the functions.
"""
import json
import os
import socket
import sys
import time

TIMEOUT = 5
USAGE = "usage: ipc.py <doc> | <doc> count <seconds> | sub <doc> | act <action> [json] | tokens <key>..."


class Client:
    """One connection, greeted. A closed connection or a refused greeting exits with a message."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(TIMEOUT)
        self.sock.connect(os.environ["KURASHI_SOCKET"])
        self.f = self.sock.makefile("rwb")
        self.send({"t": "hello", "v": 1, "client": "test", "caps": ["intents", "resync"]})
        if self.recv()["t"] != "welcome":
            sys.exit("ipc: no welcome")

    def send(self, msg):
        self.f.write((json.dumps(msg) + "\n").encode())
        self.f.flush()

    def recv(self):
        line = self.f.readline()
        if not line:
            sys.exit("ipc: connection closed")
        return json.loads(line)

    def reply(self, rid, kinds):
        """The first message for request `rid` whose type is one of `kinds`."""
        while True:
            m = self.recv()
            if m.get("id") == rid and m["t"] in kinds:
                return m


def sub(doc, null_on_err=False):
    c = Client()
    c.send({"t": "sub", "id": "s", "doc": doc})
    m = c.reply("s", ("snap", "err"))
    if m["t"] == "err" and not null_on_err:
        sys.exit("ipc: " + json.dumps(m))
    print(json.dumps(m.get("data")))


def act(action, args):
    c = Client()
    c.send({"t": "act", "id": "a", "action": action, "args": args})
    m = c.reply("a", ("done", "err", "snap"))
    print(json.dumps(m))
    return 0 if m["t"] == "done" else 1


def tokens(keys):
    c = Client()
    c.send({"t": "sub", "id": "s", "doc": "theme"})
    m = c.reply("s", ("snap", "err"))
    t = (m.get("data") or {}).get("tokens", {})
    print(json.dumps([t.get(k) for k in keys]))


def count(doc, seconds):
    """Patches of `doc` for `seconds` after its first snapshot. A timeout or a closed connection ends the count."""
    c = Client()
    c.send({"t": "sub", "id": "s", "doc": doc})
    end, patches = None, 0
    while True:
        try:
            line = c.f.readline()
        except socket.timeout:
            break
        if not line:
            break
        m = json.loads(line)
        if m.get("t") == "err":
            sys.exit("ipc: " + json.dumps(m))
        if m["t"] == "snap" and end is None:
            end = time.monotonic() + seconds
            c.sock.settimeout(max(0.05, end - time.monotonic()))
        elif m["t"] == "patch" and m.get("doc") == doc:
            patches += 1
        if end is not None:
            left = end - time.monotonic()
            if left <= 0:
                break
            c.sock.settimeout(left)
    print(patches)


def main(argv):
    a = argv[1:]
    if a[:1] == ["act"] and len(a) in (2, 3):
        return act(a[1], json.loads(a[2]) if len(a) == 3 else {})
    if a[:1] == ["sub"] and len(a) == 2:
        return sub(a[1], null_on_err=True)
    if a[:1] == ["tokens"]:
        return tokens(a[1:])
    if len(a) == 3 and a[1] == "count":
        return count(a[0], float(a[2]))
    if len(a) == 1:
        return sub(a[0])
    sys.exit(USAGE)


if __name__ == "__main__":
    sys.exit(main(sys.argv) or 0)
