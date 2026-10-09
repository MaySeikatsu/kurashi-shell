# Card W9-test-helpers — one shared virtual keyboard + pointer for sandbox tests (I6, CONTRACT #6)

**Read first:** `docs/tasks/README.md`, `docs/BACKLOG.md` row I6, `docs/CONTRACT-CHANGE.md` row 6,
`settings/keys.py` (virtual keyboard, zwp_virtual_keyboard_v1), `frontend/test-bindings.sh` (embedded
virtual pointer, zwlr_virtual_pointer_v1, ~l.48–145), `frontend/test-tray-bt.sh` (another embedded
click helper, ~l.105), `tools/bench/README.md`.

**Owned paths:** `tools/bench/wl_keys.py` (new; the content of `settings/keys.py`, same CLI),
`tools/bench/wl_pointer.py` (new; `move/click <x> <y> <left|middle|right>` and `--serve` like keys.py),
`tools/bench/README.md` (a row each), `frontend/test-bindings.sh`, `frontend/test-tray-bt.sh`.
NOT `settings/**` (another card owns it; the lead switches `settings/test.sh` to `tools/bench/wl_keys.py`
and deletes `settings/keys.py` at merge — leave `settings/keys.py` in place).

**Do:** move the helpers into the two files (raw Wayland wire, no pywayland — the devShell has none;
only `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`, never another socket); both frontend tests call them instead of
their embedded copies. Behaviour identical (same coordinates, same settle times).

**Acceptance:** `nix develop -c frontend/test-bindings.sh` and `nix develop -c frontend/test-tray-bt.sh`
pass exactly as before (use `KURASHI_BIN_DIR=tools/bench/bin` or build per the scripts' headers; on
machine B `KURASHI_RENDER_NODE=/dev/dri/renderD129`); `python3 tools/bench/wl_keys.py` and
`wl_pointer.py` without args print usage and exit 2; `grep -c zwlr_virtual_pointer frontend/*.sh` → 0.
