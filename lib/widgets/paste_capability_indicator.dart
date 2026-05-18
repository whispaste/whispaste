/// Live capability indicator for Auto-Paste — shown in the After
/// Transcription settings section and the onboarding step.
///
/// Calls into the platform paste bridge to check whether the OS would
/// allow keystroke injection right now and renders a green/red badge
/// with action buttons (test + grant + open settings).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/tokens.dart';
import '../services/desktop_paste/desktop_paste_controller.dart';
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

  PasteCapability? _last;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(prompt: false));
  }

  Future<void> _check({required bool prompt}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final paster = ref.read(pasterProvider);
      if (paster == null) {
        setState(() {
          _last = const PasteCapability(
            status: PasteCapabilityStatus.unsupported,
          );
        });
        return;
      }
      final result = await paster.checkCapability(promptIfMissing: prompt);
      _log.info(
        'capability check: status=${result.status.name} '
        'canPrompt=${result.canPrompt} detail=${result.detail}',
      );
      if (!mounted) return;
      setState(() => _last = result);
    } finally {
      if (mounted) setState(() => _checking = false);
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

  Future<void> _repairTcc() async {
    if (!Platform.isMacOS) return;
    final controller = DesktopPasteController.create();
    if (controller == null) return;
    final result = await controller.repairTccEntries();
    _log.info(
      'TCC repair: ax cleared=${result.accessibilityCleared} '
      'ae cleared=${result.appleEventsCleared} '
      'error=${result.error ?? "none"}',
    );
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
    await _check(prompt: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final cap = _last;

    final (icon, color, label) = _resolveStatus(cap, l10n);

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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_checking)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (cap?.status == PasteCapabilityStatus.permissionMissing &&
              Platform.isMacOS) ...[
            const SizedBox(height: 8),
            Text(
              l10n.pasteCapabilityRepairHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: _checking ? null : () => _check(prompt: false),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: Text(l10n.pasteCapabilityTestButton),
              ),
              if (cap?.status == PasteCapabilityStatus.permissionMissing &&
                  Platform.isMacOS) ...[
                FilledButton.icon(
                  onPressed: _checking
                      ? null
                      : () async {
                          await _check(prompt: true);
                          await _openAccessibilitySettings();
                        },
                  icon: const Icon(LucideIcons.shield, size: 14),
                  label: Text(l10n.pasteCapabilityGrantButton),
                ),
                TextButton.icon(
                  onPressed: _openAccessibilitySettings,
                  icon: const Icon(LucideIcons.settings, size: 14),
                  label: Text(l10n.pasteFailureOpenSettings),
                ),
                TextButton.icon(
                  onPressed: _checking ? null : _repairTcc,
                  icon: const Icon(LucideIcons.wrench, size: 14),
                  label: Text(l10n.pasteCapabilityRepairButton),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _resolveStatus(
    PasteCapability? cap,
    L10n l10n,
  ) {
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
