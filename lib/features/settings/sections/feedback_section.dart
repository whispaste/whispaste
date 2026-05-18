/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Keyboard Shortcut section
// ---------------------------------------------------------------------------

class KeyboardShortcutSection extends ConsumerWidget {
  const KeyboardShortcutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsKeyboardShortcut,
      subtitle: l10n.settingsKeyboardShortcutSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.toggleRight,
            label: l10n.settingsHotkeyEnabled,
            trailing: Switch(
              value: settings.hotkeyEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
            ),
          ),
          AnimatedOpacity(
            opacity: settings.hotkeyEnabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !settings.hotkeyEnabled,
              child: SettingRow(
                icon: LucideIcons.keyboard,
                label: l10n.settingsCurrentHotkey,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HotkeyDisplay(
                      hotkeyKey: settings.hotkeyKey,
                      hotkeyModifiers: settings.hotkeyModifiers,
                      hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    OutlinedButton(
                      onPressed: () async {
                        final result = await HotkeyRecorderDialog.show(
                          context,
                          initialKey: settings.hotkeyKey,
                          initialDisplayKey: settings.hotkey.hotkeyKeyDisplay,
                          initialModifiers: settings.hotkeyModifiers,
                        );
                        if (result != null) {
                          ref
                              .read(settingsProvider.notifier)
                              .updateSettings(
                                (s) => s.copyWith(
                                  hotkeyKey: result.key,
                                  hotkeyKeyDisplay: result.displayKey,
                                  hotkeyModifiers: result.modifiers,
                                ),
                              );
                        }
                      },
                      child: Text(l10n.settingsChangeHotkey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _PushToTalkRow(settings: settings),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Push-to-Talk toggle row (platform-aware)
// ---------------------------------------------------------------------------

/// Renders the Hold-to-Record (Push-to-Talk) toggle.
///
/// When the current platform does not support key-up events
/// ([HotkeyService.supportsKeyUp] is false), the toggle is disabled
/// and wrapped in a [Tooltip] explaining the limitation.
class _PushToTalkRow extends ConsumerWidget {
  const _PushToTalkRow({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly — we only need supportsKeyUp once per build
    // and do not need to rebuild on hotkey-service state changes.
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;

    final toggle = Switch(
      value: settings.pushToTalk,
      onChanged: supportsKeyUp
          ? (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(pushToTalk: v))
          : null, // null disables the switch
    );

    return SettingRow(
      icon: LucideIcons.hand,
      label: l10n.settingsHoldToRecord,
      trailing: supportsKeyUp
          ? toggle
          : Tooltip(message: l10n.pushToTalkUnavailableTooltip, child: toggle),
    );
  }
}

// ---------------------------------------------------------------------------
// Sound & Feedback section
// ---------------------------------------------------------------------------

class SoundFeedbackSection extends ConsumerWidget {
  const SoundFeedbackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsSoundFeedback,
      subtitle: l10n.settingsSoundFeedbackSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.volume2,
            label: l10n.settingsRecordStartSound,
            trailing: settingsToggle(
              value: settings.recordStartSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(recordStartSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.volumeX,
            label: l10n.settingsRecordStopSound,
            trailing: settingsToggle(
              value: settings.recordStopSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(recordStopSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.bellRing,
            label: l10n.settingsTranscriptionCompleteSound,
            trailing: settingsToggle(
              value: settings.transcriptionCompleteSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWith(transcriptionCompleteSound: v),
                  ),
            ),
          ),
          SettingRow(
            icon: LucideIcons.alarmClock,
            label: l10n.settingsDurationWarningSound,
            trailing: settingsToggle(
              value: settings.durationWarningSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(durationWarningSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.volume1,
            label: l10n.settingsSoundVolume,
            trailing: settingsSlider(
              context: context,
              value: settings.soundVolume,
              min: 0,
              max: 100,
              divisions: 20,
              valueLabel: '${settings.soundVolume.round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(soundVolume: v)),
              onChangeEnd: (v) =>
                  ref.read(soundFeedbackProvider.notifier).playVolumePreview(v),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// After Transcription section
// ---------------------------------------------------------------------------

class AfterTranscriptionSection extends ConsumerWidget {
  const AfterTranscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsAfterTranscription,
      subtitle: l10n.settingsAfterTranscriptionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.clipboardCheck,
            label: l10n.settingsAfterTranscription,
            subtitle: l10n.settingsAfterTranscriptionSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: settings.afterTranscription,
              items: AfterTranscriptionAction.values
                  .map((e) => e.value)
                  .toList(),
              labels: [
                l10n.settingsAfterTranscriptionClipboard,
                l10n.settingsAfterTranscriptionPaste,
                l10n.settingsAfterTranscriptionBoth,
                l10n.settingsAfterTranscriptionNothing,
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(afterTranscription: v));
              },
            ),
          ),
          if (settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.paste ||
              settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.clipboardAndPaste)
            SettingRow(
              icon: LucideIcons.timer,
              label: l10n.settingsAutoPasteDelay,
              subtitle: l10n.settingsAutoPasteDelaySubtitle,
              trailing: settingsSlider(
                context: context,
                value: settings.autoPasteDelay.toDouble(),
                min: 0,
                max: 2000,
                divisions: 20,
                valueLabel: fmtMs(settings.autoPasteDelay),
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(autoPasteDelay: v.round()),
                    ),
              ),
            ),
          if (settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.paste ||
              settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.clipboardAndPaste)
            _AutoPasteBlocklistField(settings: settings, ref: ref),
          if (settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.paste ||
              settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.clipboardAndPaste)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: PasteCapabilityIndicator(),
            ),
        ],
      ),
    );
  }
}

/// Text field for per-app auto-paste blocklist (comma-separated bundle IDs).
class _AutoPasteBlocklistField extends StatefulWidget {
  const _AutoPasteBlocklistField({required this.settings, required this.ref});

  final AppSettings settings;
  final WidgetRef ref;

  @override
  State<_AutoPasteBlocklistField> createState() =>
      _AutoPasteBlocklistFieldState();
}

class _AutoPasteBlocklistFieldState extends State<_AutoPasteBlocklistField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settings.autoPasteBlocklist,
    );
  }

  @override
  void didUpdateWidget(_AutoPasteBlocklistField old) {
    super.didUpdateWidget(old);
    if (old.settings.autoPasteBlocklist != widget.settings.autoPasteBlocklist) {
      _controller.text = widget.settings.autoPasteBlocklist;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      widget.ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(autoPasteBlocklist: value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingRow(
      icon: LucideIcons.shieldBan,
      label: l10n.settingsAutoPasteBlocklist,
      subtitle: l10n.settingsAutoPasteBlocklistSubtitle,
      trailing: settingsTextField(
        context: context,
        controller: _controller,
        hintText: l10n.settingsAutoPasteBlocklistPlaceholder,
        onChanged: _onChanged,
      ),
    );
  }
}
