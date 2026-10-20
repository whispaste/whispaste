import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// A shell command in a muted box: monospace, selectable, always left to
/// right (also in an RTL locale). Shown wherever the app asks the user to
/// run a command, so nobody runs `sudo` blind (XP-6-04).
class WpCommandBox extends StatelessWidget {
  const WpCommandBox({
    super.key,
    required this.command,
    required this.textKey,
    this.trailing,
  });

  final String command;

  /// Stable test id of the selectable command text.
  final Key textKey;

  /// Optional action after the command, e.g. a copy button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: EdgeInsets.only(
          left: WpSpacing.md,
          right: trailing == null ? WpSpacing.md : WpSpacing.xs,
          top: WpSpacing.xs,
          bottom: WpSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: WpColors.surfaceMutedFill,
          borderRadius: WpRadius.borderSm,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                command,
                key: textKey,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: WpColors.textPrimary,
                  fontSize: WpTypography.body,
                  height: 1.5,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
