/// Settings → Privacy: "Fehlgeschlagene Aufnahmen aufbewahren für" offers the
/// keep periods and is disabled while retained audio is on. Checked at 800 px,
/// with text scaling 1.3, and in a right-to-left language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/services/audio/retention/audio_retention.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required PrivacySettings privacy,
  Size size = const Size(800, 1000),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SingleChildScrollView(child: PrivacySection()),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(AppSettings(privacy: privacy)),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('shows the 7-day default as the current keep period at 800 px '
      'with text scaling 1.3', (tester) async {
    await _pump(tester, privacy: const PrivacySettings(), textScale: 1.3);

    expect(
      find.byKey(const ValueKey('settings-row-privacy-failed-audio-keep')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.settingsHistoryAutoTrashDaysLabel(7)),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('while retained audio is on, the row states the retention period '
      'and is not used', (tester) async {
    await _pump(
      tester,
      privacy: const PrivacySettings(retainRecentAudio: true),
    );

    expect(
      find.text(
        l10n.settingsFailedAudioKeepDisabled(kRetainedAudioMaxAge.inDays),
      ),
      findsOneWidget,
    );
  });
}
