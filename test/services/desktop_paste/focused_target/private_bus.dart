import 'package:dbus/dbus.dart';

/// A client for an in-process test bus.
///
/// The dbus package derives the EXTERNAL auth identity from `getuid()`, which
/// only exists on Linux, so a default client throws on macOS and Windows. The
/// private server never checks the caller's identity, so a fixed one keeps
/// these tests independent of the host OS.
DBusClient privateBusClient(DBusAddress address) =>
    DBusClient(address, authClient: DBusAuthClient(uid: '1000'));
