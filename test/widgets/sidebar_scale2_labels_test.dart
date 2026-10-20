/// UX-033: at text scale 2.0 every side-navigation label must stay readable.
///
/// The rail used to truncate its labels with an ellipsis ("Textbau…",
/// "Aufnahm…") and, in RTL, cut "Statistik" short. This file renders the real
/// production rail (working areas plus pinned Help and Settings) at the two
/// window sizes the app supports, at 2.0x, in de, en and he (RTL), and checks
/// that
///   * nothing overflows,
///   * no label is ellipsised,
///   * each label's laid-out height covers its complete text (no line hidden
///     by `maxLines`), and
///   * each entry still announces its full label as tooltip.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/app.dart'
    show wpHelpNavItem, wpNavDividerAfterIds, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/sidebar.dart';

import '../fixtures/test_helpers.dart';

const double _scale = 2.0;

/// Expanded rail width at 1.0x (chat-08).
const double _baseWidth = WpLayout.sidebarWidth;

/// The rail's height in the shell: window height minus the frame chrome.
double _railHeight(Size window) => window.height - WpLayout.frameChromeHeight;

Widget _railInWindow(Size window, String locale, {double scale = _scale}) =>
    makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              height: _railHeight(window),
              child: Row(
                children: [
                  WpSidebar(
                    items: wpNavItems(L10n.of(context)),
                    dividerAfterIds: wpNavDividerAfterIds,
                    activeId: 'history',
                    onItemTap: (_) {},
                    bottomItems: [
                      wpHelpNavItem(L10n.of(context)),
                      wpSettingsNavItem(L10n.of(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      locale: Locale(locale),
    );

List<String> _labels(L10n l10n) => [
  for (final item in wpNavItems(l10n)) item.label,
  l10n.navHelp,
  l10n.navSettings,
];

void main() {
  // Real glyph widths: the default test font draws every glyph one em wide.
  setUpAll(() async => loadAppFonts());

  const windows = [Size(800, 716), Size(1100, 720)];
  const locales = ['de', 'en', 'he'];

  for (final window in windows) {
    for (final locale in locales) {
      final name =
          'sidebar at ${window.width.toInt()}x${window.height.toInt()}, '
          '${_scale}x, $locale';

      testWidgets('UX-033: $name keeps every label whole', (tester) async {
        tester.view.physicalSize = window;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_railInWindow(window, locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final l10n = await L10n.delegate.load(Locale(locale));
        for (final label in _labels(l10n)) {
          final textFinder = find.text(label);
          expect(
            textFinder,
            findsOneWidget,
            reason: 'label "$label" should be rendered',
          );

          final widget = tester.widget<Text>(textFinder);
          expect(
            widget.overflow,
            isNot(TextOverflow.ellipsis),
            reason: 'label "$label" must not be ellipsised',
          );

          final paragraph = tester.renderObject<RenderParagraph>(textFinder);
          // Lay out the complete label at the width the paragraph actually
          // got. If the paragraph is shorter than that, lines are hidden.
          final full = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            textAlign: paragraph.textAlign,
            locale: paragraph.locale,
          )..layout(maxWidth: paragraph.constraints.maxWidth);
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(full.height - 0.5),
            reason:
                'label "$label" is cut to ${paragraph.size.height} px but '
                'its full text needs ${full.height} px',
          );
          // The tooltip (and with it the accessible name) is the full label.
          expect(find.byTooltip(label), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('UX-033: the rail stays a scroll view at 2.0x', (tester) async {
    const window = Size(800, 716);
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_railInWindow(window, 'de'));
    await tester.pumpAndSettle();

    // Whatever the scale, the entries must be reachable: the rail scrolls
    // when its rows no longer fit the height it is given.
    expect(
      find.descendant(
        of: find.byType(WpSidebar),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('UX-033: the rail widens with the text scale, capped at 1.5x', (
    tester,
  ) async {
    const window = Size(1100, 720);
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final entry in {
      1.0: _baseWidth,
      1.3: _baseWidth * 1.3,
      2.0: _baseWidth * WpNavRail.maxTextScaleWidthFactor,
    }.entries) {
      await tester.pumpWidget(_railInWindow(window, 'de', scale: entry.key));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(WpSidebar)).width,
        closeTo(entry.value, 0.5),
        reason: 'rail width at ${entry.key}x',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
