#!/usr/bin/env python3
# A test double for a mod's host process (MODS.md "Host processes", PROTOCOL §2). It reads the scope the daemon
# hands it in the environment, connects with the scoped hello as the web host does, and then does what --mode says.
# It is installed under the names the test mods declare (tests/hosts.rs). It ends on SIGTERM, and when its parent
# (the test process) is gone, so no test leaves it running.
import json
import os
import signal
import socket
import sys
import time


def option(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def append(path, text):
    if path:
        with open(path, "a") as f:
            f.write(text)


def send(conn, msg):
    conn.sendall((json.dumps(msg) + "\n").encode())


def wait_while_parent_lives(parent):
    while os.getppid() == parent:
        time.sleep(0.2)


mode = option("--mode", "hold")
parent = os.getppid()
append(option("--start"), "started\n")

term_file = option("--term")
if term_file:

    def on_term(signum, frame):
        append(term_file, "term\n")
        sys.exit(0)

    signal.signal(signal.SIGTERM, on_term)

if mode == "exit":
    sys.exit(3)

if mode == "noconnect":
    wait_while_parent_lives(parent)
    sys.exit(0)

token = os.environ["KURASHI_SCOPE_TOKEN"]
mod = os.environ["KURASHI_SCOPE_MOD"]
append(option("--token"), token + "\n")
conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
conn.settimeout(10)
conn.connect(option("--socket") or os.environ["KURASHI_SOCKET"])
reader = conn.makefile("r")
send(conn, {"t": "hello", "v": 1, "client": "fake-host", "caps": ["intents"],
            "scope": {"mod": mod, "token": token}})
append(option("--report"), reader.readline())

if mode == "probe":
    # What a scoped connection may do (PROTOCOL §2): its own document, `theme`, its own action, `ping`; the rest is
    # forbidden. Every reply is recorded for the test.
    send(conn, {"t": "sub", "id": "p1", "doc": "mod." + mod})
    send(conn, {"t": "sub", "id": "p2", "doc": "daemon"})
    send(conn, {"t": "act", "id": "p3", "action": mod + ".state", "args": {}})
    send(conn, {"t": "act", "id": "p4", "action": "hello.ping", "args": {}})
    send(conn, {"t": "intent", "key": "x", "value": 1})
    send(conn, {"t": "sub", "id": "p5", "doc": "theme"})
    send(conn, {"t": "ping"})
    seen, pong = set(), False
    while not (pong and {"p1", "p2", "p3", "p4", "p5"} <= seen):
        line = reader.readline()
        if not line:
            break
        append(option("--report"), line)
        message = json.loads(line)
        pong = pong or message.get("t") == "pong"
        if "id" in message:
            seen.add(message["id"])

wait_while_parent_lives(parent)
