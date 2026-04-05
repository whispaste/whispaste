import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/page_shell.dart';

/// About page — app info, version, open-source links, support, credits,
/// keyboard shortcuts, privacy, and system diagnostics.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static String get _modKey {
    try {
      if (Platform.isMacOS) return '⌘';
    } catch (_) {}
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

          // ── Brand hero ──
          const Center(child: WpBrandWordmark(height: 64)),
          const SizedBox(height: WpSpacing.md),
          Center(child: Text('Version 1.2.0', style: ts.bodySmall)),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              'Voice to text, instantly.',
              style: ts.bodyMedium?.copyWith(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),

          // ── Quick actions ──
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              _QuickAction(
                icon: LucideIcons.sparkles,
                label: "What's New",
                url: 'https://whispaste.de/changelog',
                isDark: isDark,
              ),
              _QuickAction(
                icon: IconData(
                  FontAwesomeIcons.github.codePoint,
                  fontFamily: FontAwesomeIcons.github.fontFamily,
                  fontPackage: FontAwesomeIcons.github.fontPackage,
                ),
                label: 'GitHub',
                url: 'https://github.com/whispaste/whispaste',
                isDark: isDark,
              ),
              _QuickAction(
                icon: LucideIcons.circleAlert,
                label: 'Report Issue',
                url: 'https://github.com/whispaste/whispaste/issues',
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Support this project ──
          _SectionHeader(title: 'Support this project', isDark: isDark),
          const SizedBox(height: WpSpacing.xs),
          Text(
            'WhisPaste is free and open source under the MIT license. '
            'If you find it useful, please consider supporting its development!',
            style: TextStyle(
              color: isDark
                  ? WpColorsDark.textSecondary
                  : WpColorsLight.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: WpSpacing.md),
          Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            children: [
              _SupportButton(
                icon: LucideIcons.heart,
                label: 'GitHub Sponsors',
                url: 'https://github.com/sponsors/silvio-l',
                isDark: isDark,
              ),
              _SupportButton(
                icon: IconData(
                  FontAwesomeIcons.mugHot.codePoint,
                  fontFamily: FontAwesomeIcons.mugHot.fontFamily,
                  fontPackage: FontAwesomeIcons.mugHot.fontPackage,
                ),
                label: 'Ko-fi',
                url: 'https://ko-fi.com/silviol',
                isDark: isDark,
              ),
              _SupportButton(
                icon: LucideIcons.star,
                label: 'Star on GitHub',
                url: 'https://github.com/whispaste/whispaste',
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Built with ──
          _SectionHeader(title: 'Built with', isDark: isDark),
          const SizedBox(height: WpSpacing.sm),
          _BuiltWithRow(
            icon: LucideIcons.codeXml,
            title: 'Flutter & Go',
            description:
                'Cross-platform UI with Flutter, performance-critical backend in Go via FFI.',
            isDark: isDark,
          ),
          _BuiltWithRow(
            icon: LucideIcons.mic,
            title: 'whisper.cpp & OpenAI Whisper',
            description:
                'Local and cloud speech recognition — fast, accurate, multilingual.',
            isDark: isDark,
          ),
          _BuiltWithRow(
            icon: LucideIcons.brain,
            title: 'llama.cpp',
            description:
                'Local LLM inference for AI post-processing without cloud dependency.',
            isDark: isDark,
          ),
          _BuiltWithRow(
            icon: LucideIcons.shield,
            title: 'Privacy-first',
            description:
                'Local AI inference by default — your voice never leaves your device unless you choose a cloud provider.',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Privacy & Data ──
          _SectionHeader(title: 'Privacy & Data', isDark: isDark),
          const SizedBox(height: WpSpacing.sm),
          _PrivacyPoint(
            text:
                'All transcriptions and history are stored locally on your device — never on external servers.',
            isDark: isDark,
          ),
          _PrivacyPoint(
            text:
                'Cloud providers (OpenAI, Groq, Deepgram, Anthropic, Gemini) only receive audio or text when you actively use them. Their privacy policies apply.',
            isDark: isDark,
          ),
          _PrivacyPoint(
            text:
                'No analytics, no tracking, no user accounts. Update checks contact GitHub (version + IP only).',
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Keyboard shortcuts ──
          _SectionHeader(title: 'Keyboard Shortcuts', isDark: isDark),
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
          const SizedBox(height: WpSpacing.xxxl),

          // ── Links ──
          _SectionHeader(title: 'Links', isDark: isDark),
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
            label: 'GitHub Repository',
            url: 'https://github.com/whispaste/whispaste',
            displayUrl: 'github.com/whispaste/whispaste',
            isDark: isDark,
          ),
          _LinkRow(
            icon: LucideIcons.scale,
            label: 'MIT License',
            url: 'https://github.com/whispaste/whispaste/blob/main/LICENSE',
            displayUrl: 'View on GitHub',
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

          // ── System diagnostics ──
          _SectionHeader(title: 'System Info', isDark: isDark),
          const SizedBox(height: WpSpacing.xs),
          Text(
            'Copy a compact diagnostics snapshot for bug reports.',
            style: TextStyle(
              color: isDark
                  ? WpColorsDark.textSecondary
                  : WpColorsLight.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: _CopyDiagnosticsButton(isDark: isDark),
          ),
          const SizedBox(height: WpSpacing.xxxl),

          // ── Credits ──
          Center(
            child: Text(
              'Made with ♥ by Silvio Lindstedt',
              style: ts.bodySmall?.copyWith(
                color: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Center(
            child: Text(
              'Open source under the MIT License',
              style: ts.bodySmall?.copyWith(
                color: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
        ],
      ),
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: WpSpacing.xxs),
        Container(
          height: 2,
          width: 32,
          decoration: BoxDecoration(
            color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}

// ─── Quick action pill ───────────────────────────────────────────────────────

class _QuickAction extends StatefulWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.url,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String url;
  final bool isDark;

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
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
          onTap: () async {
            final uri = Uri.parse(widget.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: AnimatedContainer(
            duration: _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                      ? WpColorsDark.hover
                      : WpColorsLight.hover)
                  : (widget.isDark
                      ? WpColorsDark.surfaceVariant
                      : WpColorsLight.surfaceVariant),
              borderRadius: WpRadius.borderFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: WpIconSize.sm, color: widget.isDark ? WpColorsDark.accent : WpColorsLight.accent),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark
                        ? WpColorsDark.textPrimary
                        : WpColorsLight.textPrimary,
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

// ─── Support button ──────────────────────────────────────────────────────────

class _SupportButton extends StatefulWidget {
  const _SupportButton({
    required this.icon,
    required this.label,
    required this.url,
    required this.isDark,
  });
  final IconData icon;
  final String label;
  final String url;
  final bool isDark;

  @override
  State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.parse(widget.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: AnimatedContainer(
            duration: _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: _hovered
                  ? accentColor.withValues(alpha: 0.15)
                  : accentColor.withValues(alpha: 0.08),
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: WpIconSize.sm, color: accentColor),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
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

// ─── Built-with row ──────────────────────────────────────────────────────────

class _BuiltWithRow extends StatelessWidget {
  const _BuiltWithRow({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color:
                  isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle,
              borderRadius: WpRadius.borderSm,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: WpIconSize.sm,
              color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? WpColorsDark.textPrimary
                        : WpColorsLight.textPrimary,
                  ),
                ),
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

// ─── Privacy point ───────────────────────────────────────────────────────────

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              LucideIcons.check,
              size: WpIconSize.xs,
              color: isDark ? WpColorsDark.success : WpColorsLight.success,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark
                    ? WpColorsDark.textSecondary
                    : WpColorsLight.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shortcut row ────────────────────────────────────────────────────────────

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

// ─── Link row ────────────────────────────────────────────────────────────────

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
            duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                      ? WpColorsDark.hover
                      : WpColorsLight.hover)
                  : (widget.isDark
                      ? WpColorsDark.hoverTransparent
                      : WpColorsLight.hoverTransparent),
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

// ─── Copy diagnostics button ─────────────────────────────────────────────────

class _CopyDiagnosticsButton extends StatefulWidget {
  const _CopyDiagnosticsButton({required this.isDark});
  final bool isDark;

  @override
  State<_CopyDiagnosticsButton> createState() =>
      _CopyDiagnosticsButtonState();
}

class _CopyDiagnosticsButtonState extends State<_CopyDiagnosticsButton> {
  bool _copied = false;

  void _copy() {
    final info = StringBuffer()
      ..writeln('WhisPaste v1.2.0')
      ..writeln('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Dart: ${Platform.version}')
      ..writeln('Locale: ${Platform.localeName}');

    Clipboard.setData(ClipboardData(text: info.toString()));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy debug info',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _copy,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant,
              borderRadius: WpRadius.borderSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _copied ? LucideIcons.checkCheck : LucideIcons.copy,
                  size: WpIconSize.sm,
                  color: _copied
                      ? (widget.isDark
                          ? WpColorsDark.success
                          : WpColorsLight.success)
                      : (widget.isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary),
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  _copied ? 'Copied!' : 'Copy Debug Info',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _copied
                        ? (widget.isDark
                            ? WpColorsDark.success
                            : WpColorsLight.success)
                        : (widget.isDark
                            ? WpColorsDark.textSecondary
                            : WpColorsLight.textSecondary),
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
