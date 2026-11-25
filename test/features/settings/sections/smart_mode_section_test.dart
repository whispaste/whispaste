/// Widget tests for [SmartModeSection].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/features/settings/sections/smart_mode_section.dart';
import 'package:whispaste/features/settings/sections/model_library_section.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/model_download_service.dart'
    show modelDeleteFailedError;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_text_model.dart';

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

  /// Stands in for a finished download.
  void finish() => state = const SmartModeDownloadState(modelDownloaded: true);
}

List<Object> _overrides({
  required _FakeSettingsNotifier settings,
  SmartModeDownloadState download = const SmartModeDownloadState(),
  bool localEngineAvailable = true,
}) {
  return [
    settingsProvider.overrideWith(() => settings),
    smartModeLocalEngineAvailableProvider.overrideWithValue(
      localEngineAvailable,
    ),
    smartModeDownloadProvider.overrideWith(
      () => _FakeDownloadNotifier(download),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartModeSection', () {
    testWidgets('edit-selection hotkey is off by default; the toggle turns it '
        'on and enables the combination line (voice-selection-edit)', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('selectionEditHotkeyToggle'));
      expect(toggle, findsOneWidget);
      // Off: the combination line is folded away, no change button.
      expect(
        find.byKey(const Key('selectionEditHotkeyComboLine')),
        findsNothing,
      );
      expect(find.byKey(const Key('selectionEditHotkeyChange')), findsNothing);
      expect(
        find.byKey(const Key('selectionEditHotkeyInactiveNotice')),
        findsNothing,
      );

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        notifier.state.value!.selectionEditHotkey.selectionEditHotkeyEnabled,
        isTrue,
      );
      expect(
        find.byKey(const Key('selectionEditHotkeyComboLine')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('selectionEditHotkeyChange')),
        findsOneWidget,
      );
      // The Smart-Mode hotkey is a separate setting and stays untouched.
      expect(
        notifier.state.value!.smartModeHotkey.smartModeHotkeyEnabled,
        isFalse,
      );
    });

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
          overrides: _overrides(
            settings: notifier,
            download: const SmartModeDownloadState(modelDownloaded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleanup').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.smartMode.standardPreset, 'cleanup');
    });

    // Ticket catchup/21: a build without the bundled local engine
    // (Linux before libllama shipped, any dev build that skipped the
    // bundling step) must not offer a local option that can only fail.
    testWidgets('local engine missing: shows the unavailable hint instead of '
        'the model download row', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: notifier,
            localEngineAvailable: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('smartModeLocalUnavailableHint')),
        findsOneWidget,
      );
      expect(find.text('Download'), findsNothing);
      expect(find.textContaining('Q4_K_M'), findsNothing);
    });

    testWidgets('local engine missing: the on-device option cannot be '
        'selected', (tester) async {
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          smartMode: AppSettings.defaults.smartMode.copyWith(
            provider: 'openai',
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: notifier,
            localEngineAvailable: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locally on device').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.smartMode.provider, 'openai');
      // OpenAI is a working choice — no hint needed while it is selected.
      expect(
        find.byKey(const Key('smartModeLocalUnavailableHint')),
        findsNothing,
      );
    });

    testWidgets('local engine present: no unavailable hint', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('smartModeLocalUnavailableHint')),
        findsNothing,
      );
    });

    testWidgets('local model: the quality hint leads to the OpenAI key, and '
        'it is shown for the local engine (D6)', (tester) async {
      const hint = ValueKey('settings-smart-mode-local-quality-hint');
      const link = ValueKey<String>('settings-smart-mode-openai-link');
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: _FakeSettingsNotifier(AppSettings.defaults),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(hint), findsOneWidget);

      await tester.tap(find.byKey(link));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SmartModeSection)),
      );
      expect(container.read(settingsScrollTargetProvider), 'api-keys-openai');
      expect(container.read(activePageProvider), 'settings');
    });

    testWidgets('OpenAI as engine: no local quality hint (D6)', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: SmartModeSection()),
          overrides: _overrides(
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                smartMode: const SmartModeSettings(provider: 'openai'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-smart-mode-local-quality-hint')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('settings-smart-mode-openai-link')),
        findsNothing,
      );
    });

    testWidgets('missing model links to the central library', (tester) async {
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

      // #2175: the text model row offers the way to the library like the
      // speech model row; #1845 keeps the locked notice free of a second
      // download button, #1792 moves the install itself into the library.
      expect(find.text('Not installed'), findsOneWidget);
      expect(find.text('Manage models'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.byIcon(LucideIcons.download), findsNothing);
    });

    testWidgets('installed model shows its label and links to management', (
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

      expect(find.text('Delete'), findsNothing);
      expect(find.text('Text model'), findsOneWidget);
      expect(find.text('Manage models'), findsOneWidget);
      expect(find.text('Download a model'), findsNothing);
      // #2175: the choice is a dropdown, no status line under it.
      expect(find.text('Gemma 4 E2B · Recommended'), findsOneWidget);
      expect(find.text('Not installed'), findsNothing);
      expect(find.textContaining('Q4_K_M'), findsNothing);
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
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          overrides: _overrides(settings: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Target language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('processing-time search target remains in Smart Mode', (
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

      expect(find.textContaining('typical 50-word recording'), findsOneWidget);
    });

    // #1633: a failed download names the category in the app language; the
    // raw technical message (HTTP status, exception text) stays in the log.
    for (final (label, message, kind) in [
      (
        'HTTP 503',
        'Download failed: HTTP 503: service unavailable',
        DownloadErrorKind.network,
      ),
      (
        'timeout',
        'Download failed: Server antwortet nicht mehr.',
        DownloadErrorKind.network,
      ),
      ('delete', modelDeleteFailedError, DownloadErrorKind.storage),
    ]) {
      testWidgets(
        'library: a failed download ($label) shows no raw error text',
        (tester) async {
          final notifier = _FakeSettingsNotifier(AppSettings.defaults);
          await tester.pumpWidget(
            makeTestable(
              const SingleChildScrollView(child: ModelLibrarySection()),
              overrides: _overrides(
                settings: notifier,
                download: SmartModeDownloadState(
                  phase: SmartModeDownloadPhase.error,
                  errorMessage: message,
                  errorKind: kind,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final l10n = L10nEn();
          expect(
            find.text(
              kind == DownloadErrorKind.storage
                  ? l10n.modelDeleteFailed
                  : l10n.modelDownloadFailed,
            ),
            findsOneWidget,
          );
          // The translated text reads 'Download failed.'; the raw one has ':'.
          for (final raw in [
            'HTTP',
            'Exception',
            'Download failed:',
            'antwortet',
            'model_',
          ]) {
            expect(find.textContaining(raw), findsNothing, reason: raw);
          }
        },
      );
    }

    testWidgets('library shows progress and cancel while downloading', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: ModelLibrarySection()),
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
      expect(
        find.byKey(const ValueKey('model-library-gemma-cancel')),
        findsOneWidget,
      );
    });
  });

  // #1686: locked presets say why at first glance, answer a click and unlock
  // without a restart.
  group('locked presets', () {
    test('each lock leads to the row that lifts it', () {
      expect(smartModeUnlockRowId(SmartModeTextModelStatus.ready), isNull);
      expect(
        smartModeUnlockRowId(SmartModeTextModelStatus.localModelMissing),
        'text-smart-mode-model',
      );
      expect(
        smartModeUnlockRowId(SmartModeTextModelStatus.cloudKeyMissing),
        'api-keys-openai',
      );
      expect(
        smartModeUnlockRowId(SmartModeTextModelStatus.customEndpointMissing),
        'text-smart-mode-endpoint-url',
      );
      // No download helps a build without the engine: the service row is
      // where the user switches to a cloud provider.
      expect(
        smartModeUnlockRowId(SmartModeTextModelStatus.localEngineUnavailable),
        'text-smart-mode-service',
      );
    });

    test('the notice shows only where a fix exists', () {
      expect(
        smartModeLockedNoticeShown(SmartModeTextModelStatus.localModelMissing),
        isTrue,
      );
      expect(
        smartModeLockedNoticeShown(SmartModeTextModelStatus.cloudKeyMissing),
        isTrue,
      );
      expect(
        smartModeLockedNoticeShown(SmartModeTextModelStatus.ready),
        isFalse,
      );
      expect(
        smartModeLockedNoticeShown(
          SmartModeTextModelStatus.localEngineUnavailable,
        ),
        isFalse,
      );
    });

    Finder notice() => find.bySemanticsIdentifier('smart-mode-locked-notice');

    testWidgets('a click on a locked preset leads to the download and keeps '
        'the value', (tester) async {
      final handle = tester.ensureSemantics();
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
      expect(notice(), findsOneWidget);

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleanup').last);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SmartModeSection)),
      );
      expect(notifier.state.value!.smartMode.standardPreset, 'off');
      expect(
        container.read(settingsScrollTargetProvider),
        'text-smart-mode-model',
      );
      expect(container.read(activePageProvider), 'smartMode');
      handle.dispose();
    });

    testWidgets('a finished download unlocks the presets without a restart', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
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
      expect(notice(), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SmartModeSection)),
      );
      (container.read(smartModeDownloadProvider.notifier)
              as _FakeDownloadNotifier)
          .finish();
      await tester.pumpAndSettle();
      expect(notice(), findsNothing);

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleanup').last);
      await tester.pumpAndSettle();
      expect(notifier.state.value!.smartMode.standardPreset, 'cleanup');
      handle.dispose();
    });

    testWidgets('the Smart Mode hotkey block shows the same notice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          overrides: _overrides(
            settings: notifier,
            download: const SmartModeDownloadState(modelDownloaded: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(notice(), findsOneWidget);
      // Away from the model row, the notice keeps its download button.
      expect(
        find.byWidgetPredicate(
          (w) => w is WpButton && w.testId == 'smart-mode-locked-action',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('smartModePresetExampleAfter', () {
    final l10n = L10nEn();

    test('off keeps the raw sample, cleanup and concise differ from it', () {
      final raw = l10n.smartModeOnboardingHintExampleBefore;
      expect(smartModePresetExampleAfter('off', l10n), raw);
      final cleanup = smartModePresetExampleAfter('cleanup', l10n);
      final concise = smartModePresetExampleAfter('concise', l10n);
      expect(cleanup, isNotNull);
      expect(concise, isNotNull);
      expect({raw, cleanup, concise}.length, 3);
    });

    test('translate has no fixed sample', () {
      expect(smartModePresetExampleAfter('translate', l10n), isNull);
    });
  });
}
