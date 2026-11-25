/// "Sprachmodell" (#2045) and "Textmodell" (#2175), one pattern: the dropdown
/// lists only installed models, its last entry and the link open the library,
/// picking an entry switches the model, and without an installed model the
/// row offers the download.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/model_library.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/widgets/model_choice_row.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';

import '../../../fixtures/test_helpers.dart';

SelectableSpeechModel _whisper(String id, SpeechModelState state) =>
    SelectableSpeechModel(
      engine: SpeechModelEngine.whisper,
      modelId: id,
      displayName: (_) => 'Whisper · $id',
      group: SpeechModelGroup.local,
      state: state,
    );

final _speech = [
  _whisper('small', const SpeechModelActive()),
  _whisper('large-v3-turbo', const SpeechModelReady()),
  _whisper('medium', const SpeechModelNotDownloaded()),
  _whisper('base', const SpeechModelDownloading(40)),
  SelectableSpeechModel(
    engine: SpeechModelEngine.openAI,
    modelId: SttProviderType.openAI.name,
    displayName: (_) => 'OpenAI',
    group: SpeechModelGroup.cloud,
    state: const SpeechModelReady(),
  ),
];

Finder _key(String id) => find.byKey(ValueKey(id));

void main() {
  test('only installed local models are offered, the active one shown', () {
    final choices = installedModelChoices(speechLibraryEntries(_speech));
    expect(choices.map((e) => e.id), ['small', 'large-v3-turbo']);
    expect(shownModelChoice(choices)?.id, 'small');
  });

  test('picking an installed entry switches the active Whisper model', () {
    final choices = installedModelChoices(speechLibraryEntries(_speech));
    final turbo = choices.firstWhere((e) => e.id == 'large-v3-turbo');
    final next = activateLibraryEntry(AppSettings.defaults, turbo);
    expect(next.sttProviderType.isLocal, isTrue);
    expect(next.onDeviceEngine, OnDeviceEngine.whisper);
    expect(next.effectiveModelId, 'large-v3-turbo');
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<SelectableSpeechModel> speech,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const SpeechModelChoiceRow(),
        locale: const Locale('en'),
        overrides: [
          speechLibraryEntriesProvider.overrideWith(
            (ref) => speechLibraryEntries(speech),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SpeechModelChoiceRow)),
    );
  }

  testWidgets('the last dropdown entry opens the model library', (
    tester,
  ) async {
    final container = await pump(tester, _speech);
    await tester.tap(_key('settings-speech-model-choice'));
    await tester.pumpAndSettle();
    expect(_key('settings-speech-model-choice-item-medium'), findsNothing);
    expect(_key('settings-speech-model-choice-item-openAI'), findsNothing);
    await tester.tap(
      _key('settings-speech-model-choice-item-$kModelLibraryChoice'),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsScrollTargetProvider), kModelLibraryRowId);
    expect(container.read(activePageProvider), 'settings');
  });

  testWidgets('without an installed model the same dropdown offers only the '
      'download', (tester) async {
    final container = await pump(tester, [
      _whisper('small', const SpeechModelNotDownloaded()),
    ]);
    expect(_key('settings-speech-manage-models'), findsOneWidget);
    await tester.tap(_key('settings-speech-model-choice'));
    await tester.pumpAndSettle();
    expect(_key('settings-speech-model-choice-item-small'), findsNothing);
    await tester.tap(
      _key('settings-speech-model-choice-item-$kModelLibraryChoice'),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsScrollTargetProvider), kModelLibraryRowId);
  });

  List<ModelLibraryEntry> textEntries({
    required bool downloaded,
    String provider = 'local',
    String openAiKey = '',
  }) => smartModeLibraryEntries(
    settings: AppSettings.defaults.copyWithSections(
      smartMode: AppSettings.defaults.smartMode.copyWith(provider: provider),
      cloudProvider: AppSettings.defaults.cloudProvider.copyWith(
        openAiApiKey: openAiKey,
      ),
    ),
    download: SmartModeDownloadState(modelDownloaded: downloaded),
    localEngineAvailable: true,
  );

  test('text models: only the installed local ones, never a cloud service', () {
    final choices = installedModelChoices(
      textEntries(downloaded: true, openAiKey: 'sk-test'),
    );
    expect(choices.map((e) => e.id), ['gemma']);
    expect(shownModelChoice(choices)?.id, 'gemma');
    expect(
      installedModelChoices(textEntries(downloaded: false, openAiKey: 'sk')),
      isEmpty,
    );
  });

  Future<ProviderContainer> pumpText(
    WidgetTester tester,
    List<ModelLibraryEntry> entries,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const TextModelChoiceRow(),
        locale: const Locale('en'),
        overrides: [
          smartModeLibraryEntriesProvider.overrideWith((ref) => entries),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(TextModelChoiceRow)),
    );
  }

  testWidgets('text models: the same dropdown, library entry and link', (
    tester,
  ) async {
    final container = await pumpText(tester, textEntries(downloaded: true));
    expect(find.text('Text model'), findsOneWidget);
    expect(find.text('Gemma 4 E2B · Recommended'), findsOneWidget);

    await tester.tap(_key('settings-smart-mode-manage-models'));
    await tester.pump();
    expect(container.read(settingsScrollTargetProvider), kModelLibraryRowId);
    expect(container.read(activePageProvider), 'settings');

    container.read(settingsScrollTargetProvider.notifier).set(null);
    await tester.tap(_key('settings-smart-mode-model-choice'));
    await tester.pumpAndSettle();
    expect(_key('settings-smart-mode-model-choice-item-gemma'), findsWidgets);
    await tester.tap(
      _key('settings-smart-mode-model-choice-item-$kModelLibraryChoice'),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsScrollTargetProvider), kModelLibraryRowId);
  });

  testWidgets('text models: without an installed model the same dropdown '
      'offers only the download', (tester) async {
    final container = await pumpText(tester, textEntries(downloaded: false));
    expect(_key('settings-smart-mode-manage-models'), findsOneWidget);
    await tester.tap(_key('settings-smart-mode-model-choice'));
    await tester.pumpAndSettle();
    expect(_key('settings-smart-mode-model-choice-item-gemma'), findsNothing);
    await tester.tap(
      _key('settings-smart-mode-model-choice-item-$kModelLibraryChoice'),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsScrollTargetProvider), kModelLibraryRowId);
  });
}
