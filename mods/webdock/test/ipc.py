#!/usr/bin/env python3
# The web dock test's socket client (stdlib only, as frontend/test-peek.sh's ipc.py): over the sandbox's kurashi
# socket ($KURASHI_SOCKET), an unscoped connection that either runs one action or prints one document.
#   ipc.py act <action> [json-args]   → prints the action's reply (done or err)
#   ipc.py doc <doc>                  → prints the document's data as JSON
# Exit 1 on an error reply or a silent mock (every read is bounded).
import json
import os
import socket
import sys


def connect():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(os.environ["KURASHI_SOCKET"])
    f = sock.makefile("rwb")

    def send(msg):
        f.write((json.dumps(msg) + "\n").encode())
        f.flush()

    def recv():
        line = f.readline()
        if not line:
            sys.exit("ipc: the socket closed")
        return json.loads(line)

    send({"t": "hello", "v": 1, "client": "webdock-test", "caps": ["intents", "resync"]})
    if recv()["t"] != "welcome":
        sys.exit("ipc: no welcome")
    return send, recv


def main():
    send, recv = connect()
    if sys.argv[1] == "act":
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        send({"t": "act", "id": "a", "action": sys.argv[2], "args": args})
        while True:
            m = recv()
            if m.get("id") == "a" and m["t"] in ("done", "err"):
                print(json.dumps(m))
                sys.exit(0 if m["t"] == "done" else 1)
    if sys.argv[1] == "doc":
        send({"t": "sub", "id": "s", "doc": sys.argv[2]})
        while True:
            m = recv()
            if m.get("t") == "snap" and m.get("id") == "s":
                print(json.dumps(m["data"]))
                return
            if m.get("t") == "err" and m.get("id") == "s":
                sys.exit("ipc: " + m.get("msg", "refused"))
    sys.exit("usage: ipc.py act <action> [json-args] | ipc.py doc <doc>")


if __name__ == "__main__":
    main()
