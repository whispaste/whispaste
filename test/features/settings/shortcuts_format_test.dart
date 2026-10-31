// UIA-KBD-02: one format for every hotkey row, three purpose cards, no
// "global" in any visible title, dependent options indented.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';

import '../../fixtures/record_device_listing_stub.dart';
import '../../fixtures/test_helpers.dart';

Future<void> _pump(
  WidgetTester tester, {
  String locale = 'en',
  AppSettings? settings,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: KeyboardShortcutSection()),
      locale: Locale(locale),
      overrides: [
        snippetPickerAvailabilityProvider.overrideWithValue(true),
        if (settings != null)
          settingsProvider.overrideWith(() => _FakeSettings(settings)),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

late L10n l10n;

void main() {
  stubRecordDeviceListing();
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('no visible text calls a hotkey "global" (en and de)', (
    tester,
  ) async {
    for (final locale in ['en', 'de']) {
      await _pump(tester, locale: locale);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => RegExp('global', caseSensitive: false).hasMatch(s))
          .toList();
      expect(texts, isEmpty, reason: 'locale $locale');
    }
  });

  testWidgets('hold-or-tap is dimmed and inert while push-to-talk is off', (
    tester,
  ) async {
    // Pinned explicitly: push-to-talk defaults to on for new installations,
    // so the precondition of this test has to be set, not inherited.
    await _pump(
      tester,
      settings: const AppSettings(
        audioInput: AudioInputSettings(pushToTalk: false),
      ),
    );
    final opacities = tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text(l10n.settingsHoldOrTap),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .map((w) => w.opacity);
    expect(
      opacities.any((o) => o < 1),
      isTrue,
      reason:
          'a disabled dependent option must look disabled, like the '
          'Smart Mode preset under its switched-off hotkey',
    );
  });
}
