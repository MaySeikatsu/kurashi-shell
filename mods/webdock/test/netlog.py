#!/usr/bin/env python3
# The web dock's privacy proof (docs/ux/webdock.md "Privacy", K38): Chromium's net log, recorded with the host's
# switches plus --log-net-log, must hold no request that the fixture pages did not make. The control page (served
# over loopback) makes one request on purpose; it must appear in the log, so an empty log cannot pass by accident.
#   netlog.py <net log file> <pages dir> <control's ping.txt URL> [the control page's own URLs...]
# Exit 0 when every URL is a fixture page's own, one of the control page's listed URLs, or about:blank, and the
# control's ping.txt request is there; 1 otherwise. The loopback origin is not allowed as a whole: a favicon.ico
# request to it is a request the page did not make.
import json
import sys


def load(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    try:
        return json.loads(text)
    except ValueError:
        # Chromium closes the events array at shutdown; a log cut short by a kill is closed here.
        body = text.rstrip().rstrip(",")
        return json.loads(body + "]}")


def urls(node, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in ("url", "original_url", "request_url") and isinstance(value, str):
                out.add(value)
            else:
                urls(value, out)
    elif isinstance(node, list):
        for item in node:
            urls(item, out)
    return out


def main():
    net_log, pages, ping = sys.argv[1], sys.argv[2], sys.argv[3]
    exact = set(sys.argv[3:])  # the control page's own requests by their full URLs: its ping.txt and itself
    log = load(net_log)
    seen = urls(log.get("events", []), set())
    own_prefix = "file://" + pages.rstrip("/") + "/"

    def allowed(u):
        return u.startswith(own_prefix) or u in exact or u == "about:blank"

    foreign = sorted(u for u in seen if not allowed(u))
    own = sorted(u for u in seen if allowed(u))
    print("net log: %d events, %d URLs (%d fixture or control, %d foreign)"
          % (len(log.get("events", [])), len(seen), len(own), len(foreign)))
    for u in own[:20]:
        print("  own:", u)
    for u in foreign:
        print("  FOREIGN:", u)
    control_seen = ping in seen
    print("positive control (the control page's request for ping.txt) in the log:", "yes" if control_seen else "NO")
    if foreign or not control_seen:
        sys.exit(1)
    print("netlog PASS")


if __name__ == "__main__":
    main()
