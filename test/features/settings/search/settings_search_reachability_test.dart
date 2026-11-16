/// Every visible settings row is in the search table and reachable through
/// the search (DEV-18). The static scan catches a row added to the page
/// without a table entry. Data tests check that every row's own title
/// suggests the row and that the row resolves to its area or Help tab; one
/// widget test per Help tab checks that its rows render there (the settings
/// areas are rendered per state in settings_search_areas_test.dart), and two
/// end-to-end tests keep the real search, keyboard pick and jump (#1492).
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/widgets/auto_paste_blocklist_field.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';

import '../../../fixtures/test_helpers.dart';
import '../../../fixtures/record_device_listing_stub.dart';

/// Row ids written in the settings sources that are not rendered: the
/// `WpLanguageRow` widget that carries `stt-language` has no caller.
const Set<String> _unrenderedRowIds = {'stt-language'};

/// Rows that only render in a particular state (an error, an engine, a
/// feature flag or a licence), so the default fixture never shows them. They
/// are still checked: the static scan finds them and the search suggests
/// them. Their page jump is not asserted here.
const Set<String> _renderedOnlyInState = {
  // Only while the system speech engine is the chosen provider.
  'speech-system',
  'advanced-automation-status',
  'advanced-automation-token',
  'advanced-onboarding-again',
  'appearance-floating-button',
  'appearance-floating-button-wayland',
  // Button look rows: only in the floating-button section (macOS/Windows).
  'appearance-floating-button-idle-capsule',
  'appearance-button-idle-opacity',
  'appearance-button-ring',
  'appearance-button-shape',
  'appearance-button-size',
  'general-autostart-error',
  'general-review-prompt-restore',
  // Only while the "Erste Schritte" card can come back.
  'general-first-steps-restore',
  'general-hotkey-smart-mode-target',
  'privacy-backup-status',
  'privacy-history-auto-lock',
  // Only while "Save recordings" is off.
  'privacy-history-delete-existing',
  'privacy-history-pin',
  'recording-clipping-hint',
  // Only while the automatic level is off (#1611).
  'recording-gain',
  'speech-cuda-pack',
  // Only while a cloud speech provider is chosen (key status line, #208).
  'speech-api-key',
  // Only while the own OpenAI-compatible endpoint is the chosen provider.
  'speech-custom-endpoint-url',
  'speech-custom-endpoint-key',
  'speech-custom-endpoint-model',
  'speech-custom-endpoint-test',
  // Only with a graphics card that the GPU check applies to (not macOS).
  'speech-gpu-probe',
  // Linux only, under Auto-Paste (V1 Wayland); the fixture renders as macOS.
  'text-linux-always-shift-paste',
  'speech-keep-loaded-minutes',
  'speech-parakeet',
  'text-smart-mode-key',
  'text-smart-mode-target',
  'text-smart-mode-endpoint-url',
  'text-smart-mode-endpoint-key',
  'text-smart-mode-endpoint-model',
  'text-smart-mode-endpoint-test',
};

final RegExp _rowIdLiteral = RegExp(r"rowId: '([a-z0-9-]+)'");

Set<String> _rowIdsInSources() {
  final ids = <String>{};
  final files = [
    ...Directory('lib/features/settings/sections').listSync(recursive: true),
    ...Directory('lib/features/settings/widgets').listSync(recursive: true),
    File('lib/features/settings/settings_page.dart'),
  ];
  for (final entity in files) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final m in _rowIdLiteral.allMatches(entity.readAsStringSync())) {
      ids.add(m.group(1)!);
    }
  }
  return ids;
}

Finder _searchInput() => find.descendant(
  of: find.byType(SettingsSearchField),
  matching: find.byType(EditableText),
);

SettingsArea _currentArea(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(SettingsPage)),
).read(settingsAreaProvider);

/// Opens the Help hub on [tab], the way a settings search jump does.
class _TabAt extends HelpTargetNotifier {
  _TabAt(this._tab);

  final HelpTab _tab;

  @override
  HelpTarget? build() => HelpTarget(tab: _tab);
}

/// Pins macOS for the body and restores the platform before the test's
/// invariant check (a teardown would run too late).
void _desktopTest(String name, WidgetTesterCallback body) =>
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  stubRecordDeviceListing();
  late L10n en;

  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  test('every visible WpSettingsRow id is in kSettingsSearchTable', () {
    final tableIds = kSettingsSearchTable.map((e) => e.rowId).toSet();
    final sourceIds = _rowIdsInSources().difference(_unrenderedRowIds);
    expect(sourceIds, isNotEmpty, reason: 'scan found no rowId literals');
    expect(
      sourceIds.difference(tableIds),
      isEmpty,
      reason: 'rows rendered on the page but missing from the search table',
    );
  });

  // Rows the search hands to a page of its own: Wörterbuch rows open the
  // Wörterbuch page, Smart Mode rows the Smart Mode page (#891). Their pages
  // have their own jump tests; neither is a settings area.
  final searched = [
    for (final entry in kSettingsSearchTable)
      if (entry.area != SettingsRowArea.dictionary &&
          entry.area != SettingsRowArea.smartMode)
        entry,
  ];

  // Data tests (#1492): the search and the jump target of every row are pure
  // table logic, so they run as one check each instead of one widget test
  // per row. The widget tests below render each area and Help tab once.
  test('every row is suggested for its own title', () {
    final missing = [
      for (final entry in searched)
        if (!matchSettingsEntries(
          kSettingsSearchTable,
          entry.titleOf(en),
          'en',
        ).any((m) => m.rowId == entry.rowId))
          '${entry.rowId} ("${entry.titleOf(en)}")',
    ];
    expect(missing, isEmpty, reason: 'a row title must suggest its row');
  });

  test('every row resolves to the place its jump opens', () {
    final wrong = <String>[];
    for (final entry in searched) {
      // The page resolves a jump through the anchor lookup (legacy ids too);
      // a row's own id must resolve to the row itself.
      if (settingsRowAnchorFor(entry.rowId)?.rowId != entry.rowId) {
        wrong.add('${entry.rowId}: resolves to another row');
      }
      final help = entry.area == SettingsRowArea.help;
      if (help != (entry.hostArea == null)) {
        wrong.add(
          '${entry.rowId}: ${help ? 'Help row with a settings area' : 'no settings area'}',
        );
      }
    }
    expect(wrong, isEmpty);
  });

  group('every Help row renders on the Help tab its jump opens', () {
    final tabs = {
      for (final entry in searched)
        if (entry.area == SettingsRowArea.help) helpTabForRow(entry.rowId),
    };
    for (final tab in tabs) {
      _desktopTest(tab.name, (tester) async {
        await tester.pumpWidget(_helpTree(tab));
        await tester.pumpAndSettle();
        expect(
          _missingRows(
            searched.where(
              (e) =>
                  e.area == SettingsRowArea.help &&
                  helpTabForRow(e.rowId) == tab,
            ),
          ),
          isEmpty,
          reason: 'the search jumps to these rows on the ${tab.name} tab',
        );
      });
    }
  });

  // The real interaction once per kind of target: type the title, pick the
  // row's suggestion with the keyboard, land on the target.
  group('search and jump end to end', () {
    _desktopTest('a settings row in another area: area switches, row shows', (
      tester,
    ) async {
      final entry = searched.lastWhere(
        (e) =>
            e.hostArea == SettingsArea.advanced &&
            !_renderedOnlyInState.contains(e.rowId),
      );
      await tester.pumpWidget(_settingsTree());
      await tester.pumpAndSettle();
      expect(_currentArea(tester), isNot(SettingsArea.advanced));

      await _searchAndPick(tester, entry, en);

      expect(_currentArea(tester), SettingsArea.advanced);
      expect(
        find.byKey(ValueKey('settings-row-${entry.rowId}')),
        findsWidgets,
        reason: 'the jump must land on the row itself',
      );
    });

    _desktopTest('a Help row: the jump opens the Help page on its tab', (
      tester,
    ) async {
      final entry = searched.firstWhere((e) => e.area == SettingsRowArea.help);
      await tester.pumpWidget(_settingsTree());
      await tester.pumpAndSettle();

      await _searchAndPick(tester, entry, en);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      expect(
        container.read(activePageProvider),
        'help',
        reason: 'the jump must open the Help page',
      );
      expect(
        container.read(helpTargetProvider)?.tab,
        helpTabForRow(entry.rowId),
      );
    });
  });
}

/// Types [entry]'s title into the search and picks its suggestion with the
/// arrow keys and Enter. Suggestions follow table order.
Future<void> _searchAndPick(
  WidgetTester tester,
  SettingsSearchEntry entry,
  L10n en,
) async {
  final title = entry.titleOf(en);
  await tester.tap(_searchInput());
  await tester.enterText(_searchInput(), title);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  final matches = matchSettingsEntries(kSettingsSearchTable, title, 'en');
  final index = matches.indexWhere((m) => m.rowId == entry.rowId);
  expect(index, isNonNegative, reason: '"$title" must suggest its row');
  for (var i = 0; i <= index; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

/// Row ids of [entries] without a rendered row; rows in
/// [_renderedOnlyInState] need a state the fixture does not set.
List<String> _missingRows(Iterable<SettingsSearchEntry> entries) => [
  for (final entry in entries)
    if (!_renderedOnlyInState.contains(entry.rowId) &&
        find.byKey(ValueKey('settings-row-${entry.rowId}')).evaluate().isEmpty)
      entry.rowId,
];

/// Overrides every tree here shares. That every settings row renders in its
/// area, including the rows that need a state, is checked per area and state
/// in settings_search_areas_test.dart.
List _sharedOverrides(HelpTab tab) => [
  // The local Smart Mode rows render only with the engine present, which the
  // default check reports on macOS and Windows alone.
  smartModeLocalEngineAvailableProvider.overrideWith((ref) => true),
  // A profile must exist for its detail rows to render.
  appProfilesProvider.overrideWith(_SeededProfiles.new),
  // The recent-apps list watches the history stream; no recordings needed.
  recentDictationAppsProvider.overrideWithValue(const []),
  // On a real Linux host the probe asks the session bus with a timeout,
  // which outlives the test as a pending timer.
  linuxFocusStatusProvider.overrideWith(
    (ref) async => LinuxFocusStatus.unsupported,
  ),
  helpTargetProvider.overrideWith(() => _TabAt(tab)),
];

Widget _settingsTree({SettingsArea? area}) => makeTestable(
  const SettingsPage(),
  locale: const Locale('en'),
  size: const Size(1280, 800),
  overrides: [
    ..._sharedOverrides(HelpTab.manual),
    if (area != null) settingsAreaProvider.overrideWith(() => _AreaAt(area)),
  ],
);

Widget _helpTree(HelpTab tab) => makeTestable(
  const HelpPage(),
  locale: const Locale('en'),
  size: const Size(1280, 800),
  overrides: _sharedOverrides(tab),
);

class _AreaAt extends SettingsAreaNotifier {
  _AreaAt(this._area);

  final SettingsArea _area;

  @override
  SettingsArea build() => _area;
}

/// One profile, so the profile detail rows are part of the tree.
class _SeededProfiles extends AppProfilesController {
  @override
  Future<List<AppProfile>> build() async => const [
    AppProfile(id: 'profile-seed', name: 'Mail'),
  ];
}
