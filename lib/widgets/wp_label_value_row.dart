import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// A label with its value at the end of the same line, the form of a figure
/// row inside a card. When both do not fit side by side (large text scale),
/// the value moves under the label instead of overflowing or squeezing the
/// label. Place it where the width is tight (a card body), so the value sits
/// at the end of the line.
class WpLabelValueRow extends StatelessWidget {
  const WpLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;

  /// Accessibility and test handle of the value text.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.md,
      runSpacing: WpSpacing.xxs,
      children: [
        Text(label, style: WpTextStyles.rowTitle),
        Text(value, key: valueKey, style: WpTextStyles.rowNote),
      ],
    );
  }
}
