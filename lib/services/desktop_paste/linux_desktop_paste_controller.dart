import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';
import 'focused_target/compositor_ipc_sources.dart'
    show focusedTargetIpcTimeout;
import 'focused_target/focused_target.dart';
import 'focused_target/linux_focused_target.dart';
import 'linux_package_format.dart';
import 'linux_portal_input.dart';
import 'terminal_targets.dart';

/// One-time command that gives WhisPaste access to `/dev/uinput`: the same
/// rule as `packaging/linux/71-whispaste-uinput.rules`, written into
/// `/etc/udev/rules.d` and loaded. Auto-Paste settings copy it to the
/// clipboard; the app never runs it. The failure toast opens those settings.
/// Linux uses uinput or a consented RemoteDesktop portal session (preferred
/// in Flatpak); lack of uinput write access alone does not block the portal.
const String kLinuxUinputUdevCommand =
    "echo 'KERNEL==\"uinput\", SUBSYSTEM==\"misc\", TAG+=\"uaccess\"' "
    '| sudo tee /etc/udev/rules.d/71-whispaste-uinput.rules '
    '&& sudo udevadm control --reload-rules '
    '&& sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

/// Snap confinement ignores the host udev rule: the `uinput` interface has to
/// be connected once (packaging/snap/README.md).
const String kSnapUinputConnectCommand = 'sudo snap connect whispaste:uinput';

/// The one-time command the Auto-Paste setup copies for [format].
String linuxUinputCopyCommand(LinuxPackageFormat format) =>
    format == LinuxPackageFormat.snap
    ? kSnapUinputConnectCommand
    : kLinuxUinputUdevCommand;

/// Undoes [kLinuxUinputUdevCommand] (R-02), same steps as
/// packaging/linux/uninstall-uinput-rule.sh: logind keeps an ACL it already
/// granted until the next login, so the rule alone would not end the access.
/// Like the script, the udevadm and setfacl steps end with `|| true`: a missing
/// /dev/uinput or acl package must not report a failure once the files are gone.
const String kLinuxUinputRemoveCommand =
    'sudo rm -f /etc/udev/rules.d/71-whispaste-uinput.rules '
    '/etc/modules-load.d/whispaste-uinput.conf '
    '&& { sudo udevadm control --reload-rules || true; } '
    '&& { sudo udevadm trigger --subsystem-match=misc '
    '--sysname-match=uinput || true; } '
    '&& { sudo setfacl -x "u:\$USER" /dev/uinput 2>/dev/null || true; }';

/// Undoes [kSnapUinputConnectCommand].
const String kSnapUinputDisconnectCommand =
    'sudo snap disconnect whispaste:uinput';

/// [NativeCapabilityResult.detail] of a "ready" that comes from the portal,
/// not from write access to /dev/uinput.
const String kLinuxPortalCapabilityDetail = 'portal';

/// The command that takes /dev/uinput access back on [format], or null when
/// [hostRule] says no rule of ours is installed. A Flatpak cannot see the
/// host's /etc, so there uinput access counts as coming from the rule.
String? linuxUinputRemoveCommand(
  LinuxPackageFormat format, {
  required bool hostRule,
}) => switch (format) {
  LinuxPackageFormat.snap => kSnapUinputDisconnectCommand,
  LinuxPackageFormat.flatpak => kLinuxUinputRemoveCommand,
  LinuxPackageFormat.native ||
  LinuxPackageFormat.appimage => hostRule ? kLinuxUinputRemoveCommand : null,
};

final _log = AppLogger('LinuxDesktopPasteController');

const _fieldTypeChannel = MethodChannel('com.whispaste.field_type');

/// The transcript goes on the clipboard as a receipt write
/// (`linux/runner/clipboard_receipt.cc`, GR-015): X11 hands the text out per
/// request, so the target's read after the paste shortcut is the proof, as on
/// macOS and Windows.
class LinuxDesktopPasteController extends ChannelDesktopPasteController
    with ChannelClipboardReceiptBridge
    implements FocusedFieldTypeProbe {
  /// [waylandFocus] answers which window has focus under Wayland, where the
  /// native X11 lookup only sees XWayland windows. By default it is picked
  /// from the session (Sway, Hyprland, niri, KWin, GNOME extension).
  ///
  /// [alwaysShift] reads the "always Ctrl+Shift+V" setting at paste time.
  ///
  /// [portal] is the second keyboard path next to uinput (RemoteDesktop
  /// portal, libei). [preferPortal] tries it first; by default only inside
  /// Flatpak, where /dev/uinput is usually out of reach.
  LinuxDesktopPasteController({
    FocusedTargetSource? waylandFocus,
    bool Function()? alwaysShift,
    LinuxPortalInput? portal,
    bool? preferPortal,
  }) : _shiftEverywhere = alwaysShift,
       _portal = portal ?? LinuxPortalInput(),
       _preferPortal =
           preferPortal ?? Platform.environment.containsKey('FLATPAK_ID'),
       _waylandFocus =
           waylandFocus ??
           waylandFocusSourceFor(
             detectLinuxFocusDesktop(Platform.environment),
             Platform.environment,
           ),
       super(_log);

  final FocusedTargetSource? _waylandFocus;
  final bool Function()? _shiftEverywhere;
  final LinuxPortalInput _portal;
  final bool _preferPortal;
  Future<FocusedTarget?>? _captured;
  bool _portalConnected = false;

  /// Whether the portal keyboard is connected in this process.
  bool get portalInputConnected => _portalConnected;

  /// Whether this desktop offers the portal keyboard at all.
  Future<bool> portalInputAvailable() => _portal.isAvailable();

  /// Asks the portal for keyboard input. The first call shows the system's
  /// consent dialog, so call it only from a user action.
  Future<PortalInputConnectResult> connectPortalInput() async {
    final result = await _portal.connect();
    _portalConnected = result.isConnected;
    return result;
  }

  /// Reconnects at startup when the user granted the portal before (a
  /// restore token is stored); never asks for the first time.
  Future<void> resumePortalInput() async {
    try {
      if (!await _portal.hasConsent()) return;
      await connectPortalInput();
    } on Object catch (e) {
      // No preferences or no portal: uinput stays the only path.
      _log.debug('Portal input not resumed', e);
    }
  }

  /// Ends the portal session and forgets the consent.
  Future<void> revokePortalInput() async {
    _portalConnected = false;
    await _portal.disconnect();
    await _portal.forgetConsent();
  }

  /// AT-SPI role of the focused field (#950): `password` for the role
  /// "password text", `normal` for another text field, `unknown` without
  /// AT-SPI or focus. Only the type crosses the channel, never content.
  @override
  Future<FocusedFieldType> focusedFieldType() async {
    final code = await _fieldTypeChannel.invokeMethod<String>(
      'focusedFieldType',
    );
    return FocusedFieldType.fromCode(code);
  }

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  /// Records the focused window from both lookups at once: the compositor's
  /// answer (Wayland) and the native X11 one (X11, XWayland).
  @override
  Future<bool> capturePasteTarget() async {
    _captured = _waylandFocus?.focusedTarget();
    return super.capturePasteTarget();
  }

  /// The captured target, from the compositor when it answered, else from
  /// the native X11 lookup. Null when neither knows it.
  Future<FocusedTarget?> capturedTarget() async {
    // The source bounds its IPC, but not the socket connect before it: a
    // compositor that never accepts would hold every paste here. The wait is
    // bounded, and the native lookup decides after it.
    final wayland = await _captured?.timeout(
      focusedTargetIpcTimeout,
      onTimeout: () => null,
    );
    if (wayland != null) return wayland;
    final native = await super.getTargetBundleId();
    return FocusedTarget.from(
      [native],
      source: 'x11',
      clientType: FocusedClientType.x11,
    );
  }

  @override
  Future<String?> getTargetBundleId() async => (await capturedTarget())?.id;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) => _route(
    'paste',
    delay,
    (d) => super.pasteClipboard(delay: d),
    (d, shift) => _portal.pasteClipboard(delay: d, shift: shift),
  );

  @override
  Future<NativePasteResult> copySelection({required Duration delay}) => _route(
    'copy',
    delay,
    (d) => super.copySelection(delay: d),
    (d, shift) => _portal.copySelection(delay: d, shift: shift),
  );

  /// uinput first (portal first inside Flatpak); when the first path lacks
  /// access, the other one is tried at once, without waiting [delay] again.
  Future<NativePasteResult> _route(
    String what,
    Duration delay,
    Future<NativePasteResult> Function(Duration delay) viaUinput,
    Future<NativePasteResult> Function(Duration delay, bool shift) viaPortal,
  ) async {
    final watch = Stopwatch()..start();
    Future<NativePasteResult> portal(Duration d) async {
      final shift = (await shortcutArguments())['shift'] == true;
      final result = await viaPortal(d, shift);
      // The portal closed the session (revoked, logged out): stop using it.
      if (result.status == NativePasteStatus.permissionMissing) {
        _portalConnected = false;
      }
      return result;
    }

    final portalFirst = _portalConnected && _preferPortal;
    var route = portalFirst ? 'portal' : 'uinput';
    var result = portalFirst ? await portal(delay) : await viaUinput(delay);
    if (result.status == NativePasteStatus.permissionMissing) {
      if (portalFirst) {
        route = 'portal>uinput';
        result = await viaUinput(Duration.zero);
      } else if (_portalConnected) {
        route = 'uinput>portal';
        result = await portal(Duration.zero);
      }
    }
    _log.debug(
      '$what via $route: ${result.status.name} in '
      '${watch.elapsedMilliseconds} ms (incl. ${delay.inMilliseconds} ms delay)',
    );
    return result;
  }

  /// uinput missing is fine while the portal keyboard is connected.
  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async {
    final native = await super.checkCapability(
      promptIfMissing: promptIfMissing,
    );
    if (native.status == NativeCapabilityStatus.ready || !_portalConnected) {
      return native;
    }
    return const NativeCapabilityResult(
      status: NativeCapabilityStatus.ready,
      detail: kLinuxPortalCapabilityDetail,
    );
  }

  /// Terminals paste with Ctrl+Shift+V and copy with Ctrl+Shift+C (V1). An
  /// unknown target (failed lookup, no focus source) keeps the plain
  /// shortcut unless the user asked for Ctrl+Shift everywhere.
  @override
  Future<Map<String, Object?>> shortcutArguments() async {
    if (_shiftEverywhere?.call() ?? false) return {'shift': true};
    FocusedTarget? target;
    try {
      target = await capturedTarget();
    } on Object catch (e) {
      // A failed or malformed answer must not stop the paste itself.
      _log.debug('Paste target unknown, plain Ctrl shortcut', e);
    }
    return {'shift': target != null && isLinuxTerminalFocus(target)};
  }
}
