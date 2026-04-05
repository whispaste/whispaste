import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/page_shell.dart';

/// Feedback page — polished, chat-inspired feedback form.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _rating = 0;
  String _category = '';
  final _commentController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _rating > 0 && _category.isNotEmpty && _commentController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = Theme.of(context).textTheme;

    if (_submitted) {
      return WpPageShell(
        child: _ThankYouView(isDark: isDark, ts: ts, onReset: _reset),
      );
    }

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title area
          Text('Send Feedback', style: ts.headlineMedium),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            'Help us improve WhisPaste — every voice matters.',
            style: ts.bodyMedium?.copyWith(
              color: isDark
                  ? WpColorsDark.textSecondary
                  : WpColorsLight.textSecondary,
            ),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // Category selection
          Text('What\'s this about?', style: ts.titleSmall),
          const SizedBox(height: WpSpacing.sm),
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              _CategoryChip(
                icon: LucideIcons.bug,
                label: 'Bug Report',
                value: 'bug',
                selected: _category,
                isDark: isDark,
                onTap: (v) => setState(() => _category = v),
              ),
              _CategoryChip(
                icon: LucideIcons.lightbulb,
                label: 'Feature Idea',
                value: 'feature',
                selected: _category,
                isDark: isDark,
                onTap: (v) => setState(() => _category = v),
              ),
              _CategoryChip(
                icon: LucideIcons.messageCircle,
                label: 'General',
                value: 'general',
                selected: _category,
                isDark: isDark,
                onTap: (v) => setState(() => _category = v),
              ),
              _CategoryChip(
                icon: LucideIcons.sparkles,
                label: 'AI Quality',
                value: 'ai',
                selected: _category,
                isDark: isDark,
                onTap: (v) => setState(() => _category = v),
              ),
            ],
          ),

          const SizedBox(height: WpSpacing.xxl),

          // Emoji rating
          Text('How are you feeling about WhisPaste?', style: ts.titleSmall),
          const SizedBox(height: WpSpacing.sm),
          _EmojiRatingRow(
            rating: _rating,
            isDark: isDark,
            onChanged: (v) => setState(() => _rating = v),
          ),

          const SizedBox(height: WpSpacing.xxl),

          // Comment field — chat-styled
          Text('Tell us more', style: ts.titleSmall),
          const SizedBox(height: WpSpacing.sm),
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? WpColorsDark.warmSurfaceGradient
                  : WpColorsLight.warmSurfaceGradient,
              borderRadius: WpRadius.borderMd,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderDefault
                    : WpColorsLight.borderDefault,
              ),
            ),
            child: TextField(
              controller: _commentController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _category == 'bug'
                    ? 'Describe what happened and what you expected…'
                    : _category == 'feature'
                        ? 'What would you like to see in WhisPaste?'
                        : _category == 'ai'
                            ? 'How was the transcription or post-processing quality?'
                            : 'Share your thoughts…',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(WpSpacing.md),
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.xl),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: AnimatedOpacity(
              duration: WpMotion.fast,
              opacity: _canSubmit ? 1.0 : 0.5,
              child: ElevatedButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: const Icon(LucideIcons.send, size: WpIconSize.sm),
                label: const Text('Send Feedback'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
                ),
              ),
            ),
          ),

          const SizedBox(height: WpSpacing.md),

          // Privacy note
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.lock,
                  size: WpIconSize.xs,
                  color: isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
                const SizedBox(width: WpSpacing.xxs),
                Text(
                  'Your feedback is anonymous and encrypted.',
                  style: ts.bodySmall?.copyWith(
                    color: isDark
                        ? WpColorsDark.textMuted
                        : WpColorsLight.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    setState(() => _submitted = true);
  }

  void _reset() {
    setState(() {
      _submitted = false;
      _rating = 0;
      _category = '';
      _commentController.clear();
    });
  }
}

// ---------------------------------------------------------------------------
// Thank-you state — shown after submission
// ---------------------------------------------------------------------------

class _ThankYouView extends StatelessWidget {
  const _ThankYouView({
    required this.isDark,
    required this.ts,
    required this.onReset,
  });

  final bool isDark;
  final TextTheme ts;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: WpSpacing.xxxl),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: isDark
                ? WpColorsDark.accentSubtle
                : WpColorsLight.accentSubtle,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            LucideIcons.heart,
            size: WpIconSize.xl,
            color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
          ),
        ),
        const SizedBox(height: WpSpacing.xl),
        Text('Thank you!', style: ts.headlineMedium),
        const SizedBox(height: WpSpacing.xs),
        Text(
          'Your feedback helps us make WhisPaste better\nfor everyone.',
          textAlign: TextAlign.center,
          style: ts.bodyMedium?.copyWith(
            color: isDark
                ? WpColorsDark.textSecondary
                : WpColorsLight.textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(LucideIcons.messagePlus, size: WpIconSize.sm),
          label: const Text('Send another'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips — selectable feedback type
// ---------------------------------------------------------------------------

class _CategoryChip extends StatefulWidget {
  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String selected;
  final bool isDark;
  final ValueChanged<String> onTap;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.value == widget.selected;

    final Color bg;
    final Color fg;

    if (isActive) {
      bg = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_hovered) {
      bg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.value),
        child: AnimatedContainer(
          duration: _hovered ? WpMotion.fast : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderFull,
            border: isActive
                ? Border.all(
                    color: (widget.isDark
                            ? WpColorsDark.accent
                            : WpColorsLight.accent)
                        .withValues(alpha: 0.3),
                  )
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: WpIconSize.sm, color: fg),
              const SizedBox(width: WpSpacing.xs),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji rating row — modern, chat-app-like rating
// ---------------------------------------------------------------------------

class _EmojiRatingRow extends StatelessWidget {
  const _EmojiRatingRow({
    required this.rating,
    required this.isDark,
    required this.onChanged,
  });

  final int rating;
  final bool isDark;
  final ValueChanged<int> onChanged;

  static const _emojis = ['😟', '😐', '🙂', '😊', '🤩'];
  static const _labels = [
    'Frustrated',
    'Meh',
    'Okay',
    'Happy',
    'Love it!',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final isSelected = rating == i + 1;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i + 1),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: WpMotion.fast,
                margin: EdgeInsets.only(
                  right: i < 4 ? WpSpacing.xs : 0,
                ),
                padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? WpColorsDark.accentSubtle
                          : WpColorsLight.accentSubtle)
                      : (isDark
                          ? WpColorsDark.surfaceVariant
                          : WpColorsLight.surfaceVariant),
                  borderRadius: WpRadius.borderMd,
                  border: isSelected
                      ? Border.all(
                          color: (isDark
                                  ? WpColorsDark.accent
                                  : WpColorsLight.accent)
                              .withValues(alpha: 0.4),
                        )
                      : Border.all(color: Colors.transparent),
                ),
                child: Column(
                  children: [
                    Text(
                      _emojis[i],
                      style: TextStyle(fontSize: isSelected ? 28 : 22),
                    ),
                    const SizedBox(height: WpSpacing.xxs),
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? (isDark
                                ? WpColorsDark.textPrimary
                                : WpColorsLight.textPrimary)
                            : (isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
