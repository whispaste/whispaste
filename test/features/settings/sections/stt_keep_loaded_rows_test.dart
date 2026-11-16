/// Tests for the "Keep model loaded" rows of the speech section: the level
/// (always, or after an idle delay) and the minutes slider. The rows write
/// `stt.idleTimeoutMinutes`, where 0 means the model stays loaded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_keep_loaded_rows.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

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

  AppSettings get current => _settings;
}

late L10n l10n;

AppSettings _localWhisper({
  int idleMinutes = 5,
  String model = 'whisper-large-v3-turbo',
}) {
  return AppSettings.defaults.copyWithSections(
    stt: AppSettings.defaults.stt.copyWith(
      provider: SttProviderType.onDevice.value,
      model: model,
      idleTimeoutMinutes: idleMinutes,
    ),
  );
}

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester, {
  required AppSettings settings,
}) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(
        child: WpSettingsGroup(
          heading: 'Speech',
          children: [SttKeepLoadedRows()],
        ),
      ),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Future<void> _choose(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('settings-stt-keep-loaded')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('settings-stt-keep-loaded-item-$item')).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Keep model loaded', () {
    testWidgets('shows the after-idle level with the stored delay', (
      tester,
    ) async {
      await _pump(tester, settings: _localWhisper(idleMinutes: 5));

      expect(find.text(l10n.settingsSttKeepLoaded), findsOneWidget);
      expect(find.text(l10n.settingsSttKeepLoadedAfterIdle), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('choosing always stores 0 and hides the minutes slider', (
      tester,
    ) async {
      final notifier = await _pump(tester, settings: _localWhisper());

      await _choose(tester, 'always');

      expect(notifier.current.stt.idleTimeoutMinutes, 0);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('choosing after idle from always restores a delay of 5 min', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        settings: _localWhisper(idleMinutes: 0),
      );

      await _choose(tester, 'after');

      expect(notifier.current.stt.idleTimeoutMinutes, 5);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('the slider stores the minutes when the drag ends', (
      tester,
    ) async {
      final notifier = await _pump(tester, settings: _localWhisper());

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(20);
      await tester.pumpAndSettle();

      expect(notifier.current.stt.idleTimeoutMinutes, 20);
    });

    testWidgets('shows the memory the loaded model needs', (tester) async {
      await _pump(tester, settings: _localWhisper());

      final mb = hw.sttModelVramMB['whisper-large-v3-turbo']!;
      final gb = NumberFormat('#,##0.#', 'en').format(mb / 1024);
      expect(find.textContaining('$gb GB'), findsOneWidget);
    });

    testWidgets('is absent for Parakeet, which has no idle unload yet', (
      tester,
    ) async {
      final settings = AppSettings.defaults.copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          provider: SttProviderType.onDevice.value,
          engine: OnDeviceEngine.parakeet.value,
        ),
      );
      await _pump(tester, settings: settings);

      expect(find.text(l10n.settingsSttKeepLoaded), findsNothing);
    });
  });
}
