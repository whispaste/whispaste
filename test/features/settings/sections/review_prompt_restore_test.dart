/// Tests for the switch that lifts a "Never ask again" choice for the rating
/// reminder (UIA-FBK-02). The switch appears only after that choice, and
/// turning it on clears the permanent opt-out and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';

import '../../../fixtures/test_helpers.dart';

const _restore = ValueKey('interface-review-prompt-restore');
const _optOutKey = 'review_prompt_permanently_dismissed';

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

Future<void> _pump(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: InterfaceGeneralSection()),
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(_FakeSettings.new)],
    ),
  );
  await tester.pumpAndSettle();
}

late WidgetTester tester;

void main() {
  testWidgets('without a "never ask again" choice there is no restore switch', (
    t,
  ) async {
    tester = t;
    await _pump({});

    expect(find.byKey(_restore), findsNothing);
  });

  testWidgets(
    'turning the reminder back on clears only the opt-out and keeps the caps (UIA-FBK-02)',
    (t) async {
      tester = t;
      await _pump({
        _optOutKey: true,
        'review_prompt_shown_count': 2,
        'review_prompt_last_snooze': 12345,
      });

      expect(find.byKey(_restore), findsOneWidget);
      await tester.ensureVisible(find.byKey(_restore));
      await tester.tap(find.byKey(_restore));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_optOutKey), isNull);
      expect(prefs.getInt('review_prompt_shown_count'), 2);
      expect(prefs.getInt('review_prompt_last_snooze'), 12345);
      expect(find.byKey(_restore), findsNothing);
    },
  );
}
