/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/build_config.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/focused_target/linux_focused_target.dart';
import '../../../services/paste/auto_paste_blocklist.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paste_policy.dart';
import '../../../services/paste/paster.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../settings_widgets.dart';
import '../widgets/auto_paste_blocklist_field.dart';
import 'linux_paste_shortcut_row.dart';
import '../widgets/wp_settings_group.dart';

// ---------------------------------------------------------------------------
// Sound & Feedback section
// ---------------------------------------------------------------------------

class SoundFeedbackSection extends ConsumerStatefulWidget {
  const SoundFeedbackSection({super.key});

  @override
  ConsumerState<SoundFeedbackSection> createState() =>
      _SoundFeedbackSectionState();
}

class _SoundFeedbackSectionState extends ConsumerState<SoundFeedbackSection> {
  /// Volume while the slider is dragged. Only the release persists it, so a
  /// drag writes the settings once instead of on every tick (UIA-SET-13).
  double? _volumeDraft;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSettingsGroup(
      heading: l10n.settingsSoundFeedback,
      children: [
        WpSettingsRow(
          rowId: 'recording-sound-volume',
          title: l10n.settingsSoundVolume,
          trailing: settingsSlider(
            context: context,
            value: _volumeDraft ?? settings.soundVolume,
            min: 0,
            max: 100,
            divisions: 20,
            valueLabel: (_volumeDraft ?? settings.soundVolume) == 0
                ? l10n.settingsOff
                : '${(_volumeDraft ?? settings.soundVolume).round()}%',
            onChanged: (v) => setState(() => _volumeDraft = v),
            onChangeEnd: (v) {
              setState(() => _volumeDraft = null);
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(soundVolume: v));
              ref.read(soundFeedbackProvider.notifier).playVolumePreview(v);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// After Transcription section
// ---------------------------------------------------------------------------

class AfterTranscriptionSection extends ConsumerWidget {
  const AfterTranscriptionSection({
    super.key,
    this.autoPasteSupported = kAutoPasteSupported,
    this.pasteFocusCheckAvailable,
  });

  /// Overridable for tests; defaults to the real build-time flag ([kAutoPasteSupported]).
  final bool autoPasteSupported;

  /// Whether WhisPaste can see the focused window, to refuse or redirect a
  /// paste after a window switch (PAR-032). Null: the Linux focus status
  /// decides (X11, or a Wayland compositor that answers). Overridable for
  /// tests.
  final bool? pasteFocusCheckAvailable;

  static final _log = AppLogger('AfterTranscriptionSection');

  static String _labelFor(AfterTranscriptionAction action, L10n l10n) =>
      afterTranscriptionSettingsLabel(action, l10n);

  /// Legacy restore after an unconfirmed paste (W-E1): only meaningful
  /// while the previous clipboard is restored at all.
  Widget _legacyRestoreRow(WidgetRef ref, AppSettings settings, L10n l10n) {
    return WpSettingsRow(
      rowId: 'text-paste-clipboard-without-receipt',
      title: l10n.settingsPasteClipboardWithoutReceipt,
      subtitle: l10n.settingsPasteClipboardWithoutReceiptSubtitle,
      trailing: settingsToggle(
        key: const ValueKey('settings-paste-clipboard-without-receipt'),
        testId: 'settings-paste-clipboard-without-receipt',
        value:
            settings.behavior.restoreClipboardAfterPaste &&
            settings.behavior.restoreClipboardWithoutReceipt,
        onChanged: settings.behavior.restoreClipboardAfterPaste
            ? (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      behavior: s.behavior.copyWith(
                        restoreClipboardWithoutReceipt: v,
                      ),
                    ),
                  )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    // Auto-paste-requiring actions don't exist as a selectable option at all
    // when the build can't perform them (MAS sandbox) — greying them out
    // with a tooltip would look like a bug to users who don't know they're
    // running a store build. The current value is routed through the same
    // resolver the recording pipeline uses, so a stale/synced "paste"
    // preference displays (and behaves) as "clipboard" instead of pointing
    // at an option that no longer exists in the list.
    final visibleActions = autoPasteSupported
        ? AfterTranscriptionAction.values
        : AfterTranscriptionAction.values
              .where(
                (a) =>
                    a != AfterTranscriptionAction.paste &&
                    a != AfterTranscriptionAction.clipboardAndPaste,
              )
              .toList();
    final resolvedAction = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
      autoPasteSupported: autoPasteSupported,
    );

    return WpSettingsGroup(
      heading: l10n.settingsAfterTranscription,
      children: [
        WpSettingsRow(
          rowId: 'text-after-dictation-action',
          title: l10n.settingsAfterTranscriptionActionLabel,
          subtitle: l10n.settingsAfterTranscriptionActionSubtitle,
          trailing: settingsDropdown(
            context: context,
            value: resolvedAction.value,
            items: visibleActions.map((e) => e.value).toList(),
            labels: visibleActions.map((e) => _labelFor(e, l10n)).toList(),
            onChanged: (v) {
              if (v == null) return;
              final newAction = AfterTranscriptionAction.values.firstWhere(
                (a) => a.value == v,
              );
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(afterTranscription: v));
              try {
                ref.read(telemetryProvider).trackSettingChange('auto_paste');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
              // The user just switched TO an Auto-Paste-requiring option —
              // request the OS permission right now instead of leaving them
              // to notice and tap the indicator's own "Grant" button below.
              // Skipped when already ready so re-selecting the same option
              // doesn't re-trigger the deep-link to System Settings.
              final requiresPaste =
                  newAction == AfterTranscriptionAction.paste ||
                  newAction == AfterTranscriptionAction.clipboardAndPaste;
              final alreadyReady =
                  ref
                      .read(pasteCapabilityNotifierProvider)
                      .capability
                      ?.status ==
                  PasteCapabilityStatus.ready;
              if (requiresPaste && Platform.isMacOS && !alreadyReady) {
                unawaited(
                  ref
                      .read(pasteCapabilityNotifierProvider.notifier)
                      .requestGrant(),
                );
              }
            },
          ),
        ),
        if (resolvedAction == AfterTranscriptionAction.paste ||
            resolvedAction == AfterTranscriptionAction.clipboardAndPaste)
          // Renders nothing while everything works; the card appears only when
          // the user has to act (see WpPasteCapabilityIndicator).
          const WpPasteCapabilityIndicator(),
        if (ref.watch(linuxPasteShortcutRowShownProvider) &&
            (resolvedAction == AfterTranscriptionAction.paste ||
                resolvedAction == AfterTranscriptionAction.clipboardAndPaste))
          LinuxPasteShortcutRow(settings: settings),
        if ((resolvedAction == AfterTranscriptionAction.paste ||
                resolvedAction == AfterTranscriptionAction.clipboardAndPaste) &&
            !(pasteFocusCheckAvailable ??
                autoPasteTargetDetectionAvailable(
                  isLinux: Platform.isLinux,
                  linuxStatus: Platform.isLinux
                      ? ref.watch(linuxFocusStatusProvider).value
                      : null,
                )))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              0,
              kSettingRowInset,
              WpSpacing.xs,
            ),
            child: Semantics(
              identifier: 'text-paste-wayland-focus-hint',
              child: Text(
                l10n.settingsPasteWaylandFocusHint,
                key: const Key('text-paste-wayland-focus-hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        WpSettingsRow(
          rowId: 'text-paste-clipboard-after',
          title: l10n.settingsPasteClipboardAfter,
          subtitle: l10n.settingsPasteClipboardAfterSubtitle,
          trailing: Semantics(
            identifier: 'settings-paste-clipboard-after',
            child: settingsDropdown(
              context: context,
              keyPrefix: 'settings-paste-clipboard-after',
              value: settings.behavior.restoreClipboardAfterPaste
                  ? 'restore'
                  : 'keep',
              items: const <String>['restore', 'keep'],
              labels: <String>[
                l10n.settingsPasteClipboardAfterRestore,
                l10n.settingsPasteClipboardAfterKeep,
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        behavior: s.behavior.copyWith(
                          restoreClipboardAfterPaste: v == 'restore',
                        ),
                      ),
                    );
              },
            ),
          ),
        ),
        _legacyRestoreRow(ref, settings, l10n),
        // Auto-paste blocklist (spec §3, moved from Erweitert).
        AutoPasteBlocklistField(settings: settings),
      ],
    );
  }
}
