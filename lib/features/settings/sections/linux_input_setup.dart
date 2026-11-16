/// Linux only (V1 Wayland): the two optional setups behind Auto-Paste, each
/// started only by the user's own button press:
/// - the desktop permission (RemoteDesktop portal) for the paste keyboard,
///   for when uinput is not set up (Flatpak);
/// - the WhisPaste GNOME extension, which tells WhisPaste the active app.
/// Shown in the settings under the "always Ctrl+Shift+V" switch and on the
/// onboarding's Auto-Paste page. [idPrefix] keeps the testIDs unique there.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/desktop_paste_controller.dart';
import '../../../services/desktop_paste/focused_target/gnome_focus_extension.dart';
import '../../../services/desktop_paste/focused_target/linux_focused_target.dart';
import '../../../services/desktop_paste/linux_desktop_paste_controller.dart';
import '../../../services/desktop_paste/linux_portal_input.dart';
import '../../../widgets/wp_button.dart';

/// The Linux paste controller, or null on other platforms and in builds
/// without Auto-Paste.
final _linuxControllerProvider = Provider<LinuxDesktopPasteController?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  return controller is LinuxDesktopPasteController ? controller : null;
});

/// Whether this desktop offers the portal keyboard.
final linuxPortalInputAvailableProvider = FutureProvider<bool>((ref) async {
  final controller = ref.watch(_linuxControllerProvider);
  return controller != null && await controller.portalInputAvailable();
});

/// What the GNOME row can offer here.
enum GnomeExtensionSetup {
  /// Not GNOME: no row.
  none,

  /// The extension runs: a button turns it off (consent withdrawn).
  enabled,

  /// Installed but off: a button turns it on.
  canEnable,

  /// Not installed (or not visible from a sandbox): a pointer to the manual.
  notInstalled,
}

final gnomeExtensionSetupProvider = FutureProvider<GnomeExtensionSetup>((
  ref,
) async {
  final env = Platform.environment;
  if (detectLinuxFocusDesktop(env) != LinuxFocusDesktop.gnome) {
    return GnomeExtensionSetup.none;
  }
  final status = await ref.watch(linuxFocusStatusProvider.future);
  if (status == LinuxFocusStatus.available) return GnomeExtensionSetup.enabled;
  return gnomeFocusExtensionInstalled(env)
      ? GnomeExtensionSetup.canEnable
      : GnomeExtensionSetup.notInstalled;
});

class LinuxInputSetup extends ConsumerStatefulWidget {
  const LinuxInputSetup({
    super.key,
    required this.idPrefix,
    this.setGnomeExtension = setGnomeFocusExtensionEnabled,
  });

  /// `text` in the settings, `onboarding` on the onboarding page.
  final String idPrefix;

  /// Turns the GNOME extension on or off (replaceable in tests).
  final Future<bool> Function(bool enabled) setGnomeExtension;

  @override
  ConsumerState<LinuxInputSetup> createState() => _LinuxInputSetupState();
}

class _LinuxInputSetupState extends ConsumerState<LinuxInputSetup> {
  PortalInputConnectStatus? _portalStatus;
  bool _portalBusy = false;
  // Null until the user pressed the GNOME button; then whether it worked.
  bool? _gnomeEnabled;
  bool _gnomeBusy = false;

  String _id(String name) => '${widget.idPrefix}-$name';

  Future<void> _connectPortal(LinuxDesktopPasteController c) async {
    setState(() => _portalBusy = true);
    final result = await c.connectPortalInput();
    if (!mounted) return;
    setState(() {
      _portalBusy = false;
      _portalStatus = result.status;
    });
  }

  Future<void> _revokePortal(LinuxDesktopPasteController c) async {
    setState(() => _portalBusy = true);
    await c.revokePortalInput();
    if (!mounted) return;
    setState(() {
      _portalBusy = false;
      _portalStatus = null;
    });
  }

  Future<void> _enableGnome() async {
    setState(() => _gnomeBusy = true);
    final ok = await widget.setGnomeExtension(true);
    if (!mounted) return;
    setState(() {
      _gnomeBusy = false;
      _gnomeEnabled = ok;
    });
    // The status line and the blocklist hint read the new state.
    if (ok) {
      ref
        ..invalidate(linuxFocusStatusProvider)
        ..invalidate(gnomeExtensionSetupProvider);
    }
  }

  Future<void> _disableGnome() async {
    setState(() => _gnomeBusy = true);
    await widget.setGnomeExtension(false);
    if (!mounted) return;
    setState(() {
      _gnomeBusy = false;
      _gnomeEnabled = null;
    });
    ref
      ..invalidate(linuxFocusStatusProvider)
      ..invalidate(gnomeExtensionSetupProvider);
  }

  static String? portalStatusText(L10n l10n, PortalInputConnectStatus? s) =>
      switch (s) {
        null => null,
        PortalInputConnectStatus.connected =>
          l10n.settingsLinuxPortalInputConnected,
        PortalInputConnectStatus.cancelled =>
          l10n.settingsLinuxPortalInputCancelled,
        PortalInputConnectStatus.unavailable ||
        PortalInputConnectStatus.failed => l10n.settingsLinuxPortalInputFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final controller = ref.watch(_linuxControllerProvider);
    final portal = ref.watch(linuxPortalInputAvailableProvider).value ?? false;
    final gnome =
        ref.watch(gnomeExtensionSetupProvider).value ??
        GnomeExtensionSetup.none;
    final gnomeOn =
        _gnomeEnabled == true || gnome == GnomeExtensionSetup.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller != null && portal)
          _block(
            context,
            id: _id('linux-portal-input'),
            title: l10n.settingsLinuxPortalInputTitle,
            body: l10n.settingsLinuxPortalInputBody,
            status: portalStatusText(
              l10n,
              _portalStatus ??
                  (controller.portalInputConnected
                      ? PortalInputConnectStatus.connected
                      : null),
            ),
            button: controller.portalInputConnected
                ? WpButton(
                    testId: _id('linux-portal-input-revoke'),
                    label: l10n.settingsLinuxPortalInputRevoke,
                    variant: WpButtonVariant.secondary,
                    tone: WpButtonTone.neutral,
                    isLoading: _portalBusy,
                    onPressed: _portalBusy
                        ? null
                        : () => _revokePortal(controller),
                  )
                : WpButton(
                    testId: _id('linux-portal-input-connect'),
                    label: l10n.settingsLinuxPortalInputConnect,
                    variant: WpButtonVariant.secondary,
                    isLoading: _portalBusy,
                    onPressed: _portalBusy
                        ? null
                        : () => _connectPortal(controller),
                  ),
          ),
        if (gnome != GnomeExtensionSetup.none || _gnomeEnabled != null)
          _block(
            context,
            id: _id('linux-gnome-extension'),
            title: l10n.settingsLinuxGnomeExtensionTitle,
            body: l10n.settingsLinuxGnomeExtensionBody,
            status: switch (_gnomeEnabled) {
              true => l10n.settingsLinuxGnomeExtensionRelogin,
              false => l10n.settingsLinuxGnomeExtensionFailed(
                gnomeFocusExtensionEnableCommand,
              ),
              null =>
                gnome == GnomeExtensionSetup.notInstalled
                    ? l10n.settingsLinuxGnomeExtensionNotInstalled
                    : null,
            },
            button: gnomeOn
                ? WpButton(
                    testId: _id('linux-gnome-extension-disable'),
                    label: l10n.settingsLinuxGnomeExtensionDisable,
                    variant: WpButtonVariant.secondary,
                    tone: WpButtonTone.neutral,
                    isLoading: _gnomeBusy,
                    onPressed: _gnomeBusy ? null : _disableGnome,
                  )
                : gnome == GnomeExtensionSetup.canEnable ||
                      _gnomeEnabled == false
                ? WpButton(
                    testId: _id('linux-gnome-extension-enable'),
                    label: l10n.settingsLinuxGnomeExtensionEnable,
                    variant: WpButtonVariant.secondary,
                    isLoading: _gnomeBusy,
                    onPressed: _gnomeBusy ? null : _enableGnome,
                  )
                : null,
          ),
      ],
    );
  }

  Widget _block(
    BuildContext context, {
    required String id,
    required String title,
    required String body,
    required String? status,
    required Widget? button,
  }) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      identifier: id,
      child: Padding(
        key: ValueKey(id),
        padding: const EdgeInsets.only(top: WpSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: WpSpacing.xs),
            Text(
              body,
              style: text.bodySmall?.copyWith(color: WpColors.textSecondary),
            ),
            if (status != null) ...[
              const SizedBox(height: WpSpacing.xs),
              Semantics(
                identifier: '$id-status',
                // Selectable: the failure text carries a terminal command.
                child: SelectableText(
                  status,
                  key: ValueKey('$id-status'),
                  style: text.bodySmall,
                ),
              ),
            ],
            if (button != null) ...[
              const SizedBox(height: WpSpacing.sm),
              button,
            ],
          ],
        ),
      ),
    );
  }
}
