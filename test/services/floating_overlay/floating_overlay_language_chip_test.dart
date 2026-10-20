/// Sprach-Chip des Aufnahme-Overlays (SW-10).
///
/// Der Chip zeigt die Sprache, mit der die laufende Aufnahme tatsächlich
/// arbeitet ([recordingLanguageProvider], vom Orchestrator gesetzt): die
/// eingefrorene Startsprache (SW-03), ersetzt durch die Profilsprache der
/// Ziel-App (SW-07) genau einmal. Settings-Änderungen während der Aufnahme
/// erreichen den Chip nicht.
///
/// Die Naht ist dieselbe wie in `floating_overlay_service_target_test`: ein
/// [FloatingOverlayController]-Fake, der den letzten Schnappschuss festhält,
/// eine In-Memory-[SettingsNotifier] und `package:fake_async`.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_choice.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/snippets/interactive_snippet_controller.dart';

class _FakeController implements FloatingOverlayController {
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  FloatingOverlaySnapshot? lastSnapshot;

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    lastSnapshot = snapshot;
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(
    double x,
    double y,
    OverlayAnchorMode anchor,
  ) async {}

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {}

  @override
  Future<void> dispose() async {
    await _eventCtrl.close();
  }
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});
  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

class _FakeInteractiveSnippetNotifier extends InteractiveSnippetController {}

/// In-Memory-[SettingsNotifier] mit festem Ausgangsstand, damit weder SQLite
/// noch der sichere Speicher angefasst werden.
class _CapturingSettingsNotifier extends SettingsNotifier {
  _CapturingSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? _initial;
    state = AsyncData(updater(current));
  }
}

/// Mikrofon offen, damit die Aufnahmeinhalte (und der Chip) gezeigt werden.
class _MicOpenAudioNotifier extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus(
    captureState: AudioCaptureState.recording,
    hasLiveSamples: true,
  );
}

AppSettings _settings(String language) => AppSettings(
  stt: SttSettings(model: 'whisper-small', language: language),
);

class _Harness {
  _Harness(this.fake, this.container);
  final _FakeController fake;
  final ProviderContainer container;

  FloatingOverlaySnapshot get snapshot => fake.lastSnapshot!;

  void setSettingsLanguage(String language) {
    container
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            stt: SttSettings(model: 'whisper-small', language: language),
          ),
        );
  }

  void dispose() => container.dispose();
}

/// A profile choice held in memory, so the test never touches preferences.
class _FixedProfileChoice extends ProfileChoiceController {
  _FixedProfileChoice(this._initial);

  final ProfileChoice _initial;

  @override
  ProfileChoice build() => _initial;

  void setChoice(ProfileChoice choice) => state = choice;
}

_Harness _build(
  FakeAsync async, {
  required String globalLanguage,
  ProfileChoice choice = const ProfileChoiceAutomatic(),
  List<AppProfile> profiles = const [],
}) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _FakeController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _CapturingSettingsNotifier(_settings(globalLanguage)),
      ),
      audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
      interactiveSnippetControllerProvider.overrideWith(
        _FakeInteractiveSnippetNotifier.new,
      ),
      profileChoiceProvider.overrideWith(() => _FixedProfileChoice(choice)),
      appProfilesProvider.overrideWith(() => _FixedProfiles(profiles)),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return _Harness(fake, container);
}

/// Startet eine Aufnahme wie der Orchestrator: die Sitzungssprache wird
/// gesetzt, bevor die Phase auf „Aufnahme“ wechselt.
void _startRecording(_Harness h, FakeAsync async, {String? sessionLanguage}) {
  if (sessionLanguage != null) {
    h.container.read(recordingLanguageProvider.notifier).set(sessionLanguage);
  }
  h.container.read(recordingProvider.notifier).startRecording();
  async.elapse(const Duration(milliseconds: 5));
  async.flushMicrotasks();
}

/// Serves a fixed profile list in tests, without touching the database.
class _FixedProfiles extends AppProfilesController {
  _FixedProfiles(this._profiles);
  final List<AppProfile> _profiles;

  @override
  Future<List<AppProfile>> build() async => _profiles;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sprach-Chip im Aufnahme-Overlay (SW-10)', () {
    test('zeigt die Profilsprache der Ziel-App, nicht die globale Sprache', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'de');
        try {
          _startRecording(h, async, sessionLanguage: 'en');

          expect(h.snapshot.languageChip, 'EN');
        } finally {
          h.dispose();
        }
      });
    });

    test('zeigt bei einem Override die Override-Sprache', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'de');
        try {
          _startRecording(h, async, sessionLanguage: 'fr');

          expect(h.snapshot.languageChip, 'FR');
        } finally {
          h.dispose();
        }
      });
    });

    test('bleibt bei einem Settings-Wechsel während der Aufnahme', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'de');
        try {
          _startRecording(h, async, sessionLanguage: 'de');
          expect(h.snapshot.languageChip, 'DE');

          h.setSettingsLanguage('en');
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          expect(h.snapshot.languageChip, 'DE');
        } finally {
          h.dispose();
        }
      });
    });

    test('aktualisiert sich einmal, wenn die Profilsprache später eintrifft, '
        'und danach nicht mehr', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'de');
        try {
          _startRecording(h, async, sessionLanguage: 'de');
          expect(h.snapshot.languageChip, 'DE');

          // Late profile resolution: the orchestrator sets the language once.
          h.container.read(recordingLanguageProvider.notifier).set('en');
          async.flushMicrotasks();
          expect(h.snapshot.languageChip, 'EN');

          // Nothing afterwards moves the chip again.
          h.setSettingsLanguage('fr');
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();
          expect(h.snapshot.languageChip, 'EN');
        } finally {
          h.dispose();
        }
      });
    });

    test('zeigt bei Auto keinen Chip', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'auto');
        try {
          _startRecording(h, async, sessionLanguage: 'auto');

          expect(h.snapshot.languageChip, isNull);
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('Profil-Chip im Aufnahme-Overlay (Ticket 13, Teil 3)', () {
    const mail = AppProfile(id: 'mail', name: 'Mail');

    test('zeigt den Namen des gewählten Profils', () {
      FakeAsync().run((async) {
        final h = _build(
          async,
          globalLanguage: 'de',
          choice: const ProfileChoiceProfile('mail'),
          profiles: const [mail],
        );
        try {
          _startRecording(h, async, sessionLanguage: 'de');

          expect(h.snapshot.profileChip, 'Mail');
          expect(h.snapshot.languageChip, 'DE');
        } finally {
          h.dispose();
        }
      });
    });

    test('zeigt bei einer automatischen Wahl kein Profil', () {
      FakeAsync().run((async) {
        final h = _build(async, globalLanguage: 'de', profiles: const [mail]);
        try {
          _startRecording(h, async, sessionLanguage: 'de');

          expect(h.snapshot.profileChip, isNull);
        } finally {
          h.dispose();
        }
      });
    });

    test('zeigt kein Profil im Leerlauf, auch bei gewähltem Profil', () {
      FakeAsync().run((async) {
        final h = _build(
          async,
          globalLanguage: 'de',
          choice: const ProfileChoiceProfile('mail'),
          profiles: const [mail],
        );
        try {
          async.flushMicrotasks();

          expect(h.snapshot.profileChip, isNull);
        } finally {
          h.dispose();
        }
      });
    });
  });
}
