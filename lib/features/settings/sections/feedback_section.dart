/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/build_config.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/focused_target/linux_focused_target.dart';
import '../../../services/paste/auto_paste_blocklist.dart';
import '../../../services/paste/auto_send.dart';
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
        _soundProfileRow(context, settings, l10n),
        for (final cue in SoundCue.values) _soundCueRow(settings, l10n, cue),
      ],
    );
  }

  /// One switch per cue (#1154), with an audition button. Volume 0 mutes
  /// every cue but leaves these switches usable, so the choice survives.
  Widget _soundCueRow(AppSettings settings, L10n l10n, SoundCue cue) {
    final (id, title) = switch (cue) {
      SoundCue.start => ('start', l10n.settingsSoundCueStart),
      SoundCue.stop => ('stop', l10n.settingsSoundCueStop),
      SoundCue.done => ('done', l10n.settingsSoundCueDone),
      SoundCue.warning => ('warning', l10n.settingsSoundCueWarning),
      SoundCue.error => ('error', l10n.settingsSoundCueError),
      SoundCue.paste => ('paste', l10n.settingsSoundCuePaste),
    };
    final available = soundCueAvailable(settings.sound.soundSet, cue);
    final unavailable = available ? null : l10n.settingsSoundCueUnavailable;
    final previewLabel = l10n.settingsSoundCuePreview(title);
    return WpSettingsRow(
      rowId: 'recording-sound-$id',
      title: title,
      disabledReason: unavailable,
      switchNamesRow: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'settings-sound-$id-preview',
            label: previewLabel,
            button: true,
            child: IconButton(
              key: Key('settings-sound-$id-preview'),
              icon: const Icon(LucideIcons.play, size: WpIconSize.sm),
              tooltip: previewLabel,
              onPressed: available
                  ? () => unawaited(
                      ref
                          .read(soundFeedbackProvider.notifier)
                          .playCuePreview(cue),
                    )
                  : null,
            ),
          ),
          settingsToggle(
            label: title,
            key: Key('settings-sound-$id-toggle'),
            testId: 'settings-sound-$id-toggle',
            value: available && soundCueEnabled(settings.sound, cue),
            disabledReason: unavailable,
            onChanged: available
                ? (v) => ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWithSections(
                          sound: withSoundCue(s.sound, cue, v),
                        ),
                      )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _soundProfileRow(
    BuildContext context,
    AppSettings settings,
    L10n l10n,
  ) {
    String label(SoundSet set) => switch (set) {
      SoundSet.classic => l10n.settingsSoundProfileClassic,
      _ => l10n.settingsSoundProfileBernstein,
    };
    return WpSettingsRow(
      rowId: 'recording-sound-profile',
      title: l10n.settingsSoundProfile,
      subtitle: l10n.settingsSoundProfileSubtitle,
      trailing: Semantics(
        label: l10n.settingsSoundProfile,
        child: settingsDropdown(
          context: context,
          keyPrefix: 'settings-sound-profile',
          testId: 'settings-sound-profile',
          value: selectableSoundSetOf(settings.sound.soundSet).value,
          items: [for (final e in selectableSoundSets) e.value],
          labels: [for (final e in selectableSoundSets) label(e)],
          onChanged: (v) async {
            if (v == null) return;
            final set = SoundSet.fromValue(v);
            await ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    sound: s.sound.copyWith(soundSet: set),
                  ),
                );
            // Audition the new profile; a muted sound stays silent.
            if (settings.soundVolume > 0) {
              unawaited(
                ref
                    .read(soundFeedbackProvider.notifier)
                    .playVolumePreview(settings.soundVolume),
              );
            }
          },
        ),
      ),
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
      switchNamesRow: true,
      trailing: settingsToggle(
        label: l10n.settingsPasteClipboardWithoutReceipt,
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

  /// Not in the Mac App Store build: its sandbox cannot read the target field.
  Widget _fitStartRow(WidgetRef ref, AppSettings settings, L10n l10n) {
    return WpSettingsRow(
      rowId: 'text-fit-dictation-start',
      title: l10n.settingsFitDictationStart,
      subtitle: l10n.settingsFitDictationStartSubtitle,
      switchNamesRow: true,
      trailing: settingsToggle(
        label: l10n.settingsFitDictationStart,
        key: const ValueKey('settings-fit-dictation-start'),
        testId: 'settings-fit-dictation-start',
        value: settings.behavior.fitDictationStart,
        onChanged: (v) => ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                behavior: s.behavior.copyWith(fitDictationStart: v),
              ),
            ),
      ),
    );
  }

  /// Snippets and side-panel texts lose their Markdown markers on paste
  /// unless this is on (#644). Shown in every build: MAS copies the snippet
  /// to the clipboard instead, and the same conversion applies there.
  Widget _pasteMarkdownRow(WidgetRef ref, AppSettings settings, L10n l10n) {
    return WpSettingsRow(
      rowId: 'text-paste-markdown',
      title: l10n.settingsPasteMarkdown,
      subtitle: l10n.settingsPasteMarkdownSubtitle,
      switchNamesRow: true,
      trailing: settingsToggle(
        label: l10n.settingsPasteMarkdown,
        key: const ValueKey('settings-paste-markdown'),
        testId: 'settings-paste-markdown',
        value: settings.behavior.pasteWithMarkdown,
        onChanged: (v) => ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                behavior: s.behavior.copyWith(pasteWithMarkdown: v),
              ),
            ),
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
              if (requiresPaste &&
                  defaultTargetPlatform == TargetPlatform.macOS &&
                  !alreadyReady) {
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
                  isLinux: defaultTargetPlatform == TargetPlatform.linux,
                  linuxStatus: defaultTargetPlatform == TargetPlatform.linux
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
        if (!kIsMasBuild) _fitStartRow(ref, settings, l10n),
        _pasteMarkdownRow(ref, settings, l10n),
        // Auto-paste blocklist (spec §3, moved from Erweitert).
        AutoPasteBlocklistField(settings: settings),
        _autoSendRow(context, ref, settings, l10n),
      ],
    );
  }

  /// Opt-in auto-send (#564): holding the extra key (Alt/Option) while
  /// releasing the recording shortcut presses Enter after a confirmed paste.
  Widget _autoSendRow(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    L10n l10n,
  ) {
    final conflict = autoSendConflictsWithHotkey(
      hotkeyModifiers: settings.hotkey.hotkeyModifiers,
      doubleTapKey: settings.hotkey.hotkeyDoubleTapKey,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WpSettingsRow(
          rowId: 'text-auto-send',
          title: l10n.settingsAutoSendToggle,
          subtitle: l10n.settingsAutoSendToggleSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsAutoSendToggle,
            key: const Key('text-auto-send-toggle'),
            testId: 'text-auto-send-toggle',
            value: settings.behavior.autoSendOnRelease,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    behavior: s.behavior.copyWith(autoSendOnRelease: v),
                  ),
                ),
          ),
        ),
        if (conflict && settings.behavior.autoSendOnRelease)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              0,
              kSettingRowInset,
              WpSpacing.xs,
            ),
            child: Semantics(
              identifier: 'text-auto-send-conflict',
              child: Text(
                l10n.settingsAutoSendConflict,
                key: const Key('text-auto-send-conflict'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}
