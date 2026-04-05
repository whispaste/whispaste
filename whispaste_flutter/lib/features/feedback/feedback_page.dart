import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/section.dart';

/// Feedback page — rating + text feedback form.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: WpSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WpSection(
            title: 'Send Feedback',
            subtitle: 'Help us improve WhisPaste',
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl, WpSpacing.md, WpSpacing.xl, WpSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: WpSpacing.sm),
                Text(
                  'How would you rate WhisPaste?',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: WpSpacing.sm),
                // Star rating
                Row(
                  children: List.generate(5, (i) {
                    final filled = i < _rating;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _rating = i + 1),
                        child: Padding(
                          padding: const EdgeInsets.only(right: WpSpacing.xxs),
                          child: Icon(
                            filled ? LucideIcons.star : LucideIcons.star,
                            size: WpIconSize.xl,
                            color: filled
                                ? (isDark ? WpColorsDark.warning : WpColorsLight.warning)
                                : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: WpSpacing.xl),
                // Comment field
                TextField(
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Tell us what you think…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: WpSpacing.lg),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(LucideIcons.send, size: WpIconSize.sm),
                  label: const Text('Send Feedback'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
