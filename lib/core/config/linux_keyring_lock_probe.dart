/// Non-prompting "is the default libsecret collection locked?" check.
///
/// flutter_secure_storage_linux unlocks a locked default collection with a
/// synchronous `secret_service_unlock_sync` inside its method-channel
/// handler, i.e. on the GTK main thread. When the unlock prompt never
/// appears (no working prompter in the session), that call never returns and
/// the whole platform thread freezes: no window, no tray, no hotkey
/// (GitHub #151). This probe only reads the collection's `Locked` property —
/// it never triggers a prompt — so callers can skip the plugin instead.
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('KeyringLockProbe');

/// Returns `true` when the default libsecret collection is locked (or the
/// probe failed), `false` otherwise — including on non-Linux platforms and
/// when libsecret or a default collection is missing, which the plugin
/// already reports quickly on its own.
///
/// No Dart-side timeout: the probe runs in its own isolate, so it can never
/// block the UI thread, and every libsecret call is a GDBus call bounded by
/// GDBus's own default call timeout. A Dart `Timer` here also leaked into
/// every widget test that realizes the real store on Linux (fake-async
/// "Timer is still pending").
Future<bool> isLinuxKeyringLocked() async {
  if (!Platform.isLinux) return false;
  try {
    return await Isolate.run(_defaultCollectionLocked);
  } catch (e) {
    _log.warning('Keyring lock probe failed, treating keyring as locked: $e');
    return true;
  }
}

bool _defaultCollectionLocked() {
  final DynamicLibrary secret;
  final DynamicLibrary gobject;
  try {
    secret = DynamicLibrary.open('libsecret-1.so.0');
    gobject = DynamicLibrary.open('libgobject-2.0.so.0');
  } on ArgumentError {
    return false;
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
  if (service == nullptr) return false;
  final alias = 'default'.toNativeUtf8();
  try {
    final collection = collectionForAliasSync(
      service,
      alias,
      0,
      nullptr,
      nullptr,
    );
    if (collection == nullptr) return false;
    final locked = collectionGetLocked(collection) != 0;
    objectUnref(collection);
    return locked;
  } finally {
    malloc.free(alias);
    objectUnref(service);
  }
}
