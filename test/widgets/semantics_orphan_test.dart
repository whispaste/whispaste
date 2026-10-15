// Regression guard for issue #153: the Windows engine crashes when the
// framework sends a semantics node no parent claims (see
// test/fixtures/semantics_tree_recorder.dart). Covers the shared widgets that
// produced such nodes; semantics_orphan_pages_test.dart covers whole pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/semantics_tree_recorder.dart';
import '../fixtures/test_helpers.dart';

void main() {
  final recorder = SemanticsRecordingBinding.ensureInitialized().recorder;
  setUp(recorder.reset);

  Future<void> pushPage(WidgetTester tester, WidgetBuilder page) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: page)),
              child: const Text('push'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
  }

  // Keeps the harness honest: if a Flutter upgrade fixes the upstream bug,
  // this fails and the workarounds below can be re-evaluated.
  testWidgets('recorder detects the upstream orphan (bare Slider, pushed)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pushPage(
      tester,
      (_) => Scaffold(body: Slider(value: 0.3, onChanged: (_) {})),
    );
    expect(recorder.violations, isNotEmpty);
    handle.dispose();
  });

  testWidgets('settingsSlider on a pushed page sends no orphan node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pushPage(
      tester,
      (context) => Scaffold(
        body: Center(
          child: settingsSlider(
            context: context,
            value: 0.5,
            min: 0,
            max: 1,
            divisions: 10,
            valueLabel: '50 %',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(recorder.violations, isEmpty);
    handle.dispose();
  });

  testWidgets('labelled WpSearchField with tooltip buttons sends no orphan '
      'node while typing and resizing', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      makeTestable(
        WpSearchField(
          controller: controller,
          hintText: 'Search…',
          variant: WpSearchFieldVariant.outlined,
          semanticsLabel: 'Search history',
          suffix: IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Search help',
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Typing reveals the clear button — a second tooltip button.
    await tester.enterText(find.byType(EditableText), 'abc');
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
    expect(recorder.violations, isEmpty);
    handle.dispose();
  });
}
