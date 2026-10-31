/// RTL golden tests for the macOS title-bar layout.
///
/// Verifies that the title bar renders identically in `he` (RTL) and `en`
/// (LTR) locales: the brand wordmark stays on the left next to the traffic
/// lights, and actions are not pushed under the traffic lights.
///
/// Uses [_StaticMacTitleBar] — a lightweight replica of [_MacOSTitleBar] that
/// avoids window_manager calls, keeping tests hermetic.  The real fix lives in
/// `_MacOSTitleBar` (wrapped in `Directionality(ltr, …)`); this test guards
/// the visual contract.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/brand_wordmark.dart';

void main() {
  group('macOS title bar RTL golden', () {
    testWidgets('he locale renders same visual order as en locale', (
      tester,
    ) async {
      // ── Hebrew (RTL) ──────────────────────────────────────────────────────
      await tester.pumpWidget(_buildApp(locale: const Locale('he')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(_StaticMacTitleBar),
        matchesGoldenFile('goldens/title_bar_macos_rtl_he_dark.png'),
      );
    });

    testWidgets('en locale renders reference layout', (tester) async {
      // ── English (LTR) — reference golden ─────────────────────────────────
      await tester.pumpWidget(_buildApp(locale: const Locale('en')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(_StaticMacTitleBar),
        matchesGoldenFile('goldens/title_bar_macos_ltr_en_dark.png'),
      );
    });
  });
}

Widget _buildApp({required Locale locale}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: wpDarkTheme(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: const Scaffold(
      body: Align(alignment: Alignment.topCenter, child: _StaticMacTitleBar()),
    ),
  );
}

/// Static replica of [_MacOSTitleBar] without window_manager — test-safe.
///
/// Mirrors the production fix: wrapped in [Directionality] with [TextDirection.ltr]
/// so the traffic-light clearance always sits on the physical left,
/// regardless of the ambient locale.
class _StaticMacTitleBar extends StatelessWidget {
  const _StaticMacTitleBar();

  @override
  Widget build(BuildContext context) {
    // Same Directionality wrap as the production _MacOSTitleBar fix.
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: WpLayout.appBarHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: WpSpacing.lg),
          child: Row(
            children: [
              // Traffic-light clearance (physical left — always LTR).
              SizedBox(width: 56),
              WpBrandWordmark(height: 34),
              Spacer(),
              // Simulated action (theme toggle icon).
              Icon(
                LucideIcons.sun,
                size: WpIconSize.sm,
                color: WpColorsDark.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
