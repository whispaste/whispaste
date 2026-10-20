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
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_screens_test.dart
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

import 'ux_fixtures.dart';

String _sizeName(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

/// One sweep variant: [pump] renders it and returns any exceptions raised
/// before the final frame (the final one is taken here). Writes the PNG.
void _sweepVariant(
  String name,
  Future<List<Object>> Function(WidgetTester tester, HistoryDatabase db) pump,
) {
  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';
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

  // Pages: every screen at every sweep size.
  for (final screen in kUxScreens) {
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

  // Onboarding: each of the seven steps, at the fixed onboarding window only.
  for (final step in kUxOnboardingSteps) {
    for (final locale in kUxSweepLocales) {
      if (!wanted(step.id, locale)) continue;
      for (final theme in kUxSweepThemes) {
        for (final scale in kUxSweepScales) {
          final name =
              '${step.id}__${_sizeName(kUxOnboardingSize)}__s${scale.toString()}'
              '__$theme'
              '_$locale';
          _sweepVariant(
            name,
            (tester, db) => pumpUxOnboarding(
              tester,
              step: step,
              db: db,
              size: kUxOnboardingSize,
              scale: scale,
              theme: theme,
              locale: locale,
            ),
          );
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
