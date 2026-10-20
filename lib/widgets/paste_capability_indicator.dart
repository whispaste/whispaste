/// Live capability indicator for Auto-Paste — shown in the After
/// Transcription settings section.
///
/// Thin presentational widget: all probe/poll/repair logic lives in
/// [PasteCapabilityNotifier]. The widget only reads notifier state and
/// dispatches user intents (test, grant, repair, open settings) back to it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../features/onboarding/steps/auto_paste_step.dart'
    show linuxPasteFormatForOnboarding;
import '../services/desktop_paste/linux_desktop_paste_controller.dart'
    show linuxUinputCopyCommand;
import '../services/desktop_paste/linux_package_format.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/permissions/stale_entry_removal_guide.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart';
import '../services/paste/paster.dart';
import 'paste_capability_restart_banner.dart';
import 'toast.dart';
import 'wp_button.dart';
import 'wp_command_box.dart';

class WpPasteCapabilityIndicator extends ConsumerStatefulWidget {
  const WpPasteCapabilityIndicator({super.key});

  @override
  ConsumerState<WpPasteCapabilityIndicator> createState() =>
      _WpPasteCapabilityIndicatorState();
}

class _WpPasteCapabilityIndicatorState
    extends ConsumerState<WpPasteCapabilityIndicator> {
  bool _busy = false;
  bool _showTroubleshoot = false;
  late final void Function() _releaseWatch;

  @override
  void initState() {
    super.initState();
    // Keep the status live while this card is on screen (30 s recheck).
    _releaseWatch = ref
        .read(pasteCapabilityNotifierProvider.notifier)
        .watchWhileVisible();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run(() => ref.read(pasteCapabilityNotifierProvider.notifier).check());
    });
  }

  @override
  void dispose() {
    _releaseWatch();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repair() async {
    if (!Platform.isMacOS) return;
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    // The sandboxed build cannot reset its own entry — the guided removal
    // is its repair.
    if (notifier.requiresManualEntryRemoval) {
      await runStaleEntryRemovalGuide(
        l10n: L10n.of(context),
        notifier: notifier,
      );
      return;
    }
    // Without evidence of a stale entry the only honest action is the
    // Settings deep-link: a reset would wipe a grant that is not even stale.
    if (!notifier.staleEntryResetCandidate) {
      await notifier.openAccessibilitySettings();
      return;
    }
    await _run(() async {
      final result = await notifier.resetStaleEntry(
        confirmReset: () => confirmTccEntryReset(l10n: L10n.of(context)),
      );
      // Declined in the dialog: nothing was reset, nothing to report.
      if (!mounted || result == null) return;
      final l10n = L10n.of(context);
      final cleared =
          result.accessibilityCleared.clamp(0, 999) +
          result.appleEventsCleared.clamp(0, 999);
      final message = result.isSupported
          ? l10n.pasteCapabilityRepairDone(cleared)
          : l10n.pasteCapabilityRepairFailed;
      // The raw SnackBar rendered both outcomes identically — a failed
      // permission reset looked exactly like a successful one. The toast
      // type carries that distinction now.
      WpToast.show(
        context,
        message: message,
        type: result.isSupported ? WpToastType.success : WpToastType.error,
        duration: const Duration(seconds: 5),
      );
      // Re-check capability without prompting so the indicator reflects the
      // post-reset state (will likely still be "missing" until the next
      // paste triggers the fresh prompt).
      await notifier.check();
    });
  }

  /// Shown only when the user has to act (permission missing, restart needed,
  /// Wayland or unsupported). A ready capability renders nothing, the way other
  /// apps stay quiet when everything works; a status that is still unknown
  /// renders nothing either.
  @override
  Widget build(BuildContext context) {
    final cap = ref.watch(pasteCapabilityNotifierProvider).capability;
    if (cap == null || cap.status == PasteCapabilityStatus.ready) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.sm,
        WpSpacing.sm,
        WpSpacing.sm,
        WpSpacing.xs,
      ),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final l10n = L10n.of(context);
    final capState = ref.watch(pasteCapabilityNotifierProvider);
    final cap = capState.capability;
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);

    final missing =
        cap?.status == PasteCapabilityStatus.permissionMissing &&
        defaultTargetPlatform == TargetPlatform.macOS;
    // Linux: the uinput device needs a one-time udev rule that only the user
    // can install. The failed-paste notification leads here (XP-5-06), so the
    // card hands over the command instead of the macOS grant flow.
    final linuxSetupNeeded =
        cap?.status == PasteCapabilityStatus.permissionMissing &&
        defaultTargetPlatform == TargetPlatform.linux;
    final waiting =
        _busy || capState.pollingPhase == PollingPhase.awaitingGrant;

    // Restart-first: the grant demonstrably happened but this running process
    // can't see it yet (stale in-process TCC view — macOS only re-evaluates
    // on a fresh launch). Showing the regular "not yet allowed" card here
    // would gaslight the user into granting again, so the prominent restart
    // banner replaces the status card entirely; the collapsed troubleshoot
    // section stays reachable for the rare repair/test edge cases.
    if (missing && notifier.needsRestart) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WpPasteCapabilityRestartBanner(
            onRestart: () => notifier.restartForGrant(),
          ),
          const SizedBox(height: WpSpacing.xxs),
          _buildTroubleshoot(context, l10n, notifier),
        ],
      );
    }

    final status = _resolveStatus(
      cap,
      l10n,
      restartIneffective: notifier.restartWasIneffective,
    );

    // Neutral card + tinted icon badge: status is carried by the badge and
    // the copy, not by flooding the whole surface with a status colour —
    // matches the onboarding cards and the quiet macOS-Settings register.
    final surface = (WpColors.surfaceVariant).withValues(alpha: 0.5);
    final border = WpColors.borderSubtle;
    final textSecondary = WpColors.textSecondary;

    return Container(
      key: const ValueKey('settings-paste-capability-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: WpRadius.borderSm,
                ),
                child: Center(
                  child: Icon(
                    status.icon,
                    size: WpIconSize.sm,
                    color: status.color,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (status.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        status.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (waiting) ...[
                const SizedBox(width: WpSpacing.sm),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          // One clear path when the permission is missing: explain why (the
          // subtitle above), offer a single primary action, and tuck self-help
          // away. (With stable code-signing the grant now survives updates, so
          // the old multi-button repair cluster is no longer the default
          // surface.)
          if (missing) ...[
            const SizedBox(height: WpSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: WpButton(
                key: const ValueKey('settings-paste-grant-button'),
                label: l10n.pasteCapabilityGrantButton,
                variant: WpButtonVariant.primary,
                icon: LucideIcons.shield,
                // Prompt, open the right Settings pane, then poll so the status
                // flips to "ready" on its own once the user ticks the box.
                onPressed: _busy
                    ? null
                    : () => _run(() => notifier.requestGrant()),
              ),
            ),
            _buildTroubleshoot(context, l10n, notifier),
          ],
          if (linuxSetupNeeded) ...[
            const SizedBox(height: WpSpacing.sm),
            // The command runs with sudo, so it is shown, not only copied.
            WpCommandBox(
              command: linuxUinputCopyCommand(
                linuxPasteFormatForOnboarding() ?? LinuxPackageFormat.native,
              ),
              textKey: const ValueKey('settings-paste-linux-command'),
            ),
            const SizedBox(height: WpSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: WpButton(
                key: const ValueKey('settings-paste-linux-copy-command'),
                label: l10n.pasteFailureLinuxUinputCopy,
                variant: WpButtonVariant.primary,
                icon: LucideIcons.copy,
                onPressed: () => _copyLinuxSetupCommand(l10n),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyLinuxSetupCommand(L10n l10n) async {
    await Clipboard.setData(
      ClipboardData(
        text: linuxUinputCopyCommand(
          linuxPasteFormatForOnboarding() ?? LinuxPackageFormat.native,
        ),
      ),
    );
    if (!mounted) return;
    WpToast.show(
      context,
      message: l10n.historyCopiedToClipboard,
      type: WpToastType.success,
      duration: const Duration(seconds: 3),
    );
  }

  /// Collapsed self-help for the rare stale-TCC-entry case. Unnecessary with
  /// stable signing, but still rescues users updating from older ad-hoc builds.
  Widget _buildTroubleshoot(
    BuildContext context,
    L10n l10n,
    PasteCapabilityNotifier notifier,
  ) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: WpButton(
            key: const ValueKey('settings-paste-troubleshoot-toggle'),
            label: l10n.pasteCapabilityTroubleshoot,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            size: WpButtonSize.dense,
            icon: _showTroubleshoot
                ? LucideIcons.chevronDown
                : LucideIcons.chevronRight,
            onPressed: () =>
                setState(() => _showTroubleshoot = !_showTroubleshoot),
          ),
        ),
        if (_showTroubleshoot) ...[
          Text(
            l10n.pasteCapabilityRepairHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 6),
          // Neutral, not accent — deliberately, because the accent these three
          // wore before the WpButton migration was never chosen: they simply
          // inherited `colorScheme.primary` from the TextButton theme, while
          // the toggle right above them already opted out to
          // `onSurfaceVariant`. They are three co-equal self-help options with
          // no recommended one among them, sitting under the card's single
          // accent CTA ("Grant"). Painting them accent would spend the colour
          // on structure instead of meaning and put three further claims on
          // the eye in a card that wants to make exactly one.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              WpButton(
                key: const ValueKey('settings-paste-test-button'),
                label: l10n.pasteCapabilityTestButton,
                variant: WpButtonVariant.ghost,
                tone: WpButtonTone.neutral,
                size: WpButtonSize.dense,
                icon: LucideIcons.refreshCw,
                onPressed: _busy ? null : () => _run(() => notifier.check()),
              ),
              WpButton(
                key: const ValueKey('settings-paste-repair-button'),
                label: l10n.pasteCapabilityRepairButton,
                variant: WpButtonVariant.ghost,
                tone: WpButtonTone.neutral,
                size: WpButtonSize.dense,
                icon: LucideIcons.wrench,
                onPressed: _busy ? null : _repair,
              ),
              // Covers the case this indicator otherwise can't recover
              // from on its own: the permission was actually granted (in
              // System Settings, possibly without ever using the "Grant"
              // button above) but this still-running process's own
              // in-process check of that grant is stale — macOS doesn't
              // re-evaluate it without a fresh process. Always offered
              // here rather than only after the polling-timeout heuristic
              // fires, since that heuristic only engages if the user went
              // through the Grant button first.
              if (defaultTargetPlatform == TargetPlatform.macOS)
                WpButton(
                  key: const ValueKey('settings-paste-restart-button'),
                  label: l10n.pasteCapabilityRestartButton,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  size: WpButtonSize.dense,
                  icon: LucideIcons.rotateCw,
                  onPressed: _busy
                      ? null
                      : () => _run(() => notifier.restartForGrant()),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Icon, badge colour, title and optional supporting line per status.
  ///
  /// `permissionMissing` uses the warning palette (not error): on first
  /// contact nothing is broken yet — the state is an invitation to grant,
  /// and red stays reserved for actual paste failures.
  ({IconData icon, Color color, String title, String? subtitle}) _resolveStatus(
    PasteCapability? cap,
    L10n l10n, {
    bool restartIneffective = false,
  }) {
    if (cap == null) {
      return (
        icon: LucideIcons.loaderCircle,
        color: WpColors.accent,
        title: l10n.pasteCapabilityCheckTitle,
        subtitle: null,
      );
    }
    return switch (cap.status) {
      PasteCapabilityStatus.ready => (
        icon: LucideIcons.circleCheck,
        color: WpColors.success,
        title: l10n.pasteCapabilityReady,
        subtitle: l10n.pasteCapabilityReadySubtitle,
      ),
      PasteCapabilityStatus.permissionMissing => (
        icon: LucideIcons.shieldAlert,
        color: WpColors.warning,
        // After a grant-driven restart that still reads missing, drop the
        // first-contact "not yet allowed / why" copy (which reads as "you
        // never did anything" and re-confuses) for an honest "the restart
        // didn't apply it — re-check in System Settings" message.
        title: restartIneffective
            ? l10n.pasteCapabilityRestartIneffectiveTitle
            : l10n.pasteCapabilityPermissionMissing,
        subtitle: restartIneffective
            ? l10n.pasteCapabilityRestartIneffectiveSubtitle
            : defaultTargetPlatform == TargetPlatform.macOS
            ? l10n.pasteCapabilityWhyMac
            : defaultTargetPlatform == TargetPlatform.linux
            ? l10n.pasteFailureLinuxUinputHint
            : null,
      ),
      PasteCapabilityStatus.unsupported => (
        icon: LucideIcons.info,
        color: WpColors.textMuted,
        title: defaultTargetPlatform == TargetPlatform.linux
            ? l10n.pasteCapabilityUnavailableLinux
            : l10n.pasteCapabilityUnsupported,
        subtitle: null,
      ),
    };
  }
}
