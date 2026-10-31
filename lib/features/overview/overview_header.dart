import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/selectable_speech_models.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/audio/recovery/recording_recovery.dart';
import '../../services/hotkey_service.dart';
import '../../services/model_download_service.dart';
import '../../services/permissions/mic_permission_notifier.dart';
import '../../services/stt_parakeet/parakeet_download_service.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_keycap.dart';
import '../onboarding/steps/trigger_step.dart'
    show onboardingHoldMode, onboardingHotkeyCaps;
import '../onboarding/stt_model_readiness.dart';
import '../settings/widgets/wayland_hotkey_notice.dart';
import 'overview_navigation.dart';

/// The dictation key caps as the onboarding shows them: the single key when one
/// listens, else the stored combination.
List<({String cap, String? side})> overviewHotkeyCaps(
  WidgetRef ref,
  L10n l10n,
) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final keyName = settings.hotkey.hotkeyDoubleTapKey;
  final singleKey =
      keyName.isNotEmpty && !ref.watch(doubleTapFallbackActiveProvider);
  return onboardingHotkeyCaps(
    l10n,
    singleKey: singleKey ? keyName : '',
    key: settings.hotkeyKey,
    modifiers: settings.hotkeyModifiers,
    display: settings.hotkey.hotkeyKeyDisplay,
  );
}

/// W1: "Hallo NAME, diktiere überall mit KÜRZEL halten/drücken" in the lead
/// stage ([WpTextStyles.lead], Hanken) under the page title, with
/// the onboarding's key caps as plain labels. The name comes from the
/// onboarding "About you" step when it was set; the key caps are the same ones
/// the onboarding shows, plain labels rather than buttons, followed by how the
/// key is used.
class OverviewGreeting extends ConsumerWidget {
  const OverviewGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final name = settings.onboarding.userFirstNameSet
        ? settings.onboarding.userFirstName.trim()
        : '';
    final caps = overviewHotkeyCaps(ref, l10n);
    final text = name.isEmpty
        ? l10n.overviewGreetingAnonymous
        : l10n.overviewGreetingNamed(name);
    final mode = onboardingHoldMode(ref)
        ? l10n.overviewHotkeyModeHold
        : l10n.overviewHotkeyModeToggle;
    return Semantics(
      container: true,
      label: '$text ${caps.map((c) => c.cap).join(' ')} $mode',
      child: ExcludeSemantics(
        child: Wrap(
          key: const ValueKey('overview-greeting'),
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.xs,
          children: [
            Text(text, style: WpTextStyles.lead),
            for (final cap in caps)
              WpKeycap.large(
                label: cap.cap,
                sublabel: cap.side,
                extent: _capExtent,
              ),
            Text(
              mode,
              style: WpTextStyles.lead.copyWith(
                fontWeight: FontWeight.w500,
                color: WpColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A cap a little taller than the lead line (22 × 1.3), so the caps sit in
  /// the sentence instead of lifting the line.
  static const double _capExtent = 34;
}

/// W2: one readiness problem and exactly one action, shown only while
/// something is missing. [overviewStatusIssue] decides which one.
class OverviewStatusLine extends ConsumerWidget {
  const OverviewStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final recoverable =
        ref.watch(interruptedRecordingsProvider).value?.recordings.length ?? 0;
    final issue = ref.watch(overviewStatusIssueProvider);
    if (issue == null) return const SizedBox.shrink();
    // Each action fixes its problem where it can: the denied microphone opens
    // the system settings, a failed download starts again. Only what needs a
    // choice leads to its page.
    final (text, action, onPressed) = switch (issue) {
      OverviewStatusIssue.recoveryPending => (
        l10n.overviewStatusRecovery(recoverable),
        l10n.overviewStatusRecoveryAction,
        () => overviewOpenTarget(ref, 'history'),
      ),
      OverviewStatusIssue.modelDownloading => (
        l10n.overviewStatusModelDownloading,
        l10n.overviewStatusModelProgressAction,
        () => overviewOpenTarget(ref, 'settings:stt-model'),
      ),
      OverviewStatusIssue.modelFailed => (
        l10n.overviewStatusModelFailed,
        l10n.overviewStatusModelRetryAction,
        () => _retryDownload(ref),
      ),
      OverviewStatusIssue.modelMissing => (
        l10n.overviewStatusModelMissing,
        l10n.overviewStatusModelAction,
        () => overviewOpenTarget(ref, 'settings:stt-model'),
      ),
      OverviewStatusIssue.micDenied => (
        l10n.overviewStatusMicDenied,
        l10n.overviewStatusMicSettingsAction,
        () => ref
            .read(micPermissionNotifierProvider.notifier)
            .openSystemSettings(),
      ),
      OverviewStatusIssue.hotkeyUnbound => (
        l10n.overviewStatusHotkeyUnbound,
        l10n.overviewStatusHotkeyAction,
        () => overviewOpenTarget(ref, 'settings:general-hotkey-dictation'),
      ),
    };
    final look = wpBannerLook(WpBannerTone.warning);
    // Announced once per problem, not on every change below it: the key
    // follows the issue, so a running download does not speak each step.
    return Semantics(
      key: ValueKey('overview-status-${issue.name}'),
      liveRegion: true,
      container: true,
      child: WpBannerSurface(
        tone: WpBannerTone.warning,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(look.icon, size: WpIconSize.md, color: look.iconColor),
                const SizedBox(width: WpSpacing.sm),
                Flexible(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            WpButton(
              testId: 'overview-status-action',
              label: action,
              variant: WpButtonVariant.secondary,
              size: WpButtonSize.dense,
              onPressed: () => unawaited(Future.sync(onPressed)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retryDownload(WidgetRef ref) async {
    final model = ref.read(missingSelectedSpeechModelProvider);
    if (model == null) return;
    await downloadSpeechModel(
      model: model,
      whisper: ref.read(modelDownloadProvider.notifier),
      parakeet: ref.read(parakeetDownloadProvider.notifier),
    );
  }
}

/// What keeps dictating from working right now, or null. The status line
/// names it; the hint place asks for nothing while there is one.
final overviewStatusIssueProvider = Provider.autoDispose<OverviewStatusIssue?>((
  ref,
) {
  final recoverable =
      ref.watch(interruptedRecordingsProvider).value?.recordings.length ?? 0;
  final modelMissing = ref.watch(missingSelectedSpeechModelProvider) != null;
  final downloading = ref.watch(onboardingSttModelDownloadingProvider);
  final whisperFailed =
      ref.watch(modelDownloadProvider).phase == DownloadPhase.error;
  final parakeetFailed =
      ref.watch(parakeetDownloadProvider).phase == ParakeetDownloadPhase.error;
  final micDenied =
      ref.watch(micPermissionNotifierProvider).status ==
      MicPermissionStatus.denied;
  final hotkeyUnbound = ref.watch(waylandHotkeyNoticeReasonProvider) != null;
  return overviewStatusIssue(
    recoveryPending: recoverable > 0,
    modelMissing: modelMissing,
    modelDownloading: downloading,
    modelFailed: modelMissing && (whisperFailed || parakeetFailed),
    micDenied: micDenied,
    hotkeyUnbound: hotkeyUnbound,
  );
});
