/// Widget tests for the "Numbers only" toggle inside [SpeechRecognitionSection]
/// (itn-cad-zahlen Ticket 06). Mirrors the cloud-mode settings override
/// approach from `stt_language_dropdown_test.dart` so the local-only
/// WpSttModelManager / BenchmarkButton stay out of the tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

late L10n l10n;

Widget _scrollable(Widget child) => SingleChildScrollView(child: child);

AppSettings _cloudSettings({bool numericOnlyMode = false}) {
  return AppSettings.defaults
      .copyWith(sttProvider: SttProviderType.openAI.value)
      .copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          numericOnlyMode: numericOnlyMode,
        ),
      );
}

/// [AppSettings.defaults] is already on-device/whisper, so this only needs
/// to override the engine for the Parakeet case.
AppSettings _localSettings({
  OnDeviceEngine engine = OnDeviceEngine.whisper,
  bool numericOnlyMode = false,
}) {
  return AppSettings.defaults
      .copyWith(sttEngine: engine.value)
      .copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          numericOnlyMode: numericOnlyMode,
        ),
      );
}

Future<_FakeSettingsNotifier> _pumpSectionWith(
  WidgetTester tester,
  AppSettings settings, {
  ValueNotifier<bool>? sectionVisible,
}) async {
  final notifier = _FakeSettingsNotifier(settings);
  final visible = sectionVisible ?? ValueNotifier<bool>(true);
  await tester.pumpWidget(
    makeTestable(
      ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, show, _) => show
            ? _scrollable(const SpeechRecognitionSection())
            : const SizedBox.shrink(),
      ),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester, {
  bool numericOnlyMode = false,
  ValueNotifier<bool>? sectionVisible,
}) => _pumpSectionWith(
  tester,
  _cloudSettings(numericOnlyMode: numericOnlyMode),
  sectionVisible: sectionVisible,
);

/// The toggle's own [SettingRow], found via its icon (locale-independent,
/// unlike matching on the label text) so the assertion doesn't depend on
/// how many other Switches are on the page.
Finder _toggleRow() => find.ancestor(
  of: find.byWidgetPredicate((w) => w is Icon && w.icon == LucideIcons.hash),
  matching: find.byType(SettingRow),
);

Switch _toggleSwitch(WidgetTester tester) => tester.widget<Switch>(
  find.descendant(of: _toggleRow(), matching: find.byType(Switch)),
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Numbers-only mode toggle', () {
    testWidgets('renders with English label and subtitle', (tester) async {
      await _pumpSection(tester);

      expect(find.text(l10n.settingsNumericOnlyMode), findsOneWidget);
      expect(find.text(l10n.settingsNumericOnlyModeSubtitle), findsOneWidget);
    });

    testWidgets('reflects settings.stt.numericOnlyMode == false by default', (
      tester,
    ) async {
      await _pumpSection(tester);

      expect(_toggleSwitch(tester).value, isFalse);
    });

    testWidgets('reflects a persisted true value on first render', (
      tester,
    ) async {
      await _pumpSection(tester, numericOnlyMode: true);

      expect(_toggleSwitch(tester).value, isTrue);
    });

    testWidgets(
      'toggling on persists via copyWithSections and survives the settings '
      'section being unmounted and remounted (settings window closed and '
      'reopened — the app-level settingsProvider container itself is not '
      're-created, only this section widget/state is)',
      (tester) async {
        final visible = ValueNotifier<bool>(true);
        final notifier = await _pumpSection(tester, sectionVisible: visible);

        _toggleSwitch(tester).onChanged!(true);
        await tester.pumpAndSettle();

        expect(notifier.current.stt.numericOnlyMode, isTrue);

        // Simulate the settings window being closed (section unmounted) and
        // reopened (section remounted), against the same persisted state.
        visible.value = false;
        await tester.pumpAndSettle();
        expect(find.byType(SpeechRecognitionSection), findsNothing);

        visible.value = true;
        await tester.pumpAndSettle();

        expect(_toggleSwitch(tester).value, isTrue);
        expect(notifier.current.stt.numericOnlyMode, isTrue);
      },
    );

    testWidgets('toggling off persists via copyWithSections', (tester) async {
      final notifier = await _pumpSection(tester, numericOnlyMode: true);

      _toggleSwitch(tester).onChanged!(false);
      await tester.pumpAndSettle();

      expect(notifier.current.stt.numericOnlyMode, isFalse);
      expect(_toggleSwitch(tester).value, isFalse);
    });

    // Regression: the toggle is a deterministic post-transcription text
    // transform (RecordingOrchestrator), not an ASR-level mode, so it must
    // stay visible for every engine/provider combination — the user should
    // decide for themselves whether to use it, not have it hidden because a
    // particular on-device engine happens to be selected.
    for (final engine in OnDeviceEngine.values) {
      testWidgets('renders for on-device engine ${engine.value}', (
        tester,
      ) async {
        await _pumpSectionWith(tester, _localSettings(engine: engine));

        expect(_toggleRow(), findsOneWidget);
        expect(find.text(l10n.settingsNumericOnlyMode), findsOneWidget);
      });
    }

    testWidgets('renders for the Deepgram cloud provider too', (tester) async {
      await _pumpSectionWith(
        tester,
        AppSettings.defaults.copyWith(
          sttProvider: SttProviderType.deepgram.value,
        ),
      );

      expect(_toggleRow(), findsOneWidget);
    });

    // CLAUDE.md Arbeitsweise Punkt 6 asks for an accessibility-large-text
    // layout check; this desktop-only app has no iOS/Android Simulator, so
    // the widget-test equivalent is a large `textScaler` against a narrow
    // settings-pane width, in every supported locale (DoD Punkt 5).
    //
    // Isolates just this row's own [SettingRow] (icon + label + subtitle +
    // toggle) rather than pumping the whole [SpeechRecognitionSection]: the
    // full section already overflows at 480px/1.8x from unrelated,
    // pre-existing rows (dropdowns, model cards) regardless of this ticket's
    // change, which would make the assertion fail for a reason outside this
    // ticket's scope. This mirrors exactly how SettingRow lays out inside
    // the section: an Expanded label column plus a fixed-size trailing
    // control in a Row (see settings_widgets.dart).
    for (final locale in const [Locale('en'), Locale('de'), Locale('he')]) {
      testWidgets(
        'no layout overflow for the isolated toggle row under 1.8x text '
        'scale — locale ${locale.languageCode}',
        (tester) async {
          late L10n rowL10n;
          await tester.pumpWidget(
            makeTestable(
              Builder(
                builder: (context) {
                  rowL10n = L10n.of(context);
                  return MediaQuery(
                    data: const MediaQueryData(
                      size: Size(480, 200),
                      textScaler: TextScaler.linear(1.8),
                    ),
                    child: SettingRow(
                      icon: LucideIcons.hash,
                      label: rowL10n.settingsNumericOnlyMode,
                      subtitle: rowL10n.settingsNumericOnlyModeSubtitle,
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

          expect(find.byType(SettingRow), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
