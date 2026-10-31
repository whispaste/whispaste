import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// The title row of a page: a Bricolage page title with an optional action on
/// its trailing edge, typically the 44 px outlined "+" icon button (spec §1).
///
/// The title is a heading for assistive technology. The trailing widget is
/// the caller's; this primitive only places it and does not style it.
class WpPageHeader extends StatelessWidget {
  const WpPageHeader({super.key, required this.title, this.trailing});

  final String title;

  /// Trailing action, aligned to the title's centre line.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: WpTextStyles.pageTitle),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: WpSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}
