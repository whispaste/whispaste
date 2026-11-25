/// Native screen-reader fixture for #668. Uses the production dialog with
/// deliberately slow, synthetic progress; never opens a user's database.
///
/// flutter run -d macos -t tool/index_rebuild_accessibility.dart
/// Add --dart-define=INDEX_REBUILD_FAIL=true for the failure path, or
/// --dart-define=INDEX_REBUILD_LOCALE=he for another app language.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:whispaste/core/accessibility/accessibility_reply_binding.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/settings/widgets/index_rebuild_dialog.dart';

Future<void> main() async {
  WpRenderEngineBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'WhisPaste Index Accessibility Fixture',
      size: Size(800, 600),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // Same palette as WpColors, so dialog surfaces and theme text match.
      theme: wpThemeFor(WpColors.current),
      locale: const Locale(
        String.fromEnvironment('INDEX_REBUILD_LOCALE', defaultValue: 'de'),
      ),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              autofocus: true,
              onPressed: () =>
                  showIndexRebuildDialog(context, _FixtureDatabase()),
              child: Text(L10n.of(context).settingsIndexRebuildTitle),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FixtureDatabase implements HistoryDatabase {
  @override
  Stream<IndexRebuildProgress> rebuildIndexes() async* {
    for (final phase in [IndexRebuildPhase.search, IndexRebuildPhase.preview]) {
      for (var done = 0; done <= 2; done++) {
        yield IndexRebuildProgress(phase, done, 2);
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    if (const bool.fromEnvironment('INDEX_REBUILD_FAIL')) {
      throw StateError('Synthetic accessibility fixture failure');
    }
    yield const IndexRebuildProgress(IndexRebuildPhase.done, 1, 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
