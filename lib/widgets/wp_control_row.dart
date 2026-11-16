/// One line of standard controls — a field with the button or dropdown that
/// acts on it (UX-131).
///
/// Every control family stands at [WpLayout.controlHeight] at normal text
/// size, so the line is flush from the first frame. What this row adds is
/// the larger text sizes: each family grows by its own metrics there (the
/// button's label line is not the field's text line), and a row that merely
/// aligns them leaves one taller than the other. Here every child is
/// stretched to the tallest one, so top and bottom edges stay shared at any
/// text scale. The gap is the same [WpSpacing.sm] on every page.
///
/// Wrap the child that takes the remaining width in `Expanded`, as in any
/// `Row`.
library;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

class WpControlRow extends StatelessWidget {
  const WpControlRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: WpSpacing.sm),
            child,
          ],
        ],
      ),
    );
  }
}
