import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('KeyboardShortcutSection', () {
    testWidgets('renders Hold to Record toggle inside the hotkey block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const KeyboardShortcutSection(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsOneWidget);
    });
  });

  group('AudioSection', () {
    testWidgets('does NOT render Hold to Record toggle in audio block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AudioSection(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsNothing);
    });
  });
}
