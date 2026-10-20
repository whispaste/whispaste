/// Settings navigation (WP-23b): the seven areas in the left column, selection
/// by tap, and deep links that switch to the area holding the target row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

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

String _pageTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(WpPageHeader),
        matching: find.byType(Text),
      ),
    )
    .data!;

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
      expect(_pageTitle(tester), l10n.settingsAreaGeneral);

      await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
      await tester.pumpAndSettle();

      expect(_pageTitle(tester), l10n.settingsAreaPrivacy);
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

  group('Settings deep links', () {
    testWidgets('a row id opens the area that holds the row', (tester) async {
      await _pumpSettings(tester, overrides: [_deepLinkTo('appearance-mode')]);

      expect(_pageTitle(tester), l10n.settingsAreaAppearance);
    });

    testWidgets('a legacy section key still resolves to its area', (
      tester,
    ) async {
      await _pumpSettings(tester, overrides: [_deepLinkTo('appearance')]);

      expect(_pageTitle(tester), l10n.settingsAreaAppearance);
    });
  });
}
