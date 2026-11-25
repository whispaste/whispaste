/// The model choice at the point of use, one pattern for speech and text
/// models (#2045, #2175): one dropdown with the models installed on this
/// device, ending in an entry that opens the model library, and the quiet
/// link "Modelle verwalten" right under it. Without an installed model the
/// row keeps the same shape: the dropdown reads "Nicht installiert" and
/// offers only the download, so the speech and the text row look alike in
/// every state. Installing and removing stay in the library (#1514).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/model_library.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_button.dart';
import '../sections/model_library_section.dart' show activateLibraryModel;
import '../settings_widgets.dart' show settingsDropdown;
import 'wp_settings_group.dart';

/// Row id of the library, the target of every way into it.
const String kModelLibraryRowId = 'models-library';

/// Dropdown value of the last entry, "Weitere Modelle herunterladen…".
const String kModelLibraryChoice = '__model-library__';

/// Opens Settings at the model library.
void openModelLibrary(WidgetRef ref) {
  ref.read(settingsScrollTargetProvider.notifier).set(kModelLibraryRowId);
  ref.read(activePageProvider.notifier).setPage('settings');
}

/// The models the dropdown offers: on this device, on disk and ready
/// (catalog and own models alike), plus the one in use or loading. In the
/// library's order, so both lists read the same.
List<ModelLibraryEntry> installedModelChoices(
  List<ModelLibraryEntry> entries,
) => [
  for (final entry in entries)
    if (entry.location == ModelLocation.local &&
        (entry.canActivate ||
            entry.status == ModelLibraryStatus.active ||
            entry.status == ModelLibraryStatus.loading))
      entry,
];

/// The entry the dropdown shows as chosen: the one in use or loading, else
/// none (the chosen model is not on disk; the dropdown then shows its hint).
ModelLibraryEntry? shownModelChoice(List<ModelLibraryEntry> choices) => choices
    .where(
      (entry) =>
          entry.status == ModelLibraryStatus.active ||
          entry.status == ModelLibraryStatus.loading,
    )
    .firstOrNull;

/// Label of one dropdown entry: the model name, and "Empfohlen" on the
/// recommendation.
String modelChoiceLabel(L10n l10n, ModelLibraryEntry entry) => entry.recommended
    ? '${entry.name(l10n)} · ${l10n.settingsSttEngineRecommended}'
    : entry.name(l10n);

/// "Sprachmodell" in the speech settings (row `stt-model`).
class SpeechModelChoiceRow extends ConsumerWidget {
  const SpeechModelChoiceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ModelChoiceRow(
    rowId: 'stt-model',
    testIdPrefix: 'settings-speech',
    title: L10n.of(context).settingsSttEngine,
    entries: ref.watch(speechLibraryEntriesProvider),
  );
}

/// "Textmodell" on the Smart Mode page (row `text-smart-mode-model`), shown
/// while Smart Mode runs on this device. Its explanation line gives the
/// processing time, like "Modell geladen halten" under the speech model.
class TextModelChoiceRow extends ConsumerWidget {
  const TextModelChoiceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ModelChoiceRow(
    rowId: 'text-smart-mode-model',
    testIdPrefix: 'settings-smart-mode',
    title: L10n.of(context).settingsSmartModeTextModel,
    subtitle: L10n.of(context).smartModeSpeedExampleInfo,
    entries: ref.watch(smartModeLibraryEntriesProvider),
  );
}

/// The shared row behind [SpeechModelChoiceRow] and [TextModelChoiceRow].
/// Test ids: `<testIdPrefix>-model-choice` (items
/// `<testIdPrefix>-model-choice-item-<id>`, the library entry
/// `-item-$kModelLibraryChoice`), `-manage-models`.
class ModelChoiceRow extends ConsumerWidget {
  const ModelChoiceRow({
    super.key,
    required this.rowId,
    required this.testIdPrefix,
    required this.title,
    required this.entries,
    this.subtitle,
  });

  final String rowId;
  final String testIdPrefix;
  final String title;

  /// Optional explanation line under the title.
  final String? subtitle;

  /// The library entries of this kind; the row offers the installed ones.
  final List<ModelLibraryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final choices = installedModelChoices(entries);
    final shown = shownModelChoice(choices);
    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        settingsDropdown(
          context: context,
          testId: '$testIdPrefix-model-choice',
          keyPrefix: '$testIdPrefix-model-choice',
          value: shown?.id,
          // Nothing installed: the dropdown says so in its hint and its only
          // entry leads to the download.
          hint: choices.isEmpty ? l10n.modelLibraryStatusNotInstalled : null,
          items: [for (final entry in choices) entry.id, kModelLibraryChoice],
          labels: [
            for (final entry in choices) modelChoiceLabel(l10n, entry),
            choices.isEmpty
                ? l10n.settingsSpeechModelDownload
                : l10n.settingsSpeechModelMore,
          ],
          onChanged: (id) {
            if (id == null || id == shown?.id) return;
            if (id == kModelLibraryChoice) {
              openModelLibrary(ref);
              return;
            }
            final entry = choices.firstWhere((entry) => entry.id == id);
            unawaited(activateLibraryModel(context, ref, entry));
          },
        ),
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          testId: '$testIdPrefix-manage-models',
          label: l10n.modelLibraryManage,
          variant: WpButtonVariant.ghost,
          onPressed: () => openModelLibrary(ref),
        ),
      ],
    );
    return WpSettingsRow(
      rowId: rowId,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
