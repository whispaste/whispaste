/// Tests confirming:
/// - The language picker inside [InterfaceSection] uses [LanguageSelector].
/// - The autostart 3-way dropdown maps bool combinations correctly and writes
///   both fields on selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/widgets/language_selector.dart';

import '../../../fixtures/test_helpers.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _pump(WidgetTester tester, FakeSettingsNotifier notifier) {
  return makeTestable(
    const SingleChildScrollView(child: InterfaceSection()),
    overrides: [settingsProvider.overrideWith(() => notifier)],
  );
}

/// Returns the DropdownButton that contains the autostart values.
Finder _autostartDropdown() => find.byWidgetPredicate(
  (w) =>
      w is DropdownButton<String> &&
      (w.items?.any((i) => i.value == 'never') ?? false),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

late L10n l10n;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  // ── Language picker ────────────────────────────────────────────────────────

  group('InterfaceSection language picker', () {
    testWidgets('renders a LanguageSelector widget', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceSection()),
          overrides: [
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(interface_: InterfaceSettings(locale: 'en')),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LanguageSelector), findsOneWidget);
    });

    testWidgets('tapping a different entry writes the code to the provider', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LanguageSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'de');
    });
  });

  // ── Autostart dropdown ─────────────────────────────────────────────────────

  group('InterfaceSection autostart dropdown', () {
    // AC: dropdown reflects loaded state — launchAtStartup=false → "Never"
    testWidgets('AC: shows "Never" when launchAtStartup=false', (tester) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(
            launchAtStartup: false,
            startMinimized: false,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_autostartDropdown(), findsOneWidget);
      final btn = tester.widget<DropdownButton<String>>(_autostartDropdown());
      expect(btn.value, 'never');
    });

    // AC: launchAtStartup=true, startMinimized=false → "Normal"
    testWidgets(
      'AC: shows "Normal" when launchAtStartup=true, startMinimized=false',
      (tester) async {
        final notifier = FakeSettingsNotifier(
          const AppSettings(
            interface_: InterfaceSettings(
              launchAtStartup: true,
              startMinimized: false,
            ),
          ),
        );
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        final btn = tester.widget<DropdownButton<String>>(_autostartDropdown());
        expect(btn.value, 'normal');
      },
    );

    // AC: launchAtStartup=true, startMinimized=true → "Minimized"
    testWidgets(
      'AC: shows "Minimized" when launchAtStartup=true, startMinimized=true',
      (tester) async {
        final notifier = FakeSettingsNotifier(
          const AppSettings(
            interface_: InterfaceSettings(
              launchAtStartup: true,
              startMinimized: true,
            ),
          ),
        );
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        final btn = tester.widget<DropdownButton<String>>(_autostartDropdown());
        expect(btn.value, 'minimized');
      },
    );

    // AC: selecting "Never" writes launchAtStartup=false, startMinimized=false
    testWidgets('AC: selecting "Never" writes (false, false)', (tester) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(
            launchAtStartup: true,
            startMinimized: false,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_autostartDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DropdownMenuItem<String> && w.value == 'never',
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.interface_.launchAtStartup, isFalse);
      expect(notifier.state.value!.interface_.startMinimized, isFalse);
    });

    // AC: selecting "Normal" writes launchAtStartup=true, startMinimized=false
    testWidgets('AC: selecting "Normal" writes (true, false)', (tester) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(
            launchAtStartup: false,
            startMinimized: false,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_autostartDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DropdownMenuItem<String> && w.value == 'normal',
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.interface_.launchAtStartup, isTrue);
      expect(notifier.state.value!.interface_.startMinimized, isFalse);
    });

    // AC: selecting "Minimized" writes launchAtStartup=true, startMinimized=true
    testWidgets('AC: selecting "Minimized" writes (true, true)', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(
            launchAtStartup: false,
            startMinimized: false,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_autostartDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DropdownMenuItem<String> && w.value == 'minimized',
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.interface_.launchAtStartup, isTrue);
      expect(notifier.state.value!.interface_.startMinimized, isTrue);
    });

    // AC: no separate toggle widgets remain for startup
    testWidgets('AC: no standalone Switch widgets for startup remain', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(
            launchAtStartup: true,
            startMinimized: true,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      // The dropdown must exist.
      expect(_autostartDropdown(), findsOneWidget);
      // Labels for the old separate toggles must not appear.
      expect(find.text(l10n.settingsStartMinimized), findsNothing);
    });
  });
}
