/// Guard against stray and stacked dividers in settings groups.
///
/// WpSettingsGroup puts one divider between each pair of children. A child
/// that renders nothing (a `SizedBox.shrink()`) therefore leaves a divider
/// behind: stacked on another one in the middle of a group, or dangling at the
/// card's top or bottom edge. Every settings area is pumped with its default
/// providers and checked for both. The CUDA row is also checked while it is
/// offered but has no pack, a state the defaults do not reach.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

import '../../fixtures/test_helpers.dart';
import 'settings_area_fixture.dart';
import 'widgets/settings_golden_board.dart';

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

Future<void> _pumpArea(
  WidgetTester tester,
  SettingsArea area, {
  List<Object> extra = const [],
}) async {
  tester.view.physicalSize = const Size(1132, 752);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  WpColors.activate(kSettingsGoldenSets['light']!);
  await tester.pumpWidget(
    makeTestable(
      settingsGoldenBoard(
        set: kSettingsGoldenSets['light']!,
        size: const Size(1100, 720),
        height: 720,
        boundaryKey: ValueKey('dividers-${area.id}'),
        child: const SettingsPage(),
      ),
      size: const Size(1132, 752),
      locale: const Locale('en'),
      overrides: [
        settingsAreaAt(area),
        hotkeyServiceProvider.overrideWith(() => _NoopHotkeyService()),
        audioInputDevicesProvider.overrideWith(
          (ref) async => const <String>['Default', 'Built-in Microphone'],
        ),
        ...extra,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoStrayDividers(WidgetTester tester, String area) {
  final dividers = find.byType(Divider);
  final tops = [
    for (var i = 0; i < dividers.evaluate().length; i++)
      tester.getRect(dividers.at(i)).top,
  ]..sort();
  for (var i = 1; i < tops.length; i++) {
    expect(
      tops[i] - tops[i - 1],
      greaterThan(1),
      reason:
          'two dividers stacked at y=${tops[i - 1]} and y=${tops[i]} in $area',
    );
  }

  // Two dividers need a row between them. A spacer between two rows (the
  // settingsInlineBreak sub-group rule) must not add a second rule: the
  // children of each card column, minus spacers, may never hold two
  // dividers next to each other.
  final groupCards = find.byKey(const ValueKey('settings-group-card'));
  for (var c = 0; c < groupCards.evaluate().length; c++) {
    final column = tester.widget<Column>(
      find
          .descendant(of: groupCards.at(c), matching: find.byType(Column))
          .first,
    );
    final children = column.children
        .where((w) => !(w is SizedBox && w.child == null))
        .toList();
    for (var i = 0; i < children.length; i++) {
      if (children[i] is! Divider) continue;
      expect(
        i > 0 && i < children.length - 1,
        isTrue,
        reason: 'divider at the edge of a group in $area',
      );
      expect(
        children[i - 1] is Divider || children[i + 1] is Divider,
        isFalse,
        reason: 'two dividers without a row between them in $area',
      );
    }
  }

  // A divider sits between two rows. One at the card's top or bottom edge
  // comes from an empty first or last child and shows as a stray rule.
  final cards = find.byKey(const ValueKey('settings-group-card'));
  for (var i = 0; i < dividers.evaluate().length; i++) {
    final divider = tester.getRect(dividers.at(i));
    for (var c = 0; c < cards.evaluate().length; c++) {
      final card = tester.getRect(cards.at(c));
      if (!card.contains(divider.center)) continue;
      expect(
        divider.top - card.top,
        greaterThan(20),
        reason: 'divider at the top edge of a group in $area',
      );
      expect(
        card.bottom - divider.bottom,
        greaterThan(20),
        reason: 'divider at the bottom edge of a group in $area',
      );
    }
  }
}

void main() {
  tearDown(() => WpColors.activate(wpLightColors));

  for (final area in SettingsArea.values) {
    testWidgets('no stray dividers in settings area ${area.id}', (
      tester,
    ) async {
      await _pumpArea(tester, area);
      _expectNoStrayDividers(tester, area.id);
    });
  }

  testWidgets(
    'no stray dividers while the CUDA row is offered without a pack',
    (tester) async {
      await _pumpArea(
        tester,
        SettingsArea.speech,
        extra: [cudaPackOfferedProvider.overrideWithValue(true)],
      );
      _expectNoStrayDividers(tester, 'speech (CUDA offered, no pack)');
    },
  );
}
