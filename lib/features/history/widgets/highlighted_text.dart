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
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
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

    const accent = WpColors.accent;
    // Translucent tint behind each match — warmer in dark mode.
    final highlightBg = accent.withValues(alpha: 0.28);

    // Performance: Avoid allocating a lowercased copy of the entire text
    // on every build. Precompile a case-insensitive RegExp instead.
    final regex = RegExp(RegExp.escape(query), caseSensitive: false);
    final spans = <TextSpan>[];
    int start = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: highlightBg,
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
