/// One permission in a list of them: what it is, why WhisPaste asks, where it
/// stands, and the one action that changes it.
///
/// The row carries no logic of its own. The caller decides the status (from
/// `permissionsOverviewProvider`) and the action; the row only renders the
/// three states (granted, missing, pending) and exposes stable test ids:
/// `permissions-row-<id>` for the row and `permissions-row-<id>-action` for its
/// button. Granted rows show a check instead of a button.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/permissions/permissions_overview_provider.dart';
import 'wp_button.dart';

/// Edge of the status badge, the same 32 px square the Auto-Paste status card
/// uses, so the rows and the card above them read as one surface.
const double _kBadgeSize = 32;

class WpPermissionRow extends StatelessWidget {
  const WpPermissionRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.purpose,
    required this.status,
    required this.optional,
    this.actionLabel,
    this.onAction,
    this.actionLoading = false,
    super.key,
  });

  /// Stable kebab-case id, e.g. `microphone` or `auto-paste`.
  final String id;
  final IconData icon;
  final String title;

  /// One sentence on what the permission is for.
  final String purpose;
  final PermissionOverviewStatus status;
  final bool optional;

  /// Label of the trailing button. `null` hides the button (granted rows).
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final granted = status == PermissionOverviewStatus.granted;

    final (
      IconData statusIcon,
      Color statusColor,
      Color tint,
    ) = switch (status) {
      PermissionOverviewStatus.granted => (
        LucideIcons.circleCheck,
        WpColors.accent,
        WpColors.accentActiveFill,
      ),
      PermissionOverviewStatus.missing => (
        LucideIcons.shieldAlert,
        WpColors.warning,
        WpColors.warningActiveFill,
      ),
      PermissionOverviewStatus.pending => (
        LucideIcons.loaderCircle,
        WpColors.textSecondary,
        WpColors.mutedActiveFill,
      ),
    };

    return Container(
      key: ValueKey('permissions-row-$id'),
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WpColors.floatingSurface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: _kBadgeSize,
            height: _kBadgeSize,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: WpRadius.borderSm,
            ),
            child: Icon(icon, size: WpIconSize.md, color: statusColor),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap, not Row: at 1.3x text scale the title and the
                // "Optional" tag must wrap onto a second line rather than
                // truncate the title.
                Wrap(
                  spacing: WpSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: FontWeight.w600,
                        color: WpColors.textPrimary,
                      ),
                    ),
                    if (optional)
                      Text(
                        l10n.permissionRowOptional,
                        style: TextStyle(
                          fontSize: WpTypography.caption,
                          color: WpColors.textMuted,
                        ),
                      ),
                  ],
                ),
                // A granted permission no longer needs its "why": the row shrinks
                // to its title, which keeps the page inside the fixed window.
                if (!granted) ...[
                  const SizedBox(height: WpSpacing.xxs),
                  Text(
                    purpose,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      height: 1.4,
                      color: WpColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          if (granted)
            Semantics(
              label: l10n.permissionRowGranted,
              child: Icon(
                LucideIcons.check,
                size: WpIconSize.md,
                color: WpColors.accent,
              ),
            )
          else if (actionLabel != null)
            WpButton(
              key: ValueKey('permissions-row-$id-action'),
              label: actionLabel!,
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.neutral,
              isLoading: actionLoading,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}
