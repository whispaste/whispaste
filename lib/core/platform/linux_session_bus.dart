/// Non-activating "is this D-Bus name owned?" check on the Linux session bus.
///
/// Plugins that talk to a desktop service through GDBus on the GTK main
/// thread (libnotify in local_notifier) start that service on demand. When
/// the service is only activatable and never comes up (Ubuntu with Plasma
/// installed points org.freedesktop.Notifications at `plasma_waitforname`,
/// which waits forever outside Plasma), the call waits for the full 25 s
/// GDBus timeout and the whole app freezes with it: no `--toggle`, no hotkey,
/// no end of a recording (XP-7-19). `NameHasOwner` never activates anything,
/// so callers can skip the plugin when nobody serves the name.
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('LinuxSessionBus');

/// Upper bound for the bus daemon's answer. It answers `NameHasOwner` from
/// its own name table, so this only matters for a wedged bus.
const sessionBusCallTimeoutMs = 1000;

/// Whether [name] currently has an owner on the session bus. `true` on
/// non-Linux platforms. `false` without a session bus, on a timeout or when
/// the check itself fails: the caller then skips a call that could block.
///
/// Runs in its own isolate, so it never blocks the UI thread; the native call
/// carries its own timeout, so there is no Dart `Timer` to leak into tests.
Future<bool> linuxSessionBusNameHasOwner(String name) async {
  if (!Platform.isLinux) return true;
  try {
    return await Isolate.run(() => _nameHasOwner(name));
  } catch (e) {
    _log.warning('Session bus name check for $name failed: $e');
    return false;
  }
}

bool _nameHasOwner(String name) {
  final DynamicLibrary gio;
  try {
    gio = DynamicLibrary.open('libgio-2.0.so.0');
  } on ArgumentError {
    return false;
  }
  final busGetSync = gio
      .lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(int, Pointer<Void>, Pointer<Void>)
      >('g_bus_get_sync');
  final connectionCallSync = gio
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Void>,
          Int32,
          Int32,
          Pointer<Void>,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
          Pointer<Void>,
        )
      >('g_dbus_connection_call_sync');
  // GVariant comes from libglib, which libgio links, so dlsym finds it here.
  final variantNewString = gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)
      >('g_variant_new_string');
  final variantNewTuple = gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Pointer<Void>>, Size),
        Pointer<Void> Function(Pointer<Pointer<Void>>, int)
      >('g_variant_new_tuple');
  final variantGetChildValue = gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Size),
        Pointer<Void> Function(Pointer<Void>, int)
      >('g_variant_get_child_value');
  final variantGetBoolean = gio
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('g_variant_get_boolean');
  final variantUnref = gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_variant_unref');
  final objectUnref = gio
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_object_unref');

  const busTypeSession = 2; // G_BUS_TYPE_SESSION
  final connection = busGetSync(busTypeSession, nullptr, nullptr);
  if (connection == nullptr) return false;
  final nativeName = name.toNativeUtf8();
  final bus = 'org.freedesktop.DBus'.toNativeUtf8();
  final path = '/org/freedesktop/DBus'.toNativeUtf8();
  final method = 'NameHasOwner'.toNativeUtf8();
  final args = malloc<Pointer<Void>>(1);
  try {
    args[0] = variantNewString(nativeName);
    // The call sinks the floating parameter tuple.
    final reply = connectionCallSync(
      connection,
      bus,
      path,
      bus,
      method,
      variantNewTuple(args, 1),
      nullptr,
      0,
      sessionBusCallTimeoutMs,
      nullptr,
      nullptr,
    );
    if (reply == nullptr) return false;
    final owned = variantGetChildValue(reply, 0);
    final result = variantGetBoolean(owned) != 0;
    variantUnref(owned);
    variantUnref(reply);
    return result;
  } finally {
    malloc
      ..free(nativeName)
      ..free(bus)
      ..free(path)
      ..free(method)
      ..free(args);
    objectUnref(connection);
  }
}
