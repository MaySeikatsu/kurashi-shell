#!/usr/bin/env python3
# The test's pins for kurashi-mock's mod.webdock (test-host.sh): the fixture pages as file:// sites, one view pin, and
# (with a port) the control page served over loopback. Prints the `mock.webdock` arguments as JSON.
#   pins.py <repo root> [loopback port]
import json
import os
import sys

root = os.path.abspath(sys.argv[1])
port = sys.argv[2] if len(sys.argv) > 2 else ""
pages = "file://" + os.path.join(root, "mods", "webdock", "test", "pages")


def site(pin, profile, view="mobile", target=None):
    return {
        "id": pin,
        "kind": "web",
        "title": pin.capitalize(),
        "target": target or pages + "/site.html#" + pin,
        "view": view,
        "profile": profile,
    }


pins = [
    site("mail", "mail"),
    site("chat", "chat", view="desktop"),
    site("typed", "typed"),
    site("split1", "split1"),
    site("split2", "split2"),
    site("shared1", "shared"),
    site("shared2", "shared"),
    site("sign", "sign"),
    site("k1", "k1"),
    site("k2", "k2"),
    site("k3", "k3"),
    site("k4", "k4"),
    site("k5", "k5"),
    {"id": "cam", "kind": "web", "title": "Camera", "target": pages + "/camera.html", "view": "mobile", "profile": "cam"},
    {"id": "bad", "kind": "web", "title": "Broken", "target": "file:///nonexistent/page.html", "view": "mobile", "profile": "bad"},
    {"id": "weather", "kind": "view", "title": "Weather", "target": "mod:weather:weather"},
]
if port:
    pins.append({"id": "ctl", "kind": "web", "title": "Control", "target": "http://127.0.0.1:%s/control.html" % port,
                 "view": "mobile", "profile": "ctl"})
print(json.dumps({"pins": pins}))
