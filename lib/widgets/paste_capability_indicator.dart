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
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/tokens.dart';
import '../services/paste/paste_capability_notifier.dart';
import '../services/paste/paster.dart';

class PasteCapabilityIndicator extends ConsumerStatefulWidget {
  const PasteCapabilityIndicator({super.key});

  @override
  ConsumerState<PasteCapabilityIndicator> createState() =>
      _PasteCapabilityIndicatorState();
}

class _PasteCapabilityIndicatorState
    extends ConsumerState<PasteCapabilityIndicator> {
  static final _log = AppLogger('PasteCapability');

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

  Future<void> _openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    );
    try {
      await launchUrl(uri);
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings', e);
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
    final capState = ref.watch(pasteCapabilityNotifierProvider);
    final cap = capState.capability;

    final (icon, color, label) = _resolveStatus(cap, l10n);
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);

    final missing =
        cap?.status == PasteCapabilityStatus.permissionMissing &&
        Platform.isMacOS;
    final waiting =
        _busy || capState.pollingPhase == PollingPhase.awaitingGrant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(WpRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (waiting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          // One clear path when the permission is missing: explain why, offer a
          // single primary action, and tuck self-help away. (With stable
          // code-signing the grant now survives updates, so the old multi-button
          // repair cluster is no longer the default surface.)
          if (missing) ...[
            const SizedBox(height: 8),
            Text(
              l10n.pasteCapabilityWhyMac,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                // Prompt, open the right Settings pane, then poll so the status
                // flips to "ready" on its own once the user ticks the box.
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await notifier.check(prompt: true);
                        await _openAccessibilitySettings();
                        notifier.startPolling();
                      }),
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
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
            ],
          ),
        ],
      ],
    );
  }

  (IconData, Color, String) _resolveStatus(PasteCapability? cap, L10n l10n) {
    if (cap == null) {
      return (
        LucideIcons.loaderCircle,
        const Color(0xFF38D9F0),
        l10n.pasteCapabilityCheckTitle,
      );
    }
    return switch (cap.status) {
      PasteCapabilityStatus.ready => (
        LucideIcons.circleCheck,
        const Color(0xFF16A34A),
        l10n.pasteCapabilityReady,
      ),
      PasteCapabilityStatus.permissionMissing => (
        LucideIcons.shieldAlert,
        const Color(0xFFEF4444),
        l10n.pasteCapabilityPermissionMissing,
      ),
      PasteCapabilityStatus.unsupported => (
        LucideIcons.info,
        const Color(0xFF6B7280),
        l10n.pasteCapabilityUnsupported,
      ),
    };
  }
}
