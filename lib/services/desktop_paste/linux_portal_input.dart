import 'package:flutter/services.dart';
import '../../core/config/secure_key_store.dart';
import '../../core/logging/app_logger.dart';
import 'desktop_paste_controller_interface.dart';

/// Linux keyboard input through the xdg-desktop-portal RemoteDesktop portal
/// (libei), the second input path next to uinput. Used on GNOME, KDE and
/// Flatpak without /dev/uinput. The native side is
/// `linux/runner/portal_remote_desktop.cc`; the channel is the desktop-paste
/// channel with the `portalInput*` methods and `via: 'portal'` arguments.
///
/// Which path is used (uinput first, portal as fallback) is decided by the
/// caller. This class only talks to the portal path.
final _log = AppLogger('LinuxPortalInput');

/// Outcome of [LinuxPortalInput.connect].
enum PortalInputConnectStatus {
  /// The portal granted keyboard input. A new restore token may come with it.
  connected,

  /// The user closed the consent dialog or disconnected.
  cancelled,

  /// The portal, libei or this build cannot provide keyboard input.
  unavailable,

  /// The portal was reached but the session did not come up.
  failed;

  static PortalInputConnectStatus fromCode(String? code) => switch (code) {
    'connected' => PortalInputConnectStatus.connected,
    'cancelled' => PortalInputConnectStatus.cancelled,
    'unavailable' => PortalInputConnectStatus.unavailable,
    _ => PortalInputConnectStatus.failed,
  };
}

/// Result of [LinuxPortalInput.connect]. [restoreToken] is set only when the
/// portal returned one; it lets the next connect skip the consent dialog.
class PortalInputConnectResult {
  const PortalInputConnectResult({required this.status, this.restoreToken});

  final PortalInputConnectStatus status;
  final String? restoreToken;

  bool get isConnected => status == PortalInputConnectStatus.connected;
}

/// Stores the portal restore token across app starts.
abstract class PortalRestoreTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// [PortalRestoreTokenStore] in the secure store (libsecret), next to the
/// API keys; a factory reset erases it there. A locked or missing keyring
/// reads as "no token" (the consent dialog shows again) and never throws.
class SecureRestoreTokenStore implements PortalRestoreTokenStore {
  SecureRestoreTokenStore([SecureKeyStore? store])
    : _store = store ?? SecureKeyStore();

  final SecureKeyStore _store;

  @override
  Future<String?> read() async {
    try {
      final token = await _store.readKey(linuxPortalRestoreTokenKey);
      return (token == null || token.isEmpty) ? null : token;
    } on Object catch (e) {
      _log.debug('portal restore token unreadable', e);
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _store.writeKey(linuxPortalRestoreTokenKey, token);
    } on Object catch (e) {
      _log.warning('portal restore token not stored; consent asked again', e);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.deleteKey(linuxPortalRestoreTokenKey);
    } on Object catch (e) {
      _log.warning('portal restore token not removed', e);
    }
  }
}

class LinuxPortalInput {
  LinuxPortalInput({
    MethodChannel? channel,
    PortalRestoreTokenStore? tokenStore,
  }) : _channel = channel ?? const MethodChannel('com.whispaste.desktop_paste'),
       _store = tokenStore ?? SecureRestoreTokenStore();

  final MethodChannel _channel;
  final PortalRestoreTokenStore _store;

  /// Whether the portal path can be used here at all: RemoteDesktop version 2
  /// on the session bus and libei loadable. Any channel failure means false.
  Future<bool> isAvailable() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('portalInputAvailable');
      return raw is bool && raw;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      _log.debug('portalInputAvailable failed', e);
      return false;
    }
  }

  /// Asks the portal for keyboard input. The first call shows the consent
  /// dialog; later calls pass the stored restore token and skip it. A new
  /// token from a successful connect replaces the stored one.
  Future<PortalInputConnectResult> connect() async {
    final stored = await _store.read();
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('portalInputConnect', {
        'restoreToken': stored,
      });
    } on MissingPluginException {
      return const PortalInputConnectResult(
        status: PortalInputConnectStatus.unavailable,
      );
    } on PlatformException catch (e) {
      _log.debug('portalInputConnect failed', e);
      return const PortalInputConnectResult(
        status: PortalInputConnectStatus.failed,
      );
    }
    if (raw is! Map) {
      return const PortalInputConnectResult(
        status: PortalInputConnectStatus.failed,
      );
    }
    final status = PortalInputConnectStatus.fromCode(raw['status'] as String?);
    final token = raw['restoreToken'];
    final newToken = (token is String && token.isNotEmpty) ? token : null;
    if (status == PortalInputConnectStatus.connected && newToken != null) {
      await _store.write(newToken);
    }
    return PortalInputConnectResult(status: status, restoreToken: newToken);
  }

  /// Closes the portal session. The stored restore token stays, so the next
  /// connect does not show the dialog again.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('portalInputDisconnect');
    } on MissingPluginException {
      _log.debug('portalInputDisconnect: no native side, nothing to close');
    } on PlatformException catch (e) {
      _log.debug('portalInputDisconnect failed', e);
    }
  }

  /// Forgets the stored restore token, so the next connect shows the consent
  /// dialog again.
  Future<void> forgetConsent() => _store.clear();

  /// Whether the user granted the portal before (a restore token is stored).
  Future<bool> hasConsent() async => await _store.read() != null;

  /// Ctrl+V (Ctrl+Shift+V with [shift]) through the portal keyboard.
  Future<NativePasteResult> pasteClipboard({
    required Duration delay,
    bool shift = false,
  }) => _sendShortcut('pasteClipboard', delay, shift);

  /// Ctrl+C (Ctrl+Shift+C with [shift]) through the portal keyboard.
  Future<NativePasteResult> copySelection({
    required Duration delay,
    bool shift = false,
  }) => _sendShortcut('copySelection', delay, shift);

  Future<NativePasteResult> _sendShortcut(
    String method,
    Duration delay,
    bool shift,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, {
        'delayMs': delay.inMilliseconds,
        'shift': shift,
        'via': 'portal',
      });
      if (raw is Map) {
        return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
      }
      return NativePasteResult.fromLegacyBool(raw is bool ? raw : null);
    } on MissingPluginException {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    } on PlatformException catch (e) {
      _log.debug('$method via portal failed', e);
      return const NativePasteResult(status: NativePasteStatus.postFailed);
    }
  }
}
