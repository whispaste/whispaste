import 'package:flutter/material.dart';
import '../../widgets/section.dart';
import '../../core/theme/tokens.dart';

/// Feedback page — rate + text feedback form.
class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WpSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WpSection(
            title: 'Send Feedback',
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help us improve WhisPaste. Your feedback is appreciated!',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: WpSpacing.lg),
                // Rating row placeholder
                Text(
                  'How would you rate WhisPaste?',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: WpSpacing.sm),
                Row(
                  children: List.generate(5, (i) {
                    return IconButton(
                      onPressed: () {
                        // TODO: Wire up rating state
                      },
                      icon: Icon(
                        Icons.star_border_rounded,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: WpSpacing.lg),
                // Comment field
                TextField(
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Tell us what you think…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: WpSpacing.lg),
                ElevatedButton(
                  onPressed: () {
                    // TODO: Submit feedback
                  },
                  child: const Text('Send Feedback'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
