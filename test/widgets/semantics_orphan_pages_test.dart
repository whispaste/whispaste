// Issue #153: resizing the main window crashed the Windows app whenever an
// accessibility client was listening. Pumps every shell page with semantics
// on, types into its search field and resizes it across the split-view
// breakpoint down to the minimum window size, failing on any update the
// engine's AXTree would reject. New pages in `wpPageWidgets` are covered
// automatically.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart' show wpPageWidgets;
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';

import '../fixtures/semantics_tree_recorder.dart';
import '../fixtures/test_helpers.dart';

List<Object> _historyOverrides() {
  final all = generateSampleEntries();
  return [
    historyEntriesProvider.overrideWith(
      (ref) => Stream.value(
        all.where((e) => e.deletedAt == null && !e.archived).toList(),
      ),
    ),
    archivedEntriesProvider.overrideWith(
      (ref) => Stream.value(
        all.where((e) => e.archived && e.deletedAt == null).toList(),
      ),
    ),
    trashEntriesProvider.overrideWith(
      (ref) => Stream.value(all.where((e) => e.deletedAt != null).toList()),
    ),
  ];
}

const _sizes = [
  Size(1280, 800),
  Size(1000, 800),
  Size(WpLayout.minWindowWidth, WpLayout.minWindowHeight),
];

Future<void> _resizeThrough(WidgetTester tester) async {
  for (final size in [..._sizes.skip(1), ..._sizes.reversed.skip(1)]) {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpAndSettle();
  }
}

void main() {
  final recorder = SemanticsRecordingBinding.ensureInitialized().recorder;
  setUp(recorder.reset);

  for (final MapEntry(key: id, value: page) in wpPageWidgets.entries) {
    testWidgets('$id page sends no orphan semantics node', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(_sizes.first);
      await tester.pumpWidget(
        makeTestable(
          page,
          overrides: _historyOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _resizeThrough(tester);

      // A query reveals each search field's clear button — the second
      // tooltip button that tripped the engine.
      final field = find.byType(EditableText);
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field.first, 'a');
        await tester.pumpAndSettle();
        await _resizeThrough(tester);
      }

      expect(recorder.violations, isEmpty);

      // Unmount and let debounce/idle timers run out before the invariant
      // check (Notes schedules one).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.binding.setSurfaceSize(null);
      handle.dispose();
    });
  }
}
