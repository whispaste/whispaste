/// Keyboard shortcuts settings area (maintainer decision 19a/20a, 2026-10-19):
/// every global hotkey lives here, the dictation hotkey first. The Smart Mode
/// section links here instead of hosting the Smart Mode and selection-edit
/// hotkeys itself.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/smart_mode/smart_mode_presets.dart';
import '../../../services/smart_mode/smart_mode_text_model.dart';
import '../../../services/snippet_picker/snippet_picker_controller.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/hotkey_fallback_toast.dart' show hotkeyFallbackMessage;
import '../hotkey_flow.dart';
import '../language_cycle_hotkey_flow.dart';
import '../quick_note_hotkey_flow.dart';
import '../selection_edit_hotkey_flow.dart';
import '../settings_widgets.dart';
import '../snippet_picker_trigger_row.dart';
import '../smart_mode_hotkey_flow.dart';
import '../snippet_picker_hotkey_flow.dart';
import '../widgets/wayland_hotkey_notice.dart';
import '../widgets/wp_settings_group.dart';
import 'linux_desktop_shortcut_block.dart';
import 'smart_mode_section.dart' show smartModeTargetLanguageLabel;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

// ---------------------------------------------------------------------------
// Keyboard Shortcut section
// ---------------------------------------------------------------------------

class KeyboardShortcutSection extends ConsumerStatefulWidget {
  const KeyboardShortcutSection({super.key});

  @override
  ConsumerState<KeyboardShortcutSection> createState() =>
      _KeyboardShortcutSectionState();
}

class _KeyboardShortcutSectionState
    extends ConsumerState<KeyboardShortcutSection>
    with HotkeyCollisionNotice {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // While another app holds the configured combination, the safe default
    // listens instead; show that one, not the one that does nothing.
    final fallback =
        settings.hotkeyEnabled && ref.watch(globalHotkeyFallbackActiveProvider);
    final active = activeGlobalHotkey(settings, fallback: fallback);
    final intro = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: WpColors.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The only place that says the hotkeys are system-wide.
        Text(l10n.shortcutsAreaIntro, style: intro),
        settingsSectionBreak,
        WpSettingsGroup(
          heading: l10n.shortcutsGroupDictate,
          children: [
            _hotkeyBlock(
              key: const ValueKey('shortcutBlock-dictation'),
              children: [
                WpSettingsRow(
                  rowId: 'general-hotkey-dictation',
                  title: l10n.settingsHotkeyEnabled,
                  subtitle: l10n.settingsHotkeyEnabledSubtitle,
                  semanticToggledValue: settings.hotkeyEnabled,
                  trailing: settingsToggle(
                    value: settings.hotkeyEnabled,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
                  ),
                ),
                settingsDimmedWhen(
                  context,
                  enabled: settings.hotkeyEnabled,
                  child: SettingsRowFrame(
                    rowId: 'general-hotkey-combo',
                    child: HotkeyComboLine(
                      label: l10n.settingsCurrentHotkey,
                      hotkeyKey: active.key,
                      hotkeyModifiers: active.modifiers,
                      hotkeyKeyDisplay: active.display,
                      padding: _comboPadding,
                      changeButtonKey: const Key('mainHotkeyChange'),
                      // Same route as every other hotkey: a combination that
                      // another WhisPaste hotkey holds is refused and reported.
                      onChange: () => recordAndReport(
                        () => recordDictationHotkey(
                          context: context,
                          ref: ref,
                          settings: settings,
                        ),
                      ),
                    ),
                  ),
                ),
                if (collidingAction != null)
                  HotkeyNotice(
                    noticeKey: const Key('mainHotkeyCollisionNotice'),
                    icon: LucideIcons.circleAlert,
                    color: WpColors.error,
                    text: l10n.settingsDictationHotkeyCollision(
                      collidingAction!,
                    ),
                  ),
                if (fallback)
                  HotkeyNotice(
                    noticeKey: const Key('mainHotkeyFallbackNotice'),
                    icon: LucideIcons.triangleAlert,
                    color: WpColors.warning,
                    text: hotkeyFallbackMessage(settings, l10n),
                  ),
                // Linux Wayland: registered, but the desktop has not bound it
                // (XP-2-06). Says why, with reconnect and the command.
                const WaylandHotkeyNotice(idPrefix: 'settings'),
                // Linux Wayland without the GlobalShortcuts portal: the
                // hotkey goes through the desktop's own shortcuts.
                LinuxDesktopShortcutBlock(settings: settings),
              ],
            ),
            // Modes of the recording hotkey: they also apply to Smart Mode.
            _PushToTalkRow(settings: settings),
            _HoldOrTapRow(settings: settings),
            _LanguageCycleHotkeyBlock(settings: settings),
          ],
        ),
        settingsSectionBreak,
        WpSettingsGroup(
          heading: l10n.shortcutsGroupNotes,
          children: [
            _QuickNoteHotkeyBlock(settings: settings),
            _SnippetPickerHotkeyBlock(settings: settings),
            // The spoken word opens the same picker as the hotkey, so it sits
            // under it. Without a native picker there is nothing to set.
            if (ref.watch(snippetPickerAvailabilityProvider))
              SnippetPickerTriggerRow(
                trigger: settings.behavior.snippetPickerTrigger,
              ),
          ],
        ),
        settingsSectionBreak,
        WpSettingsGroup(
          heading: l10n.shortcutsGroupSmartMode,
          children: [
            SmartModeHotkeyBlock(settings: settings),
            SelectionEditHotkeyBlock(settings: settings),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared layout of every hotkey block (UIA-KBD-02)
//
// One block = one row of a purpose card: the action name with its switch,
// the combination line directly below it, the notices under that, and the
// dependent options indented last. Only the switch and the combination are
// dimmed when the hotkey is off; notices stay readable.
// ---------------------------------------------------------------------------

/// Combination line aligned with the action name above it.
const EdgeInsetsDirectional _comboPadding = EdgeInsetsDirectional.fromSTEB(
  0,
  0,
  0,
  WpSpacing.xs,
);

Widget _hotkeyBlock({required Key key, required List<Widget> children}) {
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

// ---------------------------------------------------------------------------
// Quick-note hotkey block
// ---------------------------------------------------------------------------

/// Quick-note hotkey: appends dictated text to the note marked as quick note.
/// "Next favorite language" hotkey, in the Dictation card. Switches the
/// recognition language through the favorites; off by default.
class _LanguageCycleHotkeyBlock extends ConsumerStatefulWidget {
  const _LanguageCycleHotkeyBlock({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_LanguageCycleHotkeyBlock> createState() =>
      _LanguageCycleHotkeyBlockState();
}

class _LanguageCycleHotkeyBlockState
    extends ConsumerState<_LanguageCycleHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordLanguageCycleHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final stt = widget.settings.stt;
    final enabled = stt.languageCycleHotkeyEnabled;

    // `enabled &&`: the registration status is in-memory; a switched-off
    // hotkey must not keep reporting "not active".
    final registrationFailed =
        enabled &&
        ref.watch(languageCycleHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;
    // Wayland gives no global key grab to other apps; say so instead of
    // letting the switch promise a system-wide shortcut.
    final waylandSession =
        Platform.isLinux &&
        Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-languageCycle'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-language-cycle',
          title: l10n.settingsLanguageCycleHotkeyEnabled,
          subtitle: l10n.settingsLanguageCycleHotkeyHint,
          semanticToggledValue: enabled,
          trailing: settingsToggle(
            key: const Key('languageCycleHotkeyToggle'),
            value: enabled,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setLanguageCycleHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: HotkeyComboLine(
            key: const Key('languageCycleHotkeyComboLine'),
            label: l10n.settingsCurrentHotkey,
            hotkeyKey: stt.languageCycleHotkeyKey,
            hotkeyModifiers: stt.languageCycleHotkeyModifiers,
            hotkeyKeyDisplay: stt.languageCycleHotkeyKeyDisplay,
            padding: _comboPadding,
            changeButtonKey: const Key('languageCycleHotkeyChange'),
            onChange: () => unawaited(_record()),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('languageCycleHotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsLanguageCycleHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: const Key('languageCycleHotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsLanguageCycleHotkeyInactive,
          ),
        if (enabled && waylandSession)
          HotkeyNotice(
            noticeKey: const Key('languageCycleHotkeyWaylandNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsLanguageCycleHotkeyWaylandNotice,
          ),
      ],
    );
  }
}

class _QuickNoteHotkeyBlock extends ConsumerStatefulWidget {
  const _QuickNoteHotkeyBlock({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_QuickNoteHotkeyBlock> createState() =>
      _QuickNoteHotkeyBlockState();
}

class _QuickNoteHotkeyBlockState extends ConsumerState<_QuickNoteHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordQuickNoteHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = widget.settings;
    final quickNote = settings.quickNoteHotkey;
    final enabled = quickNote.quickNoteHotkeyEnabled;

    // `enabled &&`: the registration status is in-memory and only registration
    // attempts write it, so a hotkey the user just switched off must not keep
    // reporting "not active".
    final registrationFailed =
        enabled &&
        ref.watch(quickNoteHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-quickNote'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-quick-note',
          title: l10n.settingsQuickNoteHotkeyEnabled,
          subtitle: l10n.settingsQuickNoteHotkeyHint,
          semanticToggledValue: enabled,
          trailing: settingsToggle(
            key: const Key('quickNoteHotkeyToggle'),
            value: enabled,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setQuickNoteHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: HotkeyComboLine(
            key: const Key('quickNoteHotkeyComboLine'),
            label: l10n.settingsCurrentHotkey,
            hotkeyKey: quickNote.quickNoteHotkeyKey,
            hotkeyModifiers: quickNote.quickNoteHotkeyModifiers,
            hotkeyKeyDisplay: quickNote.quickNoteHotkeyKeyDisplay,
            padding: _comboPadding,
            changeButtonKey: const Key('quickNoteHotkeyChange'),
            onChange: () => unawaited(_record()),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('quickNoteHotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsQuickNoteHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: const Key('quickNoteHotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            // No replacement combination is suggested: there is none.
            text: l10n.settingsQuickNoteHotkeyInactive,
          ),
        // Where a finished quick note goes. Independent of the switch above.
        WpSettingsRow(
          rowId: 'general-quick-note-open-main-window',
          title: l10n.settingsQuickNoteOpenInMainWindow,
          subtitle: l10n.settingsQuickNoteOpenInMainWindowHint,
          semanticToggledValue: quickNote.openNoteInMainWindow,
          indent: true,
          trailing: settingsToggle(
            key: const Key('quickNoteOpenInMainWindowToggle'),
            value: quickNote.openNoteInMainWindow,
            onChanged: (v) => unawaited(
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      quickNoteHotkey: s.quickNoteHotkey.copyWith(
                        openNoteInMainWindow: v,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Snippet-picker hotkey block
// ---------------------------------------------------------------------------

/// Snippet-picker hotkey: opens the picker directly, without a recording.
///
/// Where the platform has no native picker, the block is one row that says so
/// instead of a switch that could not open anything.
class _SnippetPickerHotkeyBlock extends ConsumerStatefulWidget {
  const _SnippetPickerHotkeyBlock({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_SnippetPickerHotkeyBlock> createState() =>
      _SnippetPickerHotkeyBlockState();
}

class _SnippetPickerHotkeyBlockState
    extends ConsumerState<_SnippetPickerHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordSnippetPickerHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final snippetPicker = widget.settings.snippetPickerHotkey;
    final available = ref.watch(snippetPickerAvailabilityProvider);
    final enabled = snippetPicker.snippetPickerHotkeyEnabled;

    // `enabled &&`: see the quick-note block.
    final registrationFailed =
        enabled &&
        ref.watch(snippetPickerHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;

    if (!available) {
      return _hotkeyBlock(
        key: const ValueKey('shortcutBlock-snippetPicker'),
        children: [
          WpSettingsRow(
            rowId: 'general-hotkey-snippet-picker',
            title: l10n.settingsSnippetPickerHotkeyEnabled,
            key: const Key('snippetPickerHotkeyUnavailable'),
            // Same sentence as on the Snippets page: one fact, one wording.
            subtitle: l10n.snippetsPickerUnavailable,
            trailing: const SizedBox.shrink(),
          ),
        ],
      );
    }

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-snippetPicker'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-snippet-picker',
          title: l10n.settingsSnippetPickerHotkeyEnabled,
          subtitle: l10n.settingsSnippetPickerHotkeyHint,
          semanticToggledValue: enabled,
          trailing: settingsToggle(
            key: const Key('snippetPickerHotkeyToggle'),
            value: enabled,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSnippetPickerHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: HotkeyComboLine(
            key: const Key('snippetPickerHotkeyComboLine'),
            label: l10n.settingsCurrentHotkey,
            hotkeyKey: snippetPicker.snippetPickerHotkeyKey,
            hotkeyModifiers: snippetPicker.snippetPickerHotkeyModifiers,
            hotkeyKeyDisplay: snippetPicker.snippetPickerHotkeyKeyDisplay,
            padding: _comboPadding,
            changeButtonKey: const Key('snippetPickerHotkeyChange'),
            onChange: () => unawaited(_record()),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('snippetPickerHotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsSnippetPickerHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: const Key('snippetPickerHotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsSnippetPickerHotkeyInactive,
          ),
      ],
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
    final hotkeyService = ref.read(hotkeyServiceProvider.notifier);
    final supportsKeyUp = hotkeyService.supportsKeyUp;

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

    // Same subtitle as the onboarding twin in `trigger_step.dart`, from one
    // helper so the two rows cannot drift apart again (UIA-XP-7-12). Without
    // key-up the reason is part of the visible subtitle, not a hover-only
    // tooltip (UIA-SET-05, same as UIA-ONB-06).
    final modeHint = holdToRecordSubtitle(
      l10n,
      supportsKeyUp: supportsKeyUp,
      operatingSystem: defaultTargetPlatform == TargetPlatform.linux
          ? 'linux'
          : 'other',
    );

    return WpSettingsRow(
      rowId: 'general-hold-to-record',
      title: l10n.settingsHoldToRecord,
      subtitle: modeHint,
      // Linux key-up (handy-catchup/09) is not verified on a real GNOME/KDE
      // desktop yet — say so right at the option instead of hiding it.
      badge: hotkeyService.keyUpExperimental
          ? l10n.settingsExperimentalBadge
          : null,
      badgeKey: const Key('settings-push-to-talk-experimental-badge'),
      // Was the one toggle row in all of Settings that never announced its
      // state. Null where the platform cannot do push-to-talk, so the row
      // does not claim a state its disabled switch will not accept.
      semanticToggledValue: supportsKeyUp ? settings.pushToTalk : null,
      // A disabled Switch still contributes its own hasEnabledState/
      // hasToggledState/isToggled semantics regardless of this row's
      // `semanticToggledValue: null` above — Semantics(toggled: null)
      // only omits the row's *own* contribution, it does not stop a
      // descendant's flags from merging into the same node. Exclude
      // them here so the row (correctly) claims no state at all.
      trailing: supportsKeyUp ? toggle : ExcludeSemantics(child: toggle),
    );
  }
}

// ---------------------------------------------------------------------------
// Hold-or-tap sub-option of push-to-talk (ticket handy-catchup/07)
// ---------------------------------------------------------------------------

/// Hybrid hotkey mode: with push-to-talk on, a short tap toggles and a longer
/// hold records until release (threshold:
/// `RecordingTriggerHandler.holdOrTapThreshold`).
///
/// Indented under [_PushToTalkRow] because it only refines that mode — the
/// same dependent-option idiom as the quick-note block. Disabled while
/// push-to-talk is off, and on platforms without key-up (Linux) disabled with
/// the same "not available" hint as its parent row; dimmed in both cases.
class _HoldOrTapRow extends ConsumerWidget {
  const _HoldOrTapRow({required this.settings});

  static final _log = AppLogger('HoldOrTapRow');

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;
    final audio = settings.audioInput;
    final enabled = supportsKeyUp && audio.pushToTalk;

    final toggle = settingsToggle(
      key: const Key('holdOrTapToggle'),
      value: audio.holdOrTap,
      onChanged: enabled
          ? (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      audioInput: s.audioInput.copyWith(holdOrTap: v),
                    ),
                  );
              try {
                ref.read(telemetryProvider).trackSettingChange('hotkey_mode');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
            }
          : null,
    );

    // Dimmed like every other dependent option whose parent is off, so a
    // disabled switch never passes for an ordinary "off".
    return settingsDimmedWhen(
      context,
      enabled: enabled,
      child: WpSettingsRow(
        rowId: 'general-hold-or-tap',
        indent: true,
        title: l10n.settingsHoldOrTap,
        subtitle: supportsKeyUp
            ? l10n.settingsHoldOrTapHint
            : '${l10n.settingsHoldOrTapHint}\n'
                  '${pushToTalkUnavailableMessage(l10n)}',
        semanticToggledValue: enabled ? audio.holdOrTap : null,
        // Same reasoning as in _PushToTalkRow: a disabled Switch would
        // otherwise merge its own toggled-state flags into the row.
        trailing: supportsKeyUp ? toggle : ExcludeSemantics(child: toggle),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Smart-Mode hotkey (ticket 04) — fourth, independently configurable hotkey,
// bound to one of the three presets, applied regardless of the standard
// preset above.
// ---------------------------------------------------------------------------

class SmartModeHotkeyBlock extends ConsumerStatefulWidget {
  const SmartModeHotkeyBlock({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<SmartModeHotkeyBlock> createState() =>
      _SmartModeHotkeyBlockState();
}

class _SmartModeHotkeyBlockState extends ConsumerState<SmartModeHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordSmartModeHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final smartModeHotkey = widget.settings.smartModeHotkey;
    final enabled = smartModeHotkey.smartModeHotkeyEnabled;

    // `enabled &&`: see the quick-note block.
    final registrationFailed =
        enabled &&
        ref.watch(smartModeHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;
    // Without a usable text model the hotkey's presets cannot be picked either
    // (UIA-XP-7-05).
    final presetLockedReason = smartModeUnavailableReason(
      ref.watch(smartModeTextModelStatusProvider),
      l10n,
    );

    String presetLabel(String preset) => switch (preset) {
      'concise' => l10n.smartModePresetConcise,
      'translate' => l10n.smartModePresetTranslate,
      _ => l10n.smartModePresetCleanup,
    };

    String presetDescription(String preset) => switch (preset) {
      'concise' => l10n.smartModePresetConciseDescription,
      'translate' => l10n.smartModePresetTranslateDescription,
      _ => l10n.smartModePresetCleanupDescription,
    };

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-smartMode'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-smart-mode',
          title: l10n.settingsSmartModeHotkeyEnabled,
          subtitle: l10n.settingsSmartModeHotkeyHint,
          semanticToggledValue: enabled,
          trailing: settingsToggle(
            key: const Key('smartModeHotkeyToggle'),
            value: enabled,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSmartModeHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: SettingsRowFrame(
            rowId: 'general-hotkey-smart-mode-combination',
            child: HotkeyComboLine(
              key: const Key('smartModeHotkeyComboLine'),
              label: l10n.settingsCurrentHotkey,
              hotkeyKey: smartModeHotkey.smartModeHotkeyKey,
              hotkeyModifiers: smartModeHotkey.smartModeHotkeyModifiers,
              hotkeyKeyDisplay: smartModeHotkey.smartModeHotkeyKeyDisplay,
              padding: _comboPadding,
              changeButtonKey: const Key('smartModeHotkeyChange'),
              onChange: () => unawaited(_record()),
            ),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('smartModeHotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsSmartModeHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: const Key('smartModeHotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsSmartModeHotkeyInactive,
          ),
        // Dependent options of this hotkey, indented below it.
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WpSettingsRow(
                rowId: 'general-hotkey-smart-mode-preset',
                title: l10n.settingsSmartModeHotkeyPreset,
                subtitle: presetDescription(
                  smartModeHotkey.smartModeHotkeyPreset,
                ),
                indent: true,
                trailing: settingsDropdown(
                  context: context,
                  value: smartModeHotkey.smartModeHotkeyPreset,
                  items: const ['cleanup', 'concise', 'translate'],
                  labels: const [
                    'cleanup',
                    'concise',
                    'translate',
                  ].map(presetLabel).toList(),
                  disabledItems: presetLockedReason == null
                      ? null
                      : const {'cleanup', 'concise', 'translate'},
                  disabledTooltip: presetLockedReason,
                  onChanged: (v) {
                    if (v == null) return;
                    unawaited(setSmartModeHotkeyPreset(ref, preset: v));
                  },
                ),
              ),
              if (smartModeHotkey.smartModeHotkeyPreset == 'translate')
                WpSettingsRow(
                  rowId: 'general-hotkey-smart-mode-target',
                  title: l10n.smartModeTargetLanguage,
                  indent: true,
                  trailing: settingsDropdown(
                    context: context,
                    value: smartModeTargetLanguageFromSettingsValue(
                      smartModeHotkey.smartModeHotkeyTargetLanguage,
                    ).code,
                    items: smartModeValidatedTargetLanguages
                        .map((lang) => lang.code)
                        .toList(),
                    labels: smartModeValidatedTargetLanguages
                        .map(smartModeTargetLanguageLabel(l10n))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      unawaited(
                        setSmartModeHotkeyTargetLanguage(
                          ref,
                          targetLanguage: v,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit-selection hotkey (`.scratch/voice-selection-edit/`) — select text in
// any app, press, speak an instruction; the Smart Mode engine configured in
// the Smart Mode area rewrites the selection. It only works once that engine
// is set up.
// ---------------------------------------------------------------------------

class SelectionEditHotkeyBlock extends ConsumerStatefulWidget {
  const SelectionEditHotkeyBlock({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<SelectionEditHotkeyBlock> createState() =>
      _SelectionEditHotkeyBlockState();
}

class _SelectionEditHotkeyBlockState
    extends ConsumerState<SelectionEditHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordSelectionEditHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final hotkey = widget.settings.selectionEditHotkey;
    final enabled = hotkey.selectionEditHotkeyEnabled;

    // `enabled &&`: see the quick-note block.
    final registrationFailed =
        enabled &&
        ref.watch(selectionEditHotkeyRegistrationStatusProvider) ==
            HotkeyRegistrationStatus.conflict;

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-selectionEdit'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-selection-edit',
          title: l10n.settingsSelectionEditHotkeyEnabled,
          subtitle: l10n.settingsSelectionEditHotkeyHint,
          semanticToggledValue: enabled,
          trailing: settingsToggle(
            key: const Key('selectionEditHotkeyToggle'),
            value: enabled,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSelectionEditHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsDimmedWhen(
          context,
          enabled: enabled,
          child: HotkeyComboLine(
            key: const Key('selectionEditHotkeyComboLine'),
            label: l10n.settingsCurrentHotkey,
            hotkeyKey: hotkey.selectionEditHotkeyKey,
            hotkeyModifiers: hotkey.selectionEditHotkeyModifiers,
            hotkeyKeyDisplay: hotkey.selectionEditHotkeyKeyDisplay,
            padding: _comboPadding,
            changeButtonKey: const Key('selectionEditHotkeyChange'),
            onChange: () => unawaited(_record()),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('selectionEditHotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsSmartModeHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: const Key('selectionEditHotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsSelectionEditHotkeyInactive,
          ),
      ],
    );
  }
}
