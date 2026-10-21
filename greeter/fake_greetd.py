#!/usr/bin/env python3
# A fake greetd for greeter/test.sh: the greetd IPC (a native-endian u32 length, then JSON; greetd-ipc(7)) on a unix
# socket, with one password for every known user. It never touches PAM or a real session: start_session is only
# written to the log. Each request is one JSON line in the log (the response is logged as "ok": true/false, never
# the text typed).
#   fake_greetd.py <socket> <log> <password> <user>[,<user>...]
import json
import os
import socket
import struct
import sys
import threading

sock_path, log_path, password, users = sys.argv[1], sys.argv[2], sys.argv[3], set(sys.argv[4].split(","))
lock = threading.Lock()


def log(entry):
    with lock, open(log_path, "a") as f:
        f.write(json.dumps(entry) + "\n")


def recv(conn):
    head = b""
    while len(head) < 4:
        part = conn.recv(4 - len(head))
        if not part:
            return None
        head += part
    (n,) = struct.unpack("=I", head)
    body = b""
    while len(body) < n:
        part = conn.recv(n - len(body))
        if not part:
            return None
        body += part
    return json.loads(body)


def send(conn, msg):
    data = json.dumps(msg).encode()
    conn.sendall(struct.pack("=I", len(data)) + data)


def serve(conn):
    session = None  # {"user", "authed"}
    with conn:
        while True:
            req = recv(conn)
            if req is None:
                return
            kind = req.get("type")
            if kind == "create_session":
                user = req.get("username", "")
                log({"type": kind, "username": user})
                if session is not None:
                    send(conn, {"type": "error", "error_type": "error", "description": "a session is already being configured"})
                elif user not in users:
                    send(conn, {"type": "error", "error_type": "error", "description": "unknown user"})
                else:
                    session = {"user": user, "authed": False}
                    send(conn, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "})
            elif kind == "post_auth_message_response":
                ok = req.get("response") == password
                log({"type": kind, "ok": ok, "user": session and session["user"]})
                if session is None:
                    send(conn, {"type": "error", "error_type": "error", "description": "no session"})
                elif ok:
                    session["authed"] = True
                    send(conn, {"type": "success"})
                else:
                    session = None
                    send(conn, {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"})
            elif kind == "start_session":
                log({"type": kind, "cmd": req.get("cmd"), "env": req.get("env"), "user": session and session["user"],
                     "authed": bool(session and session["authed"])})
                if session and session["authed"]:
                    send(conn, {"type": "success"})
                else:
                    send(conn, {"type": "error", "error_type": "error", "description": "not authenticated"})
            elif kind == "cancel_session":
                log({"type": kind})
                session = None
                send(conn, {"type": "success"})
            else:
                log({"type": "unknown", "raw": kind})
                send(conn, {"type": "error", "error_type": "error", "description": "unknown request"})


if os.path.exists(sock_path):
    os.unlink(sock_path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(sock_path)
srv.listen(4)
log({"type": "listening"})
while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
