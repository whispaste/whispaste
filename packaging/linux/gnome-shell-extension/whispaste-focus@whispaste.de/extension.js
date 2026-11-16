// WhisPaste Focus: a read-only GNOME Shell extension.
//
// It exports one D-Bus method so that WhisPaste can ask which application
// window has focus. Under GNOME on Wayland, other programs have no other way to
// learn this. The method returns app identity only (app ID, WM class). It
// never returns window titles.
//
// Bus name:   de.whispaste.ShellFocus
// Object:     /de/whispaste/ShellFocus
// Interface:  de.whispaste.ShellFocus1
// Keep the interface stable. Changing it requires bumping the Version property.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BUS_NAME = 'de.whispaste.ShellFocus';
const OBJECT_PATH = '/de/whispaste/ShellFocus';
const PROTOCOL_VERSION = 1;

const INTERFACE_XML = `
<node>
  <interface name="de.whispaste.ShellFocus1">
    <method name="GetFocusedWindow">
      <arg name="window" type="a{sv}" direction="out"/>
    </method>
    <property name="Version" type="u" access="read"/>
  </interface>
</node>`;

// Builds the a{sv} dictionary for one window. Keys are added only when they
// have a value, except wm_class, wm_class_instance and client_type, which are
// always present.
function describeWindow(window) {
  const wmClass = window.get_wm_class() ?? '';
  const wmClassInstance = window.get_wm_class_instance() ?? '';
  const isWayland = window.get_client_type() === Meta.WindowClientType.WAYLAND;

  // Order: GTK application ID, sandboxed (Flatpak/Snap) app ID, then for
  // Wayland clients the WM class (that is their app ID on this compositor).
  const appId = window.get_gtk_application_id() ||
    window.get_sandboxed_app_id() ||
    (isWayland ? wmClass : '');

  const dict = {};
  if (appId)
    dict.app_id = GLib.Variant.new_string(appId);
  dict.wm_class = GLib.Variant.new_string(wmClass);
  dict.wm_class_instance = GLib.Variant.new_string(wmClassInstance);
  dict.client_type = GLib.Variant.new_string(isWayland ? 'wayland' : 'x11');
  return dict;
}

// The single out-argument of GetFocusedWindow: an a{sv} dictionary, empty when
// no window has focus. GJS takes a single out-argument as the plain return value.
function focusedWindow() {
  const window = global.display.get_focus_window();
  return window ? describeWindow(window) : {};
}

export default class WhispasteFocusExtension extends Extension {
  enable() {
    this._exported = Gio.DBusExportedObject.wrapJSObject(INTERFACE_XML, {
      GetFocusedWindow: () => focusedWindow(),
      Version: PROTOCOL_VERSION,
    });
    this._ownerId = Gio.bus_own_name(
      Gio.BusType.SESSION,
      BUS_NAME,
      Gio.BusNameOwnerFlags.NONE,
      connection => this._exportOn(connection),
      null,
      null
    );
  }

  disable() {
    if (this._ownerId) {
      Gio.bus_unown_name(this._ownerId);
      this._ownerId = 0;
    }
    if (this._exported) {
      this._exported.unexport();
      this._exported = null;
    }
  }

  _exportOn(connection) {
    if (!this._exported)
      return;
    try {
      this._exported.export(connection, OBJECT_PATH);
    } catch (e) {
      console.error(`${this.metadata.uuid}: export failed: ${e.message}`);
    }
  }
}
