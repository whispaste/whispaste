/// "Weitere Diktiertasten" (#2055) in the Dictation card of the shortcuts
/// area: up to three extra dictation keys, each with a language of its own
/// and optionally a Smart Mode choice.
///
/// Calm by default: without extra keys only the row with its add button
/// shows. Each key unfolds below it with its combination, its language, its
/// Smart Mode choice and a remove button.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/extra_dictation_keys.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/spoken_languages.dart';
import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/text/name_order.dart';
import '../../../services/dictation_key_sync.dart';
import '../../../services/floating_button/floating_button_support.dart'
    show LinuxSessionType, linuxSessionTypeFrom;
import '../../../services/hotkey_service.dart';
import '../../../widgets/wp_button.dart';
import '../dictation_key_flow.dart';
import '../hotkey_flow.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

/// The language choices of an extra key: the languages the user speaks and
/// the favorites first (the issue's "from the expected languages"), then
/// every other language, so a fixed main language plus a key for a second
/// one needs no change to the main setting.
List<({String code, String label})> dictationKeyLanguageOptions({
  required AppSettings settings,
  required String current,
  required String Function(String code) nameOf,
}) {
  final preferred = <String>{
    for (final code in [
      ...spokenLanguagesOf(settings),
      ...settings.stt.favoriteLanguages,
      current,
    ])
      if (code != 'auto' && whisperLanguages.containsKey(code)) code,
  }.toList();
  final rest = [
    for (final code in whisperLanguages.keys)
      if (!preferred.contains(code)) (code: code, label: nameOf(code)),
  ]..sort((a, b) => compareDisplayNames(a.label, b.label));
  return [
    for (final code in preferred) (code: code, label: nameOf(code)),
    ...rest,
  ];
}

class DictationKeysBlock extends ConsumerStatefulWidget {
  const DictationKeysBlock({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<DictationKeysBlock> createState() => _DictationKeysBlockState();
}

class _DictationKeysBlockState extends ConsumerState<DictationKeysBlock> {
  /// The key whose last recording collided, with the holder's name. A
  /// collision on "add" is kept under [_addSlot].
  String? _collisionKeyId;
  String? _collidingAction;

  static const _addSlot = '+';

  Future<void> _report(String slot, Future<HotkeyRecordResult> run) async {
    final result = await run;
    if (!mounted || result.change == HotkeyChange.cancelled) return;
    setState(() {
      _collisionKeyId = slot;
      _collidingAction = result.collidingActionLabel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = widget.settings;
    final keys = settings.hotkey.extraDictationKeys;
    final canAdd = keys.length < kMaxExtraDictationKeys;

    return Column(
      key: const ValueKey('shortcutBlock-dictationKeys'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WpSettingsRow(
          rowId: 'general-hotkey-dictation-keys',
          title: l10n.settingsDictationKeysTitle,
          subtitle: canAdd
              ? l10n.settingsDictationKeysHint
              : l10n.settingsDictationKeysMax(kMaxExtraDictationKeys),
          trailing: canAdd
              ? WpButton(
                  key: const Key('dictationKeyAdd'),
                  testId: 'settings-dictation-key-add',
                  label: l10n.settingsDictationKeysAdd,
                  icon: LucideIcons.plus,
                  variant: WpButtonVariant.secondary,
                  onPressed: () => unawaited(
                    _report(
                      _addSlot,
                      addDictationKey(
                        context: context,
                        ref: ref,
                        settings: settings,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_collisionKeyId == _addSlot && _collidingAction != null)
          HotkeyNotice(
            noticeKey: const Key('dictationKeyAddCollisionNotice'),
            icon: LucideIcons.circleAlert,
            color: WpColors.error,
            text: l10n.settingsLanguageCycleHotkeyCollision(_collidingAction!),
          ),
        for (final key in keys)
          _DictationKeyEntry(
            key: ValueKey('dictationKey-${key.id}'),
            settings: settings,
            entry: key,
            collidingAction: _collisionKeyId == key.id
                ? _collidingAction
                : null,
            onRecord: () => unawaited(
              _report(
                key.id,
                recordDictationKey(
                  context: context,
                  ref: ref,
                  settings: settings,
                  key: key,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DictationKeyEntry extends ConsumerWidget {
  const _DictationKeyEntry({
    super.key,
    required this.settings,
    required this.entry,
    required this.collidingAction,
    required this.onRecord,
  });

  final AppSettings settings;
  final ExtraDictationKey entry;
  final String? collidingAction;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final localeNames = LocaleNames.of(context);
    String nameOf(String code) =>
        localeNames?.nameOf(code) ?? whisperLanguages[code] ?? code;
    final id = entry.id;
    final refusedByApp = ref.watch(
      dictationKeyPlanProvider.select((p) => p.refusedIds.contains(id)),
    );
    final refusedByOs = ref.watch(
      dictationKeysRefusedByOsProvider.select((ids) => ids.contains(id)),
    );
    // Wayland binds only the main hotkey through the portal: say so instead
    // of letting the key promise a system-wide shortcut (#1934).
    final wayland =
        defaultTargetPlatform == TargetPlatform.linux &&
        linuxSessionTypeFrom(Platform.environment) == LinuxSessionType.wayland;
    final languages = dictationKeyLanguageOptions(
      settings: settings,
      current: entry.language,
      nameOf: nameOf,
    );
    const smartModes = ExtraDictationKeySmartMode.values;
    String smartModeLabel(ExtraDictationKeySmartMode mode) => switch (mode) {
      ExtraDictationKeySmartMode.standard =>
        l10n.settingsDictationKeySmartModeStandard,
      ExtraDictationKeySmartMode.off => l10n.smartModePresetOff,
      ExtraDictationKeySmartMode.cleanup => l10n.smartModePresetCleanup,
      ExtraDictationKeySmartMode.concise => l10n.smartModePresetConcise,
    };
    final title = l10n.settingsDictationKeyTitle(nameOf(entry.language));

    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsRowFrame(
            rowId: 'general-hotkey-dictation-key-$id',
            indent: true,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: WpSpacing.sm),
              child: Wrap(
                spacing: WpSpacing.sm,
                runSpacing: WpSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  WpButton(
                    key: Key('dictationKeyRemove-$id'),
                    testId: 'settings-dictation-key-remove-$id',
                    label: l10n.settingsDictationKeyRemove,
                    variant: WpButtonVariant.ghost,
                    onPressed: () =>
                        unawaited(removeDictationKey(ref, keyId: id)),
                  ),
                ],
              ),
            ),
          ),
          SettingsRowFrame(
            rowId: 'general-hotkey-dictation-key-$id-combination',
            indent: true,
            child: HotkeyComboLine(
              key: Key('dictationKeyComboLine-$id'),
              label: l10n.settingsCurrentHotkey,
              hotkeyKey: entry.key,
              hotkeyModifiers: entry.modifiers,
              hotkeyKeyDisplay: entry.keyDisplay,
              padding: const EdgeInsetsDirectional.only(bottom: WpSpacing.xs),
              changeButtonKey: Key('dictationKeyChange-$id'),
              changeTestId: 'settings-dictation-key-change-$id',
              onChange: onRecord,
            ),
          ),
          if (collidingAction != null)
            HotkeyNotice(
              noticeKey: Key('dictationKeyCollisionNotice-$id'),
              icon: LucideIcons.circleAlert,
              color: WpColors.error,
              text: l10n.settingsLanguageCycleHotkeyCollision(collidingAction!),
            ),
          if (refusedByApp)
            HotkeyNotice(
              noticeKey: Key('dictationKeyRefusedNotice-$id'),
              icon: LucideIcons.triangleAlert,
              color: WpColors.warning,
              text: l10n.settingsDictationKeyRefused,
            )
          else if (refusedByOs)
            HotkeyNotice(
              noticeKey: Key('dictationKeyInactiveNotice-$id'),
              icon: LucideIcons.triangleAlert,
              color: WpColors.warning,
              text: l10n.settingsLanguageCycleHotkeyInactive,
            ),
          if (wayland)
            HotkeyNotice(
              noticeKey: Key('dictationKeyWaylandNotice-$id'),
              icon: LucideIcons.triangleAlert,
              color: WpColors.warning,
              text: l10n.settingsDictationKeyWaylandNotice,
            ),
          WpSettingsRow(
            rowId: 'general-hotkey-dictation-key-$id-language',
            title: l10n.settingsDictationKeyLanguage,
            indent: true,
            trailing: settingsDropdown(
              context: context,
              keyPrefix: 'dictationKeyLanguage-$id',
              value: entry.language,
              items: [for (final o in languages) o.code],
              labels: [for (final o in languages) o.label],
              onChanged: (v) {
                if (v == null) return;
                unawaited(setDictationKeyLanguage(ref, keyId: id, language: v));
              },
            ),
          ),
          WpSettingsRow(
            rowId: 'general-hotkey-dictation-key-$id-smart-mode',
            title: l10n.settingsDictationKeySmartMode,
            indent: true,
            trailing: settingsDropdown(
              context: context,
              keyPrefix: 'dictationKeySmartMode-$id',
              value: entry.smartMode.storageValue,
              items: [for (final m in smartModes) m.storageValue],
              labels: [for (final m in smartModes) smartModeLabel(m)],
              onChanged: (v) {
                if (v == null) return;
                unawaited(
                  setDictationKeySmartMode(
                    ref,
                    keyId: id,
                    smartMode: ExtraDictationKeySmartMode.fromStorage(v),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
