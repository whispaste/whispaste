/// Start screens that replace the shell when the history database cannot be
/// used (`lib/features/startup/`). Writes a PNG per theme and locale plus
/// `startup-a11y.txt`: which control holds the focus and what a screen reader
/// is told on arrival. Asserts nothing. Tagged `ux-screens`, never run in CI.
///
///   `UX_SCREENS_DIR=OUT_DIR wp-test.sh run WORKTREE --host ubu generators/ux/ux_startup_test.dart`
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/features/startup/database_upgrade_interrupted_screen.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<String> _themes = ['navy', 'dark'];
const List<String> _locales = ['de', 'he'];

/// Which start-screen button holds the focus, and every live-region text.
String _a11yReport(WidgetTester tester) {
  final focus = FocusManager.instance.primaryFocus?.context;
  var focused = 'none';
  for (final key in ['database-upgrade-retry', 'database-upgrade-quit']) {
    if (focus == null) break;
    final holds = find
        .ancestor(
          of: find.byElementPredicate((e) => e == focus),
          matching: find.byKey(ValueKey(key)),
        )
        .evaluate()
        .isNotEmpty;
    if (holds) focused = key;
  }
  // What a screen reader announces when a live region appears: its own
  // label plus the labels below it.
  String spoken(SemanticsNode node) {
    final parts = <String>[node.getSemanticsData().label];
    node.visitChildren((c) {
      parts.add(spoken(c));
      return true;
    });
    return parts.where((t) => t.isNotEmpty).join(' ');
  }

  final live = [
    for (final e
        in find
            .byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true,
            )
            .evaluate())
      if (tester
          .getSemantics(find.byWidget(e.widget))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion)
        spoken(tester.getSemantics(find.byWidget(e.widget))),
  ];
  return 'focus: $focused\n'
      'live region: ${live.isEmpty ? 'none' : live.join(' | ')}\n';
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final theme in _themes) {
    for (final locale in _locales) {
      final name = 'startup-upgrade-interrupted__${theme}_$locale';
      testWidgets('ux-startup: $name', (tester) async {
        final semantics = tester.ensureSemantics();
        final db = await openSeededUxDatabase(tester);
        addTearDown(() => tester.runAsync(db.close));

        await pumpUxBody(
          tester,
          body: const DatabaseUpgradeInterruptedScreen(),
          db: db,
          size: kUxSize1100,
          theme: theme,
          locale: locale,
        );
        await tester.pump(const Duration(milliseconds: 600));

        Directory(outDir).createSync(recursive: true);
        File('$outDir/startup-a11y.txt').writeAsStringSync(
          '$name\n${_a11yReport(tester)}\n',
          mode: FileMode.append,
        );
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey(kUxCaptureKey)),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });

        final error = tester.takeException();
        if (error != null) {
          File(
            '$outDir/exceptions.log',
          ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
        }
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
