/// Appearance settings card (ticket, spec 07-settings-ia §3 "Darstellung"):
/// the mode picker, dock utilisation and the clipboard side panel.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/editor/editor_text_view.dart';
import '../../../widgets/editor_text_view_scope.dart';
import '../../../widgets/searchable_list_page.dart' show showWpListMenu;
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/spell/spell_check.dart';
import '../../../widgets/editor_spell_check.dart' show spellLanguageLabel;
import '../../../services/clipboard_history/clipboard_app_exclusion.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';
import '../widgets/clipboard_exclusion_editor.dart';
import '../widgets/wp_appearance_picker.dart';
import '../widgets/wp_settings_group.dart';

class InterfaceAppearanceSection extends ConsumerWidget {
  const InterfaceAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final iface = settings.interface_;
    final textView =
        ref.watch(editorTextViewProvider).value ?? EditorTextView.standard;
    // `null` while the system is still asked; empty = no checker (#670).
    final spellLanguages = ref.watch(spellLanguagesProvider).value;
    final spellItems = [
      spellCheckLanguageAuto,
      ...?spellLanguages,
      // A choice imported from another system stays visible as it is.
      if (iface.spellCheckLanguage != spellCheckLanguageAuto &&
          !(spellLanguages ?? const []).contains(iface.spellCheckLanguage))
        iface.spellCheckLanguage,
    ];

    return WpSettingsGroup(
      children: [
        SettingsRowFrame(
          rowId: 'appearance-mode',
          child: KeyedSubtree(
            key: const ValueKey('settings-appearance'),
            child: WpAppearancePicker(
              mode: iface.appearance,
              platformBrightness: MediaQuery.platformBrightnessOf(context),
              onChanged: (mode) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      interface_: s.interface_.copyWith(appearance: mode),
                    ),
                  ),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-editor-text-view',
          title: l10n.editorTextViewMenu,
          subtitle: l10n.editorTextViewCurrentSize(textView.textSize),
          trailing: Builder(
            builder: (context) => WpButton(
              testId: 'settings-editor-text-view',
              label: l10n.editorTextViewMenu,
              variant: WpButtonVariant.secondary,
              onPressed: () =>
                  showWpListMenu(context, editorTextViewMenuActions(context)),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-spell-check',
          title: l10n.settingsSpellCheck,
          subtitle: spellLanguages != null && spellLanguages.isEmpty
              ? l10n.settingsSpellCheckUnavailable
              : l10n.settingsSpellCheckSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSpellCheck,
            testId: 'settings-spell-check-toggle',
            value: iface.spellCheckEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    interface_: s.interface_.copyWith(spellCheckEnabled: v),
                  ),
                ),
          ),
        ),
        if (iface.spellCheckEnabled)
          WpSettingsRow(
            rowId: 'appearance-spell-check-language',
            title: l10n.settingsSpellCheckLanguage,
            subtitle: l10n.settingsSpellCheckLanguageSubtitle,
            indent: true,
            trailing: settingsDropdown(
              context: context,
              testId: 'settings-spell-check-language',
              value: iface.spellCheckLanguage,
              items: spellItems,
              labels: [
                for (final tag in spellItems)
                  tag == spellCheckLanguageAuto
                      ? l10n.settingsSpellCheckLanguageAuto
                      : spellLanguageLabel(context, tag),
              ],
              onChanged: spellLanguages == null || spellLanguages.isEmpty
                  ? null
                  : (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWithSections(
                            interface_: s.interface_.copyWith(
                              spellCheckLanguage: v ?? spellCheckLanguageAuto,
                            ),
                          ),
                        ),
            ),
          ),
        WpSettingsRow(
          rowId: 'appearance-backend-utilization',
          title: l10n.settingsShowBackendUtilization,
          subtitle: l10n.settingsShowBackendUtilizationSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsShowBackendUtilization,
            value: iface.showBackendUtilization,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    interface_: s.interface_.copyWith(
                      showBackendUtilization: v,
                    ),
                  ),
                ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-side-panel',
          title: l10n.settingsSidePanelEnabled,
          subtitle: l10n.settingsSidePanelEnabledSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsSidePanelEnabled,
            value: iface.sidePanelEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    interface_: s.interface_.copyWith(sidePanelEnabled: v),
                  ),
                ),
          ),
        ),
        if (iface.sidePanelEnabled)
          WpSettingsRow(
            rowId: 'appearance-side-panel-edge',
            title: l10n.settingsSidePanelEdge,
            subtitle: l10n.settingsSidePanelEdgeSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: iface.sidePanelEdge.value,
              items: const ['left', 'right'],
              labels: [
                l10n.settingsSidePanelEdgeLeft,
                l10n.settingsSidePanelEdgeRight,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      interface_: s.interface_.copyWith(
                        sidePanelEdge: SidePanelEdge.fromValue(v),
                      ),
                    ),
                  ),
            ),
          ),
        if (iface.sidePanelEnabled)
          WpSettingsRow(
            rowId: 'appearance-clipboard-exclusions',
            title: l10n.settingsClipboardExclusionsRow,
            subtitle:
                kIsWeb || !clipboardSourceAppDetectable(defaultTargetPlatform)
                ? l10n.settingsClipboardExclusionsHintLinux
                : l10n.settingsClipboardExclusionsRowSubtitle(
                    clipboardExclusionsOf(settings).length,
                  ),
            trailing: WpButton(
              testId: 'settings-clipboard-exclusions-edit',
              label: l10n.settingsClipboardExclusionsEdit,
              variant: WpButtonVariant.secondary,
              onPressed: () => showClipboardExclusionEditor(context),
            ),
          ),
      ],
    );
  }
}
