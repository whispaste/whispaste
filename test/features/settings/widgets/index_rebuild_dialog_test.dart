import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/widgets/index_rebuild_dialog.dart';

import '../../../fixtures/test_helpers.dart';

class _RebuildDatabase implements HistoryDatabase {
  final progress = StreamController<IndexRebuildProgress>();

  @override
  Stream<IndexRebuildProgress> rebuildIndexes() => progress.stream;

  @override
  Future<void> close() => progress.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final locale in L10n.supportedLocales) {
      testWidgets('rebuild keyboard and announcements: $platform $locale', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final db = _RebuildDatabase();
        addTearDown(() {
          unawaited(db.close());
        });
        late L10n l10n;
        await tester.pumpWidget(
          makeTestable(
            Builder(
              builder: (context) {
                l10n = L10n.of(context);
                return TextButton(
                  onPressed: () => showIndexRebuildDialog(context, db),
                  child: const Text('Rebuild'),
                );
              },
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final dialog = find.byKey(
          const ValueKey('settings-index-rebuild-dialog'),
        );
        expect(dialog, findsOneWidget);

        // announce() bypasses the test messenger on macOS (see
        // core/accessibility/announce.dart); the native VoiceOver check
        // covers that branch.
        void announced(List<String> messages) {
          final got = tester.takeAnnouncements().map((a) => a.message);
          if (platform == TargetPlatform.macOS) return;
          expect(got, messages);
        }

        announced([l10n.settingsIndexRebuildSearchPhase]);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(dialog, findsOneWidget);
        db.progress.add(
          const IndexRebuildProgress(IndexRebuildPhase.search, 1, 2),
        );
        await tester.pump();
        // Counts inside a phase are not read out again.
        announced([]);
        expect(
          find.text(l10n.settingsIndexRebuildSearch(1, 2)),
          findsOneWidget,
        );
        db.progress.add(
          const IndexRebuildProgress(IndexRebuildPhase.preview, 1, 2),
        );
        await tester.pump();
        announced([l10n.settingsIndexRebuildPreviewPhase]);
        db.progress.add(
          const IndexRebuildProgress(IndexRebuildPhase.done, 1, 1),
        );
        await db.progress.close();
        await tester.pumpAndSettle();
        announced([l10n.settingsIndexRebuildDone]);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  testWidgets('failure is announced and can be closed with Enter', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final db = _RebuildDatabase();
    addTearDown(() {
      unawaited(db.close());
    });
    late L10n l10n;
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return TextButton(
              onPressed: () => showIndexRebuildDialog(context, db),
              child: const Text('Rebuild'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Rebuild'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeAnnouncements().map((a) => a.message), [
      l10n.settingsIndexRebuildSearchPhase,
    ]);
    db.progress.addError(StateError('rebuild failed'));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements().map((a) => a.message), [
      l10n.settingsIndexRebuildFailed,
    ]);
    expect(find.text(l10n.settingsIndexRebuildFailed), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-index-rebuild-progress')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-index-rebuild-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
