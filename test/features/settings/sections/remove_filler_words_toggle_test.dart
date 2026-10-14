/// Widget tests for the "Remove filler words" toggle inside
/// [SpeechRecognitionSection] (handy-catchup ticket 16). Same cloud-mode
/// setup as `numeric_only_mode_toggle_test.dart`, so the local-only model
/// manager stays out of the tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

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

const _toggleKey = Key('removeFillerWordsToggle');

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester,
  AppSettings settings,
) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: SpeechRecognitionSection()),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

AppSettings _cloud({bool removeFillerWords = false}) => AppSettings.defaults
    .copyWith(sttProvider: SttProviderType.openAI.value)
    .copyWithSections(
      stt: AppSettings.defaults.stt.copyWith(
        removeFillerWords: removeFillerWords,
      ),
    );

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_toggleKey));

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Remove filler words toggle', () {
    testWidgets('renders label and subtitle, off by default', (tester) async {
      await _pumpSection(tester, _cloud());

      expect(find.text(l10n.settingsRemoveFillerWords), findsOneWidget);
      expect(find.text(l10n.settingsRemoveFillerWordsSubtitle), findsOneWidget);
      expect(_switch(tester).value, isFalse);
    });

    testWidgets('reflects a persisted true value', (tester) async {
      await _pumpSection(tester, _cloud(removeFillerWords: true));

      expect(_switch(tester).value, isTrue);
    });

    testWidgets('toggling persists the setting', (tester) async {
      final notifier = await _pumpSection(tester, _cloud());

      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(notifier.current.stt.removeFillerWords, isTrue);
      expect(_switch(tester).value, isTrue);
    });

    // A text transform after transcription, so it applies to every engine.
    for (final engine in OnDeviceEngine.values) {
      testWidgets('renders for on-device engine ${engine.value}', (
        tester,
      ) async {
        await _pumpSection(
          tester,
          AppSettings.defaults.copyWith(sttEngine: engine.value),
        );

        expect(find.byKey(_toggleKey), findsOneWidget);
      });
    }

    for (final locale in const [
      Locale('en'),
      Locale('de'),
      Locale('he'),
      Locale('ru'),
    ]) {
      testWidgets('no overflow under 1.8x text scale — '
          '${locale.languageCode}', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            Builder(
              builder: (context) {
                final rowL10n = L10n.of(context);
                return MediaQuery(
                  data: const MediaQueryData(
                    size: Size(480, 200),
                    textScaler: TextScaler.linear(1.8),
                  ),
                  child: SettingRow(
                    icon: LucideIcons.messageSquareOff,
                    label: rowL10n.settingsRemoveFillerWords,
                    subtitle: rowL10n.settingsRemoveFillerWordsSubtitle,
                    semanticToggledValue: false,
                    trailing: settingsToggle(value: false, onChanged: (_) {}),
                  ),
                );
              },
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
