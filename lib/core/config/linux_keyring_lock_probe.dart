/// Non-prompting "is the default libsecret collection locked?" check.
///
/// flutter_secure_storage_linux unlocks a locked default collection with a
/// synchronous `secret_service_unlock_sync` inside its method-channel
/// handler, i.e. on the GTK main thread. When the unlock prompt never
/// appears (no working prompter in the session), that call never returns and
/// the whole platform thread freezes: no window, no tray, no hotkey
/// (GitHub #151). This probe only reads the collection's `Locked` property —
/// it never triggers a prompt — so callers can skip the plugin instead.
///
/// The probe also bounds the Secret Service activation. When the session bus
/// cannot start `org.freedesktop.secrets` (e.g. gnome-keyring finds the
/// daemon of another session and never claims the name),
/// `secret_service_get_sync` waits for the full 25 s GDBus timeout, and the
/// plugin repeats that wait on the GTK main thread: `--toggle`, SIGUSR2 and
/// the end of a recording stall with it (XP-7-01, XP-6-11).
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('KeyringLockProbe');

/// What the secure-storage plugin would run into on this machine.
enum KeyringAvailability {
  /// Safe to call the plugin. Also returned on non-Linux platforms and when
  /// libsecret or a default collection is missing, which the plugin reports
  /// quickly on its own.
  usable,

  /// The default collection is locked; the plugin would prompt.
  locked,

  /// The Secret Service did not answer within [secretServiceStartTimeoutMs];
  /// the plugin would block the GTK main thread for the GDBus timeout.
  unreachable,
}

/// Upper bound for starting (or finding) the Secret Service on the session
/// bus. A running daemon answers in milliseconds, a fresh gnome-keyring
/// activates well within it.
const secretServiceStartTimeoutMs = 2000;

/// Probes the keyring without prompting. A failed probe counts as locked.
///
/// No Dart-side timeout: the probe runs in its own isolate, so it can never
/// block the UI thread, and the one call that can hang (Secret Service
/// activation) is bounded natively by [secretServiceStartTimeoutMs]. A Dart
/// `Timer` here also leaked into every widget test that realizes the real
/// store on Linux (fake-async "Timer is still pending").
Future<KeyringAvailability> probeLinuxKeyring() async {
  if (!Platform.isLinux) return KeyringAvailability.usable;
  try {
    final index = await Isolate.run(_probeDefaultCollection);
    return KeyringAvailability.values[index];
  } catch (e) {
    _log.warning('Keyring lock probe failed, treating keyring as locked: $e');
    return KeyringAvailability.locked;
  }
}

/// Returns a [KeyringAvailability] index.
int _probeDefaultCollection() {
  final DynamicLibrary secret;
  final DynamicLibrary gobject;
  final DynamicLibrary gio;
  try {
    secret = DynamicLibrary.open('libsecret-1.so.0');
    gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    gio = DynamicLibrary.open('libgio-2.0.so.0');
  } on ArgumentError {
    return KeyringAvailability.usable.index;
  }
  if (!_secretServiceStarts(gio)) {
    return KeyringAvailability.unreachable.index;
  }

  final serviceGetSync = secret
      .lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(int, Pointer<Void>, Pointer<Void>)
      >('secret_service_get_sync');
  final collectionForAliasSync = secret
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Int32,
          Pointer<Void>,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Utf8>,
          int,
          Pointer<Void>,
          Pointer<Void>,
        )
      >('secret_collection_for_alias_sync');
  final collectionGetLocked = secret
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('secret_collection_get_locked');
  final objectUnref = gobject
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('g_object_unref');

  // SECRET_SERVICE_NONE / SECRET_COLLECTION_NONE: no session, no item
  // loading — neither can prompt. A null GError** just drops the error.
  final service = serviceGetSync(0, nullptr, nullptr);
  if (service == nullptr) return KeyringAvailability.unreachable.index;
  final alias = 'default'.toNativeUtf8();
  try {
    final collection = collectionForAliasSync(
      service,
      alias,
      0,
      nullptr,
      nullptr,
    );
    if (collection == nullptr) return KeyringAvailability.usable.index;
    final locked = collectionGetLocked(collection) != 0;
    objectUnref(collection);
    return locked
        ? KeyringAvailability.locked.index
        : KeyringAvailability.usable.index;
  } finally {
    malloc.free(alias);
    objectUnref(service);
  }
}

/// Calls `StartServiceByName("org.freedesktop.secrets")` on the session bus
/// with an explicit timeout. True once the name has an owner (already running
/// or just activated), and also without a session bus: then the plugin fails
/// fast on its own.
bool _secretServiceStarts(DynamicLibrary gio) {
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
  final variantNewUint32 = gio
      .lookupFunction<
        Pointer<Void> Function(Uint32),
        Pointer<Void> Function(int)
      >('g_variant_new_uint32');
  final variantNewTuple = gio
      .lookupFunction<
        Pointer<Void> Function(Pointer<Pointer<Void>>, Size),
        Pointer<Void> Function(Pointer<Pointer<Void>>, int)
      >('g_variant_new_tuple');
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
  if (connection == nullptr) return true;
  final name = 'org.freedesktop.secrets'.toNativeUtf8();
  final bus = 'org.freedesktop.DBus'.toNativeUtf8();
  final path = '/org/freedesktop/DBus'.toNativeUtf8();
  final method = 'StartServiceByName'.toNativeUtf8();
  final args = malloc<Pointer<Void>>(2);
  try {
    args[0] = variantNewString(name);
    args[1] = variantNewUint32(0);
    // The call sinks the floating parameter tuple.
    final reply = connectionCallSync(
      connection,
      bus,
      path,
      bus,
      method,
      variantNewTuple(args, 2),
      nullptr,
      0,
      secretServiceStartTimeoutMs,
      nullptr,
      nullptr,
    );
    if (reply == nullptr) return false;
    variantUnref(reply);
    return true;
  } finally {
    malloc
      ..free(name)
      ..free(bus)
      ..free(path)
      ..free(method)
      ..free(args);
    objectUnref(connection);
  }
}
