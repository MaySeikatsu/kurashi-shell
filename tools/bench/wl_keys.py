#!/usr/bin/env python3
# Presses keys on the sandbox's seat through a virtual keyboard (zwp_virtual_keyboard_v1), for the settings
# and frontend keyboard tests. It speaks only to the sandbox's own socket: XDG_RUNTIME_DIR must be a
# tools/bench/sandbox.sh runtime dir (/tmp/kurashi-sb-<name>), so eval the sandbox's env lines first.
#   tools/bench/wl_keys.py tab space  → one keyboard for this call: press Tab, then Space
#   tools/bench/wl_keys.py alt+up shift+tab escape → chords: Alt held while Up, Shift while Tab, then Escape
#                                       (modifiers: shift, ctrl, alt, super; ctrl+shift+tab holds both)
#   tools/bench/wl_keys.py colon slash period 0    → characters, one token each: `:` `/` `.` and the digits, and
#                                       the other punctuation of CHAR_TOKENS (`-`, `_`, `+`, `?`, `&`, `#`, …)
#   tools/bench/wl_keys.py --serve    → one keyboard for the whole run: every stdin line is keys to press
#                                       ("tab", "space", "x", …); EOF ends it. A keyboard that goes away makes
#                                       the compositor drop the window's keyboard focus, so a test that Tabs
#                                       more than once keeps one open.
# Usage errors exit 2, connection errors exit 1. Raw wire (the devShell has no pywayland); the pointer
# twin is tools/bench/wl_pointer.py.
import array
import os
import re
import socket
import struct
import sys
import time

# Named keys: evdev code and keysym. The keymap maps evdev code + 8, as XKB keycodes do.
SPECIAL = {"tab": (15, "Tab"), "return": (28, "Return"), "space": (57, "space"), "escape": (1, "Escape"),
           "backspace": (14, "BackSpace"), "delete": (111, "Delete"),
           "left": (105, "Left"), "right": (106, "Right"), "up": (103, "Up"), "down": (108, "Down")}
# Modifiers: evdev code, keysym and the XKB real modifier they set (Alt is Mod1, Super is Mod4 — the Mod of kurashi's
# combos, W38-keys).
MODIFIERS = {"shift": (42, "Shift_L", "Shift"), "ctrl": (29, "Control_L", "Control"),
             "alt": (56, "Alt_L", "Mod1"), "super": (125, "Super_L", "Mod4")}
# The bit each modifier is in the modifier state (xkb's real modifiers in order: Shift, Lock, Control, Mod1 … Mod4).
MODIFIER_BITS = {"shift": 1 << 0, "ctrl": 1 << 2, "alt": 1 << 3, "super": 1 << 6}
# Letters a-z (evdev codes in QWERTY order), for typing into text fields.
LETTER_CODES = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38,
                44, 45, 46, 47, 48, 49, 50]
LETTERS = {letter: (code, letter) for letter, code in zip("qwertyuiopasdfghjklzxcvbnm", LETTER_CODES)}
# Digits and the punctuation a URL or a path needs (W18-settings, I81): one key each, unshifted on this keymap, so
# `:` is the key named colon. The evdev code is the US key's where there is one; the shifted ones get spare codes.
CHARS = {str(d): (11 if d == 0 else d + 1, str(d)) for d in range(10)}
CHARS.update({"minus": (12, "minus"), "equal": (13, "equal"), "bracketleft": (26, "bracketleft"),
              "bracketright": (27, "bracketright"), "semicolon": (39, "semicolon"), "apostrophe": (40, "apostrophe"),
              "grave": (41, "grave"), "backslash": (43, "backslash"), "comma": (51, "comma"),
              "period": (52, "period"), "slash": (53, "slash")})
CHARS.update({name: (200 + i, name) for i, name in enumerate(
    ["colon", "underscore", "plus", "question", "percent", "ampersand", "asterisk", "at", "numbersign",
     "asciitilde", "exclam", "quotedbl", "parenleft", "parenright", "less", "greater", "braceleft", "braceright"])})
# The character a test may type as a token of its own (`:`, `/`, `.`), and the name of its key.
CHAR_TOKENS = {"-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", ";": "semicolon",
               "'": "apostrophe", "`": "grave", "\\": "backslash", ",": "comma", ".": "period", "/": "slash",
               ":": "colon", "_": "underscore", "+": "plus", "?": "question", "%": "percent", "&": "ampersand",
               "*": "asterisk", "@": "at", "#": "numbersign", "~": "asciitilde", "!": "exclam", '"': "quotedbl",
               "(": "parenleft", ")": "parenright", "<": "less", ">": "greater", "{": "braceleft", "}": "braceright"}
KEYS = {name: code for name, (code, _) in SPECIAL.items()}
KEYS.update({letter: code for letter, (code, _) in LETTERS.items()})
KEYS.update({name: code for name, (code, _) in CHARS.items()})
KEYS.update({name: code for name, (code, _, _) in MODIFIERS.items()})
# Keycodes in table order: the named keys, the letters, the characters, then the modifiers (keymap() counts the
# modifiers from the end).
ENTRIES = (list(SPECIAL.values()) + list(LETTERS.values()) + list(CHARS.values())
           + [(code, sym) for code, sym, _ in MODIFIERS.values()])

# The only socket this helper opens is in a sandbox runtime dir; the user's /run/user/<uid> never matches.
SANDBOX_RUNTIME = re.compile(r"/tmp/kurashi-sb-[^/]+")
USAGE = ("usage: wl_keys.py <key|modifier+key> [...] | wl_keys.py --serve   (keys: " + " ".join(KEYS)
         + "; modifiers: " + " ".join(MODIFIERS) + ")")


def keymap():
    # A complete keymap for exactly the keys above, with no includes: the compositor needs no
    # xkeyboard-config data to compile it. Keycode names are K00, K01, … in table order.
    codes = " ".join(f"<K{i:02d}> = {code + 8};" for i, (code, _) in enumerate(ENTRIES))
    symbols = []
    for i, (_, sym) in enumerate(ENTRIES):
        if sym == "Tab":  # Shift+Tab is ISO_Left_Tab, as on a real keyboard
            symbols.append(f"key <K{i:02d}> {{ type = \"TWO_LEVEL\", symbols[Group1] = [ Tab, ISO_Left_Tab ] }};")
        else:
            symbols.append(f"key <K{i:02d}> {{ [ {sym} ] }};")
    # A modifier key sets its real modifier, so keys pressed while it is held see it.
    first = len(ENTRIES) - len(MODIFIERS)
    for j, (_, _, mod) in enumerate(MODIFIERS.values()):
        symbols.append(f"modifier_map {mod} {{ <K{first + j:02d}> }};")
    types = ('type "ONE_LEVEL" { modifiers = none; level_name[Level1] = "Any"; }; '
             'type "TWO_LEVEL" { modifiers = Shift; map[Shift] = Level2; '
             'level_name[Level1] = "Base"; level_name[Level2] = "Shift"; };')
    text = ("xkb_keymap {\n"
            f'  xkb_keycodes "kurashi" {{ minimum = 8; maximum = 255; {codes} }};\n'
            f'  xkb_types "kurashi" {{ {types} }};\n'
            '  xkb_compat "kurashi" { };\n'
            f'  xkb_symbols "kurashi" {{ {" ".join(symbols)} }};\n'
            "};\n")
    return text.encode() + b"\x00"


KEYMAP = keymap()

# Client object ids must be allocated in order (libwayland rejects a skipped id): the display is 1,
# the registry 2, the setup sync 3, then seat, manager and keyboard; the sync callbacks follow.
DISPLAY, REG, SEAT, MANAGER, KBD = 1, 2, 4, 5, 6


def die(message, code=2):
    print(message, file=sys.stderr)
    sys.exit(code)


def sandbox_socket():
    # Refuse any other socket: outside a sandbox these variables name the user's session, where a virtual
    # keyboard would type into their windows.
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if not SANDBOX_RUNTIME.fullmatch(runtime) or not display or "/" in display:
        sys.exit("wl_keys.py: XDG_RUNTIME_DIR/WAYLAND_DISPLAY are not a sandbox's; eval the output of "
                 "tools/bench/sandbox.sh start first (refusing to touch another session)")
    return os.path.join(runtime, display)


class Keyboard:
    """A virtual keyboard on the sandbox seat. It exists while this object's socket is open."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        try:
            self.sock.connect(sandbox_socket())
        except OSError as e:
            sys.exit(f"wl_keys.py: cannot connect to the sandbox socket: {e}")
        self.inbuf = bytearray()
        self.callbacks = 3   # the next free object id
        self.setup()

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
                sys.exit("wl_keys.py: the compositor did not answer within 5 s")
            if not chunk:
                sys.exit("wl_keys.py: compositor closed the connection")
            self.inbuf.extend(chunk)

    def new_callback(self):
        self.callbacks += 1
        return self.callbacks - 1

    def roundtrip(self):
        # wl_display.sync: returns once the compositor has handled everything sent before it.
        cb = self.new_callback()
        self.send(DISPLAY, 0, struct.pack("<I", cb))
        while True:
            obj, op, body = self.read_event()
            if obj == cb and op == 0:
                return
            if obj == DISPLAY and op == 0:  # wl_display.error
                sys.exit(f"wl_keys.py: wayland error {body!r}")

    def setup(self):
        # wl_display.get_registry, then sync: the globals are announced before the callback fires.
        self.send(DISPLAY, 1, struct.pack("<I", REG))
        cb = self.new_callback()
        self.send(DISPLAY, 0, struct.pack("<I", cb))
        globals_ = {}
        while True:
            obj, op, body = self.read_event()
            if obj == REG and op == 0:  # wl_registry.global(name, interface, version)
                name, = struct.unpack_from("<I", body, 0)
                n, = struct.unpack_from("<I", body, 4)
                iface = body[8:8 + n - 1].decode()
                version, = struct.unpack_from("<I", body, 8 + ((n + 3) & ~3))
                globals_[iface] = (name, version)
            elif obj == cb and op == 0:
                break
            elif obj == DISPLAY and op == 0:
                sys.exit(f"wl_keys.py: wayland error {body!r}")

        def bind(iface, max_version, new_id):
            name, version = globals_[iface]  # KeyError: the compositor does not offer it
            self.send(REG, 0, struct.pack("<I", name) + string(iface)
                      + struct.pack("<II", min(version, max_version), new_id))

        bind("wl_seat", 5, SEAT)
        bind("zwp_virtual_keyboard_manager_v1", 1, MANAGER)
        # create_virtual_keyboard(seat, new_id): the seat gains a keyboard for the clients.
        self.send(MANAGER, 0, struct.pack("<II", SEAT, KBD))
        # keymap(format, fd, size): xkb_v1 is format 1; the fd travels as ancillary data, and the
        # size counts the terminating NUL that KEYMAP ends with.
        fd = os.memfd_create("kurashi-keymap")
        os.write(fd, KEYMAP)
        self.sock.sendmsg([struct.pack("<IHH", KBD, 0, 8 + 8) + struct.pack("<II", 1, len(KEYMAP))],
                          [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [fd]))])
        os.close(fd)
        self.callbacks = KBD + 1   # the sync callbacks below take the ids after the keyboard
        # Clients learn about the new keyboard asynchronously; a key sent before they have it is lost.
        time.sleep(0.5)

    def key(self, code, state):
        # key(time, key, state): pressed (1), then released (0).
        self.send(KBD, 1, struct.pack("<III", ms(), code, state))

    def modifiers(self, depressed):
        # zwp_virtual_keyboard_v1.modifiers(mods_depressed, mods_latched, mods_locked, group): the modifier state the
        # keys that follow are sent with. The key event alone did not carry Alt to the clients (W18-settings).
        self.send(KBD, 2, struct.pack("<IIII", depressed, 0, 0, 0))

    def chord(self, mods, name):
        # Modifiers go down first and up last; each change is confirmed by a roundtrip, so the
        # compositor has it before the key that needs it. The state the modifiers add up to is sent too.
        depressed = 0
        for mod in mods:
            self.key(MODIFIERS[mod][0], 1)
            self.roundtrip()
            depressed |= MODIFIER_BITS[mod]
            self.modifiers(depressed)
            self.roundtrip()
        self.key(KEYS[name], 1)
        time.sleep(0.05)
        self.key(KEYS[name], 0)
        self.roundtrip()
        for mod in reversed(mods):
            self.key(MODIFIERS[mod][0], 0)
            self.roundtrip()
            depressed &= ~MODIFIER_BITS[mod]
            self.modifiers(depressed)
            self.roundtrip()
        time.sleep(0.1)


def ms():
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


def string(text):
    raw = text.encode() + b"\0"
    return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def parse(token):
    # `alt+up`: Alt held while Up is pressed; `ctrl+shift+tab` holds both; a bare name is pressed alone. A character
    # is a token of its own (`:`, `/`, `+`), so `+` never reads as a chord.
    if token in CHAR_TOKENS:
        return [], CHAR_TOKENS[token]
    *mods, name = token.split("+")
    for mod in mods:
        if mod not in MODIFIERS:
            die(f"wl_keys.py: {mod!r} is not a modifier (modifiers: {' '.join(MODIFIERS)})")
    if name not in KEYS:
        die(f"wl_keys.py: unknown key {name!r} (known: {' '.join(KEYS)})")
    return mods, name


def main(argv):
    if argv == ["--serve"]:
        kb = Keyboard()
        for line in sys.stdin:
            chords = [parse(token) for token in line.split()]  # refuse a line before pressing any of it
            for mods, name in chords:
                kb.chord(mods, name)
        return
    if not argv:
        die(USAGE)
    chords = [parse(token) for token in argv]
    kb = Keyboard()
    for mods, name in chords:
        kb.chord(mods, name)


if __name__ == "__main__":
    main(sys.argv[1:])
