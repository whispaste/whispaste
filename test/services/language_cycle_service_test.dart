import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/language_cycle_service.dart';

class _InMemorySettings extends SettingsNotifier {
  _InMemorySettings(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? _initial;
    state = AsyncData(updater(current));
  }
}

ProviderContainer _container({required RecordingPhase phase}) {
  const settings = AppSettings(
    stt: SttSettings(
      model: 'whisper-small',
      language: 'de',
      favoriteLanguages: ['de', 'en'],
    ),
  );
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _InMemorySettings(settings)),
      recordingPhaseProvider.overrideWith((ref) => phase),
    ],
  );
}

void main() {
  group('next-favorite-language hotkey feedback (SW-01)', () {
    test('a press during a recording says the language applies from the next '
        'recording', () async {
      final container = _container(phase: RecordingPhase.recording);
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container.read(languageCycleFeedbackProvider.notifier).cycle();

      final feedback = container.read(languageCycleFeedbackProvider);
      expect(feedback?.language, 'en');
      expect(feedback?.duringRecording, isTrue);
    });

    test('a press while idle is a plain switch', () async {
      final container = _container(phase: RecordingPhase.idle);
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container.read(languageCycleFeedbackProvider.notifier).cycle();

      final feedback = container.read(languageCycleFeedbackProvider);
      expect(feedback?.language, 'en');
      expect(feedback?.duringRecording, isFalse);
    });
  });

  group('hotkey of one favorite language (#2137)', () {
    test(
      'switches straight to that language, with the same feedback',
      () async {
        final container = _container(phase: RecordingPhase.idle);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        await container
            .read(languageCycleFeedbackProvider.notifier)
            .switchTo('en');

        expect(container.read(settingsProvider).value?.stt.language, 'en');
        expect(container.read(languageCycleFeedbackProvider)?.language, 'en');
      },
    );

    test('a language that is no favorite is ignored', () async {
      final container = _container(phase: RecordingPhase.idle);
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container
          .read(languageCycleFeedbackProvider.notifier)
          .switchTo('ru');

      expect(container.read(settingsProvider).value?.stt.language, 'de');
      expect(container.read(languageCycleFeedbackProvider), isNull);
    });
  });
}
