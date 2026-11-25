/// Hand-off test of the rating dialog (#2185): each button returns the
/// answer the watcher records, a share reports its channel and keeps the
/// dialog open, and the Mac App Store build offers no rating button of its
/// own (Apple's dialog is the ask there). Elements are found by test id.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/review/review_ask.dart';
import 'package:whispaste/features/review/review_ask_dialog.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late List<String> clipboard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<({ReviewAskAnswer? Function() answer, List<String> shares})> open(
    WidgetTester tester,
    ReviewRateWay way,
  ) async {
    ReviewAskAnswer? answer;
    final shares = <String>[];
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showReviewAskDialog(
                context: context,
                way: way,
                onShared: shares.add,
              );
            },
            child: const Text('open'),
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (answer: () => answer, shares: shares);
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  for (final (id, expected) in [
    ('review-ask-rate', ReviewAskAnswer.rate),
    ('review-ask-later', ReviewAskAnswer.later),
    ('review-ask-never', ReviewAskAnswer.never),
  ]) {
    testWidgets('$id answers ${expected.name}', (tester) async {
      final dialog = await open(tester, ReviewRateWay.microsoftStoreDialog);
      await tester.tap(byId(id));
      await tester.pumpAndSettle();
      expect(dialog.answer(), expected);
    });
  }

  testWidgets('copying the text reports its channel, the dialog stays', (
    tester,
  ) async {
    final dialog = await open(tester, ReviewRateWay.githubStar);
    final copy = find.byKey(const ValueKey('review-ask-share-copy'));
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(dialog.shares, ['copy']);
    // The copied link carries the campaign, never anything dictated.
    expect(clipboard.single, contains('mtm_campaign=app-share-copy'));
    expect(byId('review-ask-body'), findsOneWidget);
    expect(dialog.answer(), isNull);
  });

  testWidgets('Mac App Store: no rating button, only close and never', (
    tester,
  ) async {
    final dialog = await open(tester, ReviewRateWay.appleSystemDialog);
    expect(byId('review-ask-rate'), findsNothing);
    expect(byId('review-ask-later'), findsNothing);
    await tester.tap(byId('review-ask-close'));
    await tester.pumpAndSettle();
    expect(dialog.answer(), ReviewAskAnswer.done);
  });
}
