/// Updates settings section — consolidates every update-related control in
/// one place: the automatic update check (`checkUpdates`) and the release
/// channel toggle (`beta`/`stable`).
///
/// Store builds have no self-updater and no release channel at all (PRD §6.3:
/// stores are stable-only), so the whole section hides for
/// [DeployChannel.store] — AC „Store-Build blendet den Toggle sinnvoll aus".
/// The same applies to package-manager-managed installs (Homebrew Cask,
/// Scoop) — see [isExternallyManaged].
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/stable_revert_hint_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/update_actions.dart';
import '../../../services/update_channel_service.dart';
import '../../../services/update_service.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../settings_widgets.dart';

class UpdatesSection extends ConsumerWidget {
  const UpdatesSection({super.key});

  static final _log = AppLogger('UpdatesSection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final channel = ref.watch(deployChannelProvider);

    // Store / package-managed builds: no self-updater, no release channel →
    // hide the section entirely rather than rendering an empty shell.
    if (isExternallyManaged(channel)) return const SizedBox.shrink();

    final updateChannel =
        ref.watch(updateChannelProvider).value ?? UpdateChannel.stable;
    final isBeta = updateChannel == UpdateChannel.beta;
    final revertHint = ref.watch(stableRevertHintProvider);
    final updateState = ref.watch(updateProvider);
    final (checkIcon, checkLabel) = resolveUpdateActionDisplay(
      phase: updateState.phase,
      channel: channel,
      state: updateState,
      l10n: l10n,
    );

    return WpSection(
      title: l10n.settingsUpdates,
      subtitle: l10n.settingsUpdatesSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.refreshCw,
            label: l10n.settingsCheckUpdates,
            subtitle: l10n.settingsCheckUpdatesSubtitle,
            semanticToggledValue: settings.updates.checkUpdates,
            trailing: settingsToggle(
              value: settings.updates.checkUpdates,
              onChanged: (v) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(checkUpdates: v));
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('check_updates');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
          // Manual check — routes identically to the About page and status
          // bar chip via `triggerUpdateAction` (PRD Bug 5: this used to be
          // the only surface with a working manual check).
          SettingRow(
            icon: LucideIcons.downloadCloud,
            label: l10n.settingsCheckForUpdatesNow,
            trailing: WpButton(
              label: checkLabel,
              variant: WpButtonVariant.secondary,
              icon: checkIcon,
              onPressed: updateState.isBusy
                  ? null
                  : () => triggerUpdateAction(
                      ref: ref,
                      updateState: updateState,
                      channel: channel,
                    ),
            ),
          ),
          SettingRow(
            icon: LucideIcons.flaskConical,
            label: l10n.settingsBetaUpdates,
            subtitle: l10n.settingsBetaUpdatesSubtitle,
            semanticToggledValue: isBeta,
            trailing: settingsToggle(
              value: isBeta,
              onChanged: (v) {
                ref
                    .read(updateChannelProvider.notifier)
                    .setChannel(v ? UpdateChannel.beta : UpdateChannel.stable);
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('beta_updates');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
                if (!v) {
                  // Switching back to Stable: check once whether the
                  // installed beta is ahead of the current stable-latest
                  // (PRD §7.3, AC-7) — Sparkle can't downgrade, so surface a
                  // one-time manual-download hint instead of doing nothing.
                  unawaited(
                    ref
                        .read(stableRevertHintProvider.notifier)
                        .checkAfterSwitchToStable(),
                  );
                } else {
                  ref.read(stableRevertHintProvider.notifier).dismiss();
                }
              },
            ),
          ),
          if (revertHint.visible)
            _StableRevertHintNotice(
              stableVersion: revertHint.stableVersion!,
              onDismiss: () =>
                  ref.read(stableRevertHintProvider.notifier).dismiss(),
            ),
        ],
      ),
    );
  }
}

/// One-time "beta ahead of stable" hint (PRD §7.3, AC-7) — a reuse
/// composition of the existing warning-badge visual pattern already
/// established in `insufficient_ram_screen.dart` (warning-tinted surface,
/// icon, text), token-bound throughout. No new component, no new visual
/// language.
/// The "go back to stable vX" link inside [_StableRevertHintNotice].
///
/// Was a bare [GestureDetector] under a `Semantics(link:, label:)` that
/// repeated the [Text] beneath it — pointer-only *and* announced twice. Of
/// every link in the app this is the one that must not need a working mouse:
/// it is the way out of a beta that may be misbehaving.
///
/// Same contract as every other tappable thing in the app: [InkWell] carries
/// focus and Enter/Space, [WpFocusRing] draws the focus visual through the
/// shared node, and the house `MergeSemantics` + label-less [Semantics] idiom
/// lets the rendered text be the accessible name.
class _StableRevertLink extends StatefulWidget {
  const _StableRevertLink({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_StableRevertLink> createState() => _StableRevertLinkState();
}

class _StableRevertLinkState extends State<_StableRevertLink> {
  final _focusNode = FocusNode(debugLabel: 'StableRevertLink');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // loam-ignore: a11y-interactive-semantics – name folds in from the rendered text
    return MergeSemantics(
      child: Semantics(
        link: true,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: WpRadius.borderSm,
            // WpFocusRing owns the focus visual.
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.color,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StableRevertHintNotice extends StatelessWidget {
  const _StableRevertHintNotice({
    required this.stableVersion,
    required this.onDismiss,
  });

  final String stableVersion;
  final VoidCallback onDismiss;

  Future<void> _openStableRelease() async {
    try {
      await launchUrl(
        Uri.parse('$kGitHubRepoUrl/releases/latest'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      UpdatesSection._log.warning('Could not open stable release URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warning = isDark ? WpColorsDark.warning : WpColorsLight.warning;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: WpIconSize.sm, color: warning),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsStableRevertHintMessage,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: textPrimary),
                ),
                const SizedBox(height: WpSpacing.xxs),
                _StableRevertLink(
                  label: l10n.settingsStableRevertHintLink(stableVersion),
                  color: warning,
                  onTap: () => unawaited(_openStableRelease()),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: WpIconSize.xs),
            tooltip: l10n.actionDismiss,
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: WpLayout.minTouchTarget,
              minHeight: WpLayout.minTouchTarget,
            ),
          ),
        ],
      ),
    );
  }
}
