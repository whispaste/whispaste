/// Keyboard shortcuts settings area (maintainer decision 19a/20a, 2026-10-19):
/// every global hotkey lives here, the dictation hotkey first. The Smart Mode
/// section links here instead of hosting the Smart Mode and selection-edit
/// hotkeys itself.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/favorite_language_hotkeys.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/app_profiles/profile_hotkey_sync.dart'
    show favoriteLanguageHotkeyRefusalsProvider;
import '../../../services/hotkey_service.dart';
import '../../../services/smart_mode/smart_mode_presets.dart';
import '../../../services/smart_mode/smart_mode_text_model.dart';
import '../../../services/snippet_picker/snippet_picker_controller.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/tray_language_menu.dart' show languageMenuName;
import '../../../widgets/hotkey_fallback_toast.dart' show hotkeyFallbackMessage;
import '../../../widgets/hotkey_slow_tap_hint.dart';
import '../../../widgets/wp_button.dart';
import '../hotkey_flow.dart';
import '../one_shot_hotkey_flow.dart';
import '../quick_note_hotkey_flow.dart';
import '../selection_edit_hotkey_flow.dart';
import '../settings_widgets.dart';
import '../snippet_picker_trigger_row.dart';
import '../smart_mode_hotkey_flow.dart';
import '../snippet_picker_hotkey_flow.dart';
import '../widgets/wayland_hotkey_notice.dart';
import '../widgets/wp_settings_group.dart';
import 'dictation_keys_block.dart';
import 'linux_desktop_shortcut_block.dart';
import 'smart_mode_section.dart'
    show
        SmartModeLockedNotice,
        smartModeLockedNoticeShown,
        smartModeTargetLanguageLabel;

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
  /// "Change" on the dictation trigger: one recorder for a combination or a
  /// single key. A combination goes through the usual collision check.
  Future<void> _changeDictationTrigger(AppSettings settings) => recordAndReport(
    () => recordDictationHotkey(context: context, ref: ref, settings: settings),
  );

  /// The dictation trigger while it is one single key.
  Widget _singleKeyTriggerLine(
    L10n l10n,
    String keyName,
    AppSettings settings,
  ) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: _comboPadding,
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.settingsCurrentHotkey,
            style: tt.bodySmall?.copyWith(color: WpColors.textMuted),
          ),
          Text(
            modifierOnlyLabel(l10n, keyName),
            key: const Key('mainHotkeyDoubleTapValue'),
          ),
          WpButton(
            key: const Key('mainHotkeyChange'),
            testId: 'settings-hotkey-main-change',
            label: l10n.settingsChangeHotkey,
            variant: WpButtonVariant.secondary,
            onPressed: () => unawaited(_changeDictationTrigger(settings)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // While another app holds the configured combination, the safe default
    // listens instead; show that one, not the one that does nothing.
    final fallback =
        settings.hotkeyEnabled && ref.watch(globalHotkeyFallbackActiveProvider);
    final active = activeGlobalHotkey(settings, fallback: fallback);
    // The saved double tap is not observable here: the combination listens.
    final doubleTapFallback =
        settings.hotkey.hotkeyDoubleTapKey.isNotEmpty &&
        ref.watch(doubleTapFallbackActiveProvider);
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
                  switchNamesRow: true,
                  trailing: settingsToggle(
                    label: l10n.settingsHotkeyEnabled,
                    value: settings.hotkeyEnabled,
                    showOffState: true,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
                  ),
                ),
                settingsSwitchedOffWhen(
                  context,
                  enabled: settings.hotkeyEnabled,
                  collapse: true,
                  child: SettingsRowFrame(
                    rowId: 'general-hotkey-combo',
                    // One trigger for the dictation: a combination or one
                    // single key (never both). The row shows what listens, so
                    // a saved key that cannot listen here does not appear.
                    child:
                        settings.hotkey.hotkeyDoubleTapKey.isEmpty ||
                            doubleTapFallback
                        ? HotkeyComboLine(
                            label: l10n.settingsCurrentHotkey,
                            hotkeyKey: active.key,
                            hotkeyModifiers: active.modifiers,
                            hotkeyKeyDisplay: active.display,
                            padding: _comboPadding,
                            changeButtonKey: const Key('mainHotkeyChange'),
                            changeTestId: 'settings-hotkey-main-change',
                            onChange: () =>
                                unawaited(_changeDictationTrigger(settings)),
                          )
                        : _singleKeyTriggerLine(
                            l10n,
                            settings.hotkey.hotkeyDoubleTapKey,
                            settings,
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
                    text: hotkeyFallbackMessage(
                      settings,
                      l10n,
                      status: ref.watch(hotkeyRegistrationStatusProvider),
                    ),
                  ),
                if (doubleTapFallback)
                  HotkeyNotice(
                    noticeKey: const Key('mainHotkeyDoubleTapFallbackNotice'),
                    icon: LucideIcons.info,
                    color: WpColors.textMuted,
                    text: doubleTapFallbackNotice(
                      l10n,
                      unavailable: ref.watch(doubleTapUnavailableProvider),
                    ),
                  ),
                // Linux Wayland: registered, but the desktop has not bound it
                // (XP-2-06). Says why, with reconnect and the command.
                const WaylandHotkeyNotice(idPrefix: 'settings'),
                // macOS: another app's slow keyboard tap, named calmly (#915).
                const WpHotkeySlowTapHint(idPrefix: 'settings-hotkey'),
                if (settings.hotkeyEnabled &&
                    ref.watch(hotkeyRegistrationStatusProvider) ==
                        HotkeyRegistrationStatus.unavailable)
                  const HotkeyPendingNotice(
                    noticeKey: Key('mainHotkeyPendingNotice'),
                  ),
                // Linux Wayland without the GlobalShortcuts portal: the
                // hotkey goes through the desktop's own shortcuts.
                LinuxDesktopShortcutBlock(settings: settings),
              ],
            ),
            // Modes of the recording hotkey: they also apply to Smart Mode.
            _HotkeyOperationRow(settings: settings),
            _DoubleTapRow(settings: settings),
            // Extra dictation keys with a language of their own (#2055).
            DictationKeysBlock(settings: settings),
            _OneShotHotkeyBlock(
              settings: settings,
              hotkey: languageCycleHotkey,
              rowId: 'general-hotkey-language-cycle',
              title: l10n.settingsLanguageCycleHotkeyEnabled,
              subtitle: l10n.settingsLanguageCycleHotkeyHint,
              status: languageCycleHotkeyRegistrationStatusProvider,
            ),
            _FavoriteLanguageHotkeysBlock(settings: settings),
            _OneShotHotkeyBlock(
              settings: settings,
              hotkey: repasteHotkey,
              rowId: 'general-hotkey-repaste',
              title: l10n.settingsRepasteHotkeyEnabled,
              subtitle: l10n.settingsRepasteHotkeyHint,
              status: repasteHotkeyRegistrationStatusProvider,
            ),
            _OneShotHotkeyBlock(
              settings: settings,
              hotkey: learnCorrectionHotkey,
              rowId: 'general-hotkey-learn-correction',
              title: l10n.settingsLearnCorrectionHotkeyEnabled,
              subtitle: l10n.settingsLearnCorrectionHotkeyHint,
              status: learnCorrectionHotkeyRegistrationStatusProvider,
            ),
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
        // Rarely changed, so it stays out of the dictation card (UX-076).
        if (hotkeyOperationOf(
              settings,
              supportsKeyUp: ref
                  .read(hotkeyServiceProvider.notifier)
                  .supportsKeyUp,
            ) ==
            HotkeyOperation.holdOrTap) ...[
          settingsSectionBreak,
          WpSettingsGroup(
            heading: l10n.settingsAdvanced,
            children: [
              _HoldOrTapThresholdRow(
                thresholdMs: settings.audioInput.holdOrTapThresholdMs,
              ),
            ],
          ),
        ],
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
// marked "switched off" and inert when the hotkey is off; notices stay
// readable.
// ---------------------------------------------------------------------------

/// Combination line aligned with the action name above it.
const EdgeInsetsDirectional _comboPadding = EdgeInsetsDirectional.fromSTEB(
  0,
  0,
  0,
  WpSpacing.xs,
);

/// The notice under a hotkey that stays off: [conflictText] names a refused
/// combination, an unknown key has its own cause.
String _inactiveNotice(
  L10n l10n,
  HotkeyRegistrationStatus status,
  String conflictText,
) => status == HotkeyRegistrationStatus.unknownKey
    ? l10n.hotkeyUnknownKeyInactive
    : conflictText;

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
/// A one-shot extra hotkey (off by default): switch, combination, and the
/// collision, inactive and Wayland notices. The notices name no action, so
/// every such hotkey shares their texts.
class _OneShotHotkeyBlock extends ConsumerStatefulWidget {
  const _OneShotHotkeyBlock({
    required this.settings,
    required this.hotkey,
    required this.rowId,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final AppSettings settings;
  final OneShotHotkey hotkey;
  final String rowId;
  final String title;
  final String subtitle;
  final ProviderListenable<HotkeyRegistrationStatus> status;

  @override
  ConsumerState<_OneShotHotkeyBlock> createState() =>
      _OneShotHotkeyBlockState();
}

class _OneShotHotkeyBlockState extends ConsumerState<_OneShotHotkeyBlock>
    with HotkeyCollisionNotice {
  Future<void> _record() => recordAndReport(
    () => recordOneShotHotkey(
      context: context,
      ref: ref,
      settings: widget.settings,
      hotkey: widget.hotkey,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final id = widget.hotkey.actionId;
    final current = widget.hotkey.read(widget.settings);
    final enabled = current.enabled;

    // `enabled &&`: the registration status is in-memory; a switched-off
    // hotkey must not keep reporting "not active".
    final hotkeyStatus = ref.watch(widget.status);
    final registrationFailed = enabled && hotkeyStatus.needsNewKey;
    final registrationPending =
        enabled && hotkeyStatus == HotkeyRegistrationStatus.unavailable;
    // Wayland gives no global key grab to other apps; say so instead of
    // letting the switch promise a system-wide shortcut.
    final waylandSession =
        defaultTargetPlatform == TargetPlatform.linux &&
        Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';

    return _hotkeyBlock(
      key: ValueKey('shortcutBlock-$id'),
      children: [
        WpSettingsRow(
          rowId: widget.rowId,
          title: widget.title,
          subtitle: widget.subtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: widget.title,
            key: Key('${id}HotkeyToggle'),
            value: enabled,
            showOffState: true,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(
                setOneShotHotkeyEnabled(ref, widget.hotkey, enabled: v),
              );
            },
          ),
        ),
        settingsSwitchedOffWhen(
          context,
          enabled: enabled,
          collapse: true,
          child: HotkeyComboLine(
            key: Key('${id}HotkeyComboLine'),
            label: l10n.settingsCurrentHotkey,
            hotkeyKey: current.key,
            hotkeyModifiers: current.modifiers,
            hotkeyKeyDisplay: current.display,
            padding: _comboPadding,
            changeButtonKey: Key('${id}HotkeyChange'),
            onChange: () => unawaited(_record()),
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: Key('${id}HotkeyCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsLanguageCycleHotkeyCollision(collidingAction!),
          ),
        if (registrationFailed)
          HotkeyNotice(
            noticeKey: Key('${id}HotkeyInactiveNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: _inactiveNotice(
              l10n,
              hotkeyStatus,
              l10n.settingsLanguageCycleHotkeyInactive,
            ),
          ),
        if (registrationPending)
          HotkeyPendingNotice(noticeKey: Key('${id}HotkeyPendingNotice')),
        if (enabled && waylandSession)
          HotkeyNotice(
            noticeKey: Key('${id}HotkeyWaylandNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsLanguageCycleHotkeyWaylandNotice,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One hotkey per favorite language (#2137, GitHub #161)
// ---------------------------------------------------------------------------

/// One line per current favorite: its own combination, which switches the
/// recognition language straight to it. No switch: a language with a key is
/// on, "Remove" turns it off. Without favorites the row says where they come
/// from and opens the language dialog with the stars.
class _FavoriteLanguageHotkeysBlock extends ConsumerWidget {
  const _FavoriteLanguageHotkeysBlock({required this.settings});

  final AppSettings settings;

  void _chooseFavorites(WidgetRef ref) {
    // Favorites are set by star in the language dialog (#1610); the same
    // jump as the "no favorites" notice of the cycle hotkey.
    ref.read(settingsScrollTargetProvider.notifier).set('speech-language');
    ref.read(settingsLanguageDialogRequestProvider.notifier).request();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final favorites = settings.stt.favoriteLanguages;
    final refused = ref.watch(favoriteLanguageHotkeyRefusalsProvider);
    final anyKey = activeFavoriteLanguageHotkeys(
      favorites: favorites,
      hotkeys: settings.stt.favoriteLanguageHotkeys,
    ).isNotEmpty;
    final waylandSession =
        defaultTargetPlatform == TargetPlatform.linux &&
        Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-favoriteLanguages'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-favorite-languages',
          title: l10n.settingsFavoriteLanguageHotkeysTitle,
          subtitle: favorites.isEmpty
              ? l10n.settingsFavoriteLanguageHotkeysEmpty
              : l10n.settingsFavoriteLanguageHotkeysHint,
          trailing: favorites.isEmpty
              ? WpButton(
                  key: const Key('favoriteLanguageHotkeysChooseFavorites'),
                  label: l10n.settingsFavoriteLanguageHotkeysChooseFavorites,
                  variant: WpButtonVariant.secondary,
                  onPressed: () => _chooseFavorites(ref),
                )
              : const SizedBox.shrink(),
        ),
        for (final (index, code) in favorites.indexed)
          _FavoriteLanguageHotkeyLine(
            key: ValueKey('favoriteLanguageHotkeyLine-$code'),
            settings: settings,
            code: code,
            position: index,
            refused: refused.contains(code),
          ),
        if (anyKey && waylandSession)
          HotkeyNotice(
            noticeKey: const Key('favoriteLanguageHotkeysWaylandNotice'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsLanguageCycleHotkeyWaylandNotice,
          ),
      ],
    );
  }
}

class _FavoriteLanguageHotkeyLine extends ConsumerStatefulWidget {
  const _FavoriteLanguageHotkeyLine({
    super.key,
    required this.settings,
    required this.code,
    required this.position,
    required this.refused,
  });

  final AppSettings settings;
  final String code;

  /// Place in the favorites, for the suggested combination of a new key.
  final int position;

  /// The stored key does not work right now (see
  /// `favoriteLanguageHotkeyRefusalsProvider`).
  final bool refused;

  @override
  ConsumerState<_FavoriteLanguageHotkeyLine> createState() =>
      _FavoriteLanguageHotkeyLineState();
}

class _FavoriteLanguageHotkeyLineState
    extends ConsumerState<_FavoriteLanguageHotkeyLine>
    with HotkeyCollisionNotice {
  FavoriteLanguageHotkey? get _hotkey =>
      widget.settings.stt.favoriteLanguageHotkeys[widget.code];

  Future<void> _record() {
    final current = _hotkey;
    // A new key starts from the favorite's place (1 to 5) with Ctrl+Option
    // on macOS (Cmd+Shift+3/4/5 are the system's screenshot keys) and
    // Ctrl+Shift elsewhere; the user presses their own combination anyway.
    final suggestedModifiers = defaultTargetPlatform == TargetPlatform.macOS
        ? 'ctrl+alt'
        : 'ctrl+shift';
    return recordAndReport(
      () => recordHotkey(
        context: context,
        ref: ref,
        settings: widget.settings,
        actionId: favoriteLanguageHotkeyActionId(widget.code),
        initialKey: current?.key ?? '${widget.position + 1}',
        initialDisplayKey: current?.keyDisplay ?? '',
        initialModifiers: current?.modifiers ?? suggestedModifiers,
        apply: (s, result) => s.copyWithSections(
          stt: s.stt.copyWith(
            favoriteLanguageHotkeys: withFavoriteLanguageHotkey(
              s.stt.favoriteLanguageHotkeys,
              widget.code,
              FavoriteLanguageHotkey(
                key: result.key,
                keyDisplay: result.displayKey,
                modifiers: result.modifiers,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _remove() {
    clearHotkeyCollision();
    return ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            stt: s.stt.copyWith(
              favoriteLanguageHotkeys: withFavoriteLanguageHotkey(
                s.stt.favoriteLanguageHotkeys,
                widget.code,
                null,
              ),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tt = Theme.of(context).textTheme;
    final hotkey = _hotkey;
    final name = languageMenuName(widget.code);
    final code = widget.code;
    final changeLabel = hotkey == null
        ? l10n.settingsFavoriteLanguageHotkeySet
        : l10n.settingsChangeHotkey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: _comboPadding,
          child: Wrap(
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(name, style: tt.bodyMedium),
              if (hotkey == null)
                Text(
                  l10n.settingsFavoriteLanguageHotkeyNone,
                  style: tt.bodySmall?.copyWith(color: WpColors.textMuted),
                )
              else
                HotkeyDisplay(
                  hotkeyKey: hotkey.key,
                  hotkeyModifiers: hotkey.modifiers,
                  hotkeyKeyDisplay: hotkey.keyDisplay,
                ),
              WpButton(
                key: Key('favoriteLanguageHotkeyChange-$code'),
                label: changeLabel,
                // The button text alone does not say which language.
                semanticsLabel: '$changeLabel: $name',
                variant: WpButtonVariant.secondary,
                onPressed: () => unawaited(_record()),
              ),
              if (hotkey != null)
                WpButton(
                  key: Key('favoriteLanguageHotkeyRemove-$code'),
                  label: l10n.settingsFavoriteLanguageHotkeyRemove,
                  semanticsLabel:
                      '${l10n.settingsFavoriteLanguageHotkeyRemove}: $name',
                  variant: WpButtonVariant.ghost,
                  onPressed: () => unawaited(_remove()),
                ),
            ],
          ),
        ),
        if (collidingAction != null)
          HotkeyNotice(
            noticeKey: Key('favoriteLanguageHotkeyCollision-$code'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsLanguageCycleHotkeyCollision(collidingAction!),
          ),
        if (hotkey != null && widget.refused)
          HotkeyNotice(
            noticeKey: Key('favoriteLanguageHotkeyInactive-$code'),
            icon: LucideIcons.triangleAlert,
            color: WpColors.warning,
            text: l10n.settingsFavoriteLanguageHotkeyInactive,
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
    final hotkeyStatus = ref.watch(quickNoteHotkeyRegistrationStatusProvider);
    final registrationFailed = enabled && hotkeyStatus.needsNewKey;
    final registrationPending =
        enabled && hotkeyStatus == HotkeyRegistrationStatus.unavailable;

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-quickNote'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-quick-note',
          title: l10n.settingsQuickNoteHotkeyEnabled,
          subtitle: l10n.settingsQuickNoteHotkeyHint,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsQuickNoteHotkeyEnabled,
            key: const Key('quickNoteHotkeyToggle'),
            value: enabled,
            showOffState: true,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setQuickNoteHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsSwitchedOffWhen(
          context,
          enabled: enabled,
          collapse: true,
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
            text: _inactiveNotice(
              l10n,
              hotkeyStatus,
              l10n.settingsQuickNoteHotkeyInactive,
            ),
          ),
        if (registrationPending)
          const HotkeyPendingNotice(
            noticeKey: Key('quickNoteHotkeyPendingNotice'),
          ),
        // Where a finished quick note goes. Independent of the switch above.
        WpSettingsRow(
          rowId: 'general-quick-note-open-main-window',
          title: l10n.settingsQuickNoteOpenInMainWindow,
          subtitle: l10n.settingsQuickNoteOpenInMainWindowHint,
          switchNamesRow: true,
          indent: true,
          trailing: settingsToggle(
            label: l10n.settingsQuickNoteOpenInMainWindow,
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
        // Which note a dictation goes to (#661). Default the marked quick
        // note, the behaviour before the choice existed.
        WpSettingsRow(
          rowId: 'general-quick-note-destination',
          title: l10n.settingsQuickNoteDestination,
          subtitle: l10n.settingsQuickNoteDestinationHint,
          indent: true,
          trailing: settingsDropdown(
            context: context,
            value: quickNote.destination.value,
            items: QuickNoteDestination.values.map((d) => d.value).toList(),
            labels: [
              l10n.settingsQuickNoteDestinationMarkedNote,
              l10n.settingsQuickNoteDestinationLastNote,
              l10n.settingsQuickNoteDestinationNewNote,
            ],
            keyPrefix: 'quick-note-destination',
            testId: 'quick-note-destination',
            onChanged: (v) {
              if (v == null) return;
              unawaited(
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        quickNoteHotkey: s.quickNoteHotkey.copyWith(
                          destination: QuickNoteDestination.fromValue(v),
                        ),
                      ),
                    ),
              );
            },
          ),
        ),
        // How each appended dictation is dated (#803). Default margin mark:
        // the note text stays clean, the moment sits beside it.
        WpSettingsRow(
          rowId: 'general-quick-note-timestamp-style',
          title: l10n.settingsQuickNoteTimestampStyle,
          subtitle: l10n.settingsQuickNoteTimestampStyleHint,
          indent: true,
          trailing: settingsDropdown(
            context: context,
            value: quickNote.timestampStyle.value,
            items: QuickNoteTimestampStyle.values.map((s) => s.value).toList(),
            labels: [
              l10n.settingsQuickNoteTimestampTextLine,
              l10n.settingsQuickNoteTimestampMarginMark,
              l10n.settingsQuickNoteTimestampBoth,
            ],
            keyPrefix: 'quick-note-timestamp-style',
            testId: 'quick-note-timestamp-style',
            onChanged: (v) {
              if (v == null) return;
              unawaited(
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        quickNoteHotkey: s.quickNoteHotkey.copyWith(
                          timestampStyle: QuickNoteTimestampStyle.fromValue(v),
                        ),
                      ),
                    ),
              );
            },
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
    final hotkeyStatus = ref.watch(
      snippetPickerHotkeyRegistrationStatusProvider,
    );
    final registrationFailed = enabled && hotkeyStatus.needsNewKey;
    final registrationPending =
        enabled && hotkeyStatus == HotkeyRegistrationStatus.unavailable;

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
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSnippetPickerHotkeyEnabled,
            key: const Key('snippetPickerHotkeyToggle'),
            value: enabled,
            showOffState: true,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSnippetPickerHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsSwitchedOffWhen(
          context,
          enabled: enabled,
          collapse: true,
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
            text: _inactiveNotice(
              l10n,
              hotkeyStatus,
              l10n.settingsSnippetPickerHotkeyInactive,
            ),
          ),
        if (registrationPending)
          const HotkeyPendingNotice(
            noticeKey: Key('snippetPickerHotkeyPendingNotice'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// How the dictation hotkey is operated (UX-075)
// ---------------------------------------------------------------------------

/// One choice instead of two switches: press to start and stop, hold, or tap
/// or hold. Hold and tap-or-hold need key-up and a combination; where either
/// is missing the entries are locked and the subtitle says why.
class _HotkeyOperationRow extends ConsumerWidget {
  const _HotkeyOperationRow({required this.settings});

  static final _log = AppLogger('HotkeyOperationRow');

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly: supportsKeyUp is needed once per build and
    // hotkey-service state changes need no rebuild here.
    final hotkeyService = ref.read(hotkeyServiceProvider.notifier);
    final supportsKeyUp = hotkeyService.supportsKeyUp;
    final singleKey = settings.hotkey.hotkeyDoubleTapKey.isNotEmpty;
    final operation = hotkeyOperationOf(settings, supportsKeyUp: supportsKeyUp);
    final operatingSystem = defaultTargetPlatform == TargetPlatform.linux
        ? 'linux'
        : 'other';

    final operationLabels = [
      l10n.settingsHotkeyOperationToggle,
      l10n.settingsHotkeyOperationHold,
      l10n.settingsHoldOrTap,
    ];

    return WpSettingsRow(
      rowId: 'general-hold-to-record',
      title: l10n.settingsHotkeyOperation,
      subtitle: hotkeyOperationSubtitle(
        l10n,
        operation,
        supportsKeyUp: supportsKeyUp,
        singleKey: singleKey,
        operatingSystem: operatingSystem,
      ),
      // Linux key-up (catchup/09) is not verified on a real GNOME/KDE
      // desktop yet: say so right at the option instead of hiding it.
      badge: hotkeyService.keyUpExperimental
          ? l10n.settingsExperimentalBadge
          : null,
      badgeKey: const Key('settings-push-to-talk-experimental-badge'),
      // Sized to its longest label, not capped at the generic 240 px: at
      // text scale 2.0 "Gedrückt halten" ellipsized in the capped trigger
      // (#1018). The row still caps the width by its own space.
      trailing: SharedWidthDropdown(
        labels: operationLabels,
        selectedLabel: operationLabels[operation.index],
        child: settingsDropdown(
          context: context,
          value: operation.name,
          items: [for (final o in HotkeyOperation.values) o.name],
          labels: operationLabels,
          expanded: true,
          // A single key offers hold + double tap or the double tap alone;
          // "Tap or hold" cannot share a key with the double tap.
          disabledItems: singleKey
              ? {
                  HotkeyOperation.holdOrTap.name,
                  if (!supportsKeyUp) HotkeyOperation.hold.name,
                }
              : supportsKeyUp
              ? null
              : {HotkeyOperation.hold.name, HotkeyOperation.holdOrTap.name},
          disabledTooltip: singleKey && supportsKeyUp
              ? l10n.settingsDoubleTapBlockedByHoldOrTap
              : pushToTalkUnavailableMessage(
                  l10n,
                  operatingSystem: operatingSystem,
                ),
          keyPrefix: 'settings-hotkey-operation',
          testId: 'settings-hotkey-operation',
          onChanged: (v) {
            if (v == null) return;
            ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) =>
                      withHotkeyOperation(s, HotkeyOperation.values.byName(v)),
                );
            try {
              ref.read(telemetryProvider).trackSettingChange('hotkey_mode');
            } catch (e) {
              _log.debug('telemetry failed: $e');
            }
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Double tap for hands-free dictation (maintainer 2026-10-30)
// ---------------------------------------------------------------------------

/// Two quick taps of the dictation trigger start hands-free dictation, one
/// press ends it. Applies to a combination in hold mode and to a single key
/// in any mode but hold-or-tap, whose short tap already latches; elsewhere
/// the switch is dimmed with the reason.
class _DoubleTapRow extends ConsumerWidget implements SettingsRowStandIn {
  const _DoubleTapRow({required this.settings});

  final AppSettings settings;

  /// Builds an indented dependent row, so the group's divider in front of it
  /// starts on the same indented edge.
  @override
  bool get indent => true;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;
    final hold = supportsKeyUp && settings.pushToTalk;
    final singleKey = settings.hotkey.hotkeyDoubleTapKey.isNotEmpty;
    final holdOrTap = hold && settings.audioInput.holdOrTap;
    final enabled = !holdOrTap && (hold || singleKey);
    final value = settings.hotkey.hotkeyDoubleTap;

    final toggle = settingsToggle(
      label: l10n.settingsDoubleTapHandsFree,
      key: const Key('doubleTapToggle'),
      value: value,
      onChanged: enabled
          ? (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    hotkey: s.hotkey.copyWith(hotkeyDoubleTap: v),
                  ),
                )
          : null,
    );

    return settingsSwitchedOffWhen(
      context,
      enabled: enabled,
      child: WpSettingsRow(
        rowId: 'general-double-tap',
        indent: true,
        title: l10n.settingsDoubleTapHandsFree,
        subtitle: enabled
            ? l10n.settingsDoubleTapHandsFreeHint
            : '${l10n.settingsDoubleTapHandsFreeHint}\n'
                  '${holdOrTap ? l10n.settingsDoubleTapBlockedByHoldOrTap : l10n.settingsDoubleTapNeedsHold}',
        switchNamesRow: enabled,
        trailing: enabled ? toggle : ExcludeSemantics(child: toggle),
      ),
    );
  }
}

/// Threshold slider of tap-or-hold (Automatisch), under "Advanced": presses
/// shorter than the value latch the recording, longer ones are push-to-talk.
/// Steps of 50 ms within the clamped settings range.
class _HoldOrTapThresholdRow extends ConsumerStatefulWidget {
  const _HoldOrTapThresholdRow({required this.thresholdMs});

  final int thresholdMs;

  @override
  ConsumerState<_HoldOrTapThresholdRow> createState() =>
      _HoldOrTapThresholdRowState();
}

class _HoldOrTapThresholdRowState
    extends ConsumerState<_HoldOrTapThresholdRow> {
  static const _step = 50;

  /// Slider position while a drag runs; null otherwise.
  int? _dragMs;

  void _store(int ms) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            audioInput: s.audioInput.copyWith(holdOrTapThresholdMs: ms),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final shown = _dragMs ?? widget.thresholdMs;
    return WpSettingsRow(
      key: const Key('settings-hotkey-main-threshold'),
      rowId: 'general-hold-or-tap-threshold',
      title: l10n.settingsHoldOrTapThreshold,
      trailing: settingsSlider(
        context: context,
        value: shown.toDouble(),
        min: minHoldOrTapThresholdMs.toDouble(),
        max: maxHoldOrTapThresholdMs.toDouble(),
        divisions: (maxHoldOrTapThresholdMs - minHoldOrTapThresholdMs) ~/ _step,
        valueLabel: l10n.settingsHoldOrTapThresholdValue(shown),
        onChanged: (v) => setState(() => _dragMs = _snap(v)),
        onChangeEnd: (v) {
          setState(() => _dragMs = null);
          _store(_snap(v));
        },
      ),
    );
  }

  int _snap(double v) {
    final steps = ((v - minHoldOrTapThresholdMs) / _step).round();
    return minHoldOrTapThresholdMs + steps * _step;
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
    final hotkeyStatus = ref.watch(smartModeHotkeyRegistrationStatusProvider);
    final registrationFailed = enabled && hotkeyStatus.needsNewKey;
    final registrationPending =
        enabled && hotkeyStatus == HotkeyRegistrationStatus.unavailable;
    // Without a usable text model the hotkey's presets cannot be picked either
    // (UIA-XP-7-05).
    final textModelStatus = ref.watch(smartModeTextModelStatusProvider);
    final presetLockedReason = smartModeUnavailableReason(
      textModelStatus,
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
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSmartModeHotkeyEnabled,
            key: const Key('smartModeHotkeyToggle'),
            value: enabled,
            showOffState: true,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSmartModeHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsSwitchedOffWhen(
          context,
          enabled: enabled,
          collapse: true,
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
            text: _inactiveNotice(
              l10n,
              hotkeyStatus,
              l10n.settingsSmartModeHotkeyInactive,
            ),
          ),
        if (registrationPending)
          const HotkeyPendingNotice(
            noticeKey: Key('smartModeHotkeyPendingNotice'),
          ),
        // Dependent options of this hotkey, indented below it; inert while
        // the hotkey is off, which the switch above says.
        settingsSwitchedOffWhen(
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
              // Every preset of this hotkey is locked, so the dropdown stays
              // shut; the reason and the fix sit right under it (#1686).
              if (smartModeLockedNoticeShown(textModelStatus))
                const WpSettingsDetail(
                  indent: true,
                  child: SmartModeLockedNotice(),
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
// Edit-selection hotkey — select text in
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
    final hotkeyStatus = ref.watch(
      selectionEditHotkeyRegistrationStatusProvider,
    );
    final registrationFailed = enabled && hotkeyStatus.needsNewKey;
    final registrationPending =
        enabled && hotkeyStatus == HotkeyRegistrationStatus.unavailable;

    return _hotkeyBlock(
      key: const ValueKey('shortcutBlock-selectionEdit'),
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-selection-edit',
          title: l10n.settingsSelectionEditHotkeyEnabled,
          subtitle: l10n.settingsSelectionEditHotkeyHint,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSelectionEditHotkeyEnabled,
            key: const Key('selectionEditHotkeyToggle'),
            value: enabled,
            showOffState: true,
            onChanged: (v) {
              clearHotkeyCollision();
              unawaited(setSelectionEditHotkeyEnabled(ref, enabled: v));
            },
          ),
        ),
        settingsSwitchedOffWhen(
          context,
          enabled: enabled,
          collapse: true,
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
            text: _inactiveNotice(
              l10n,
              hotkeyStatus,
              l10n.settingsSelectionEditHotkeyInactive,
            ),
          ),
        if (registrationPending)
          const HotkeyPendingNotice(
            noticeKey: Key('selectionEditHotkeyPendingNotice'),
          ),
      ],
    );
  }
}
