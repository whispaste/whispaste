import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/hardware_info_service.dart' as hw;

final _log = AppLogger('InsufficientRamScreen');

/// Full-screen blocking error shown when system RAM is below [hw.kMinRamMB].
///
/// Displayed instead of the main app — the user can only quit or visit
/// the system requirements page. Never blocks when RAM detection fails
/// (null → fail-open).
class InsufficientRamScreen extends StatelessWidget {
  const InsufficientRamScreen({super.key, required this.detectedGb});

  /// Detected RAM in GB (e.g. 4.0 for a 4 GB system).
  final double detectedGb;

  static const String _learnMoreUrl = 'https://whispaste.de/#faq';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: WpColorsDark.frameGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WpSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _ErrorCard(
                detectedGb: detectedGb,
                l10n: l10n,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.detectedGb, required this.l10n});

  final double detectedGb;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _AppIcon(),
        const SizedBox(height: WpSpacing.xl),

        _WarningBadge(label: l10n.insufficientRamSystemCheck),
        const SizedBox(height: WpSpacing.lg),

        Text(
          l10n.insufficientRamTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: WpColorsDark.textPrimary,
            height: 1.15,
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        _RamSummaryRow(
          detectedGb: detectedGb,
          yourSystemLabel: l10n.insufficientRamYourSystem,
          requiredLabel: l10n.insufficientRamRequired,
        ),
        const SizedBox(height: WpSpacing.lg),

        Text(
          l10n.insufficientRamBody(detectedGb, hw.kMinRamMB ~/ 1024),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: WpColorsDark.textSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: _QuitButton(label: l10n.insufficientRamQuit),
        ),
        const SizedBox(height: WpSpacing.md),

        _LearnMoreLink(label: l10n.insufficientRamLearnMore),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/app_icon.png',
      width: 80,
      height: 80,
      errorBuilder: (_, e, s) => const SizedBox(
        width: 80,
        height: 80,
        child: Icon(LucideIcons.mic, size: 48, color: WpColorsDark.textPrimary),
      ),
    );
  }
}

class _WarningBadge extends StatelessWidget {
  const _WarningBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WpColorsDark.warningOrange.withValues(alpha: 0.15),
        borderRadius: WpRadius.borderFull,
        border: Border.all(
          color: WpColorsDark.warningOrange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.triangleAlert,
            size: 15,
            color: WpColorsDark.warningOrange,
          ),
          const SizedBox(width: WpSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WpColorsDark.warningOrange,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RamSummaryRow extends StatelessWidget {
  const _RamSummaryRow({
    required this.detectedGb,
    required this.yourSystemLabel,
    required this.requiredLabel,
  });

  final double detectedGb;
  final String yourSystemLabel;
  final String requiredLabel;

  @override
  Widget build(BuildContext context) {
    const requiredGb = hw.kMinRamMB ~/ 1024;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.lg,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: WpColorsDark.surfaceVariant,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColorsDark.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RamChip(
            label: yourSystemLabel,
            value: '${detectedGb.toStringAsFixed(1)} GB',
            valueColor: WpColorsDark.warningOrange,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
            child: Container(
              width: 1,
              height: 28,
              color: WpColorsDark.borderSubtle,
            ),
          ),
          _RamChip(
            label: requiredLabel,
            value: '$requiredGb GB',
            valueColor: WpColorsDark.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _RamChip extends StatelessWidget {
  const _RamChip({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: WpColorsDark.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _QuitButton extends StatefulWidget {
  const _QuitButton({required this.label});

  final String label;

  @override
  State<_QuitButton> createState() => _QuitButtonState();
}

class _QuitButtonState extends State<_QuitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => exit(1),
          child: AnimatedContainer(
            duration: WpMotion.fast,
            decoration: BoxDecoration(
              color: _hovered
                  ? WpColorsDark.errorRedHover
                  : WpColorsDark.errorRed,
              borderRadius: WpRadius.borderMd,
              boxShadow: WpShadows.elevated,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.x, size: 18, color: Colors.white),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LearnMoreLink extends StatefulWidget {
  const _LearnMoreLink({required this.label});

  final String label;

  @override
  State<_LearnMoreLink> createState() => _LearnMoreLinkState();
}

class _LearnMoreLinkState extends State<_LearnMoreLink> {
  bool _hovered = false;

  Future<void> _open() async {
    try {
      await launchUrl(
        Uri.parse(InsufficientRamScreen._learnMoreUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _log.warning('Could not open system requirements URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => unawaited(_open()),
          child: AnimatedDefaultTextStyle(
            duration: WpMotion.fast,
            style: TextStyle(
              fontSize: 13,
              color: _hovered
                  ? WpColorsDark.textPrimary
                  : WpColorsDark.textSecondary,
              decoration: TextDecoration.underline,
              decorationColor: _hovered
                  ? WpColorsDark.textPrimary
                  : WpColorsDark.textSecondary,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
