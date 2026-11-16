/// Flatpak autostart through `org.freedesktop.portal.Background` (#97).
///
/// Inside the sandbox `$XDG_CONFIG_HOME/autostart` is not the user's real
/// autostart folder, so the portal writes the entry (with the right app ID)
/// on the host. The portal cannot be asked whether autostart is on, so the
/// last granted state is kept in a marker file in the sandbox config folder.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:path/path.dart' as p;

import 'autostart_backend.dart';

/// The portal refused or failed; lands in `autostartSyncFailureProvider`.
class AutostartPortalException implements Exception {
  AutostartPortalException(this.message);
  final String message;
  @override
  String toString() => 'AutostartPortalException: $message';
}

/// Outcome of one `RequestBackground` call.
class BackgroundPortalResult {
  const BackgroundPortalResult({required this.response, this.autostart});

  /// `Request::Response` code: 0 success, 1 cancelled by the user, 2 other.
  final int response;

  /// The `autostart` value of the results, when the portal sent one.
  final bool? autostart;
}

/// Sends `RequestBackground`; injectable so tests need no session bus.
typedef BackgroundPortalCall =
    Future<BackgroundPortalResult> Function({
      required bool autostart,
      required List<String> commandline,
      required String reason,
    });

/// Throws [AutostartPortalException] unless the portal granted [wantEnabled].
void checkBackgroundResult(
  BackgroundPortalResult result, {
  required bool wantEnabled,
}) {
  if (result.response == 1) {
    throw AutostartPortalException('The request was denied.');
  }
  if (result.response != 0) {
    throw AutostartPortalException(
      'The portal failed (response ${result.response}).',
    );
  }
  // A grant that says the opposite of the request is a refusal.
  if (result.autostart != null && result.autostart != wantEnabled) {
    throw AutostartPortalException(
      wantEnabled ? 'Autostart was not granted.' : 'Autostart stays enabled.',
    );
  }
}

/// Calls the portal on the session bus and waits for its `Response` signal.
Future<BackgroundPortalResult> requestBackgroundOverDBus({
  required bool autostart,
  required List<String> commandline,
  required String reason,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final bus = DBusClient.session();
  try {
    final token = 'wp${Random().nextInt(1 << 30)}';
    final sender = bus.uniqueName.substring(1).replaceAll('.', '_');
    final handle = DBusObjectPath(
      '/org/freedesktop/portal/desktop/request/$sender/$token',
    );
    final request = DBusRemoteObject(
      bus,
      name: 'org.freedesktop.portal.Desktop',
      path: handle,
    );
    // Subscribed before the call: the answer can come before it returns.
    final signals = DBusRemoteObjectSignalStream(
      object: request,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
    );
    final response = signals.first.timeout(timeout);
    final portal = DBusRemoteObject(
      bus,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
    await portal.callMethod(
      'org.freedesktop.portal.Background',
      'RequestBackground',
      [
        const DBusString(''),
        DBusDict.stringVariant({
          'handle_token': DBusString(token),
          'reason': DBusString(reason),
          'autostart': DBusBoolean(autostart),
          'commandline': DBusArray.string(commandline),
          'dbus-activatable': const DBusBoolean(false),
        }),
      ],
      replySignature: DBusSignature('o'),
    );
    final signal = await response;
    final code = (signal.values[0] as DBusUint32).value;
    final results = signal.values[1].asStringVariantDict();
    final granted = results['autostart'];
    return BackgroundPortalResult(
      response: code,
      autostart: granted is DBusBoolean ? granted.value : null,
    );
  } on DBusMethodResponseException catch (e) {
    throw AutostartPortalException('${e.errorName}: ${e.response.values}');
  } on TimeoutException {
    throw AutostartPortalException('The portal did not answer.');
  } finally {
    await bus.close();
  }
}

/// [AutostartBackend] for Flatpak.
class FlatpakPortalAutostartBackend implements AutostartBackend {
  FlatpakPortalAutostartBackend({required this.env, BackgroundPortalCall? call})
    : _call = call ?? requestBackgroundOverDBus;

  final Map<String, String> env;
  final BackgroundPortalCall _call;

  /// The command the portal writes into the host entry; the portal adds
  /// `flatpak run <app id>` itself.
  static const commandline = ['whispaste', '--autostart'];
  static const reason = 'Start WhisPaste at login so the hotkey is ready.';

  File get _marker {
    final config = env['XDG_CONFIG_HOME'];
    final dir = (config != null && config.isNotEmpty && p.isAbsolute(config))
        ? config
        : p.join(env['HOME'] ?? '', '.config');
    return File(p.join(dir, 'whispaste-autostart-portal'));
  }

  @override
  Future<bool> isEnabled() => _marker.exists();

  @override
  Future<void> enable() async {
    checkBackgroundResult(
      await _call(autostart: true, commandline: commandline, reason: reason),
      wantEnabled: true,
    );
    await _marker.parent.create(recursive: true);
    await _marker.writeAsString('on\n');
  }

  @override
  Future<void> disable() async {
    checkBackgroundResult(
      await _call(autostart: false, commandline: commandline, reason: reason),
      wantEnabled: false,
    );
    if (await _marker.exists()) await _marker.delete();
  }

  @override
  Future<bool> requiresApproval() async => false;

  @override
  Future<void> openLoginItems() async {}
}
