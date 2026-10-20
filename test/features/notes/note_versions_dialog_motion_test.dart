/// The versions panel opens within the normal motion token and respects the
/// system reduce-motion flag (WP-31a, benchmark finding on the panel open).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/notes/widgets/note_versions_dialog.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  Widget opener({required bool reduceMotion}) {
    return makeTestable(
      Builder(
        builder: (outer) => MediaQuery(
          data: MediaQuery.of(outer).copyWith(disableAnimations: reduceMotion),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-versions'),
                  onPressed: () => showNoteVersionsDialog(
                    context: context,
                    noteId: 'note-1',
                  ),
                  child: const Text('versions'),
                ),
              ),
            ),
          ),
        ),
      ),
      locale: const Locale('de'),
    );
  }

  Future<Duration> openedTransition(
    WidgetTester tester, {
    required bool reduceMotion,
  }) async {
    await tester.pumpWidget(opener(reduceMotion: reduceMotion));
    await tester.tap(find.byKey(const ValueKey('open-versions')));
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Schließen')))!;
    final duration = route.transitionDuration;
    await tester.pumpAndSettle();
    // Drift's stream timers must finish inside the test.
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    return duration;
  }

  testWidgets('the versions panel opens within the normal motion token', (
    tester,
  ) async {
    final duration = await openedTransition(tester, reduceMotion: false);
    expect(duration, lessThanOrEqualTo(WpMotion.normal));
  });

  testWidgets('reduce motion makes the versions panel open without motion', (
    tester,
  ) async {
    final duration = await openedTransition(tester, reduceMotion: true);
    expect(duration, Duration.zero);
  });
}
