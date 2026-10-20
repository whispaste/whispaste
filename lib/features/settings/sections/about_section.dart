/// "Über WhisPaste" — the About content as the last settings area (WP-78).
///
/// What a user needs to know about the installed app lives here: the version,
/// the update check, the links, the licences and the credits. The support
/// content, the handbook and the diagnostics live on the Help page; the privacy
/// and shortcut cards were dropped because Settings already shows both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_info.dart';
import '../../../core/app_urls.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/update_actions.dart';
import '../../../services/update_service.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_text_link.dart';
import '../settings_widgets.dart' show settingsSectionBreak;
import '../widgets/wp_settings_group.dart';
import '../../../widgets/external_link.dart';

/// The update row's subtitle: why an install failed, that an install waits
/// for the dictation, or whether an update is available.
String _updateStatus(
  L10n l10n,
  UpdateState state, {
  required bool recordingBusy,
}) {
  if (state.phase == UpdatePhase.error) {
    switch (state.installFailure) {
      case InstallFailure.launchFailed:
        return l10n.updateInstallFailed;
      case InstallFailure.installerMissing:
        return l10n.updateInstallerMissing;
      case null:
        return l10n.updateError;
    }
  }
  if (state.installDeferred && recordingBusy) {
    return l10n.updateInstallAfterRecording;
  }
  return state.phase == UpdatePhase.available
      ? l10n.settingsNavUpdateAvailable
      : l10n.settingsNavUpToDate;
}

/// A URL as a reader sees it: no scheme, no trailing slash.
String _displayUrl(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ts = Theme.of(context).textTheme;
    final langCode = ref.watch(localeProvider).languageCode;
    final channel = ref.watch(deployChannelProvider);
    final updateState = ref.watch(updateProvider);
    final storeBuild = channel == DeployChannel.store;
    // Resolved up front, like `updates_section.dart` does for the same action.
    final (checkIcon, checkLabel) = resolveUpdateActionDisplay(
      phase: updateState.phase,
      channel: channel,
      state: updateState,
      l10n: l10n,
    );
    final recordingBusy = isDictationBusy(ref.watch(recordingProvider).phase);
    final updateStatus = _updateStatus(
      l10n,
      updateState,
      recordingBusy: recordingBusy,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: WpSpacing.md),
        const Center(child: WpBrandWordmark(height: 64)),
        const SizedBox(height: WpSpacing.md),
        Center(child: Text(l10n.aboutVersion(appVersion), style: ts.bodySmall)),
        const SizedBox(height: WpSpacing.xs),
        Center(
          child: Text(
            l10n.aboutTagline,
            style: ts.bodyMedium?.copyWith(color: WpColors.textSecondary),
          ),
        ),
        settingsSectionBreak,

        // Packages (Homebrew, Scoop, …) own their updates, so no check there.
        if (channel != DeployChannel.packageManaged) ...[
          WpSettingsGroup(
            heading: l10n.settingsUpdates,
            children: [
              WpSettingsRow(
                rowId: 'about-check-updates',
                title: l10n.settingsCheckForUpdatesNow,
                subtitle: storeBuild
                    ? l10n.settingsStoreUpdatesUnavailable
                    : updateStatus,
                trailing: Semantics(
                  identifier: 'settings-about-check-updates',
                  child: WpButton(
                    key: const ValueKey('settings-about-check-updates'),
                    label: checkLabel,
                    variant: WpButtonVariant.secondary,
                    icon: checkIcon,
                    // The spinner takes the icon's slot, so the button does not
                    // jump width while the check runs.
                    isLoading: updateState.isBusy,
                    onPressed: storeBuild || updateState.isBusy
                        ? null
                        : () => triggerUpdateAction(
                            ref: ref,
                            updateState: updateState,
                            channel: channel,
                          ),
                  ),
                ),
              ),
            ],
          ),
          settingsSectionBreak,
        ],

        WpSettingsGroup(
          heading: l10n.aboutLinks,
          children: [
            _LinkRow(
              rowId: 'about-whats-new',
              title: l10n.aboutWhatsNew,
              url: kChangelogUrl,
              buttonKey: 'settings-about-whats-new',
            ),
            _LinkRow(
              rowId: 'about-website',
              title: l10n.aboutWebsite,
              url: websiteHomeUrl(langCode),
              buttonKey: 'settings-about-website',
            ),
            _LinkRow(
              rowId: 'about-github-repo',
              title: l10n.aboutGitHubRepo,
              url: kGitHubRepoUrl,
              buttonKey: 'settings-about-github-repo',
            ),
            _LinkRow(
              rowId: 'about-follow-x',
              title: l10n.aboutFollowOnX,
              url: kMaintainerXUrl,
              buttonKey: 'settings-about-follow-x',
            ),
            _LinkRow(
              rowId: 'about-mit-license',
              title: l10n.aboutMitLicense,
              url: '$kGitHubRepoUrl/blob/main/LICENSE',
              buttonKey: 'settings-about-mit-license',
            ),
            WpSettingsRow(
              rowId: 'about-third-party-licenses',
              title: l10n.aboutThirdPartyLicenses,
              subtitle: l10n.aboutThirdPartyLicensesDetail,
              trailing: Semantics(
                identifier: 'settings-about-third-party-licenses',
                child: WpButton(
                  key: const ValueKey('settings-about-third-party-licenses'),
                  label: l10n.actionOpen,
                  semanticsLabel: l10n.actionOpenNamed(
                    l10n.aboutThirdPartyLicenses,
                  ),
                  variant: WpButtonVariant.secondary,
                  tone: WpButtonTone.neutral,
                  icon: LucideIcons.scrollText,
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'WhisPaste',
                    applicationVersion: appVersion,
                  ),
                ),
              ),
            ),
            _LinkRow(
              rowId: 'about-privacy-policy',
              title: l10n.aboutPrivacyPolicy,
              url: privacyPolicyUrl(langCode),
              buttonKey: 'settings-about-privacy-policy',
            ),
            _LinkRow(
              rowId: 'about-imprint',
              title: l10n.aboutImprint,
              url: imprintUrl(langCode),
              buttonKey: 'settings-about-imprint',
            ),
          ],
        ),
        settingsSectionBreak,

        WpSettingsGroup(
          heading: l10n.aboutBuiltWith,
          children: [
            _CreditBlock(
              title: l10n.aboutFlutterGo,
              description: l10n.aboutFlutterGoDesc,
            ),
            _CreditBlock(
              title: l10n.aboutWhisper,
              description: l10n.aboutWhisperDesc,
            ),
            _CreditBlock(
              title: l10n.aboutParakeet,
              description: l10n.aboutParakeetDesc,
            ),
            // NVIDIA's model is CC-BY-4.0, which requires attribution where the
            // model is credited, so both credits stay links.
            _CreditLink(
              key: const ValueKey('about-parakeet-model-link'),
              label: l10n.aboutParakeetModelCredit,
              url: 'https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3',
            ),
            _CreditLink(
              key: const ValueKey('about-parakeet-gguf-link'),
              label: l10n.aboutParakeetGgufCredit,
              url: 'https://huggingface.co/ggml-org/parakeet-GGUF',
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.lg),

        Center(
          child: Text(
            l10n.aboutMadeWith,
            style: ts.bodySmall?.copyWith(color: WpColors.textMuted),
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Center(
          child: Text(
            l10n.aboutOpenSource,
            style: ts.bodySmall?.copyWith(
              color: WpColors.textMuted,
              fontSize: WpTypography.caption,
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xl),
      ],
    );
  }
}

/// A settings row whose trailing button opens [url] in the browser. The row's
/// subtitle shows the address, so a reader sees where the button leads.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.rowId,
    required this.title,
    required this.url,
    required this.buttonKey,
  });

  final String rowId;
  final String title;
  final String url;
  final String buttonKey;

  @override
  Widget build(BuildContext context) {
    return WpSettingsRow(
      rowId: rowId,
      title: title,
      subtitle: _displayUrl(url),
      trailing: Semantics(
        identifier: buttonKey,
        child: WpButton(
          key: ValueKey(buttonKey),
          label: L10n.of(context).actionOpen,
          semanticsLabel: L10n.of(context).actionOpenNamed(title),
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.externalLink,
          onPressed: () => openExternalUrl(context, url),
        ),
      ),
    );
  }
}

/// One credited component: its name and what it does for WhisPaste.
class _CreditBlock extends StatelessWidget {
  const _CreditBlock({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ts.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(
              color: WpColors.textSecondary,
              fontSize: WpTypography.body,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A licence credit that opens its source, shown as a text link.
class _CreditLink extends StatelessWidget {
  const _CreditLink({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: WpTextLink(
          label: label,
          icon: LucideIcons.externalLink,
          onPressed: () => openExternalUrl(context, url),
        ),
      ),
    );
  }
}
