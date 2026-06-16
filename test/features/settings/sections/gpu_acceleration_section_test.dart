/// Widget tests for GPU acceleration controls embedded in [SpeechRecognitionSection].
///
/// Covers:
///   AC1 — GPU dropdown is visible in the STT section when the provider is
///          on-device (local mode).
///   AC2 — GPU dropdown is absent when a cloud provider is selected.
///   AC3 — Selecting a GPU value from inside the STT section persists it to
///          [BehaviorSettings.gpuAcceleration].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

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

class _FakeSttNotifier extends SttServerStateNotifier {
  @override
  SttStatus build() => const SttStatus(serverState: SttServerState.stopped);
}

class _FakeDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _pump(WidgetTester tester, _FakeSettingsNotifier notifier) {
  return makeTestable(
    const SingleChildScrollView(child: SpeechRecognitionSection()),
    overrides: [
      settingsProvider.overrideWith(() => notifier),
      localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
      modelDownloadProvider.overrideWith(() => _FakeDownloadNotifier()),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

late L10n l10n;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('GPU acceleration in SpeechRecognitionSection', () {
    // AC1 — visible in local (on-device) mode
    testWidgets(
      'AC1: GPU dropdown label is visible when sttProviderType is onDevice',
      (tester) async {
        // Default AppSettings has sttProviderType == onDevice.
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(l10n.settingsGpuAcceleration), findsOneWidget);
      },
    );

    // AC2 — absent when cloud provider is selected
    testWidgets(
      'AC2: GPU dropdown label is absent when a cloud provider is selected',
      (tester) async {
        final cloudSettings = AppSettings.defaults.copyWith(
          sttProvider: SttProviderType.openAI.value,
        );
        final notifier = _FakeSettingsNotifier(cloudSettings);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(l10n.settingsGpuAcceleration), findsNothing);
      },
    );

    testWidgets('AC2: GPU dropdown absent for Deepgram provider', (
      tester,
    ) async {
      final cloudSettings = AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.deepgram.value,
      );
      final notifier = _FakeSettingsNotifier(cloudSettings);
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.settingsGpuAcceleration), findsNothing);
    });

    // AC3 — value persists when changed via the STT section dropdown
    testWidgets(
      'AC3: selecting "disabled" writes GpuAcceleration.disabled to behavior',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        // Locate the GPU dropdown by finding the DropdownButton whose items
        // include 'enabled' (a value only in the GPU dropdown, not the
        // provider or language dropdowns).
        final gpuDropdownFinder = find.byWidgetPredicate(
          (w) =>
              w is DropdownButton<String> &&
              (w.items?.any((i) => i.value == GpuAcceleration.enabled.value) ??
                  false),
        );
        expect(gpuDropdownFinder, findsOneWidget);

        await tester.tap(gpuDropdownFinder);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == GpuAcceleration.disabled.value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.state.value!.behavior.gpuAcceleration,
          GpuAcceleration.disabled.value,
        );
      },
    );

    testWidgets(
      'AC3: after persisting "disabled", dropdown reflects the new value',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        final gpuDropdownFinder = find.byWidgetPredicate(
          (w) =>
              w is DropdownButton<String> &&
              (w.items?.any((i) => i.value == GpuAcceleration.enabled.value) ??
                  false),
        );

        await tester.tap(gpuDropdownFinder);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == GpuAcceleration.disabled.value,
          ),
        );
        await tester.pumpAndSettle();

        // Trigger a rebuild.
        await tester.pump();

        final dropdown = tester.widget<DropdownButton<String>>(
          gpuDropdownFinder,
        );
        expect(dropdown.value, GpuAcceleration.disabled.value);
      },
    );
  });
}
