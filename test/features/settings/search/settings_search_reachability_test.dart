/// Every visible settings row is in the search table and reachable through
/// the search (DEV-18). The static scan catches a row added to the page
/// without a table entry; the jump test searches each row's own title, picks
/// that row's suggestion, and checks the page lands on its area with the row
/// on screen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_navigation.dart';
import 'package:whispaste/features/settings/widgets/settings_search_field.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

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
  'advanced-automation-status',
  'advanced-automation-token',
  'advanced-beta-rollback-hint',
  'advanced-feature-spotlights',
  'advanced-onboarding-again',
  'appearance-floating-button',
  'appearance-floating-button-wayland',
  // Button look rows: only in the floating-button section (macOS/Windows).
  'appearance-button-idle-opacity',
  'appearance-button-ring',
  'appearance-button-shape',
  'appearance-button-size',
  'general-autostart-error',
  'general-review-prompt-restore',
  'general-hotkey-smart-mode-target',
  'privacy-backup-status',
  'privacy-history-auto-lock',
  'privacy-history-pin',
  'recording-clipping-hint',
  'speech-cuda-pack',
  'speech-deepgram-key',
  // Only with a graphics card that the GPU check applies to (not macOS).
  'speech-gpu-probe',
  // Linux only, under Auto-Paste (V1 Wayland); the fixture renders as macOS.
  'text-linux-always-shift-paste',
  'speech-keep-loaded-minutes',
  'speech-parakeet',
  'text-smart-mode-key',
  'text-smart-mode-target',
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

String _pageTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(WpPageHeader),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// Opens the Help hub on [tab], the way a settings search jump does.
class _TabAt extends HelpTargetNotifier {
  _TabAt(this._tab);

  final HelpTab _tab;

  @override
  HelpTarget? build() => HelpTarget(tab: _tab);
}

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

  group('each table row is reached by search and jump', () {
    for (final entry in kSettingsSearchTable) {
      // Dictionary rows open the Wörterbuch page, not a settings area.
      if (entry.area == SettingsRowArea.dictionary) continue;
      testWidgets('"${entry.rowId}" is reached through its own title', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingsPage(),
            locale: const Locale('en'),
            size: const Size(1280, 800),
            // The local Smart Mode rows render only with the engine present,
            // which the default check reports on macOS and Windows alone.
            overrides: [
              smartModeLocalEngineAvailableProvider.overrideWith((ref) => true),
              // A profile must exist for its detail rows to render.
              appProfilesProvider.overrideWith(_SeededProfiles.new),
              helpTargetProvider.overrideWith(
                () => _TabAt(helpTabForRow(entry.rowId)),
              ),
              // The hold-or-tap threshold renders only while that switch is on.
              if (entry.rowId == 'general-hold-or-tap-threshold')
                settingsProvider.overrideWith(() => _HoldOrTapOn()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final title = entry.titleOf(en);
        await tester.tap(_searchInput());
        await tester.enterText(_searchInput(), title);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Suggestions follow table order; pick this row's suggestion.
        final matches = matchSettingsEntries(kSettingsSearchTable, title, 'en');
        final index = matches.indexWhere((m) => m.rowId == entry.rowId);
        expect(index, isNonNegative, reason: '"$title" must suggest its row');
        for (var i = 0; i <= index; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        if (entry.area == SettingsRowArea.help) {
          // Help rows leave Settings: the jump sets the Help page, which
          // renders the row under its own settings-row key.
          final container = ProviderScope.containerOf(
            tester.element(find.byType(SettingsPage)),
          );
          expect(
            container.read(activePageProvider),
            'help',
            reason: 'the jump must open the Help page',
          );
          // Same overrides as the Settings tree above: a ProviderScope cannot
          // change its override count between pumps.
          await tester.pumpWidget(
            makeTestable(
              const HelpPage(),
              locale: const Locale('en'),
              size: const Size(1280, 800),
              overrides: [
                smartModeLocalEngineAvailableProvider.overrideWith(
                  (ref) => true,
                ),
                // Same count as the Settings tree: riverpod forbids changing it.
                appProfilesProvider.overrideWith(_SeededProfiles.new),
                helpTargetProvider.overrideWith(
                  () => _TabAt(helpTabForRow(entry.rowId)),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          // Rows in _renderedOnlyInState need a state the Help page does not
          // reach in the default fixture; for them the page jump is the check.
          if (_renderedOnlyInState.contains(entry.rowId)) return;
          expect(
            find.byKey(ValueKey('settings-row-${entry.rowId}')),
            findsWidgets,
            reason: 'the Help page must show the row',
          );
          return;
        }

        if (_renderedOnlyInState.contains(entry.rowId)) return;
        expect(
          _pageTitle(tester),
          settingsAreaLabel(en, entry.area.hostArea!),
          reason: 'the jump must switch to the row\'s area',
        );
        expect(
          find.byKey(ValueKey('settings-row-${entry.rowId}')),
          findsWidgets,
          reason: 'the jump must land on the row itself',
        );
      });
    }
  });
}

/// One profile, so the profile detail rows are part of the tree.
class _SeededProfiles extends AppProfilesController {
  @override
  Future<List<AppProfile>> build() async => const [
    AppProfile(id: 'profile-seed', name: 'Mail'),
  ];
}

class _HoldOrTapOn extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWithSections(
    audioInput: AppSettings.defaults.audioInput.copyWith(
      pushToTalk: true,
      holdOrTap: true,
    ),
  );
}
