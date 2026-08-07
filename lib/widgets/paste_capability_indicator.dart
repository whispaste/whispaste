/// Live capability indicator for Auto-Paste — shown in the After
/// Transcription settings section.
///
/// Thin presentational widget: all probe/poll/repair logic lives in
/// [PasteCapabilityNotifier]. The widget only reads notifier state and
/// dispatches user intents (test, grant, repair, open settings) back to it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/paste/paster.dart';
import 'paste_capability_restart_banner.dart';
import 'toast.dart';
import 'wp_button.dart';

class PasteCapabilityIndicator extends ConsumerStatefulWidget {
  const PasteCapabilityIndicator({super.key});

  @override
  ConsumerState<PasteCapabilityIndicator> createState() =>
      _PasteCapabilityIndicatorState();
}

class _PasteCapabilityIndicatorState
    extends ConsumerState<PasteCapabilityIndicator> {
  bool _busy = false;
  bool _showTroubleshoot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run(() => ref.read(pasteCapabilityNotifierProvider.notifier).check());
    });
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
    await _run(() async {
      final result = await notifier.repair();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final capState = ref.watch(pasteCapabilityNotifierProvider);
    final cap = capState.capability;
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);

    final missing =
        cap?.status == PasteCapabilityStatus.permissionMissing &&
        Platform.isMacOS;
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
          PasteCapabilityRestartBanner(
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
      isDark,
      restartIneffective: notifier.restartWasIneffective,
    );

    // Neutral card + tinted icon badge: status is carried by the badge and
    // the copy, not by flooding the whole surface with a status colour —
    // matches the onboarding cards and the quiet macOS-Settings register.
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Container(
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
        ],
      ),
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
                label: l10n.pasteCapabilityTestButton,
                variant: WpButtonVariant.ghost,
                tone: WpButtonTone.neutral,
                size: WpButtonSize.dense,
                icon: LucideIcons.refreshCw,
                onPressed: _busy ? null : () => _run(() => notifier.check()),
              ),
              WpButton(
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
              if (Platform.isMacOS)
                WpButton(
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
    L10n l10n,
    bool isDark, {
    bool restartIneffective = false,
  }) {
    if (cap == null) {
      return (
        icon: LucideIcons.loaderCircle,
        color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
        title: l10n.pasteCapabilityCheckTitle,
        subtitle: null,
      );
    }
    return switch (cap.status) {
      PasteCapabilityStatus.ready => (
        icon: LucideIcons.circleCheck,
        color: isDark ? WpColorsDark.success : WpColorsLight.success,
        title: l10n.pasteCapabilityReady,
        subtitle: l10n.pasteCapabilityReadySubtitle,
      ),
      PasteCapabilityStatus.permissionMissing => (
        icon: LucideIcons.shieldAlert,
        color: isDark ? WpColorsDark.warning : WpColorsLight.warning,
        // After a grant-driven restart that still reads missing, drop the
        // first-contact "not yet allowed / why" copy (which reads as "you
        // never did anything" and re-confuses) for an honest "the restart
        // didn't apply it — re-check in System Settings" message.
        title: restartIneffective
            ? l10n.pasteCapabilityRestartIneffectiveTitle
            : l10n.pasteCapabilityPermissionMissing,
        subtitle: restartIneffective
            ? l10n.pasteCapabilityRestartIneffectiveSubtitle
            : (Platform.isMacOS ? l10n.pasteCapabilityWhyMac : null),
      ),
      PasteCapabilityStatus.unsupported => (
        icon: LucideIcons.info,
        color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        title: l10n.pasteCapabilityUnsupported,
        subtitle: null,
      ),
    };
  }
}
