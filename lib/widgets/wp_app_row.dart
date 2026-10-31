/// One app in an app list: its readable name, the raw identifier in small
/// secondary text, an optional leading slot and an optional trailing action.
///
/// The leading slot is for the app icon (user-research-2026-10/11). It is left
/// empty for now, so icons can be added later without touching the rows that
/// use this widget.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

class WpAppRow extends StatelessWidget {
  const WpAppRow({
    super.key,
    required this.identifier,
    required this.name,
    this.testId,
    this.leading,
    this.trailing,
    this.onTap,
  });

  /// The identifier as stored (bundle id, exe name or WM_CLASS).
  final String identifier;

  /// Readable name derived from [identifier].
  final String name;

  /// Stable id for tests and agents, e.g. `settings-paste-blocklist-row-chrome`.
  final String? testId;

  /// Reserved for the app icon. Null renders no slot.
  final Widget? leading;

  /// Trailing action, e.g. a remove button. Null renders nothing.
  final Widget? trailing;

  /// Makes the whole row a button (picker rows). Null keeps it static.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: WpSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  identifier,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: WpSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );

    final body = onTap == null
        ? content
        : InkWell(
            borderRadius: WpRadius.borderSm,
            onTap: onTap,
            child: content,
          );

    return Semantics(
      key: testId == null ? null : ValueKey<String>(testId!),
      identifier: testId,
      label: name,
      hint: identifier,
      button: onTap != null,
      child: body,
    );
  }
}
