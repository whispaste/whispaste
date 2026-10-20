/// Widget tests for the automation integrations block (WP-38 / 8.2 to 8.4).
///
/// Covers the hooks dialog: adding a loopback hook, the rejection messages
/// for non-loopback URLs and an empty event set, the eight-hook limit, and
/// removal. The settings notifier is a fake, so the assertions read the
/// rendered state the dialog derives from it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/automation_hooks.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/widgets/automation_integrations.dart';

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
}

Widget _pump({List<AutomationHook> hooks = const []}) {
  final settings = AppSettings.defaults.copyWithSections(
    automationApi: AppSettings.defaults.automationApi.copyWith(hooks: hooks),
  );
  return makeTestable(
    const SingleChildScrollView(child: AutomationIntegrationsGroup()),
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
    ],
  );
}

Finder _urlField() => find.descendant(
  of: find.byKey(const ValueKey('automation-hook-url')),
  matching: find.byType(EditableText),
);

Future<void> _openDialog(WidgetTester tester) async {
  // The binding's default view is 800x600; the dialog needs more height.
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.tap(find.byKey(const ValueKey('automation-event-hooks-manage')));
  await tester.pumpAndSettle();
}

Future<void> _enterUrl(WidgetTester tester, String url) async {
  await tester.enterText(_urlField(), url);
  await tester.pump();
}

Future<void> _add(WidgetTester tester) async {
  // The dialog body scrolls; bring the add button into view like a user would.
  await tester.ensureVisible(find.byKey(const ValueKey('automation-hook-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('automation-hook-add')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the group shows both rows and an empty hook count', (
    tester,
  ) async {
    await tester.pumpWidget(_pump());

    expect(
      find.byKey(const ValueKey('settings-row-automation-event-hooks')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('settings-row-automation-cli-mcp')),
      findsOne,
    );
    expect(find.text('No hooks'), findsOne);
  });

  testWidgets('the hooks row says hooks fire while the API server is off', (
    tester,
  ) async {
    await tester.pumpWidget(_pump());

    expect(
      find.textContaining('keep firing even when the API server is off'),
      findsOne,
    );
  });

  testWidgets('adding a loopback hook lists it and updates the count', (
    tester,
  ) async {
    await tester.pumpWidget(_pump());
    await _openDialog(tester);

    await _enterUrl(tester, 'http://127.0.0.1:9000/hook');
    await _add(tester);

    expect(find.text('http://127.0.0.1:9000/hook'), findsOne);
    // Once in the checkbox, once in the hook's event line.
    expect(find.text('Transcript finished'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('automation-hook-error')), findsNothing);
    expect(find.byKey(const ValueKey('automation-hooks-empty')), findsNothing);
  });

  testWidgets('localhost and IPv6 loopback are accepted', (tester) async {
    await tester.pumpWidget(_pump());
    await _openDialog(tester);

    await _enterUrl(tester, 'http://localhost:9001/hook');
    await _add(tester);
    await _enterUrl(tester, 'http://[::1]:9002/hook');
    await _add(tester);

    expect(find.text('http://localhost:9001/hook'), findsOne);
    expect(find.text('http://[::1]:9002/hook'), findsOne);
  });

  for (final url in [
    'http://example.com/hook',
    'http://localhost.evil.com/hook',
    'http://2130706433/hook',
    'http://[::ffff:127.0.0.1]/hook',
    'https://127.0.0.1/hook',
  ]) {
    testWidgets('rejects non-loopback URL $url with a message', (tester) async {
      await tester.pumpWidget(_pump());
      await _openDialog(tester);

      await _enterUrl(tester, url);
      await _add(tester);

      expect(find.byKey(const ValueKey('automation-hook-error')), findsOne);
      expect(find.text('No connection set up yet.'), findsOne);
    });
  }

  testWidgets('a hook without any event is refused', (tester) async {
    await tester.pumpWidget(_pump());
    await _openDialog(tester);

    await _enterUrl(tester, 'http://127.0.0.1:9000/hook');
    await tester.tap(
      find.byKey(const ValueKey('automation-hook-event-transcript-finished')),
    );
    await tester.pump();
    await _add(tester);

    expect(find.text('Choose at least one event.'), findsOne);
    expect(find.text('No connection set up yet.'), findsOne);
  });

  testWidgets('the ninth hook is refused with the limit message', (
    tester,
  ) async {
    final full = [
      for (var i = 0; i < kAutomationHookMaxCount; i++)
        AutomationHook(
          url: 'http://127.0.0.1:${9100 + i}/hook',
          events: {'note.changed'},
        ),
    ];
    await tester.pumpWidget(_pump(hooks: full));
    await _openDialog(tester);

    await _enterUrl(tester, 'http://127.0.0.1:9200/hook');
    await _add(tester);

    expect(find.text('You can add up to 8 hooks.'), findsOne);
    // The typed URL stays in the field; the list must not gain a ninth row.
    expect(
      find.byKey(const ValueKey('automation-hook-remove-8')),
      findsNothing,
    );
  });

  testWidgets('removing the only hook returns the dialog to the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pump(
        hooks: const [
          AutomationHook(
            url: 'http://127.0.0.1:9300/hook',
            events: {'note.changed'},
          ),
        ],
      ),
    );
    await _openDialog(tester);

    expect(find.text('http://127.0.0.1:9300/hook'), findsOne);
    await tester.tap(find.byKey(const ValueKey('automation-hook-remove-0')));
    await tester.pumpAndSettle();
    // Removing asks first (UIA-SET-03).
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('http://127.0.0.1:9300/hook'), findsNothing);
    expect(find.text('No connection set up yet.'), findsOne);
  });

  testWidgets('cancelling the remove question keeps the hook (UIA-SET-03)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pump(
        hooks: const [
          AutomationHook(
            url: 'http://127.0.0.1:9300/hook',
            events: {'note.changed'},
          ),
        ],
      ),
    );
    await _openDialog(tester);

    await tester.tap(find.byKey(const ValueKey('automation-hook-remove-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('http://127.0.0.1:9300/hook'), findsOne);
  });
}
