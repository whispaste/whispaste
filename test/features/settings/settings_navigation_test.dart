/// Settings navigation (ticket): the seven areas in the left column, selection
/// by tap, and deep links that switch to the area holding the target row.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/sections/permissions_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/settings/widgets/settings_navigation.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// Answers at once: a real channel never replies in a widget test, and the
/// privacy area's permission rows read the microphone status on open.
class _AnsweringMic implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

/// Starts with [_target] already set, as a deep link from elsewhere would.
class _DeepLinkScrollTarget extends SettingsScrollTargetNotifier {
  _DeepLinkScrollTarget(this._target);

  final String _target;

  @override
  String? build() => _target;
}

Override _deepLinkTo(String rowId) => settingsScrollTargetProvider.overrideWith(
  () => _DeepLinkScrollTarget(rowId),
);

SettingsArea _currentArea(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(SettingsPage)),
).read(settingsAreaProvider);

Future<void> _pumpSettings(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      const SettingsPage(),
      locale: const Locale('en'),
      overrides: [
        hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
        micPermissionCheckerProvider.overrideWithValue(_AnsweringMic()),
        ...overrides,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Settings navigation', () {
    // #1916: the entry named itself and then appended its visible text, so
    // assistive tech read every area twice ("General General").
    testWidgets('each area entry is one button named once', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpSettings(tester);

      for (final area in SettingsArea.values) {
        final data = tester
            .getSemantics(find.byKey(ValueKey('settings-nav-${area.id}')))
            .getSemanticsData();
        expect(data.label, settingsAreaLabel(l10n, area), reason: area.id);
        expect(data.flagsCollection.isButton, isTrue, reason: area.id);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: area.id);
      }
      handle.dispose();
    });

    testWidgets('lists all seven areas with stable ids', (tester) async {
      await _pumpSettings(tester);

      for (final area in SettingsArea.values) {
        expect(
          find.byKey(ValueKey('settings-nav-${area.id}')),
          findsOneWidget,
          reason: area.id,
        );
      }
    });

    testWidgets('tapping an area switches the page to it', (tester) async {
      await _pumpSettings(tester);
      expect(_currentArea(tester), SettingsArea.general);

      await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
      await tester.pumpAndSettle();

      expect(_currentArea(tester), SettingsArea.privacy);
    });

    testWidgets('the open area is marked as selected', (tester) async {
      await _pumpSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-speech')));
      await tester.pumpAndSettle();

      final row = tester.getSemantics(
        find.byKey(const ValueKey('settings-nav-speech')),
      );
      expect(row.flagsCollection.isSelected.toString(), contains('isTrue'));
    });
  });

  // #1845: areas started inconsistently, some with their own heading, some
  // with a sub-heading or only a description. Each now opens with its name,
  // and no group under it repeats that name.
  testWidgets('every area starts with its own name as heading', (tester) async {
    await _pumpSettings(tester);
    for (final area in SettingsArea.values) {
      await tester.tap(find.byKey(ValueKey('settings-nav-${area.id}')));
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('settings-area-heading'));
      final name = settingsAreaLabel(l10n, area);
      expect(
        find.descendant(of: heading, matching: find.text(name)),
        findsOneWidget,
        reason: area.id,
      );
    }
  });

  group('Settings deep links', () {
    testWidgets('a row id opens the area that holds the row', (tester) async {
      await _pumpSettings(tester, overrides: [_deepLinkTo('appearance-mode')]);

      expect(_currentArea(tester), SettingsArea.appearance);
    });

    testWidgets('a legacy section key still resolves to its area', (
      tester,
    ) async {
      await _pumpSettings(tester, overrides: [_deepLinkTo('appearance')]);

      expect(_currentArea(tester), SettingsArea.appearance);
    });

    testWidgets('the jump moves keyboard focus onto a control of the row', (
      tester,
    ) async {
      await _pumpSettings(tester, overrides: [_deepLinkTo('appearance-mode')]);

      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: find.byKey(const ValueKey('settings-row-appearance-mode')),
        ),
        findsOneWidget,
      );
    });
  });

  group('Settings search', () {
    testWidgets('Enter without a highlight opens the first match and focuses '
        'a control of its row', (tester) async {
      await _pumpSettings(tester);
      final field = find.byKey(const ValueKey('settings-search-field'));
      await tester.tap(field);
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(EditableText)),
        'appearance',
      );
      // No pump past the debounce: Enter applies the query itself.
      final container = ProviderScope.containerOf(tester.element(field));
      final first = matchSettingsEntries(
        settingsSearchTableFor(defaultTargetPlatform),
        'appearance',
        container.read(localeProvider).languageCode,
      ).first;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: find.byKey(ValueKey('settings-row-${first.rowId}')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Enter without a match keeps the focus in the field', (
      tester,
    ) async {
      await _pumpSettings(tester);
      final field = find.byKey(const ValueKey('settings-search-field'));
      await tester.tap(field);
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(EditableText)),
        'zzqxnomatch',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: field,
        ),
        findsOneWidget,
      );
    });
  });

  group('Permission rows per platform', () {
    // The rule: a row appears only where the system has a grant to give.
    const expected = <TargetPlatform, Set<String>>{
      TargetPlatform.macOS: {
        kPermissionMicRowId,
        kPermissionPasteRowId,
        kPermissionInputMonitoringRowId,
      },
      TargetPlatform.windows: {kPermissionMicRowId},
      TargetPlatform.linux: {},
    };
    const all = {
      kPermissionMicRowId,
      kPermissionPasteRowId,
      kPermissionInputMonitoringRowId,
    };

    for (final MapEntry(key: platform, value: rows) in expected.entries) {
      testWidgets('${platform.name}: rows and search hits match', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final searchable = {
            for (final e in settingsSearchTableFor(platform)) e.rowId,
          }.intersection(all);
          expect(searchable, rows, reason: 'search offers only shown rows');

          await _pumpSettings(tester, overrides: [_deepLinkTo('privacy')]);
          for (final id in all) {
            expect(
              find.byKey(ValueKey('settings-row-$id')),
              rows.contains(id) ? findsOneWidget : findsNothing,
              reason: id,
            );
          }
          // An empty section leaves no heading behind.
          expect(
            find.text(l10n.settingsPermissions),
            rows.isEmpty ? findsNothing : findsWidgets,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });
}
