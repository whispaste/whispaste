#!/usr/bin/env python3
"""Opens one plain window for the focus-source e2e check.

Usage: focus_probe_window.py <gtk3|gtk4> <application-id> <seconds>
GTK 4 gives a native Wayland window whose app id is <application-id>;
GTK 3 with GDK_BACKEND=x11 gives an XWayland window whose WM_CLASS
instance is the program name set below.
"""
import sys

import gi

toolkit, app_id, seconds = sys.argv[1], sys.argv[2], int(sys.argv[3])
gi.require_version("Gtk", "4.0" if toolkit == "gtk4" else "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

if toolkit == "gtk3":
    GLib.set_prgname(app_id)


def activate(app):
    window = Gtk.ApplicationWindow(application=app, title="whispaste probe")
    window.set_default_size(320, 200)
    window.present()


app = Gtk.Application(application_id=app_id)
app.connect("activate", activate)
GLib.timeout_add_seconds(seconds, app.quit)
app.run([])
