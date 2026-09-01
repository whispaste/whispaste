/// Ziel-Anzeige des schwebenden Aufnahme-Overlays (Ticket 25).
///
/// Sperrt fest, dass ein Vorgang mit Ziel [RecordingTarget.quickNote] im
/// Overlay als solcher erkennbar ist — während der Aufnahme und in der
/// Abschluss-Meldung — und dass ein Vorgang mit Ziel
/// [RecordingTarget.clipboard] Wort für Wort so bleibt wie bisher.
///
/// Die Naht ist dieselbe wie in `floating_overlay_service_interaction_test`:
/// ein [FloatingOverlayController]-Fake, der den letzten Schnappschuss
/// festhält, plus eine In-Memory-[SettingsNotifier] und `package:fake_async`.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/snippets/interactive_snippet_controller.dart';

// ── Fake interactive-snippet session notifier ────────────────────────────────

/// Lets a test set the session state directly, without driving a real
/// `InteractiveSnippetController.start()` sequence (which would need a fully
/// wired `RecordingOrchestrator` this lightweight harness doesn't build).
class _FakeInteractiveSnippetNotifier extends InteractiveSnippetController {
  void setSession(InteractiveSnippetSessionState? session) {
    state = session;
  }
}

// ── Fake controller ───────────────────────────────────────────────────────────

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

/// In-Memory-[SettingsNotifier] mit einem festen Ausgangsstand, damit weder
/// SQLite noch der sichere Speicher angefasst werden.
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

class _Harness {
  _Harness(this.fake, this.container);
  final _FakeController fake;
  final ProviderContainer container;

  FloatingOverlaySnapshot get snapshot => fake.lastSnapshot!;

  void dispose() => container.dispose();
}

/// Dieselbe Sprachauflösung wie im Dienst — der Test hängt damit nicht an der
/// Systemsprache der Testmaschine.
L10n get _l10n {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  try {
    return lookupL10n(locale);
  } catch (_) {
    return lookupL10n(const Locale('en'));
  }
}

const _quickNoteHotkey = QuickNoteHotkeySettings(
  quickNoteHotkeyEnabled: true,
  quickNoteHotkeyKey: 'Y',
  quickNoteHotkeyModifiers: 'ctrl+shift',
);

AppSettings _settings({
  FloatingOverlaySize size = FloatingOverlaySize.normal,
  String afterTranscription = 'paste',
  QuickNoteHotkeySettings quickNote = _quickNoteHotkey,
  HotkeySettings hotkey = const HotkeySettings(),
}) => AppSettings(
  overlay: OverlaySettings(overlaySize: size.value),
  afterTranscriptionSection: AfterTranscriptionSettings(
    afterTranscription: afterTranscription,
  ),
  quickNoteHotkey: quickNote,
  hotkey: hotkey,
);

_Harness _build(FakeAsync async, {AppSettings? settings}) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _FakeController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _CapturingSettingsNotifier(settings ?? _settings()),
      ),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
      interactiveSnippetControllerProvider.overrideWith(
        _FakeInteractiveSnippetNotifier.new,
      ),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return _Harness(fake, container);
}

void _record(
  _Harness h,
  FakeAsync async, {
  required RecordingTarget target,
  bool toCompletion = false,
}) {
  h.container.read(recordingTargetProvider.notifier).set(target);
  final rec = h.container.read(recordingProvider.notifier);
  rec.startRecording();
  async.elapse(const Duration(milliseconds: 5));
  async.flushMicrotasks();
  if (!toCompletion) return;
  rec.stopRecording();
  async.elapse(const Duration(milliseconds: 5));
  rec.completeTranscription('hallo welt');
  async.elapse(const Duration(milliseconds: 5));
  async.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Aufnahme mit Ziel Schnellnotiz', () {
    test('benennt das Ziel im Sprachausgabe-Text (label)', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(h, async, target: RecordingTarget.quickNote);

          expect(h.snapshot.state, OverlayVisualState.recording);
          expect(h.snapshot.label, _l10n.overlayRecordingQuickNote);
          expect(h.snapshot.label, isNot(_l10n.overlayRecording));
        } finally {
          h.dispose();
        }
      });
    });

    test('benennt das Ziel im sichtbaren Text der normalen Größe', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(h, async, target: RecordingTarget.quickNote);

          expect(h.snapshot.elapsed, contains(_l10n.overlayTargetQuickNote));
          // Der Zeitzähler bleibt in der normalen Größe erhalten.
          expect(h.snapshot.elapsed, contains('0:0'));
        } finally {
          h.dispose();
        }
      });
    });

    test('verkürzt den sichtbaren Text in kompakt und mini auf das Ziel', () {
      for (final size in [
        FloatingOverlaySize.compact,
        FloatingOverlaySize.mini,
      ]) {
        FakeAsync().run((async) {
          final h = _build(async, settings: _settings(size: size));
          try {
            _record(h, async, target: RecordingTarget.quickNote);

            expect(
              h.snapshot.elapsed,
              _l10n.overlayTargetQuickNote,
              reason:
                  'Größe ${size.value}: nur das Ziel, sonst frisst der Text '
                  'die Wellenform auf',
            );
          } finally {
            h.dispose();
          }
        });
      }
    });

    test('nennt im Stopp-Hinweis die Schnellnotiz-Kombination', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(h, async, target: RecordingTarget.quickNote);

          final expected = formatHotkeyShortcut(
            _quickNoteHotkey.quickNoteHotkeyModifiers,
            _quickNoteHotkey.quickNoteHotkeyKey,
            l10n: _l10n,
            displayOverride: _quickNoteHotkey.quickNoteHotkeyKeyDisplay,
          );
          expect(h.snapshot.hint, _l10n.overlayKeyboardHint(expected));

          final mainHotkey = formatHotkeyShortcut(
            const AppSettings().hotkeyModifiers,
            const AppSettings().hotkeyKey,
            l10n: _l10n,
          );
          expect(h.snapshot.hint, isNot(contains(mainHotkey)));
        } finally {
          h.dispose();
        }
      });
    });

    test('lässt den Stopp-Hinweis leer, wenn der Hotkey aus ist', () {
      FakeAsync().run((async) {
        final h = _build(
          async,
          settings: _settings(quickNote: const QuickNoteHotkeySettings()),
        );
        try {
          _record(h, async, target: RecordingTarget.quickNote);

          expect(h.snapshot.hint, isEmpty);
        } finally {
          h.dispose();
        }
      });
    });

    test('behauptet in der Abschluss-Meldung kein Einfügen', () {
      FakeAsync().run((async) {
        // afterTranscription: 'paste' — die alte Ableitung hätte hier
        // „Eingefügt" gemeldet, obwohl nichts eingefügt wurde.
        final h = _build(async);
        try {
          _record(
            h,
            async,
            target: RecordingTarget.quickNote,
            toCompletion: true,
          );

          expect(h.snapshot.state, OverlayVisualState.done);
          expect(h.snapshot.doneMessage, _l10n.overlayDoneQuickNote);
          expect(h.snapshot.doneMessage, isNot(_l10n.overlayDonePasted));
          expect(h.snapshot.doneMessage, isNot(_l10n.overlayDone));
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('Aufnahme eines interaktiven Snippet-Feldes', () {
    test('zeigt die Sprich-jetzt-Anweisung im sichtbaren Text der normalen '
        'Größe (vorher: nur der bloße Zeitzähler, siehe WpOverlayPainter '
        '"_isRecording ? timerText : statusText")', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          (h.container.read(interactiveSnippetControllerProvider.notifier)
                  as _FakeInteractiveSnippetNotifier)
              .setSession(
                const InteractiveSnippetSessionState(
                  fieldIndex: 0,
                  fieldCount: 2,
                  fieldName: 'Vorname',
                ),
              );
          _record(h, async, target: RecordingTarget.templateField);

          final expectedLabel = _l10n.interactiveSnippetSpeakNowLabel(
            'Vorname',
            1,
            2,
          );
          expect(h.snapshot.elapsed, contains(expectedLabel));
          // Der Zeitzähler bleibt in der normalen Größe erhalten.
          expect(h.snapshot.elapsed, contains('0:0'));
        } finally {
          h.dispose();
        }
      });
    });

    test('verkürzt den sichtbaren Text in kompakt und mini auf das Feld', () {
      for (final size in [
        FloatingOverlaySize.compact,
        FloatingOverlaySize.mini,
      ]) {
        FakeAsync().run((async) {
          final h = _build(async, settings: _settings(size: size));
          try {
            (h.container.read(interactiveSnippetControllerProvider.notifier)
                    as _FakeInteractiveSnippetNotifier)
                .setSession(
                  const InteractiveSnippetSessionState(
                    fieldIndex: 1,
                    fieldCount: 2,
                    fieldName: 'Nachname',
                  ),
                );
            _record(h, async, target: RecordingTarget.templateField);

            expect(
              h.snapshot.elapsed,
              _l10n.interactiveSnippetSpeakNowLabel('Nachname', 2, 2),
              reason:
                  'Größe ${size.value}: nur das Feld, sonst frisst der Text '
                  'die Wellenform auf',
            );
          } finally {
            h.dispose();
          }
        });
      }
    });

    test('nennt im Hinweis Enter und Esc zusätzlich zum Haupt-Hotkey', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          (h.container.read(interactiveSnippetControllerProvider.notifier)
                  as _FakeInteractiveSnippetNotifier)
              .setSession(
                const InteractiveSnippetSessionState(
                  fieldIndex: 0,
                  fieldCount: 2,
                  fieldName: 'Vorname',
                ),
              );
          _record(h, async, target: RecordingTarget.templateField);

          final mainHotkey = formatHotkeyShortcut(
            const AppSettings().hotkeyModifiers,
            const AppSettings().hotkeyKey,
            l10n: _l10n,
          );
          expect(
            h.snapshot.hint,
            _l10n.overlayKeyboardHintNextFieldEnter(mainHotkey),
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('nennt im Hinweis nur Enter/Esc, wenn der Haupt-Hotkey aus ist '
        '(die sequenz-gebundenen Tasten funktionieren trotzdem)', () {
      FakeAsync().run((async) {
        final h = _build(
          async,
          settings: _settings(
            hotkey: const HotkeySettings(hotkeyEnabled: false),
          ),
        );
        try {
          (h.container.read(interactiveSnippetControllerProvider.notifier)
                  as _FakeInteractiveSnippetNotifier)
              .setSession(
                const InteractiveSnippetSessionState(
                  fieldIndex: 0,
                  fieldCount: 2,
                  fieldName: 'Vorname',
                ),
              );
          _record(h, async, target: RecordingTarget.templateField);

          expect(h.snapshot.hint, _l10n.overlayKeyboardHintNextFieldEnterOnly);
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('Ansage-Vorlauf eines interaktiven Snippet-Feldes', () {
    _FakeInteractiveSnippetNotifier notifier(_Harness h) =>
        h.container.read(interactiveSnippetControllerProvider.notifier)
            as _FakeInteractiveSnippetNotifier;

    test('zeigt die Ansage in allen drei Größen als prominenten Text '
        '(transcribing-Komposition — die einzige, die in jeder Größe Text '
        'malt)', () {
      for (final size in [
        FloatingOverlaySize.normal,
        FloatingOverlaySize.compact,
        FloatingOverlaySize.mini,
      ]) {
        FakeAsync().run((async) {
          final h = _build(async, settings: _settings(size: size));
          try {
            notifier(h).setSession(
              const InteractiveSnippetSessionState(
                fieldIndex: 1,
                fieldCount: 3,
                fieldName: 'Betreff',
                announcing: true,
              ),
            );
            async.flushMicrotasks();

            expect(
              h.snapshot.visible,
              isTrue,
              reason: 'Größe ${size.value}: Ansage muss sichtbar sein',
            );
            expect(h.snapshot.state, OverlayVisualState.transcribing);
            expect(
              h.snapshot.label,
              _l10n.interactiveSnippetAnnounceLabel(2, 3, 'Betreff'),
            );
          } finally {
            h.dispose();
          }
        });
      }
    });

    test('versteckt das Overlay, wenn die Sequenz während der ersten Ansage '
        'abgebrochen wird (Phase bleibt idle — kein Phasenwechsel würde je '
        'verstecken)', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          notifier(h).setSession(
            const InteractiveSnippetSessionState(
              fieldIndex: 0,
              fieldCount: 2,
              fieldName: 'Vorname',
              announcing: true,
            ),
          );
          async.flushMicrotasks();
          expect(h.snapshot.visible, isTrue);

          notifier(h).setSession(null);
          async.flushMicrotasks();

          expect(h.snapshot.visible, isFalse);
        } finally {
          h.dispose();
        }
      });
    });

    test('eine Aufnahme im Anschluss an die Ansage übermalt sie ganz '
        'normal', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          notifier(h).setSession(
            const InteractiveSnippetSessionState(
              fieldIndex: 0,
              fieldCount: 2,
              fieldName: 'Vorname',
              announcing: true,
            ),
          );
          async.flushMicrotasks();
          expect(h.snapshot.state, OverlayVisualState.transcribing);

          notifier(h).setSession(
            const InteractiveSnippetSessionState(
              fieldIndex: 0,
              fieldCount: 2,
              fieldName: 'Vorname',
            ),
          );
          _record(h, async, target: RecordingTarget.templateField);

          expect(h.snapshot.state, OverlayVisualState.recording);
          expect(
            h.snapshot.elapsed,
            contains(_l10n.interactiveSnippetSpeakNowLabel('Vorname', 1, 2)),
          );
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('Aufnahme mit Ziel Zwischenablage bleibt unverändert', () {
    test('Beschriftung, Zeitzähler und Hinweis wie bisher', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(h, async, target: RecordingTarget.clipboard);

          expect(h.snapshot.label, _l10n.overlayRecording);
          expect(h.snapshot.elapsed, '0:00');
          expect(
            h.snapshot.hint,
            _l10n.overlayKeyboardHint(
              formatHotkeyShortcut(
                const AppSettings().hotkeyModifiers,
                const AppSettings().hotkeyKey,
                l10n: _l10n,
              ),
            ),
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('Abschluss-Meldung folgt weiter der Auto-Einfügen-Einstellung', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(
            h,
            async,
            target: RecordingTarget.clipboard,
            toCompletion: true,
          );

          expect(h.snapshot.doneMessage, _l10n.overlayDonePasted);
        } finally {
          h.dispose();
        }
      });
    });

    test('nach einem Schnellnotiz-Vorgang zeigt der nächste Vorgang wieder die '
        'Zwischenablage-Texte', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          _record(
            h,
            async,
            target: RecordingTarget.quickNote,
            toCompletion: true,
          );
          expect(h.snapshot.doneMessage, _l10n.overlayDoneQuickNote);

          h.container.read(recordingProvider.notifier).reset();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          _record(
            h,
            async,
            target: RecordingTarget.clipboard,
            toCompletion: true,
          );

          expect(h.snapshot.doneMessage, _l10n.overlayDonePasted);
        } finally {
          h.dispose();
        }
      });
    });

    test('lässt den Stopp-Hinweis leer, wenn der Haupt-Hotkey aus ist', () {
      // Der Hinweis-Zweig wurde für Ticket 25 umgebaut; dieser Fall sperrt,
      // dass der abgeschaltete Haupt-Hotkey weiter zu einem leeren Hinweis
      // führt statt zu einer Kombination, die es gar nicht gibt.
      FakeAsync().run((async) {
        final h = _build(
          async,
          settings: _settings(
            hotkey: const HotkeySettings(hotkeyEnabled: false),
          ),
        );
        try {
          _record(h, async, target: RecordingTarget.clipboard);

          expect(h.snapshot.state, OverlayVisualState.recording);
          expect(h.snapshot.hint, isEmpty);
        } finally {
          h.dispose();
        }
      });
    });

    test('kompakte Größe behält den reinen Zeitzähler', () {
      FakeAsync().run((async) {
        final h = _build(
          async,
          settings: _settings(size: FloatingOverlaySize.compact),
        );
        try {
          _record(h, async, target: RecordingTarget.clipboard);

          expect(h.snapshot.elapsed, '0:00');
        } finally {
          h.dispose();
        }
      });
    });
  });
}
