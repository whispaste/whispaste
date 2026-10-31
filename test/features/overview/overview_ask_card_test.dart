import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_ask_card.dart';
import 'package:whispaste/features/overview/overview_providers.dart';

import '../../fixtures/test_helpers.dart';

/// Hand-off test: each action of the milestone and rate/share card records
/// its choice where the next visit reads it. Actions are found by testID.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester,
    OverviewAskCard card,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: OverviewAskCardView()),
        overrides: [overviewAskCardProvider.overrideWithValue(card)],
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(OverviewAskCardView)),
    );
  }

  Future<SharedPreferences> tapAndRead(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
    return SharedPreferences.getInstance();
  }

  testWidgets('"Später" snoozes, the close button stops asking', (
    tester,
  ) async {
    await pump(tester, const OverviewRateShareCard());
    var prefs = await tapAndRead(tester, 'overview-rate-later');
    expect(prefs.getInt('review_prompt_last_snooze'), isNotNull);
    expect(prefs.getBool('review_prompt_permanently_dismissed'), isNull);

    prefs = await tapAndRead(tester, 'overview-rate-never');
    expect(prefs.getBool('review_prompt_permanently_dismissed'), isTrue);
  });

  testWidgets('sharing copies the website link and counts as asked', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, const OverviewRateShareCard());
    final prefs = await tapAndRead(tester, 'overview-share');
    expect(copied, startsWith('https://whispaste.de'));
    expect(prefs.getInt('review_prompt_last_shown'), isNotNull);
  });

  testWidgets('closing a milestone remembers it and the day', (tester) async {
    final container = await pump(tester, const OverviewMilestoneCard(100));
    await tester.tap(find.bySemanticsIdentifier('overview-milestone-close'));
    await tester.pumpAndSettle();
    final prefs = container.read(overviewPrefsProvider);
    expect(prefs.milestonesSeen, {100});
    expect(prefs.askCardDay, isNotNull);
  });
}
