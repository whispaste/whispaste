import 'package:flutter/material.dart';
import '../../widgets/section.dart';
import '../../core/theme/tokens.dart';

/// About page — app info, version, credits, links.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WpSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: WpSpacing.xxxl),
          // App icon placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: WpRadius.borderLg,
            ),
            child: Icon(Icons.mic_rounded, size: 40, color: cs.primary),
          ),
          const SizedBox(height: WpSpacing.lg),
          Text(
            'WhisPaste',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            'v1.2.0',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            'Dictate anywhere, paste everywhere.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WpSpacing.xxxl),
          WpSection(
            title: 'Credits',
            padding: EdgeInsets.zero,
            child: const Text(
              'Built with Flutter, Go, whisper.cpp, and llama.cpp.\n\n'
              '© WhisPaste. All rights reserved.',
            ),
          ),
        ],
      ),
    );
  }
}
