import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/theme/colors.dart';
import '../data/providers.dart';

/// Drop-in replacement for [Text] that highlights every occurrence of the
/// current [historySearchProvider] query using the design-system accent colour.
///
/// Falls back to a plain [Text] when the query is empty (zero overhead).
class HighlightedText extends ConsumerWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.style,
    required this.isDark,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final bool isDark;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(historySearchProvider).trim();

    if (query.isEmpty || text.isEmpty) {
      // Use zero-width space instead of empty string to prevent RenderParagraph null check crash
      return Text(
        text.isEmpty ? '\u200B' : text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    // Translucent tint behind each match — warmer in dark mode.
    final highlightBg = accent.withValues(alpha: isDark ? 0.28 : 0.20);
    final lower = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;
    while (start < text.length) {
      final idx = lower.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lowerQuery.length),
          style: TextStyle(
            backgroundColor: highlightBg,
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = idx + lowerQuery.length;
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
