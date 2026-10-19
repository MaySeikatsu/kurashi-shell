import gi, os, sys
gi.require_version("Gtk", "4.0"); gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gtk, Gtk4LayerShell as LS
BASE = os.environ.get("SPIKE_BASE") == "1"
if not BASE:
    gi.require_version("WebKit", "6.0")
    from gi.repository import WebKit
# Children inherit the sandbox's network namespace; drop the join preload for them (same as the Chromium spike).
os.environ.pop("LD_PRELOAD", None)
def activate(app):
    win = Gtk.Window(application=app)
    LS.init_for_window(win); LS.set_layer(win, LS.Layer.TOP)
    for e in (LS.Edge.LEFT, LS.Edge.TOP, LS.Edge.BOTTOM): LS.set_anchor(win, e, True)
    LS.set_keyboard_mode(win, LS.KeyboardMode.ON_DEMAND)
    win.set_default_size(480, -1)
    if BASE:
        win.set_child(Gtk.Label(label="baseline")); win.present(); print("SPIKE LOAD 2", flush=True); return
    store = os.environ["SPIKE_STORE"]
    session = WebKit.NetworkSession.new(store + "/wk-data", store + "/wk-cache")
    view = WebKit.WebView(network_session=session)
    view.connect("notify::title", lambda v, p: print("SPIKE TITLE", v.get_title(), flush=True))
    view.connect("load-changed", lambda v, e: print("SPIKE LOAD", 2 if int(e) == 3 else int(e), flush=True))
    win.set_child(view); view.load_uri(os.environ["SPIKE_URL"]); win.present(); view.grab_focus()
app = Gtk.Application(application_id="dev.kurashi.webkitspike"); app.connect("activate", activate); app.run([])
