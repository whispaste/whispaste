/// The auto-paste block list is an app list editor, not a comma text field:
/// rows with a readable name and the identifier, remove buttons, and an
/// "Add app" picker that offers recently dictated apps first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/features/settings/widgets/auto_paste_blocklist_field.dart';
import 'package:whispaste/services/paste/auto_paste_blocklist.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

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
}

AppSettings _settings(String blocklist) =>
    AppSettings.defaults.copyWithSections(
      behavior: AppSettings.defaults.behavior.copyWith(
        autoPasteBlocklist: blocklist,
      ),
    );

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester, {
  required String blocklist,
  bool detection = true,
  bool macOS = true,
  List<RecentTargetApp> recent = const [],
}) async {
  final notifier = _FakeSettingsNotifier(_settings(blocklist));
  await tester.pumpWidget(
    makeTestable(
      Consumer(
        builder: (context, ref, _) {
          final settings =
              ref.watch(settingsProvider).value ?? AppSettings.defaults;
          return SingleChildScrollView(
            child: AutoPasteBlocklistField(
              settings: settings,
              targetDetectionAvailable: detection,
              isMacOS: macOS,
            ),
          );
        },
      ),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => notifier),
        recentDictationAppsProvider.overrideWith((ref) => recent),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

String _stored(_FakeSettingsNotifier notifier) =>
    notifier.state.value!.behavior.autoPasteBlocklist;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('list rows', () {
    testWidgets('an empty list says so and offers the add button', (
      tester,
    ) async {
      await _pump(tester, blocklist: '');

      expect(find.text(l10n.settingsPasteBlocklistEmpty), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-paste-blocklist-add')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('each entry shows a readable name and its identifier', (
      tester,
    ) async {
      await _pump(tester, blocklist: 'com.apple.Terminal, notepad.exe');

      expect(
        find.byKey(
          const ValueKey('settings-paste-blocklist-row-com-apple-terminal'),
        ),
        findsOneWidget,
      );
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('com.apple.Terminal'), findsOneWidget);
      expect(find.text('notepad'), findsOneWidget);
      expect(find.text('notepad.exe'), findsOneWidget);
    });

    testWidgets('the remove button drops exactly that entry', (tester) async {
      final notifier = await _pump(
        tester,
        blocklist: 'com.apple.Terminal, notepad.exe',
      );

      await tester.tap(
        find.byKey(
          const ValueKey('settings-paste-blocklist-remove-com-apple-terminal'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_stored(notifier), 'notepad.exe');
    });

    testWidgets('an old comma-separated value reads unchanged', (tester) async {
      await _pump(tester, blocklist: 'com.1password.1password,Safari');

      expect(find.text('com.1password.1password'), findsOneWidget);
      // Safari is shown as its name and as its identifier.
      expect(find.text('Safari'), findsNWidgets(2));
    });
  });

  group('picker', () {
    testWidgets(
      'recently dictated apps are offered and picking one blocks it',
      (tester) async {
        final notifier = await _pump(
          tester,
          blocklist: '',
          recent: [
            RecentTargetApp(
              identifier: 'Slack',
              lastUsed: DateTime(2026, 10, 2),
            ),
            RecentTargetApp(
              identifier: 'chrome.exe',
              lastUsed: DateTime(2026, 10, 1),
            ),
          ],
        );

        await tester.tap(
          find.byKey(const ValueKey('settings-paste-blocklist-add')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.settingsPasteBlocklistPickerTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.settingsPasteBlocklistRecentHeading),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(
            const ValueKey('settings-paste-blocklist-picker-app-chrome'),
          ),
        );
        await tester.pumpAndSettle();

        expect(_stored(notifier), 'chrome.exe');
        expect(find.text(l10n.settingsPasteBlocklistPickerTitle), findsNothing);
      },
    );

    testWidgets('apps already on the list are not offered again', (
      tester,
    ) async {
      await _pump(
        tester,
        blocklist: 'chrome',
        recent: [
          RecentTargetApp(
            identifier: 'chrome.exe',
            lastUsed: DateTime(2026, 10, 2),
          ),
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-paste-blocklist-add')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-paste-blocklist-picker-empty')),
        findsOneWidget,
      );
    });

    testWidgets('without history the picker explains and keeps manual entry', (
      tester,
    ) async {
      await _pump(tester, blocklist: '');

      await tester.tap(
        find.byKey(const ValueKey('settings-paste-blocklist-add')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-paste-blocklist-picker-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-paste-blocklist-manual-add')),
        findsOneWidget,
      );
    });

    testWidgets(
      'manual identifier entry adds it and the add button needs text',
      (tester) async {
        final handle = tester.ensureSemantics();
        final notifier = await _pump(tester, blocklist: '');

        await tester.tap(
          find.byKey(const ValueKey('settings-paste-blocklist-add')),
        );
        await tester.pumpAndSettle();

        final manualAdd = find.byKey(
          const ValueKey('settings-paste-blocklist-manual-add'),
        );
        expect(
          tester
              .widget<WpButton>(
                find.ancestor(of: manualAdd, matching: find.byType(WpButton)),
              )
              .onPressed,
          isNull,
        );

        await tester.enterText(
          find.descendant(
            of: find.byKey(
              const ValueKey('settings-paste-blocklist-manual-field'),
            ),
            matching: find.byType(TextField),
          ),
          'notepad.exe',
        );
        await tester.pump();
        await tester.tap(manualAdd);
        await tester.pumpAndSettle();

        expect(_stored(notifier), 'notepad.exe');
        handle.dispose();
      },
    );
  });

  group('platform variants', () {
    testWidgets('without target detection (Wayland) the plain hint is shown', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await _pump(tester, blocklist: '', detection: false);
        expect(
          find.bySemanticsIdentifier(
            'text-auto-paste-blocklist-no-detection-hint',
          ),
          findsOneWidget,
        );
        expect(
          find.text(l10n.settingsAutoPasteBlocklistNoDetectionHint),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a short name is no warning on Windows or Linux', (
      tester,
    ) async {
      await _pump(tester, blocklist: 'Safari', macOS: false);

      expect(
        find.byKey(const Key('text-auto-paste-blocklist-short-prefix-warning')),
        findsNothing,
      );
    });

    testWidgets('a short name on macOS shows the bundle-id warning', (
      tester,
    ) async {
      await _pump(tester, blocklist: 'Safari', macOS: true);

      expect(
        find.byKey(const Key('text-auto-paste-blocklist-short-prefix-warning')),
        findsOneWidget,
      );
    });
  });
}
