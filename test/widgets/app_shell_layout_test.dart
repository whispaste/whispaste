/// Geometry of the WP-20 app shell, measured on the shared board
/// (test/fixtures/app_shell_board.dart) against chat-08 and spec §1–2:
/// the sidebar runs the full window height, the dock floats over the content
/// column only, nav rows centre their icon and label, the page header carries
/// the content inset, and the dock's status reads as plain text.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:whispaste/widgets/brand_wordmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_page_header.dart';
import 'package:whispaste/widgets/wp_status_dot.dart';

import '../fixtures/app_shell_board.dart';
import '../fixtures/test_helpers.dart';

/// WCAG 2.x relative luminance of an opaque colour.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

Future<void> _pumpBoard(
  WidgetTester tester,
  Size size, {
  WpThemeColors set = wpLightColors,
  double textScale = 1,
}) async {
  final en = lookupL10n(const Locale('en'));
  WpColors.activate(set);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      SizedBox(
        width: size.width,
        height: size.height,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: appShellBoard(
              set,
              en,
              compactSidebar: size.width < WpShellTokens.breakpointCompact,
            ),
          ),
        ),
      ),
      size: size,
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

void main() {
  final en = lookupL10n(const Locale('en'));

  // Text widths decide how the dock's groups share the width, so measure with
  // the bundled fonts, as the goldens do, not the test engine's Ahem blocks.
  setUpAll(loadAppFonts);

  tearDown(() => WpColors.activate(wpLightColors));

  for (final width in <double>[800, 1100, 1440]) {
    group('shell at ${width.toInt()} px', () {
      final size = Size(width, width == 800 ? 740 : 800);

      testWidgets('the sidebar runs the full window height', (tester) async {
        await _pumpBoard(tester, size);
        final sidebar = _rect(tester, find.byType(WpSidebar));
        expect(sidebar.bottom, size.height);
        expect(sidebar.top, WpLayout.appBarHeight);
      });

      testWidgets(
        'the dock floats over the content column: its left edge is at least 12 px right of the sidebar',
        (tester) async {
          await _pumpBoard(tester, size);
          final sidebar = _rect(tester, find.byType(WpSidebar));
          final dock = _rect(
            tester,
            find.byKey(const ValueKey('dock-surface')),
          );
          expect(dock.left, greaterThanOrEqualTo(sidebar.right + 12));
          expect(dock.left, sidebar.right + WpShellTokens.dockInset);
        },
      );

      testWidgets('the dock sits 12 px from the window edges and bottom', (
        tester,
      ) async {
        await _pumpBoard(tester, size);
        final dock = _rect(tester, find.byKey(const ValueKey('dock-surface')));
        expect(dock.right, size.width - WpShellTokens.dockInset);
        expect(dock.bottom, size.height - WpShellTokens.dockInset);
        expect(dock.height, WpShellTokens.dockHeight);
      });

      testWidgets(
        'every nav row is 44 high, with icon and label centred on one line',
        (tester) async {
          await _pumpBoard(tester, size);
          for (final id in [
            'snippets',
            'notes',
            'history',
            'smartMode',
            'replacements',
            'analytics',
            'help',
            'settings',
          ]) {
            final row = find.byKey(ValueKey('sidebar-nav-$id'));
            final box = _rect(tester, row);
            expect(box.height, WpShellTokens.navItemHeight, reason: id);

            final icon = _rect(
              tester,
              find.descendant(of: row, matching: find.byType(Icon)),
            );
            expect(icon.height, WpNavRail.iconSize, reason: id);
            expect(icon.center.dy, closeTo(box.center.dy, 0.5), reason: id);

            // The icon-only rail below the compact breakpoint has no label.
            if (size.width < WpShellTokens.breakpointCompact) continue;
            final label = _rect(
              tester,
              find.descendant(of: row, matching: find.byType(Text)),
            );
            expect(label.center.dy, closeTo(box.center.dy, 0.5), reason: id);
            expect(label.left - icon.right, WpNavRail.iconLabelGap, reason: id);
          }
        },
      );

      testWidgets(
        'the page title keeps the content inset: 32 px left, 24 px below the title band',
        (tester) async {
          await _pumpBoard(tester, size);
          final sidebar = _rect(tester, find.byType(WpSidebar));
          final title = _rect(
            tester,
            find.descendant(
              of: find.byType(WpPageHeader),
              matching: find.byType(Text),
            ),
          );
          expect(title.left - sidebar.right, WpSpacing.xl);
          expect(title.top, WpLayout.appBarHeight + WpSpacing.lg);
        },
      );

      testWidgets(
        'the status reads as plain 16 px text, right-aligned, beside a 10 px dot',
        (tester) async {
          await _pumpBoard(tester, size);
          final dock = _rect(
            tester,
            find.byKey(const ValueKey('dock-surface')),
          );
          // A tight dock (under 720 px) shows the shortest ready text instead.
          final sidebarWidth = size.width < WpShellTokens.breakpointCompact
              ? WpLayout.sidebarWidthCompact
              : WpLayout.sidebarWidth;
          final dockWidth =
              size.width - sidebarWidth - 2 * WpShellTokens.dockInset;
          final status = find.text(
            dockWidth < 720
                ? en.statusReady
                : '${en.statusReady} · ${en.statusLocal}',
          );
          expect(status, findsOneWidget);

          final text = tester.widget<Text>(status);
          expect(text.style?.fontSize, WpTypeScaleTokens.bodyLg);
          expect(text.style?.color, WpColorsDark.textPrimary);

          final statusRect = _rect(tester, status);
          expect(dock.right - statusRect.right, lessThanOrEqualTo(24));

          final dot = _rect(tester, find.byType(WpStatusDot));
          expect(dot.width, 10);
          expect(dot.height, 10);
          expect(dot.right, lessThanOrEqualTo(statusRect.left));
        },
      );
    });
  }

  testWidgets('the status text meets WCAG AA (4.5:1) on the dock navy', (
    tester,
  ) async {
    await _pumpBoard(tester, const Size(1100, 800));
    final text = tester.widget<Text>(
      find.text('${en.statusReady} · ${en.statusLocal}'),
    );
    expect(
      contrastRatio(text.style!.color!, wpStagePalette.canvas),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('the dock shows the Smart Mode group and the speech engine', (
    tester,
  ) async {
    await _pumpBoard(tester, const Size(1100, 800));
    expect(find.byKey(const ValueKey('dock-smart-mode')), findsOneWidget);
    expect(find.text(en.smartModePresetOff), findsOneWidget);
    expect(find.text(kBoardSttLabel), findsOneWidget);
  });

  group('compact dock at 800 x 600', () {
    const size = Size(800, 600);

    for (final scale in <double>[1, 1.3]) {
      group('text scale ${scale}x', () {
        testWidgets('every group stays visible inside the dock', (
          tester,
        ) async {
          await _pumpBoard(tester, size, textScale: scale);
          final dock = _rect(
            tester,
            find.byKey(const ValueKey('dock-surface')),
          );
          for (final finder in [
            find.byKey(const ValueKey('dock-dictate')),
            find.byKey(const ValueKey('dock-engine')),
            find.text(kBoardSttLabel),
            find.text(en.statusReady),
            find.byType(WpStatusDot),
          ]) {
            expect(finder, findsOneWidget);
            final rect = _rect(tester, finder);
            expect(rect.left, greaterThanOrEqualTo(dock.left));
            expect(rect.right, lessThanOrEqualTo(dock.right));
          }
        });

        testWidgets('the dock has no scrollable and no overflow', (
          tester,
        ) async {
          await _pumpBoard(tester, size, textScale: scale);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('dock-surface')),
              matching: find.byType(Scrollable),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('every overline is a single line', (tester) async {
          await _pumpBoard(tester, size, textScale: scale);
          final smartOverline = find.text(en.navSmartMode.toUpperCase());
          if (smartOverline.evaluate().isNotEmpty) {
            expect(tester.widget<Text>(smartOverline).maxLines, 1);
            expect(
              _rect(tester, smartOverline).height,
              lessThan(12 * scale * 1.6),
            );
          }
          // The speech overline stays while the measured row has room for it
          // and is dropped only when it does not, so a shown overline is
          // checked for a single line like the Smart Mode one.
          final speech = find.text(en.settingsSpeechRecognition.toUpperCase());
          if (speech.evaluate().isNotEmpty) {
            expect(tester.widget<Text>(speech).maxLines, 1);
          }
        });

        if (scale == 1) {
          testWidgets('the Smart Mode overline is not truncated', (
            tester,
          ) async {
            await _pumpBoard(tester, size, textScale: scale);
            final finder = find.text(en.navSmartMode.toUpperCase());
            if (finder.evaluate().isEmpty) {
              // Below the compact breakpoint Smart Mode lives in Mehr.
              await tester.tap(find.byKey(const ValueKey('dock-overflow')));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('dock-menu-smart-mode')),
                findsOneWidget,
              );
              return;
            }
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            final natural = TextPainter(
              text: paragraph.text,
              textDirection: TextDirection.ltr,
              textScaler: paragraph.textScaler,
              maxLines: 1,
            )..layout();
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(natural.width - 0.5),
            );
          });
        }

        testWidgets('the hotkey stays reachable: keycap or Dictate tooltip', (
          tester,
        ) async {
          await _pumpBoard(tester, size, textScale: scale);
          // The keycap is the first step the measured row gives up, so it may
          // already be gone; then the hotkey is on the Dictate button.
          if (find.byKey(const ValueKey('dock-hotkey')).evaluate().isNotEmpty) {
            return;
          }
          expect(
            tester
                .getSemantics(find.byKey(const ValueKey('dock-dictate')))
                .hint,
            contains('⇧⌘ D'),
          );
          await tester.tap(find.byKey(const ValueKey('dock-overflow')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('dock-menu-hotkey')),
            findsOneWidget,
          );
        });

        testWidgets(
          'the Dictate button is at least an icon and at most its full width',
          (tester) async {
            await _pumpBoard(tester, size, textScale: scale);
            final width = _rect(
              tester,
              find.byKey(const ValueKey('dock-dictate')),
            ).width;
            expect(width, greaterThanOrEqualTo(WpDockTokens.controlHeight));
            expect(width, lessThanOrEqualTo(WpDockTokens.dictateWidth));
          },
        );
      });
    }
  });

  group('dark dock edge', () {
    testWidgets('the dark dock carries a 1 px frost 15 % rim', (tester) async {
      await _pumpBoard(tester, const Size(1100, 800), set: wpDarkColors);
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey('dock-surface')),
      );
      final border = (surface.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, WpColorsDark.frostBorder15);
    });

    testWidgets(
      'the rim separates the dock from the dark surface better than the bare canvas',
      (tester) async {
        await _pumpBoard(tester, const Size(1100, 800), set: wpDarkColors);
        final surfaceColor = wpDarkColors.surface;
        final rimOnSurface = Color.alphaBlend(
          WpColorsDark.frostBorder15,
          surfaceColor,
        );
        final rimContrast = contrastRatio(rimOnSurface, surfaceColor);
        final canvasContrast = contrastRatio(
          wpStagePalette.canvas,
          surfaceColor,
        );
        expect(rimContrast, greaterThan(canvasContrast));
        expect(rimContrast, greaterThanOrEqualTo(1.2));
      },
    );

    testWidgets('the light dock has no rim', (tester) async {
      await _pumpBoard(tester, const Size(1100, 800));
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey('dock-surface')),
      );
      expect((surface.decoration! as BoxDecoration).border, isNull);
    });
  });

  testWidgets(
    'the dock has no vertical dividers: spacing separates the groups',
    (tester) async {
      await _pumpBoard(tester, const Size(1100, 800));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-surface')),
          matching: find.byType(VerticalDivider),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('the original word-and-image mark heads the sidebar', (
    tester,
  ) async {
    await _pumpBoard(tester, const Size(1100, 800));
    final mark = _rect(tester, find.byType(WpBrandWordmark));
    expect(mark.height, WpNavRail.brandHeight);
    expect(mark.right, lessThanOrEqualTo(WpLayout.sidebarWidth));
  });
}
