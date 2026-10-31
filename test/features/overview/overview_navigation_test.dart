import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/overview/overview_navigation.dart';

/// Hand-off test: a row or action of the overview must land on the right page
/// and, for a Settings target, the right row. Targets are asserted as plain
/// ids, never by label.
void main() {
  Future<ProviderContainer> pumpWithTarget(
    WidgetTester tester,
    String target, {
    void Function(WidgetRef ref)? open,
  }) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Scaffold(
                body: TextButton(
                  key: const ValueKey('overview-test-go'),
                  onPressed: () => open != null
                      ? open(ref)
                      : overviewOpenTarget(ref, target),
                  child: const Text('go'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('overview-test-go')));
    await tester.pump();
    return container;
  }

  testWidgets('a nav target opens that page', (tester) async {
    final container = await pumpWithTarget(tester, 'history');
    expect(container.read(activePageProvider), 'history');
  });

  testWidgets('a settings target opens Settings at the named row', (
    tester,
  ) async {
    final container = await pumpWithTarget(tester, 'settings:stt-model');
    expect(container.read(activePageProvider), 'settings');
    expect(container.read(settingsScrollTargetProvider), 'stt-model');
  });

  testWidgets('a recording opens the Aufnahmen page on that entry', (
    tester,
  ) async {
    final container = await pumpWithTarget(
      tester,
      '',
      open: (ref) => overviewOpenRecording(ref, 'entry-7'),
    );
    expect(container.read(activePageProvider), 'history');
    expect(container.read(historyOpenEntryProvider), 'entry-7');
  });
}
