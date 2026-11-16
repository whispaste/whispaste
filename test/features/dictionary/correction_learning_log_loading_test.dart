/// The learning log does not flash its empty text while the log is first read
/// (#618): until the load finishes it shows neither the empty text nor an
/// error, and only then the empty text.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/dictionary/correction_learning_log.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_log.dart';
import 'package:whispaste/widgets/wp_error_notice.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('first load shows neither the empty text nor an error', (
    tester,
  ) async {
    final load = Completer<List<CorrectionLogEntry>>();
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(
          body: SingleChildScrollView(child: CorrectionLearningLog()),
        ),
        locale: const Locale('en'),
        overrides: [correctionLogProvider.overrideWith((ref) => load.future)],
      ),
    );
    await tester.pump();

    const empty = ValueKey('dictionary-learning-log-empty');
    expect(find.byKey(empty), findsNothing);
    expect(
      find.byKey(const ValueKey('dictionary-learning-log-list')),
      findsNothing,
    );
    expect(find.byType(WpErrorNotice), findsNothing);

    load.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byKey(empty), findsOneWidget);
  });
}
