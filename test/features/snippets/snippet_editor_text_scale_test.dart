/// The snippet editor stays usable at 200 % text size in a short window
/// (#1371): head, body and footer never overflow, and every control is
/// still reached with Tab.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

import '../../fixtures/test_helpers.dart';

Widget _scaled(Widget child, double scale) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> openEditor(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required String kind,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await db.upsertSnippetWithFields(
        id: 's1',
        title: 'Gruss',
        body: 'Hallo {name}',
        createdAt: DateTime(2026),
        kind: kind,
        fieldNames: kind == 'interactive' ? const ['name'] : const [],
      );
    });
    await tester.pumpWidget(
      makeTestable(
        _scaled(const SnippetsPage(), scale),
        size: size,
        db: db,
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('snippets-item-s1'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  for (final kind in ['static', 'interactive']) {
    for (final size in const [
      Size(1280, 720),
      Size(900, 720),
      Size(720, 720),
      Size(1280, 480),
      Size(900, 400),
    ]) {
      testWidgets('the $kind snippet editor fits at 200 % in a '
          '${size.width.toInt()}x${size.height.toInt()} window', (
        tester,
      ) async {
        await openEditor(tester, size: size, scale: 2, kind: kind);
        // An overflow is reported as a FlutterError and fails the test here.
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('snippets-editor-hint')),
          findsOneWidget,
        );

        // Tab walks through every control of the editor; each one it lands
        // on is scrolled into the window.
        final editor = find.bySemanticsIdentifier('snippets-editor');
        final window = Offset.zero & size;
        final reached = <String>{};
        for (var i = 0; i < 60; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused == null) continue;
          final inEditor = find
              .ancestor(
                of: find.byElementPredicate((e) => e == focused),
                matching: editor,
              )
              .evaluate()
              .isNotEmpty;
          if (!inEditor) continue;
          final box = focused.findRenderObject()! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(
            rect.overlaps(window),
            isTrue,
            reason: 'focused ${focused.widget} at $rect is out of view',
          );
          for (final id in ['snippets-editor-close', 'snippets-body-field']) {
            if (find
                .ancestor(
                  of: find.byElementPredicate((e) => e == focused),
                  matching: find.bySemanticsIdentifier(id),
                )
                .evaluate()
                .isNotEmpty) {
              reached.add(id);
            }
          }
        }
        expect(reached, {'snippets-editor-close', 'snippets-body-field'});

        // The hint at the bottom of the pane can be scrolled into view.
        final hint = find.byKey(const ValueKey('snippets-editor-hint'));
        await tester.ensureVisible(hint);
        await tester.pumpAndSettle();
        expect(window.contains(tester.getBottomLeft(hint)), isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 10));
      });
    }
  }
}
