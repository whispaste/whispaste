/// The longest endonym fits the General settings row without an ellipsis, at
/// the default and at the enlarged text scale, and the language and autostart
/// dropdowns share one width. A row too narrow for it ellipsizes, and the
/// semantics keep the full name.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../../fixtures/test_helpers.dart';

const _longestEndonym = 'Português (Brasil)';

class _PtSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(interface_: InterfaceSettings(locale: 'pt'));

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required double textScale,
  double? width,
}) async {
  Widget section = Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: const SingleChildScrollView(child: InterfaceGeneralSection()),
    ),
  );
  if (width != null) {
    section = SizedBox(width: width, child: section);
  }
  await tester.pumpWidget(
    makeTestable(
      section,
      size: const Size(1280, 800),
      overrides: [settingsProvider.overrideWith(() => _PtSettings())],
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dropdownIn(int row) => find.descendant(
  of: find.byType(WpSettingsRow).at(row),
  matching: find.byType(WpDropdown<String>),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await L10n.delegate.load(const Locale('en'));
    // Measure with the app's fonts; the default test font is Ahem, which is
    // far wider than the real face.
    await loadAppFonts();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'the longest endonym is not ellipsized and both dropdowns match at text scale $scale',
      (tester) async {
        await _pump(tester, textScale: scale);

        final languageWidth = tester.getSize(_dropdownIn(0)).width;
        final autostartWidth = tester.getSize(_dropdownIn(1)).width;
        // ignore: avoid_print
        print(
          'scale $scale: language ${languageWidth}px, autostart ${autostartWidth}px',
        );
        expect(languageWidth, autostartWidth);

        final label = tester.renderObject<RenderParagraph>(
          find.text(_longestEndonym),
        );
        // Unclipped, the label needs more width than the trigger gives it.
        expect(
          label.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(label.size.width + 0.5),
        );
      },
    );
  }

  testWidgets(
    'a row too narrow for the endonym ellipsizes and keeps the full name in semantics',
    (tester) async {
      await _pump(tester, textScale: 1.3, width: 150);

      final label = tester.renderObject<RenderParagraph>(
        find.text(_longestEndonym),
      );
      expect(
        label.getMaxIntrinsicWidth(double.infinity),
        greaterThan(label.size.width),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.value == _longestEndonym,
        ),
        findsOneWidget,
      );
    },
  );
}
