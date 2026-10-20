/// Tests confirming:
/// - The language picker inside [InterfaceGeneralSection] uses [WpLanguageSelector]
///   and renders at the same row height as its dropdown siblings.
/// - The autostart 3-way dropdown maps bool combinations correctly and writes
///   both fields on selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/features/settings/sections/interface_appearance_section.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/widgets/language_selector.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../../fixtures/test_helpers.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

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
    const SingleChildScrollView(child: InterfaceGeneralSection()),
    overrides: [settingsProvider.overrideWith(() => notifier)],
  );
}

Widget _pumpAppearance(WidgetTester tester, FakeSettingsNotifier notifier) {
  return makeTestable(
    const SingleChildScrollView(child: InterfaceAppearanceSection()),
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

  group('InterfaceGeneralSection language picker', () {
    testWidgets('renders a WpLanguageSelector widget', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceGeneralSection()),
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

      expect(find.byType(WpLanguageSelector), findsOneWidget);
    });

    testWidgets('tapping a different entry writes the code to the provider', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );

      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: InterfaceGeneralSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WpLanguageSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch').last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.locale, 'de');
    });

    // Regression, twice over. First the language row was the only one on the
    // page whose trigger was 48 dp while its neighbours ran at a dense 32,
    // and SettingRow only sets a *minimum* height, so it stood taller than
    // them. The fix then went the wrong way — it shrank this row to 32 —
    // which left every dropdown row in Settings shorter than the search
    // fields, buttons and text fields everywhere else in the app, and
    // shorter than the API-key row two sections down. There is now one
    // control height, 48 dp, and this test pins the language row to it
    // *and* to its siblings, so neither half can drift again.
    testWidgets('renders at the same row height as its dropdown siblings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pump(
          tester,
          FakeSettingsNotifier(
            const AppSettings(interface_: InterfaceSettings(locale: 'en')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row order in InterfaceGeneralSection: language, autostart, ... The
      // autostart dropdown row is the subtitle-less like-for-like sibling.
      final rows = find.byType(WpSettingsRow);
      final languageHeight = tester.getSize(rows.at(0)).height;
      final autostartHeight = tester.getSize(rows.at(1)).height;

      expect(languageHeight, autostartHeight);
      // Parity alone would still hold if all three rows moved together, so
      // pin the visible trigger at the dropdown height (spec §4: 40 px). The
      // layout box around it is the 48 px touch target, so measure the trigger
      // itself rather than the selector's outer box.
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.descendant(
                      of: find.byType(WpLanguageSelector),
                      matching: find.byType(DropdownButtonHideUnderline),
                    ),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height,
        WpShellTokens.controlHeight,
      );
    });
  });

  // ── Trailing control width ─────────────────────────────────────────────────

  group('InterfaceGeneralSection trailing dropdown widths', () {
    // Both trailing dropdowns of this group take one width from the longest
    // label of either (see SharedWidthDropdown). The exact width is pinned by
    // interface_language_fit_test.dart.
    testWidgets('language and autostart dropdowns share one width', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pump(
          tester,
          FakeSettingsNotifier(
            const AppSettings(interface_: InterfaceSettings(locale: 'en')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rows = find.byType(WpSettingsRow);
      final languageWidth = tester
          .getSize(
            find.descendant(
              of: rows.at(0),
              matching: find.byType(WpDropdown<String>),
            ),
          )
          .width;
      final autostartWidth = tester
          .getSize(
            find.descendant(
              of: rows.at(1),
              matching: find.byType(WpDropdown<String>),
            ),
          )
          .width;

      expect(languageWidth, autostartWidth);
    });

    // WpSettingsGroup puts one divider between each pair of children. The
    // approval hint is a child that renders nothing unless macOS holds the
    // login item back, so it used to stack two dividers 1 px apart under the
    // autostart row. Without a pending approval there must be exactly one
    // divider between two rows.
    testWidgets('no two dividers stack when the autostart hint is idle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pump(
          tester,
          FakeSettingsNotifier(
            const AppSettings(interface_: InterfaceSettings(locale: 'en')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dividers = find.byType(Divider);
      // Four rows (language, autostart, notifications, close to tray).
      expect(dividers, findsNWidgets(3));
      for (var i = 1; i < 3; i++) {
        final previous = tester.getRect(dividers.at(i - 1));
        final current = tester.getRect(dividers.at(i));
        expect(current.top - previous.bottom, greaterThan(1));
      }
    });
  });

  // ── Autostart dropdown ─────────────────────────────────────────────────────

  group('InterfaceGeneralSection autostart dropdown', () {
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

  // ── Backend utilization toggle ─────────────────────────────────────────────

  group('InterfaceAppearanceSection backend utilization toggle', () {
    // Regression: an earlier version of this handler called the wrong
    // AppSettings mutation API (`copyWith(interface_: ...)`, which has no
    // such parameter) — a compile error that a shallower test wouldn't have
    // caught as a behavior failure. This asserts the write actually reaches
    // `interface_.showBackendUtilization`.
    testWidgets('toggling it writes interface_.showBackendUtilization', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          interface_: InterfaceSettings(showBackendUtilization: true),
        ),
      );
      await tester.pumpWidget(_pumpAppearance(tester, notifier));
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey('settings-row-appearance-backend-utilization'),
      );
      expect(row, findsOneWidget);
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(notifier.state.value!.interface_.showBackendUtilization, isFalse);
    });
  });
}
