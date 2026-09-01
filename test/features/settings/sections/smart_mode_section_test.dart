/// Widget tests for [SmartModeSection] (ticket 01 of `.scratch/smart-mode-v2/`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/sections/smart_mode_section.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

class _FakeDownloadNotifier extends SmartModeDownloadNotifier {
  _FakeDownloadNotifier(this._initial);
  final SmartModeDownloadState _initial;

  @override
  SmartModeDownloadState build() => _initial;
}

List<Object> _overrides({
  required _FakeSettingsNotifier settings,
  SmartModeDownloadState download = const SmartModeDownloadState(),
}) {
  return [
    settingsProvider.overrideWith(() => settings),
    smartModeDownloadProvider.overrideWith(
      () => _FakeDownloadNotifier(download),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartModeSection', () {
    testWidgets('preset dropdown defaults to Off', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('selecting a preset updates AppSettings.smartMode', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleanup').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.smartMode.standardPreset, 'cleanup');
    });

    testWidgets('shows Download action when model is not downloaded', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: notifier,
            download: const SmartModeDownloadState(modelDownloaded: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('shows Delete action and model label when downloaded', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: notifier,
            download: const SmartModeDownloadState(modelDownloaded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
      expect(find.textContaining(smartModeModel.label), findsOneWidget);
    });

    testWidgets(
      'target-language row is hidden unless preset is Translate (ticket 03)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SmartModeSection()),
            overrides: _overrides(settings: notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Target language'), findsNothing);
      },
    );

    testWidgets(
      'selecting Translate reveals the target-language row, defaulting to '
      'English (ticket 03 validated German+English; the rest gated behind '
      'ticket 09)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            smartMode: const SmartModeSettings(standardPreset: 'translate'),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SmartModeSection()),
            overrides: _overrides(settings: notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Target language'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
      },
    );

    testWidgets(
      'hotkey target-language row is hidden unless the hotkey preset is '
      'Translate (ticket 09)',
      (tester) async {
        final notifier = _FakeSettingsNotifier(
          AppSettings.defaults.copyWithSections(
            smartModeHotkey: const SmartModeHotkeySettings(
              smartModeHotkeyEnabled: true,
            ),
          ),
        );
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SmartModeSection()),
            overrides: _overrides(settings: notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Target language'), findsNothing);
      },
    );

    testWidgets('selecting Translate as the hotkey preset reveals its own '
        'target-language row, independent of the standard preset, defaulting '
        'to English', (tester) async {
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          smartModeHotkey: const SmartModeHotkeySettings(
            smartModeHotkeyEnabled: true,
            smartModeHotkeyPreset: 'translate',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Target language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets(
      'shows RAM-footprint and processing-time info next to the model row',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: SmartModeSection()),
            overrides: _overrides(settings: notifier),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('shared with the transcription model'),
          findsOneWidget,
        );
        expect(
          find.textContaining('typical 50-word dictation'),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows progress bar while downloading', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: notifier,
            download: const SmartModeDownloadState(
              phase: SmartModeDownloadPhase.downloading,
              progressPercent: 42,
              bytesDownloaded: 1000,
              totalBytes: 2000,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
