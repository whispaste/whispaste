/// The "Erste Schritte" card's behaviour, found by testID: an item action leads
/// to its place, a recording sent to another app checks off the first step,
/// the card hides during a recording, and closing it writes the dismissal. Layout and wording are not checked here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/first_steps/first_steps_card.dart';
import 'package:whispaste/features/first_steps/first_steps_watcher.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _initial));
  }
}

class _SettableRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void setPhase(RecordingPhase phase) => state = RecordingState(phase: phase);
}

AppSettings _armed({String done = ''}) => AppSettings.defaults.copyWithSections(
  onboarding: OnboardingSettings(firstStepsArmed: true, firstStepsDone: done),
);

HistoryEntry _dictation(String id, {String? targetApp}) => HistoryEntry(
  id: id,
  content: 'text',
  title: '',
  timestamp: DateTime(2026, 10, 30, 12),
  durationSec: 1,
  processingDurationSec: 0,
  language: 'de',
  languageHint: '',
  tags: '',
  pinned: false,
  source: 'dictation',
  model: 'whisper',
  isLocal: true,
  costUsd: 0,
  archived: false,
  titleEdited: false,
  colorSlot: 0,
  targetApp: targetApp,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required AppSettings settings,
  List<HistoryEntry> history = const [],
}) async {
  await tester.pumpWidget(
    makeTestable(
      const Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [FirstStepsWatcher(), FirstStepsCard()]),
        ),
      ),
      size: const Size(900, 1200),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
        recordingProvider.overrideWith(_SettableRecording.new),
        historyEntriesProvider.overrideWith((ref) => Stream.value(history)),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FirstStepsCard)));
}

Finder _byId(String id) => find.byKey(ValueKey<String>(id));

void main() {
  testWidgets('the first-paste action opens the hotkey row in Settings', (
    tester,
  ) async {
    final container = await _pump(tester, settings: _armed());

    await tester.tap(
      find.bySemanticsIdentifier('home-first-steps-item-first_paste-action'),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'settings');
    expect(
      container.read(settingsScrollTargetProvider),
      'general-hotkey-dictation',
    );
  });

  testWidgets('the copy action opens the recordings', (tester) async {
    final container = await _pump(tester, settings: _armed());

    await tester.tap(
      find.bySemanticsIdentifier('home-first-steps-item-copy_recording-action'),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'history');
  });

  testWidgets('the personalize action opens the dictionary', (tester) async {
    final container = await _pump(tester, settings: _armed());

    await tester.tap(
      find.bySemanticsIdentifier('home-first-steps-item-personalize-action'),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'replacements');
  });

  testWidgets('the note action opens the notes', (tester) async {
    final container = await _pump(tester, settings: _armed());

    await tester.tap(
      find.bySemanticsIdentifier('home-first-steps-item-note_dictation-action'),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'notes');
  });

  testWidgets('a recording sent to another app checks off the first step', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      settings: _armed(),
      history: [
        _dictation('a', targetApp: 'de.whispaste.app'),
        _dictation('b', targetApp: 'Warp-Stable'),
      ],
    );

    expect(
      container.read(settingsProvider).value!.onboarding.firstStepsDone,
      'first_paste',
    );
  });

  testWidgets('recordings only inside WhisPaste check off nothing', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      settings: _armed(),
      history: [
        _dictation('a', targetApp: 'de.whispaste.app'),
        _dictation('b'),
      ],
    );

    expect(
      container.read(settingsProvider).value!.onboarding.firstStepsDone,
      isEmpty,
    );
  });

  testWidgets('the card is hidden for the whole recording', (tester) async {
    final container = await _pump(tester, settings: _armed());
    expect(_byId('home-first-steps'), findsOneWidget);

    (container.read(recordingProvider.notifier) as _SettableRecording).setPhase(
      RecordingPhase.recording,
    );
    await tester.pumpAndSettle();
    expect(_byId('home-first-steps'), findsNothing);

    (container.read(recordingProvider.notifier) as _SettableRecording).setPhase(
      RecordingPhase.idle,
    );
    await tester.pumpAndSettle();
    expect(_byId('home-first-steps'), findsOneWidget);
  });

  testWidgets('closing the card writes the dismissal and keeps progress', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      settings: _armed(done: 'first_paste'),
    );

    await tester.tap(find.bySemanticsIdentifier('home-first-steps-close'));
    await tester.pumpAndSettle();

    expect(_byId('home-first-steps'), findsNothing);
    final onboarding = container.read(settingsProvider).value!.onboarding;
    expect(onboarding.firstStepsDismissed, isTrue);
    expect(onboarding.firstStepsDone, 'first_paste');
  });

  testWidgets('an existing install never sees the card', (tester) async {
    await _pump(tester, settings: AppSettings.defaults);
    expect(_byId('home-first-steps'), findsNothing);
  });
}
