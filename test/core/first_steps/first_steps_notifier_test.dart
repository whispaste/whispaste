/// The "Erste Schritte" notifier: confirmed items are written, nothing moves
/// during a recording, dismiss and "Neu anzeigen" keep the progress, and the
/// success state ends after its hold.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/first_steps/first_steps.dart';
import 'package:whispaste/core/first_steps/first_steps_notifier.dart';
import 'package:whispaste/core/recording/recording_state.dart';

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

/// Recording notifier whose phase a test can move on demand.
class _SettableRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void setPhase(RecordingPhase phase) => state = RecordingState(phase: phase);
}

AppSettings _armed({
  bool dismissed = false,
  String done = '',
  String vocabulary = '',
}) => AppSettings.defaults.copyWithSections(
  onboarding: OnboardingSettings(
    firstStepsArmed: true,
    firstStepsDismissed: dismissed,
    firstStepsDone: done,
  ),
  stt: AppSettings.defaults.stt.copyWith(customVocabulary: vocabulary),
);

/// A container with the settings resolved, inside the caller's fake clock.
ProviderContainer _container(FakeAsync async, AppSettings settings) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      recordingProvider.overrideWith(_SettableRecording.new),
    ],
  );
  addTearDown(container.dispose);
  container.read(settingsProvider);
  async.flushMicrotasks();
  return container;
}

_SettableRecording _recording(ProviderContainer container) =>
    container.read(recordingProvider.notifier) as _SettableRecording;

OnboardingSettings _onboarding(ProviderContainer container) =>
    container.read(settingsProvider).value!.onboarding;

void main() {
  test('an existing install writes nothing', () {
    fakeAsync((async) {
      final container = _container(async, AppSettings.defaults);
      _recording(container).setPhase(RecordingPhase.done);
      container
          .read(firstStepsNotifierProvider.notifier)
          .dictationFinished(pasted: true, toNote: false, transcript: 'Text');
      async.flushMicrotasks();
      expect(_onboarding(container).firstStepsDone, isEmpty);
      expect(container.read(firstStepsNotifierProvider), isFalse);
    });
  });

  test('a finished dictation into a note confirms the note step', () {
    fakeAsync((async) {
      final container = _container(async, _armed());
      _recording(container).setPhase(RecordingPhase.done);
      container
          .read(firstStepsNotifierProvider.notifier)
          .dictationFinished(pasted: false, toNote: true, transcript: 'Text');
      async.flushMicrotasks();
      expect(parseFirstStepsDone(_onboarding(container).firstStepsDone), {
        FirstStepsItem.noteDictation,
      });
    });
  });

  test('nothing changes while a recording runs', () {
    fakeAsync((async) {
      final container = _container(async, _armed());
      final recording = _recording(container);
      final notifier = container.read(firstStepsNotifierProvider.notifier);

      recording.setPhase(RecordingPhase.recording);
      notifier.dictationFinished(
        pasted: true,
        toNote: false,
        transcript: 'Text',
      );
      container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              stt: s.stt.copyWith(customVocabulary: 'Kubernetes'),
            ),
          );
      async.flushMicrotasks();
      notifier.reconcileVocabulary();
      async.flushMicrotasks();

      expect(_onboarding(container).firstStepsDone, isEmpty);

      // The watcher re-checks once the recording is over.
      recording.setPhase(RecordingPhase.idle);
      notifier.reconcileVocabulary();
      async.flushMicrotasks();
      expect(parseFirstStepsDone(_onboarding(container).firstStepsDone), {
        FirstStepsItem.personalize,
      });
    });
  });

  test('dismiss and "Neu anzeigen" keep the confirmed items', () {
    fakeAsync((async) {
      final container = _container(async, _armed(done: 'first_paste'));
      final notifier = container.read(firstStepsNotifierProvider.notifier);

      notifier.dismiss();
      async.flushMicrotasks();
      expect(_onboarding(container).firstStepsDismissed, isTrue);
      expect(_onboarding(container).firstStepsDone, 'first_paste');

      notifier.showAgain();
      async.flushMicrotasks();
      expect(_onboarding(container).firstStepsDismissed, isFalse);
      expect(_onboarding(container).firstStepsDone, 'first_paste');
    });
  });

  test('the last item starts a success state that ends after its hold', () {
    fakeAsync((async) {
      final container = _container(
        async,
        _armed(done: 'first_paste,copy_recording,note_dictation'),
      );
      final notifier = container.read(firstStepsNotifierProvider.notifier);

      notifier.reconcileVocabulary();
      async.flushMicrotasks();
      // Not yet: vocabulary is blank, so the last item is still open.
      expect(container.read(firstStepsNotifierProvider), isFalse);

      container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              stt: s.stt.copyWith(customVocabulary: 'Kubernetes'),
            ),
          );
      async.flushMicrotasks();
      notifier.reconcileVocabulary();
      async.flushMicrotasks();

      expect(container.read(firstStepsNotifierProvider), isTrue);
      async.elapse(kFirstStepsCelebration - const Duration(milliseconds: 1));
      expect(container.read(firstStepsNotifierProvider), isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(container.read(firstStepsNotifierProvider), isFalse);
    });
  });

  test('a closed card does not start the success state', () {
    fakeAsync((async) {
      final container = _container(
        async,
        _armed(
          dismissed: true,
          done: 'first_paste,long_dictation,overlay_look',
        ),
      );
      container.read(firstStepsNotifierProvider.notifier).reconcileVocabulary();
      async.flushMicrotasks();
      container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              stt: s.stt.copyWith(customVocabulary: 'Kubernetes'),
            ),
          );
      async.flushMicrotasks();
      container.read(firstStepsNotifierProvider.notifier).reconcileVocabulary();
      async.flushMicrotasks();
      expect(container.read(firstStepsNotifierProvider), isFalse);
    });
  });
}
