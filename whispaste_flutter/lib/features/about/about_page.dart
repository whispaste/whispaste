import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/brand_logo.dart';

/// About page — app info, version, credits, links.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WpSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WpLayout.pageMaxWidth),
          child: Column(
            children: [
              const SizedBox(height: WpSpacing.xxl),
              // Real app icon with background
              const WpBrandLogo(
                size: 80,
                withBackground: true,
              ),
              const SizedBox(height: WpSpacing.lg),
              Text(
                'WhisPaste',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: WpSpacing.xxs),
              Text(
                'v1.2.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                'Dictate anywhere, paste everywhere.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WpSpacing.xxxl),
              // Info cards
              _InfoCard(
                icon: LucideIcons.codeXml,
                title: 'Built with',
                description: 'Flutter, Go, whisper.cpp, llama.cpp',
                isDark: isDark,
              ),
              const SizedBox(height: WpSpacing.sm),
              _InfoCard(
                icon: LucideIcons.shield,
                title: 'Privacy',
                description: 'Local-first — your data stays on your device',
                isDark: isDark,
              ),
              const SizedBox(height: WpSpacing.sm),
              _InfoCard(
                icon: LucideIcons.globe,
                title: 'Platforms',
                description: 'Windows, macOS, Linux (coming soon)',
                isDark: isDark,
              ),
              const SizedBox(height: WpSpacing.xxxl),
              Text(
                '© WhisPaste. All rights reserved.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated,
        borderRadius: WpRadius.borderMd,
        border: Border.all(
          color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: WpIconSize.md, color: cs.primary),
          const SizedBox(width: WpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
