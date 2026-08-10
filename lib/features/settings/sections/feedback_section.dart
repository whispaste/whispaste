/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/build_config.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paste_policy.dart';
import '../../../services/paste/paster.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../../snippets/snippets_page.dart' show snippetsProvider;
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
            semanticToggledValue: settings.hotkeyEnabled,
            trailing: settingsToggle(
              value: settings.hotkeyEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
            ),
          ),
          AnimatedOpacity(
            opacity: settings.hotkeyEnabled ? 1.0 : 0.4,
            duration: WpMotion.durationFor(context, WpMotion.normal),
            // ExcludeFocus alongside IgnorePointer: the dimmed row blocked the
            // mouse but stayed in the tab order, so keyboard users could focus
            // a 40%-opacity "Change hotkey" button and open the recorder for a
            // hotkey that is switched off. Blocking one input device and not
            // the other is the defect; both go together.
            child: ExcludeFocus(
              excluding: !settings.hotkeyEnabled,
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
                      WpButton(
                        label: l10n.settingsChangeHotkey,
                        variant: WpButtonVariant.secondary,
                        onPressed: () async {
                          final result = await WpHotkeyRecorderDialog.show(
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
                      ),
                    ],
                  ),
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

  static final _log = AppLogger('PushToTalkRow');

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly — we only need supportsKeyUp once per build
    // and do not need to rebuild on hotkey-service state changes.
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;

    final toggle = settingsToggle(
      value: settings.pushToTalk,
      onChanged: supportsKeyUp
          ? (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(pushToTalk: v));
              try {
                ref.read(telemetryProvider).trackSettingChange('hotkey_mode');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
            }
          : null, // null disables the switch
    );

    // Mirrors the onboarding twin in `trigger_step.dart`: the subtitle always
    // describes what pressing the hotkey does *right now*, so the toggle's
    // effect is never abstract. The two rows had drifted apart despite the
    // comment over there promising they would not — this row had neither the
    // live hint nor a state a screen reader could hear.
    final modeHint = settings.pushToTalk && supportsKeyUp
        ? l10n.onboardingTriggerModeHoldHint
        : l10n.onboardingTriggerModeToggleHint;

    return SettingRow(
      icon: LucideIcons.hand,
      label: l10n.settingsHoldToRecord,
      subtitle: modeHint,
      // Was the one toggle row in all of Settings that never announced its
      // state. Null where the platform cannot do push-to-talk, so the row
      // does not claim a state its disabled switch will not accept.
      semanticToggledValue: supportsKeyUp ? settings.pushToTalk : null,
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
            icon: LucideIcons.volume1,
            label: l10n.settingsSoundVolume,
            trailing: settingsSlider(
              context: context,
              value: settings.soundVolume,
              min: 0,
              max: 100,
              divisions: 20,
              valueLabel: settings.soundVolume == 0
                  ? l10n.settingsOff
                  : '${settings.soundVolume.round()}%',
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
  const AfterTranscriptionSection({
    super.key,
    this.autoPasteSupported = kAutoPasteSupported,
  });

  /// Overridable for tests; defaults to the real build-time flag ([kAutoPasteSupported]).
  final bool autoPasteSupported;

  static final _log = AppLogger('AfterTranscriptionSection');

  static String _labelFor(AfterTranscriptionAction action, L10n l10n) =>
      afterTranscriptionSettingsLabel(action, l10n);

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
    // Snippet-Picker trigger — macOS-only for now (Windows/Linux land with
    // the platform controllers). Without the guard the field would render on
    // every platform but setting it would silently type the trigger word into
    // the user's document as literal text.
    final trigger = settings.behavior.snippetPickerTrigger;
    final triggerIsSet = trigger.trim().isNotEmpty;
    // Conditional watch on purpose: the snippet list lives in the database,
    // and there is nothing to warn about until a trigger word exists. With no
    // trigger set — the default — opening Settings must not pull the snippet
    // table in just to decide not to show a hint.
    final showEmptyListHint =
        triggerIsSet &&
        !(ref.watch(snippetsProvider).value?.isNotEmpty ?? true);

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

    return WpSection(
      title: l10n.settingsAfterTranscription,
      subtitle: l10n.settingsAfterTranscriptionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.clipboardCheck,
            label: l10n.settingsAfterTranscriptionActionLabel,
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
            const Padding(
              // kSettingRowInset horizontally, like every other inline block
              // in Settings. This one sat at 16 and started 4 px right of the
              // rows it belongs to — the kind of drift that reads as sloppy
              // without ever being noticed as a specific mistake.
              padding: EdgeInsets.fromLTRB(
                kSettingRowInset,
                WpSpacing.sm,
                kSettingRowInset,
                WpSpacing.xs,
              ),
              child: WpPasteCapabilityIndicator(),
            ),
          if (Platform.isMacOS)
            _SnippetPickerTriggerField(
              trigger: trigger,
              ref: ref,
              showEmptyListHint: showEmptyListHint,
            ),
        ],
      ),
    );
  }
}

/// The single global trigger word that opens the Snippet-Picker when a
/// transcript matches it exactly.
///
/// Lives here rather than on the Snippets page, where it used to ride the
/// list's header slot: it is one global string, set once and then left alone,
/// and it belongs to the after-transcription pipeline — the orchestrator
/// checks it *before* the after-transcription action runs and takes over the
/// transcript on a match, so it is a branch of this section's subject, not a
/// property of any one snippet. Per the project's settings-placement rule,
/// rarely changed and centrally relevant goes to Settings; only per-object
/// state stays inline at the object. Off the list's header it also stopped
/// pushing the snippets themselves half a card down the page.
///
/// Empty string means the picker is off — the subtitle copy spells that out
/// so the off-state is legible at a glance. Debounced-commit shape shared
/// with `_AutoPasteBlocklistField`.
class _SnippetPickerTriggerField extends StatefulWidget {
  const _SnippetPickerTriggerField({
    required this.trigger,
    required this.ref,
    required this.showEmptyListHint,
  });

  final String trigger;
  final WidgetRef ref;

  /// True when a trigger word is set but the snippet list is empty — the
  /// trigger currently does nothing (dictating it falls through to a normal
  /// paste), which this row must say out loud instead of letting the user
  /// discover it mid-dictation.
  final bool showEmptyListHint;

  @override
  State<_SnippetPickerTriggerField> createState() =>
      _SnippetPickerTriggerFieldState();
}

class _SnippetPickerTriggerFieldState
    extends State<_SnippetPickerTriggerField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.trigger);
  }

  @override
  void didUpdateWidget(_SnippetPickerTriggerField old) {
    super.didUpdateWidget(old);
    // External change (e.g. settings import) — not an echo of our own commit.
    if (old.trigger != widget.trigger && widget.trigger != _controller.text) {
      _controller.text = widget.trigger;
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
      // Raw value on purpose: the dispatcher normalizes both sides via
      // `normalizeForExactMatch` (see `snippet_picker_dispatch.dart`).
      widget.ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              behavior: s.behavior.copyWith(snippetPickerTrigger: value),
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingRow(
          icon: LucideIcons.audioLines,
          label: l10n.snippetsPickerTriggerLabel,
          subtitle: l10n.snippetsPickerTriggerSubtitle,
          trailing: settingsTextField(
            context: context,
            controller: _controller,
            hintText: l10n.snippetsPickerTriggerHint,
            onChanged: _onChanged,
            semanticLabel: l10n.snippetsPickerTriggerLabel,
          ),
        ),
        if (widget.showEmptyListHint)
          Padding(
            // kSettingRowInset horizontally, like every other inline block in
            // Settings — same gutter as the rows it belongs to.
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              WpSpacing.xxs,
              kSettingRowInset,
              WpSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: WpIconSize.xs,
                  color: isDark ? WpColorsDark.warning : WpColorsLight.warning,
                ),
                const SizedBox(width: WpSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.snippetsPickerTriggerEmptyListHint,
                    style: TextStyle(
                      color: isDark
                          ? WpColorsDark.warning
                          : WpColorsLight.warning,
                      fontSize: WpTypography.small,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
