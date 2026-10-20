/// Measurement frame for the scroll-ownership guard (WP-81).
///
/// Puts a page into the real app composition — title band, sidebar, page
/// header, content pane and the recording dock — so the content pane height a
/// test measures is the one the user actually gets at a given window size.
/// Pages are mounted through [pumpScrollFrame]; geometry is read back with
/// [measureScrollShare] and [countFullyVisibleRows].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/app.dart'
    show wpHelpNavItem, wpNavDividerAfterIds, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/app_shell.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import 'test_helpers.dart';

/// Key on the content pane below the page header: the area the page owns.
const kScrollFramePaneKey = ValueKey('scroll-frame-pane');

/// Pumps [page] inside the app composition at [size] (logical pixels) and
/// [textScale]. Returns once the first frame has settled.
Future<void> pumpScrollFrame(
  WidgetTester tester, {
  required Size size,
  required Widget page,
  double textScale = 1,
  HistoryDatabase? db,
  List<Object> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  final l10n = lookupL10n(locale);
  WpColors.activate(wpDarkColors);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _frame(l10n, page),
        ),
      ),
      size: size,
      db: db,
      overrides: [...overrides],
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _frame(L10n l10n, Widget page) {
  return Theme(
    data: wpThemeFor(wpDarkColors),
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: wpDarkColors.frame.frameGradient),
      child: WpAppShell(
        titleBar: const SizedBox(height: WpLayout.appBarHeight),
        sidebar: WpSidebar(
          items: wpNavItems(l10n),
          dividerAfterIds: wpNavDividerAfterIds,
          activeId: 'replacements',
          onItemTap: (_) {},
          bottomItems: [wpHelpNavItem(l10n), wpSettingsNavItem(l10n)],
        ),
        contentDecoration: BoxDecoration(color: wpDarkColors.surface),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                WpSpacing.xl,
                WpSpacing.lg,
                WpSpacing.xl,
                WpSpacing.xs,
              ),
              child: WpPageHeader(title: 'Page'),
            ),
            Expanded(key: kScrollFramePaneKey, child: page),
          ],
        ),
        dock: WpRecordingDock(
          sttModeLabel: 'Whisper · small',
          sttState: SttServerState.ready,
          localProcessing: true,
          hotkeyLabel: formatHotkeyKeycap(
            'meta+shift',
            'D',
            l10n: l10n,
            isMacOS: true,
          ),
        ),
      ),
    ),
  );
}

/// Height of the content pane and of the largest scroll viewport inside it.
///
/// The viewport is the box of the biggest [Scrollable] under the pane: for a
/// `ListView`/`CustomScrollView` that box is the visible area.
({double paneHeight, double viewportHeight}) measureScrollShare(
  WidgetTester tester,
) {
  final pane = tester.getRect(find.byKey(kScrollFramePaneKey));
  var viewport = 0.0;
  final scrollables = find.descendant(
    of: find.byKey(kScrollFramePaneKey),
    matching: find.byType(Scrollable),
  );
  for (final element in scrollables.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final h = box.size.height;
    if (h > viewport) viewport = h;
  }
  return (paneHeight: pane.height, viewportHeight: viewport);
}

/// Counts text widgets whose data starts with [prefix] and whose box lies
/// entirely inside the largest scroll viewport of the content pane. Used to
/// count rows on a list where each row carries a unique text prefix.
int countFullyVisibleRows(WidgetTester tester, String prefix) {
  final pane = tester.getRect(find.byKey(kScrollFramePaneKey));
  Rect? viewport;
  var best = 0.0;
  final scrollables = find.descendant(
    of: find.byKey(kScrollFramePaneKey),
    matching: find.byType(Scrollable),
  );
  for (final element in scrollables.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    if (box.size.height > best) {
      best = box.size.height;
      viewport = tester.getRect(find.byElementPredicate((e) => e == element));
    }
  }
  final area = viewport == null ? pane : viewport.intersect(pane);
  final texts = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').startsWith(prefix),
  );
  final seen = <String>{};
  var count = 0;
  for (final element in texts.evaluate()) {
    final text = (element.widget as Text).data!;
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    if (rect.top >= area.top && rect.bottom <= area.bottom && seen.add(text)) {
      count++;
    }
  }
  return count;
}
