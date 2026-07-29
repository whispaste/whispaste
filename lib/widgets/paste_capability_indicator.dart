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
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/paste/paster.dart';
import 'paste_capability_restart_banner.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
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
          const PasteCapabilityRestartBanner(),
          const SizedBox(height: WpSpacing.xxs),
          _buildTroubleshoot(context, l10n, notifier),
        ],
      );
    }

    final status = _resolveStatus(cap, l10n, isDark);

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
              child: FilledButton.icon(
                // Prompt, open the right Settings pane, then poll so the status
                // flips to "ready" on its own once the user ticks the box.
                onPressed: _busy
                    ? null
                    : () => _run(() => notifier.requestGrant()),
                icon: const Icon(LucideIcons.shield, size: 14),
                label: Text(l10n.pasteCapabilityGrantButton),
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
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _showTroubleshoot = !_showTroubleshoot),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            icon: Icon(
              _showTroubleshoot
                  ? LucideIcons.chevronDown
                  : LucideIcons.chevronRight,
              size: 14,
            ),
            label: Text(l10n.pasteCapabilityTroubleshoot),
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
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _run(() => notifier.check()),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: Text(l10n.pasteCapabilityTestButton),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _repair,
                icon: const Icon(LucideIcons.wrench, size: 14),
                label: Text(l10n.pasteCapabilityRepairButton),
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
                TextButton.icon(
                  onPressed: _busy ? null : MacOSLifecycleChannel.restart,
                  icon: const Icon(LucideIcons.rotateCw, size: 14),
                  label: Text(l10n.pasteCapabilityRestartButton),
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
    bool isDark,
  ) {
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
        title: l10n.pasteCapabilityPermissionMissing,
        subtitle: Platform.isMacOS ? l10n.pasteCapabilityWhyMac : null,
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
