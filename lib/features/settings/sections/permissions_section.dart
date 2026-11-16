/// The permissions overview in Settings > Privacy (#1198): microphone,
/// Auto-Paste and Input Monitoring, each with its status, one sentence on its
/// purpose and the one action that changes it.
///
/// Microphone and Auto-Paste come from `permissionsOverviewProvider`, which
/// this section only reads (the onboarding renders it unchanged). Input
/// Monitoring comes from `inputMonitoringStatusProvider`: needed only for a
/// single key as the trigger.
///
/// A row appears only where the system has a grant the user can give or take
/// away: macOS shows all three, Windows only the microphone, and Linux none,
/// so Settings hides the whole section there. The Wayland limit of the
/// single-key trigger is named in the key picker, not here.
///
/// The statuses stay live while the section is visible: the macOS grants are
/// polled, so a switch flipped in System Settings shows without a restart.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/permission_helper_service.dart';
import '../../../services/permissions/input_monitoring_grant.dart';
import '../../../services/permissions/input_monitoring_status.dart';
import '../../../services/permissions/mic_permission_notifier.dart';
import '../../../services/permissions/permissions_overview_provider.dart';
import '../../../widgets/wp_button.dart';
import '../widgets/wp_settings_group.dart';

/// Row ids of the three permission rows (search, deep links, guard).
const kPermissionMicRowId = 'privacy-permission-microphone';
const kPermissionPasteRowId = 'privacy-permission-auto-paste';
const kPermissionInputMonitoringRowId = 'privacy-permission-input-monitoring';

class PermissionsSection extends ConsumerStatefulWidget {
  const PermissionsSection({super.key});

  @override
  ConsumerState<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends ConsumerState<PermissionsSection> {
  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  InputMonitoringAccessNotifier? _inputMonitoring;
  void Function()? _releasePasteWatch;
  PermissionHelperService? _helper;
  StreamSubscription<PermissionHelperEvent>? _helperEvents;
  bool _helperShown = false;
  bool _inputMonitoringBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final platform = defaultTargetPlatform;
      if (micPermissionApplies(platform)) {
        unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
      }
      if (!_isMac) return;
      final access = ref.read(inputMonitoringAccessProvider.notifier);
      _inputMonitoring = access;
      access.startPolling();
      final paste = ref.read(pasteCapabilityNotifierProvider.notifier);
      // No immediate check here: the app already probes Auto-Paste at start
      // and on every return to the foreground, and the watch re-reads it
      // every two seconds while this section is visible.
      _releasePasteWatch = paste.watchWhileVisible(
        interval: const Duration(seconds: 2),
      );
      _helper = ref.read(permissionHelperProvider);
      _helperEvents = _helper!.events.listen((event) {
        _helperShown = false;
        if (event.kind == PermissionHelperKind.inputMonitoring) {
          unawaited(_inputMonitoring?.check());
        }
      });
    });
  }

  @override
  void dispose() {
    _inputMonitoring?.stopPolling();
    _releasePasteWatch?.call();
    unawaited(_helperEvents?.cancel());
    if (_helperShown) unawaited(_helper?.hide());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final overview = ref.watch(permissionsOverviewProvider);
    final inputStatus = ref.watch(inputMonitoringStatusProvider);
    final hotkey =
        ref.watch(settingsProvider.select((s) => s.value?.hotkey)) ??
        AppSettings.defaults.hotkey;
    final needed = inputMonitoringNeeded(hotkey);

    return WpSettingsGroup(
      heading: l10n.settingsPermissions,
      children: [
        for (final entry in overview)
          switch (entry.id) {
            PermissionOverviewId.microphone => _row(
              l10n,
              rowId: kPermissionMicRowId,
              id: 'microphone',
              title: l10n.permissionRowMicTitle,
              purpose: entry.status == PermissionOverviewStatus.unresponsive
                  ? l10n.permissionRowMicNoResponse
                  : l10n.permissionRowMicPurpose,
              status: entry.status,
              onAction: () => _micAction(entry.status),
            ),
            PermissionOverviewId.autoPaste => _row(
              l10n,
              rowId: kPermissionPasteRowId,
              id: 'auto-paste',
              title: l10n.permissionRowPasteTitle,
              purpose: l10n.permissionRowPastePurpose,
              status: entry.status,
              onAction: () => unawaited(
                ref
                    .read(pasteCapabilityNotifierProvider.notifier)
                    .requestGrant(),
              ),
            ),
          },
        if (inputMonitoringPermissionApplies(defaultTargetPlatform))
          _row(
            l10n,
            rowId: kPermissionInputMonitoringRowId,
            id: 'input-monitoring',
            title: l10n.permissionRowInputMonitoringTitle,
            purpose: _inputMonitoringPurpose(l10n, needed: needed),
            status: inputStatus,
            // The same label and steps as the withdrawn-grant notice (#1200).
            missingLabel: l10n.permissionRowGrant,
            // Tests run under another platform: only macOS can show the prompt.
            onAction: _isMac
                ? () => unawaited(_inputMonitoringAction(l10n))
                : null,
            busy: _inputMonitoringBusy,
          ),
      ],
    );
  }

  String _inputMonitoringPurpose(L10n l10n, {required bool needed}) => needed
      ? l10n.permissionRowInputMonitoringPurpose
      : l10n.permissionRowInputMonitoringNotNeeded;

  Widget _row(
    L10n l10n, {
    required String rowId,
    required String id,
    required String title,
    required String purpose,
    required PermissionOverviewStatus status,
    VoidCallback? onAction,
    bool busy = false,
    String? missingLabel,
  }) {
    final actionLabel = switch (status) {
      PermissionOverviewStatus.missing =>
        missingLabel ?? l10n.actionOpenSystemSettings,
      PermissionOverviewStatus.pending => l10n.permissionRowAllow,
      PermissionOverviewStatus.unresponsive => l10n.actionRetry,
      PermissionOverviewStatus.granted ||
      PermissionOverviewStatus.notNeeded => null,
    };
    return WpSettingsRow(
      rowId: rowId,
      title: title,
      subtitle: purpose,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusLabel(id: id, status: status),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: WpSpacing.sm),
            WpButton(
              key: ValueKey('permissions-$id-action'),
              testId: 'permissions-$id-action',
              label: actionLabel,
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.neutral,
              isLoading: busy,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }

  void _micAction(PermissionOverviewStatus status) {
    final mic = ref.read(micPermissionNotifierProvider.notifier);
    switch (status) {
      case PermissionOverviewStatus.missing:
        // Denied once: the system no longer asks, only the settings pane helps.
        unawaited(mic.openSystemSettings());
        mic.startPolling();
      case PermissionOverviewStatus.unresponsive:
        // The status read hung: ask it again, without a system prompt.
        unawaited(mic.check());
      case _:
        unawaited(mic.request());
    }
  }

  /// The shared "Grant access" steps (#1200), the same as in the notice
  /// that reports a withdrawn grant.
  Future<void> _inputMonitoringAction(L10n l10n) async {
    if (_inputMonitoringBusy) return;
    setState(() => _inputMonitoringBusy = true);
    try {
      final step = await grantInputMonitoring(read: ref.read, l10n: l10n);
      if (step == InputMonitoringGrantStep.helperShown) _helperShown = true;
    } finally {
      if (mounted) setState(() => _inputMonitoringBusy = false);
    }
  }
}

/// Icon and word for the status: "Allowed", "Missing", "No response",
/// "Not needed". A
/// pending status shows no word; its "Allow" button says enough.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.id, required this.status});

  final String id;
  final PermissionOverviewStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final (IconData icon, Color color, String? label) = switch (status) {
      PermissionOverviewStatus.granted => (
        LucideIcons.circleCheck,
        WpColors.accent,
        l10n.permissionRowGranted,
      ),
      PermissionOverviewStatus.missing => (
        LucideIcons.shieldAlert,
        WpColors.warning,
        l10n.permissionRowMissing,
      ),
      PermissionOverviewStatus.notNeeded => (
        LucideIcons.circleMinus,
        WpColors.textMuted,
        l10n.permissionRowNotNeeded,
      ),
      PermissionOverviewStatus.unresponsive => (
        LucideIcons.circleAlert,
        WpColors.warning,
        l10n.permissionRowNoResponse,
      ),
      PermissionOverviewStatus.pending => (
        LucideIcons.circleDashed,
        WpColors.textSecondary,
        null,
      ),
    };
    return Semantics(
      identifier: 'permissions-$id-status',
      child: Row(
        key: ValueKey('permissions-$id-status'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: WpIconSize.sm, color: color),
          if (label != null) ...[
            const SizedBox(width: WpSpacing.xxs),
            Text(
              label,
              style: TextStyle(fontSize: WpTypography.small, color: color),
            ),
          ],
        ],
      ),
    );
  }
}
