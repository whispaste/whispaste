/// Snapshot-Mapping-Tests: RecordingPhase → FloatingOverlaySnapshot-Content.
///
/// Stellt sicher, dass derselbe Content plattformunabhängig und deterministisch
/// erzeugt wird (Issue 06 AC: Labels aus L10n, Elapsed-Format M:SS,
/// Done/Error-Messages, progress-Berechnung).
///
/// Alle Tests laufen ohne Widget-Pump (reine Dart-Unit-Tests), da sie nur die
/// Mapping-Logik und das public interface von [FloatingOverlayView.painterFor]
/// sowie [doneMessageFor] verifizieren.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

// ── Format-Hilfsfunktion (spiegelt FloatingOverlayService._formatElapsed) ──

/// Formatiert [elapsed] als `M:SS` (Minuten ohne führende Null,
/// Sekunden immer 2-stellig). Spiegelt die private Implementierung in
/// [FloatingOverlayService._formatElapsed] — der gemeinsame Formatkontrakt,
/// den alle Plattformen konsumieren müssen.
String _formatElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

// ── Snapshot-Builder ────────────────────────────────────────────────────────

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  bool isDark = true,
  bool compact = false,
  String elapsed = '',
  String? errorMessage,
  String? doneMessage,
  String label = '',
  double progress = 0.0,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    isDark: isDark,
    compact: compact,
    label: label,
    elapsed: elapsed,
    errorMessage: errorMessage,
    doneMessage: doneMessage,
    progress: progress,
  );
}

void main() {
  final l10n = L10nEn();

  // ── Elapsed-Format M:SS ──────────────────────────────────────────────────

  group('Elapsed-Format M:SS (deterministisch)', () {
    test('0 Sekunden → "0:00"', () {
      expect(_formatElapsed(Duration.zero), '0:00');
    });

    test('9 Sekunden → "0:09" (zweistellige Sekunden)', () {
      expect(_formatElapsed(const Duration(seconds: 9)), '0:09');
    });

    test('59 Sekunden → "0:59"', () {
      expect(_formatElapsed(const Duration(seconds: 59)), '0:59');
    });

    test('60 Sekunden → "1:00" (Minutenübertrag)', () {
      expect(_formatElapsed(const Duration(seconds: 60)), '1:00');
    });

    test('90 Sekunden → "1:30"', () {
      expect(_formatElapsed(const Duration(seconds: 90)), '1:30');
    });

    test('10 Minuten → "10:00" (keine führende Null bei Minuten)', () {
      expect(_formatElapsed(const Duration(minutes: 10)), '10:00');
    });

    test('painterFor leitet elapsed als timerText durch (recording)', () {
      // Verifiziert die Verdrahtung snapshot.elapsed → painter.timerText.
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          elapsed: '1:30',
          label: 'Recording',
          progress: 0.4,
        ),
      );
      expect(painter.timerText, '1:30');
    });

    test('elapsed ist leer für Nicht-recording-States', () {
      for (final state in [
        OverlayVisualState.transcribing,
        OverlayVisualState.done,
        OverlayVisualState.error,
      ]) {
        // Die Service-Logik: elapsed wird nur bei recording gesetzt.
        // painterFor leitet statusText aus label/doneMessage/errorMessage ab,
        // nicht aus elapsed.
        final painter = FloatingOverlayView.painterFor(
          snapshot: _snap(
            state,
            elapsed: '', // korrekt vom Service gesetzt
            label: 'Some label',
          ),
        );
        // timerText ist nicht leer (Painter nutzt statusText für non-recording).
        // Hier prüfen wir, dass elapsed='' korrekt durchgeleitet wird.
        expect(painter.timerText, isEmpty);
      }
    });
  });

  // ── L10n-Labels ─────────────────────────────────────────────────────────

  group('L10n-Labels (en)', () {
    test('overlayRecording Label stimmt', () {
      expect(l10n.overlayRecording, 'Recording');
    });

    test('overlayTranscribing Label stimmt', () {
      expect(l10n.overlayTranscribing, 'Transcribing…');
    });

    test('overlayError Label stimmt', () {
      expect(l10n.overlayError, 'Error');
    });

    test('overlayDoneReady Label stimmt', () {
      expect(l10n.overlayDoneReady, 'Done');
    });

    test('painterFor leitet label als statusText durch (transcribing)', () {
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.transcribing,
          label: l10n.overlayTranscribing,
        ),
      );
      expect(painter.statusText, l10n.overlayTranscribing);
    });
  });

  // ── Done/Error-Messages ──────────────────────────────────────────────────

  group('doneMessageFor — afterAction → L10n-Message', () {
    test('"paste" → overlayDonePasted ("Pasted")', () {
      expect(doneMessageFor('paste', l10n), l10n.overlayDonePasted);
      expect(l10n.overlayDonePasted, 'Pasted');
    });

    test('"clipboard" → overlayDone ("Copied")', () {
      expect(doneMessageFor('clipboard', l10n), l10n.overlayDone);
      expect(l10n.overlayDone, 'Copied');
    });

    test('"copy" → overlayDone ("Copied") — Alias', () {
      expect(doneMessageFor('copy', l10n), l10n.overlayDone);
    });

    test('"copy_and_paste" → overlayDoneBoth ("Copied & Pasted")', () {
      expect(doneMessageFor('copy_and_paste', l10n), l10n.overlayDoneBoth);
      expect(l10n.overlayDoneBoth, 'Copied & Pasted');
    });

    test('"clipboard_and_paste" → overlayDoneBoth — Alias', () {
      expect(doneMessageFor('clipboard_and_paste', l10n), l10n.overlayDoneBoth);
    });

    test('null / unbekannter Wert → overlayDoneReady ("Done")', () {
      expect(doneMessageFor(null, l10n), l10n.overlayDoneReady);
      expect(doneMessageFor('nothing', l10n), l10n.overlayDoneReady);
    });

    test('painterFor: doneMessage hat Vorrang vor label (done-State)', () {
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.done,
          doneMessage: l10n.overlayDonePasted,
          label: l10n.overlayDoneReady,
        ),
      );
      // Reihenfolge in painterFor: doneMessage ?? errorMessage ?? label
      expect(painter.statusText, l10n.overlayDonePasted);
    });

    test('painterFor: errorMessage hat Vorrang vor label (error-State)', () {
      const localisedError = 'Network timeout';
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.error,
          errorMessage: localisedError,
          label: l10n.overlayError,
        ),
      );
      expect(painter.statusText, localisedError);
    });

    test(
      'painterFor: label als Fallback wenn doneMessage/errorMessage null',
      () {
        final painter = FloatingOverlayView.painterFor(
          snapshot: _snap(
            OverlayVisualState.done,
            label: l10n.overlayDoneReady,
          ),
        );
        expect(painter.statusText, l10n.overlayDoneReady);
      },
    );
  });

  // ── Progress-Berechnung ──────────────────────────────────────────────────

  group('progress — Weitergabe und Berechnung', () {
    test('progress 0.4 → painter.progress = 0.4', () {
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          progress: 0.4,
          elapsed: '1:00',
          label: 'Recording',
        ),
      );
      expect(painter.progress, 0.4);
    });

    test('progress 0.0 → kein Timeline-Bereich (Unlimited)', () {
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          progress: 0.0,
          elapsed: '0:00',
          label: 'Recording',
        ),
      );
      expect(painter.progress, 0.0);
    });

    test('progress 1.0 (volle Dauer erreicht)', () {
      final painter = FloatingOverlayView.painterFor(
        snapshot: _snap(
          OverlayVisualState.recording,
          progress: 1.0,
          elapsed: '5:00',
          label: 'Recording',
        ),
      );
      expect(painter.progress, 1.0);
    });

    test('progress ist 0.0 für transcribing/done/error', () {
      for (final state in [
        OverlayVisualState.transcribing,
        OverlayVisualState.done,
        OverlayVisualState.error,
      ]) {
        final painter = FloatingOverlayView.painterFor(
          snapshot: _snap(state, progress: 0.0),
        );
        expect(
          painter.progress,
          0.0,
          reason: '${state.name} sollte progress=0',
        );
      }
    });
  });

  // ── State-Mapping ────────────────────────────────────────────────────────

  group('designStateFor — OverlayVisualState → OverlayDesignState', () {
    test('recording → recording', () {
      expect(
        FloatingOverlayView.designStateFor(OverlayVisualState.recording),
        OverlayDesignState.recording,
      );
    });

    test('transcribing → transcribing', () {
      expect(
        FloatingOverlayView.designStateFor(OverlayVisualState.transcribing),
        OverlayDesignState.transcribing,
      );
    });

    test('done → done', () {
      expect(
        FloatingOverlayView.designStateFor(OverlayVisualState.done),
        OverlayDesignState.done,
      );
    });

    test('error → error', () {
      expect(
        FloatingOverlayView.designStateFor(OverlayVisualState.error),
        OverlayDesignState.error,
      );
    });
  });
}
