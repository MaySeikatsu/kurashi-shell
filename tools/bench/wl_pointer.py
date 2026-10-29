#!/usr/bin/env python3
# Moves and clicks the pointer on the sandbox's seat through a virtual pointer (zwlr_virtual_pointer_v1), for
# the frontend click tests. The sandbox seat has no pointer device (WLR_LIBINPUT_NO_DEVICES, headless backend),
# so `swaymsg seat - cursor press` reaches no client. It speaks only to the sandbox's own socket (the rule of
# tools/bench/wl_keys.py).
#   tools/bench/wl_pointer.py move <x> <y>                  → move, then settle
#   tools/bench/wl_pointer.py click <x> <y> <left|middle|right>
#   tools/bench/wl_pointer.py sweep <x0> <y0> <x1> <y1> <s> → travel in a straight line in s seconds (~60 motion events/s,
#                                                             no settle between them: a pointer that really moves)
#   tools/bench/wl_pointer.py --serve                       → one pointer for the whole run: every stdin line is
#                                                             "move x y", "click x y <button>" or "sweep …"; EOF ends it
# x and y are layout coordinates, the ones swaymsg's rects use. The layout box comes from xdg-output on the same
# socket, so a caller needs no output size. Timing is what the frontend tests always used: 0.5 s after the pointer
# appears, 0.2 s between motion and press, 0.5 s before the pointer goes away (closing the socket destroys it).
# Usage errors exit 2, connection errors exit 1.
import os
import re
import socket
import struct
import sys
import time

BUTTONS = {"left": 272, "middle": 274, "right": 273}   # evdev BTN_LEFT, BTN_MIDDLE, BTN_RIGHT
SANDBOX_RUNTIME = re.compile(r"/tmp/kurashi-sb-[^/]+")
USAGE = ("usage: wl_pointer.py move <x> <y> | wl_pointer.py click <x> <y> <left|middle|right> "
         "| wl_pointer.py sweep <x0> <y0> <x1> <y1> <seconds> | wl_pointer.py --serve")
DISPLAY = 1


def die(message, code=2):
    print(message, file=sys.stderr)
    sys.exit(code)


def sandbox_socket():
    # Refuse any other socket: outside a sandbox these variables name the user's session, where a virtual
    # pointer would click in their windows.
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if not SANDBOX_RUNTIME.fullmatch(runtime) or not display or "/" in display:
        sys.exit("wl_pointer.py: XDG_RUNTIME_DIR/WAYLAND_DISPLAY are not a sandbox's; eval the output of "
                 "tools/bench/sandbox.sh start first (refusing to touch another session)")
    return os.path.join(runtime, display)


def string(text):
    raw = text.encode() + b"\0"
    return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


def command(parts):
    # "move x y", "click x y <button>" or "sweep x0 y0 x1 y1 s" → (verb, x, y, rest); anything else is a usage
    # error. rest: the button for a click, (x1, y1, seconds) for a sweep, None for a move.
    try:
        if len(parts) == 3 and parts[0] == "move":
            return "move", int(parts[1]), int(parts[2]), None
        if len(parts) == 4 and parts[0] == "click" and parts[3] in BUTTONS:
            return "click", int(parts[1]), int(parts[2]), parts[3]
        if len(parts) == 6 and parts[0] == "sweep":
            return "sweep", int(parts[1]), int(parts[2]), (int(parts[3]), int(parts[4]), float(parts[5]))
        if len(parts) == 5 and parts[0] == "wheel":
            return "wheel", int(parts[1]), int(parts[2]), (int(parts[3]), float(parts[4]))
    except ValueError:
        pass
    die("wl_pointer.py: want 'move <x> <y>', 'click <x> <y> <left|middle|right>' or "
        "'sweep <x0> <y0> <x1> <y1> <seconds>' or 'wheel <x> <y> <notches> <seconds between>' (negative: down)")


class Pointer:
    """A virtual pointer on the sandbox seat. It exists while this object's socket is open."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        try:
            self.sock.connect(sandbox_socket())
        except OSError as e:
            sys.exit(f"wl_pointer.py: cannot connect to the sandbox socket: {e}")
        self.inbuf = bytearray()
        self.last_id = DISPLAY   # client ids go up by one: libwayland rejects a skipped id
        self.globals = []        # (name, interface, version) from wl_registry.global
        self.reg = self.new_id()
        self.send(DISPLAY, 1, struct.pack("<I", self.reg))   # wl_display.get_registry
        for obj, op, body in self.roundtrip():
            if obj == self.reg and op == 0:  # wl_registry.global(name, interface, version)
                name, = struct.unpack_from("<I", body, 0)
                n, = struct.unpack_from("<I", body, 4)
                iface = body[8:8 + n - 1].decode()
                version, = struct.unpack_from("<I", body, 8 + ((n + 3) & ~3))
                self.globals.append((name, iface, version))

        seat = self.bind(*self.find("wl_seat"), 5)
        # The virtual pointer maps x / x_extent onto the layout's bounding box (the device is not mapped to an
        # output), so x, y are taken relative to that box. xdg-output gives each output's logical geometry: the
        # numbers swaymsg reports as rects.
        xdg_manager = self.bind(*self.find("zxdg_output_manager_v1"), 3)
        outputs = [g for g in self.globals if g[1] == "wl_output"]
        if not outputs:
            sys.exit("wl_pointer.py: the compositor announces no output")
        xdg = []
        for name, iface, version in outputs:
            output = self.bind(name, iface, version, 4)
            obj = self.new_id()
            self.send(xdg_manager, 1, struct.pack("<II", obj, output))   # get_xdg_output(id, output)
            xdg.append(obj)
        pos, size = {}, {}
        for obj, op, body in self.roundtrip():
            if obj in xdg and op == 0:    # zxdg_output_v1.logical_position(x, y)
                pos[obj] = struct.unpack_from("<ii", body)
            elif obj in xdg and op == 1:  # zxdg_output_v1.logical_size(width, height)
                size[obj] = struct.unpack_from("<ii", body)
        if len(pos) < len(xdg) or len(size) < len(xdg):
            sys.exit("wl_pointer.py: xdg-output sent no logical geometry")
        x0 = min(pos[o][0] for o in xdg)
        y0 = min(pos[o][1] for o in xdg)
        x1 = max(pos[o][0] + size[o][0] for o in xdg)
        y1 = max(pos[o][1] + size[o][1] for o in xdg)
        self.box = (x0, y0, x1 - x0, y1 - y0)

        manager = self.bind(*self.find("zwlr_virtual_pointer_manager_v1"), 2)
        self.pointer = self.new_id()
        self.send(manager, 0, struct.pack("<II", seat, self.pointer))   # create_virtual_pointer(seat, id)
        time.sleep(0.5)  # let clients learn about the new pointer capability before the first event

    def send(self, obj, op, payload=b""):
        self.sock.sendall(struct.pack("<IHH", obj, op, 8 + len(payload)) + payload)

    def read_event(self):
        while True:
            if len(self.inbuf) >= 8:
                obj, op, size = struct.unpack_from("<IHH", self.inbuf)
                if len(self.inbuf) >= size:
                    body = bytes(self.inbuf[8:size])
                    del self.inbuf[:size]
                    return obj, op, body
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                sys.exit("wl_pointer.py: the compositor did not answer within 5 s")
            if not chunk:
                sys.exit("wl_pointer.py: compositor closed the connection")
            self.inbuf.extend(chunk)

    def new_id(self):
        self.last_id += 1
        return self.last_id

    def find(self, iface):
        for name, have, version in self.globals:
            if have == iface:
                return name, have, version
        sys.exit(f"wl_pointer.py: the compositor does not offer {iface}")

    def bind(self, name, iface, version, max_version):
        # wl_registry.bind(name, interface, version, new_id); returns the new object's id.
        new = self.new_id()
        self.send(self.reg, 0, struct.pack("<I", name) + string(iface)
                  + struct.pack("<II", min(version, max_version), new))
        return new

    def roundtrip(self):
        # wl_display.sync: returns the events sent before the callback fired, so everything sent before this
        # call has been handled by the compositor.
        cb = self.new_id()
        self.send(DISPLAY, 0, struct.pack("<I", cb))
        events = []
        while True:
            obj, op, body = self.read_event()
            if obj == cb and op == 0:
                return events
            if obj == DISPLAY and op == 0:  # wl_display.error
                sys.exit(f"wl_pointer.py: wayland error {body!r}")
            events.append((obj, op, body))

    def motion(self, x, y):
        # motion_absolute(time, x, y, x_extent, y_extent) inside the layout box, then frame.
        bx, by, bw, bh = self.box
        if not (0 <= x - bx < bw and 0 <= y - by < bh):
            die(f"wl_pointer.py: ({x}, {y}) is outside the layout ({bx}, {by}, {bw}x{bh})")
        self.send(self.pointer, 1, struct.pack("<IIIII", ms(), x - bx, y - by, bw, bh))
        self.send(self.pointer, 4)

    def settle(self):
        # The compositor has handled everything sent so far; give it time to act before the pointer goes away.
        self.roundtrip()
        time.sleep(0.5)

    def move(self, x, y):
        self.motion(x, y)
        self.settle()

    def click(self, x, y, button):
        self.motion(x, y)
        time.sleep(0.2)
        # button(time, button, state): pressed (1), then released (0); each event is a frame.
        self.send(self.pointer, 2, struct.pack("<III", ms(), BUTTONS[button], 1))
        self.send(self.pointer, 4)
        self.send(self.pointer, 2, struct.pack("<III", ms(), BUTTONS[button], 0))
        self.send(self.pointer, 4)
        self.settle()

    def sweep(self, x0, y0, x1, y1, seconds):
        # Motion events about every 16 ms from (x0, y0) to (x1, y1), so the last one lands after `seconds`. No settle
        # between events (a move waits 0.5 s), so the frontend gets a pointer that really travels.
        steps = max(1, round(seconds * 60))
        start = time.monotonic()
        for i in range(steps + 1):
            f = i / steps
            self.motion(round(x0 + (x1 - x0) * f), round(y0 + (y1 - y0) * f))
            time.sleep(max(0.0, start + (i + 1) * seconds / steps - time.monotonic()))
        self.roundtrip()   # the compositor has handled every event before the next line is read

    def wheel(self, x, y, notches, gap):
        # Mouse-wheel notches at (x, y): axis_source(wheel), then per notch axis_discrete(time, vertical, value, ±1) and a
        # frame, `gap` s apart (a positive count scrolls up, as a wheel turned away from the user).
        self.motion(x, y)
        time.sleep(0.2)
        step = -1 if notches > 0 else 1
        for _ in range(abs(notches)):
            self.send(self.pointer, 5, struct.pack("<I", 0))
            self.send(self.pointer, 7, struct.pack("<IIii", ms(), 0, step * 15 * 256, step))
            self.send(self.pointer, 4)
            self.roundtrip()
            time.sleep(gap)
        self.settle()

    def perform(self, cmd):
        verb, x, y, rest = cmd
        if verb == "move":
            self.move(x, y)
        elif verb == "sweep":
            self.sweep(x, y, *rest)
        elif verb == "wheel":
            self.wheel(x, y, *rest)
        else:
            self.click(x, y, rest)


def main(argv):
    if argv == ["--serve"]:
        pointer = Pointer()
        for line in sys.stdin:
            parts = line.split()
            if parts:
                pointer.perform(command(parts))
        return
    if not argv:
        die(USAGE)
    cmd = command(argv)   # validated before connecting: a usage error must not open a socket
    pointer = Pointer()
    pointer.perform(cmd)


if __name__ == "__main__":
    main(sys.argv[1:])
