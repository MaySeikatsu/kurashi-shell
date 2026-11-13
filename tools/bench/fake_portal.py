#!/usr/bin/env python3
"""A stand-in for xdg-desktop-portal's Settings interface on a sandbox's session bus (session 33): only
`org.freedesktop.appearance color-scheme` (0 none, 1 dark, 2 light), read from a file that tests write ("dark" or
"light"); a change of the file sends `SettingChanged`, as the real portal does when the desktop's scheme changes.
  python3 fake_portal.py <scheme-file>      (run with a python that has dbus-python and pygobject)"""
import sys
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

IFACE = "org.freedesktop.portal.Settings"
NS, KEY = "org.freedesktop.appearance", "color-scheme"


def value_of(path):
    try:
        text = open(path).read().strip()
    except OSError:
        text = ""
    return dbus.UInt32({"dark": 1, "light": 2}.get(text, 0))


class Settings(dbus.service.Object):
    def __init__(self, bus, path):
        super().__init__(bus, "/org/freedesktop/portal/desktop")
        self.path = path
        self.now = value_of(path)
        GLib.timeout_add(150, self.poll)

    def poll(self):
        v = value_of(self.path)
        if v != self.now:
            self.now = v
            self.SettingChanged(NS, KEY, dbus.UInt32(v))
        return True

    @dbus.service.method(IFACE, in_signature="ss", out_signature="v")
    def ReadOne(self, ns, key):
        if (ns, key) != (NS, KEY):
            raise dbus.exceptions.DBusException("org.freedesktop.portal.Error.NotFound", "no such setting")
        return dbus.UInt32(self.now)

    @dbus.service.method(IFACE, in_signature="ss", out_signature="v")
    def Read(self, ns, key):  # the old call: a variant in a variant
        return dbus.UInt32(self.ReadOne(ns, key), variant_level=1)

    @dbus.service.method(IFACE, in_signature="as", out_signature="a{sa{sv}}")
    def ReadAll(self, namespaces):
        return {NS: {KEY: dbus.UInt32(self.now)}}

    @dbus.service.signal(IFACE, signature="ssv")
    def SettingChanged(self, ns, key, value):
        pass

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return dbus.UInt32(2)  # version


DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.freedesktop.portal.Desktop", bus)
Settings(bus, sys.argv[1])
print("fake_portal: up", flush=True)
GLib.MainLoop().run()
