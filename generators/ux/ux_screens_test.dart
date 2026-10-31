/// UX screenshot harness: renders every screen of `ux_fixtures.dart` at the
/// sweep sizes, text scales, themes and locales and writes one PNG per
/// combination. It asserts nothing: it is a survey tool for the UX reviewer
/// (`.claude/agents/ux-reviewer.md`), not a golden test.
///
/// Covers the pages (`kUxScreens`), the seven onboarding steps at the fixed
/// onboarding window size, and the shell with and without two stacked toasts.
///
/// Tagged `ux-screens`, so the normal suite and CI skip it (dart_test.yaml,
/// ci.yml `--exclude-tags`). Run it on the Mac, where the fonts are real:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_screens_test.dart
///
/// Optional filters: UX_ONLY (substring of the screen id), UX_LOCALES (e.g. de,he).
/// Layout exceptions are appended to exceptions.log in the output dir instead of
/// failing the run, so one broken screen does not hide the rest.
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

import '../../test/ux_audit/ux_fixtures.dart';

String _sizeName(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

/// One sweep variant: [pump] renders it and returns any exceptions raised
/// before the final frame (the final one is taken here). Writes the PNG.
void _sweepVariant(
  String name,
  Future<List<Object>> Function(WidgetTester tester, HistoryDatabase db) pump,
) {
  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';
  testWidgets('ux-screen: $name', (tester) async {
    final db = await openSeededUxDatabase(tester);
    addTearDown(() => tester.runAsync(db.close));

    final errors = await pump(tester, db);
    final error = tester.takeException();
    if (error != null) errors.add(error);
    if (errors.isNotEmpty) {
      Directory(outDir).createSync(recursive: true);
      File('$outDir/exceptions.log').writeAsStringSync(
        errors.map((e) => '$name: $e\n').join(),
        mode: FileMode.append,
      );
    }

    await tester.runAsync(() async {
      // The whole view, not only the frame below the app: toasts live in the
      // navigator's overlay, above the home route, and would be missing.
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & view.size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(outDir).createSync(recursive: true);
      File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // Close any toast before the tree goes away. Their auto-dismiss timer does
    // not run under the test clock, and tearing the overlay down while a toast
    // animates fails with an active ticker.
    final closeLabel = L10n.of(
      tester.element(find.byType(Scaffold).first),
    ).actionDismiss;
    for (var i = 0; i < 4; i++) {
      final close = find.byTooltip(closeLabel);
      if (close.evaluate().isEmpty) break;
      await tester.tap(close.first);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

void main() {
  setUpAll(() async => loadAppFonts());

  final only = Platform.environment['UX_ONLY'];
  final localeFilter = Platform.environment['UX_LOCALES']?.split(',');

  bool wanted(String id, String locale) =>
      (only == null || id.contains(only)) &&
      (localeFilter == null || localeFilter.contains(locale));

  // Pages: every screen at every sweep size, then the states the normal suite
  // does not guard (history with an import queue and interrupted recordings).
  for (final screen in [...kUxScreens, ...kUxHistoryStateScreens]) {
    for (final locale in kUxSweepLocales) {
      if (!wanted(screen.id, locale)) continue;
      for (final theme in kUxSweepThemes) {
        for (final scale in kUxSweepScales) {
          for (final size in kUxSweepSizes) {
            final name =
                '${screen.id}__${_sizeName(size)}__s${scale.toString()}'
                '__$theme'
                '_$locale';
            _sweepVariant(name, (tester, db) async {
              await pumpUxScreen(
                tester,
                screen: screen,
                db: db,
                size: size,
                scale: scale,
                theme: theme,
                locale: locale,
              );
              return <Object>[];
            });
          }
        }
      }
    }
  }

  // Onboarding: each step at the fixed onboarding window (and at the 800 px
  // guard width). One palette only: the onboarding stage (WpColorsDark).
  for (final step in kUxOnboardingSteps) {
    for (final locale in kUxSweepLocales) {
      if (!wanted(step.id, locale)) continue;
      for (final size in [
        kUxOnboardingSize,
        kUxOnboardingWidthSize,
        kUxOnboardingCompactSize,
      ]) {
        for (final scale in kUxSweepScales) {
          final name =
              '${step.id}__${_sizeName(size)}__s${scale.toString()}'
              '__stage_$locale';
          _sweepVariant(
            name,
            (tester, db) => pumpUxOnboarding(
              tester,
              step: step,
              db: db,
              size: size,
              scale: scale,
              theme: 'dark',
              locale: locale,
            ),
          );
        }
      }
    }
  }

  // Main window in the small work areas (UX-091): the shell (dock and rail)
  // and the two pages most used there, at the default and the largest text
  // scale, in de and he. The window is capped below its 716 px minimum there.
  for (final size in kUxSmallWindowSizes) {
    for (final scale in const [1.0, 2.0]) {
      for (final locale in const ['de', 'he']) {
        for (final id in [...kUxShellIds, 'history', 'settings']) {
          if (!wanted(id, locale)) continue;
          final name =
              '${id}__${_sizeName(size)}__s${scale.toString()}__navy'
              '_$locale';
          _sweepVariant(name, (tester, db) async {
            if (kUxShellIds.contains(id)) {
              await pumpUxShell(
                tester,
                id: id,
                db: db,
                size: size,
                scale: scale,
                theme: 'navy',
                locale: locale,
              );
            } else {
              await pumpUxScreen(
                tester,
                screen: kUxScreens.firstWhere((s) => s.id == id),
                db: db,
                size: size,
                scale: scale,
                theme: 'navy',
                locale: locale,
              );
            }
            return <Object>[];
          });
        }
      }
    }
  }

  // Shell: the bare window and the window with two stacked toasts, at every
  // sweep size.
  for (final id in kUxShellIds) {
    for (final locale in kUxSweepLocales) {
      if (!wanted(id, locale)) continue;
      for (final theme in kUxSweepThemes) {
        for (final scale in kUxSweepScales) {
          for (final size in kUxSweepSizes) {
            final name =
                '${id}__${_sizeName(size)}__s${scale.toString()}'
                '__$theme'
                '_$locale';
            _sweepVariant(name, (tester, db) async {
              await pumpUxShell(
                tester,
                id: id,
                db: db,
                size: size,
                scale: scale,
                theme: theme,
                locale: locale,
              );
              return <Object>[];
            });
          }
        }
      }
    }
  }
}
