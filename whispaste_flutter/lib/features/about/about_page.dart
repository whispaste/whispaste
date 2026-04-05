import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/page_shell.dart';

/// About page — app info, version, credits, links, keyboard shortcuts.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// Platform-aware modifier key label.
  static String get _modKey {
    try {
      if (Platform.isMacOS) return '⌘';
    } catch (_) {
      // Platform not available (web) — fall back to Ctrl
    }
    return 'Ctrl';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = Theme.of(context).textTheme;

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: WpSpacing.xl),
          // Brand wordmark — centered
          const Center(child: WpBrandWordmark(height: 64)),
          const SizedBox(height: WpSpacing.md),
          Center(child: Text('Version 1.2.0', style: ts.bodySmall)),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              'Dictate anywhere, paste everywhere.',
              style: ts.bodyMedium?.copyWith(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xxl),

          // Info cards — fill width
          _InfoCard(
            icon: LucideIcons.codeXml,
            title: 'Built with',
            description: 'Flutter, Go, whisper.cpp, llama.cpp',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.sm),
          _InfoCard(
            icon: LucideIcons.shield,
            title: 'Privacy-first',
            description:
                'Local AI inference by default — your voice never leaves your device unless you choose a cloud service.',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.sm),
          _InfoCard(
            icon: LucideIcons.monitor,
            title: 'Platforms',
            description: 'Windows  ·  macOS and Linux in development',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xxl),

          // Keyboard shortcuts
          Text('Keyboard Shortcuts', style: ts.titleMedium),
          const SizedBox(height: WpSpacing.sm),
          _ShortcutRow(
            label: 'Start / Stop recording',
            shortcut: '$_modKey + Shift + R',
            isDark: isDark,
          ),
          _ShortcutRow(
            label: 'Command palette',
            shortcut: '$_modKey + K',
            isDark: isDark,
          ),
          _ShortcutRow(
            label: 'Settings',
            shortcut: '$_modKey + ,',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xxl),

          // Links
          Text('Links', style: ts.titleMedium),
          const SizedBox(height: WpSpacing.sm),
          _LinkRow(
            icon: LucideIcons.globe,
            label: 'Website',
            url: 'https://whispaste.com',
            displayUrl: 'whispaste.com',
            isDark: isDark,
          ),
          _LinkRow(
            icon: IconData(
              FontAwesomeIcons.github.codePoint,
              fontFamily: FontAwesomeIcons.github.fontFamily,
              fontPackage: FontAwesomeIcons.github.fontPackage,
            ),
            label: 'GitHub',
            url: 'https://github.com/whispaste',
            displayUrl: 'github.com/whispaste',
            isDark: isDark,
          ),
          _LinkRow(
            icon: LucideIcons.fileText,
            label: 'Privacy Policy',
            url: 'https://whispaste.com/privacy',
            displayUrl: 'whispaste.com/privacy',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xxxl),

          Center(
            child: Text(
              '© ${DateTime.now().year} WhisPaste. All rights reserved.',
              style: ts.bodySmall,
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        gradient: isDark
            ? WpColorsDark.warmSurfaceGradient
            : WpColorsLight.warmSurfaceGradient,
        borderRadius: WpRadius.borderMd,
        border: Border.all(
          color: isDark
              ? WpColorsDark.glassBorder
              : WpColorsLight.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.accentSubtle
                  : WpColorsLight.accentSubtle,
              borderRadius: WpRadius.borderSm,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: WpIconSize.md,
              color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
            ),
          ),
          const SizedBox(width: WpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.label,
    required this.shortcut,
    required this.isDark,
  });

  final String label;
  final String shortcut;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs + 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant,
              borderRadius: WpRadius.borderSm,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderDefault
                    : WpColorsLight.borderDefault,
              ),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textPrimary
                    : WpColorsLight.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatefulWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.url,
    required this.displayUrl,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String url;
  final String displayUrl;
  final bool isDark;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _isHovered = false;

  Future<void> _launch() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.label}: ${widget.displayUrl}',
      link: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: _launch,
          child: AnimatedContainer(
            duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark ? WpColorsDark.hover : WpColorsLight.hover)
                  : Colors.transparent,
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: WpIconSize.sm,
                  color: widget.isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  widget.displayUrl,
                  style: TextStyle(
                    color: widget.isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                Icon(
                  LucideIcons.externalLink,
                  size: WpIconSize.xs,
                  color: widget.isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
