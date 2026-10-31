/// Widget tests for the optional NVIDIA CUDA pack row: one state per
/// phase, the on/off switch, and its visibility inside the STT section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/cuda_pack_row.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

import '../../../fixtures/test_helpers.dart';

const _pack = CudaPackInfo(
  id: 'ggml-test-r1',
  url: 'https://example.invalid/pack.zip',
  archiveSizeBytes: 400 * 1024 * 1024,
  archiveSha256: '',
  files: [],
);

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

class _FakeCudaPackNotifier extends CudaPackNotifier {
  _FakeCudaPackNotifier(this._initial);
  final CudaPackState _initial;
  int installCalls = 0;
  int acceptCalls = 0;

  @override
  CudaPackState build() => _initial;

  int removeCalls = 0;

  @override
  Future<void> install() async => installCalls++;

  @override
  Future<void> remove() async => removeCalls++;
  @override
  Future<void> acceptEulaAndInstall() async => acceptCalls++;

  int consentCalls = 0;

  @override
  Future<void> recordEulaConsent() async => consentCalls++;
}

/// Settings with the NVIDIA EULA accepted for [packId].
AppSettings _acceptedFor(String packId) =>
    AppSettings.defaults.copyWithSections(
      behavior: AppSettings.defaults.behavior.copyWith(
        cudaEulaAccepted: cudaEulaConsentValue(packId),
      ),
    );

class _FakeSttNotifier extends SttServerStateNotifier {
  @override
  SttStatus build() => const SttStatus(serverState: SttServerState.stopped);
}

class _FakeDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

void main() {
  Widget row(
    CudaPackState state, {
    _FakeSettingsNotifier? settings,
    _FakeCudaPackNotifier? notifier,
  }) => makeTestable(
    const CudaPackRow(),
    overrides: [
      settingsProvider.overrideWith(
        () => settings ?? _FakeSettingsNotifier(AppSettings.defaults),
      ),
      cudaPackProvider.overrideWith(
        () => notifier ?? _FakeCudaPackNotifier(state),
      ),
    ],
  );

  testWidgets('offers the download when the pack is not installed', (
    tester,
  ) async {
    final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
    await tester.pumpWidget(
      row(
        notifier._initial,
        settings: _FakeSettingsNotifier(_acceptedFor(_pack.id)),
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-cuda-pack-row')), findsOneWidget);
    expect(find.byKey(const Key('settings-cuda-pack-toggle')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
    expect(notifier.installCalls, 1);
  });

  group('NVIDIA EULA consent before the download', () {
    testWidgets('asks first, and cancel starts nothing and stores nothing', (
      tester,
    ) async {
      final settings = _FakeSettingsNotifier(AppSettings.defaults);
      final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
      await tester.pumpWidget(
        row(notifier._initial, settings: settings, notifier: notifier),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuda-eula-dialog')), findsOneWidget);
      expect(find.byKey(const Key('cuda-eula-link')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cuda-eula-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuda-eula-dialog')), findsNothing);
      expect(notifier.installCalls, 0);
      expect(notifier.acceptCalls, 0);
      expect(settings._settings.behavior.cudaEulaAccepted, isEmpty);
    });

    testWidgets('the bundled licence text opens from the dialog before any '
        'download', (tester) async {
      final settings = _FakeSettingsNotifier(AppSettings.defaults);
      final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
      await tester.pumpWidget(
        row(notifier._initial, settings: settings, notifier: notifier),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cuda-eula-fulltext-open')));
      // The bundled text loads through real asset I/O, outside the fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      final text = tester
          .widget<SelectableText>(find.byKey(const Key('cuda-eula-fulltext')))
          .data;
      expect(text, contains('NVIDIA'));
      await tester.tap(find.byKey(const Key('cuda-eula-fulltext-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuda-eula-dialog')), findsOneWidget);
      expect(notifier.installCalls, 0);
    });

    testWidgets('accept hands over to the download with consent recorded', (
      tester,
    ) async {
      final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
      await tester.pumpWidget(row(notifier._initial, notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cuda-eula-accept')));
      await tester.pumpAndSettle();

      expect(notifier.acceptCalls, 1);
      expect(notifier.installCalls, 0);
    });

    testWidgets('an already accepted pack version is not asked again', (
      tester,
    ) async {
      final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
      await tester.pumpWidget(
        row(
          notifier._initial,
          settings: _FakeSettingsNotifier(_acceptedFor(_pack.id)),
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuda-eula-dialog')), findsNothing);
      expect(notifier.installCalls, 1);
    });

    testWidgets('a new pack version asks again', (tester) async {
      final notifier = _FakeCudaPackNotifier(const CudaPackState(pack: _pack));
      await tester.pumpWidget(
        row(
          notifier._initial,
          settings: _FakeSettingsNotifier(_acceptedFor('ggml-old-r1')),
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-cuda-pack-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuda-eula-dialog')), findsOneWidget);
      expect(notifier.installCalls, 0);
    });
  });

  testWidgets('shows progress and cancel while downloading', (tester) async {
    await tester.pumpWidget(
      row(
        const CudaPackState(
          pack: _pack,
          phase: CudaPackPhase.downloading,
          bytesReceived: 100 * 1024 * 1024,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('settings-cuda-pack-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-cuda-pack-cancel')), findsOneWidget);
    expect(find.textContaining('25'), findsOneWidget);
  });

  testWidgets('names the failure after an error', (tester) async {
    await tester.pumpWidget(
      row(const CudaPackState(pack: _pack, error: CudaPackError.verification)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-cuda-pack-error')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-cuda-pack-download')),
      findsOneWidget,
    );
  });

  testWidgets('removing the CUDA pack asks first and keeps it on cancel '
      '(UIA-SET-03)', (tester) async {
    const installed = CudaPackState(pack: _pack, installed: true);
    final notifier = _FakeCudaPackNotifier(installed);
    await tester.pumpWidget(row(installed, notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-cuda-pack-remove')));
    await tester.pumpAndSettle();
    expect(notifier.removeCalls, 0);

    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(notifier.removeCalls, 0);

    await tester.tap(find.byKey(const Key('settings-cuda-pack-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();
    expect(notifier.removeCalls, 1);
  });

  testWidgets('an installed pack without consent asks for it, not a toggle', (
    tester,
  ) async {
    const installed = CudaPackState(pack: _pack, installed: true);
    final notifier = _FakeCudaPackNotifier(installed);
    await tester.pumpWidget(row(installed, notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-cuda-pack-toggle')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-cuda-pack-consent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cuda-eula-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cuda-eula-cancel')));
    await tester.pumpAndSettle();
    expect(notifier.consentCalls, 0);

    await tester.tap(find.byKey(const Key('settings-cuda-pack-consent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cuda-eula-accept')));
    await tester.pumpAndSettle();
    expect(notifier.consentCalls, 1);
    expect(notifier.installCalls, 0);
  });

  testWidgets('switches CUDA off once installed', (tester) async {
    final settings = _FakeSettingsNotifier(_acceptedFor(_pack.id));
    await tester.pumpWidget(
      row(
        const CudaPackState(pack: _pack, installed: true),
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-cuda-pack-remove')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-cuda-pack-toggle')));
    await tester.pumpAndSettle();
    expect(settings._settings.behavior.cudaAcceleration, isFalse);
  });

  group('SpeechRecognitionSection', () {
    Widget section({required bool offered}) => makeTestable(
      const SingleChildScrollView(child: SpeechRecognitionSection()),
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(AppSettings.defaults),
        ),
        localSttBundleProvider.overrideWith(() => _FakeSttNotifier()),
        modelDownloadProvider.overrideWith(() => _FakeDownloadNotifier()),
        cudaPackProvider.overrideWith(
          () => _FakeCudaPackNotifier(const CudaPackState(pack: _pack)),
        ),
        cudaPackOfferedProvider.overrideWithValue(offered),
      ],
    );

    testWidgets('shows the row when the pack is offered', (tester) async {
      await tester.pumpWidget(section(offered: true));
      await tester.pumpAndSettle();
      expect(find.byType(CudaPackRow), findsOneWidget);
    });

    testWidgets('hides the row otherwise (Store, no NVIDIA, no pack)', (
      tester,
    ) async {
      await tester.pumpWidget(section(offered: false));
      await tester.pumpAndSettle();
      expect(find.byType(CudaPackRow), findsNothing);
    });
  });
}
