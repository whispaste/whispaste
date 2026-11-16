/// The tray icon shows the dictation state (#137): which recording phase maps
/// to which icon variant, asset, status line and tooltip.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/tray_icon_state.dart';

String _statusLine(TrayMenuState state, Map<String, String> labels) =>
    buildTrayCommands(
      state,
      labels,
    ).firstWhere((c) => c.id == TrayCommandIds.status).labelKey;

void main() {
  group('trayIconStateFor', () {
    const expected = {
      RecordingPhase.idle: TrayIconState.idle,
      RecordingPhase.recording: TrayIconState.recording,
      RecordingPhase.transcribing: TrayIconState.processing,
      RecordingPhase.refining: TrayIconState.processing,
      RecordingPhase.done: TrayIconState.idle,
      RecordingPhase.error: TrayIconState.idle,
    };

    test('covers every recording phase', () {
      expect(expected.keys, unorderedEquals(RecordingPhase.values));
    });

    for (final entry in expected.entries) {
      test('${entry.key.name} shows the ${entry.value.name} icon', () {
        expect(trayIconStateFor(entry.key), entry.value);
      });
    }

    test('the icon is busy exactly while the dictation is busy', () {
      for (final phase in RecordingPhase.values) {
        expect(
          trayIconStateFor(phase) != TrayIconState.idle,
          isDictationBusy(phase),
          reason: phase.name,
        );
      }
    });
  });

  group('trayStateIconAsset', () {
    test('idle keeps the platform idle icon on every platform', () {
      expect(trayStateIconAsset(TrayIconState.idle, windows: true), isNull);
      expect(trayStateIconAsset(TrayIconState.idle, windows: false), isNull);
    });

    test('Windows reads ICO variants, the other platforms PNG', () {
      expect(
        trayStateIconAsset(TrayIconState.recording, windows: true),
        'assets/tray/tray-recording.ico',
      );
      expect(
        trayStateIconAsset(TrayIconState.processing, windows: true),
        'assets/tray/tray-processing.ico',
      );
      expect(
        trayStateIconAsset(TrayIconState.recording, windows: false),
        'assets/tray/tray-recording.png',
      );
      expect(
        trayStateIconAsset(TrayIconState.processing, windows: false),
        'assets/tray/tray-processing.png',
      );
    });
  });

  group('status line and tooltip', () {
    late Map<String, String> labels;
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
      labels = trayLabelsFor(l10n);
    });

    TrayMenuState menuState({
      required bool recording,
      bool processing = false,
    }) => TrayMenuState(
      isRecording: recording,
      isProcessing: processing,
      micDeviceLabels: const ['default'],
      selectedMic: 'default',
    );

    test('every state has a status label in the app language', () {
      expect(
        labels[trayStatusLabelKey(TrayIconState.idle)],
        l10n.trayStatusReady,
      );
      expect(
        labels[trayStatusLabelKey(TrayIconState.recording)],
        l10n.trayStatusRecording,
      );
      expect(
        labels[trayStatusLabelKey(TrayIconState.processing)],
        l10n.statusBarTranscribing,
      );
    });

    test('the menu status line names each state with its own dot', () {
      expect(
        _statusLine(menuState(recording: false), labels),
        '🟢 ${l10n.trayStatusReady}',
      );
      expect(
        _statusLine(menuState(recording: true), labels),
        '🔴 ${l10n.trayStatusRecording}',
      );
      expect(
        _statusLine(menuState(recording: false, processing: true), labels),
        '🟡 ${l10n.statusBarTranscribing}',
      );
    });

    test('the tooltip leads with the state only while a dictation runs', () {
      expect(
        trayStateTooltip(TrayIconState.idle, status: 'Ready', details: 'D'),
        'D',
      );
      expect(
        trayStateTooltip(
          TrayIconState.recording,
          status: 'Recording…',
          details: 'D',
        ),
        'Recording… · D',
      );
      expect(
        trayStateTooltip(
          TrayIconState.processing,
          status: 'Processing…',
          details: 'D',
        ),
        'Processing… · D',
      );
    });
  });
}
