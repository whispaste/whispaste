import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/history_detail_provider.dart';
import 'package:whispaste/features/history/widgets/smart_mode_undo_actions.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/widgets/wp_button.dart';

const _raw = 'Wir treffen uns um drei.';
const _result = 'Wir treffen uns um 15 Uhr.';

void main() {
  _shortcutLabelTests();
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> seed({bool applied = true, String? output}) {
    return db.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: const Value('e1'),
        content: Value(output ?? _result),
        title: const Value('Titel'),
        timestamp: Value(DateTime(2026, 10, 18)),
        originalTranscript: const Value(_raw),
        smartModeInput: const Value(_raw),
        smartModeApplied: Value(applied),
      ),
    );
  }

  Widget host(Widget child) {
    return ProviderScope(
      overrides: [historyDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('the row undoes and then restores the Smart Mode result', (
    tester,
  ) async {
    await seed();
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) {
            final detail = ref.watch(historyDetailProvider('e1'));
            final entry = detail.asData?.value.entry;
            if (entry == null) return const SizedBox.shrink();
            return SmartModeUndoRow(entryId: 'e1', fallback: entry);
          },
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('history-entry-smart-undo')));
    await _settle(tester);
    expect((await db.getEntry('e1'))!.content, _raw);
    expect(find.byKey(const ValueKey('history-entry-smart-restore')), findsOne);

    await tester.tap(find.byKey(const ValueKey('history-entry-smart-restore')));
    await _settle(tester);
    expect((await db.getEntry('e1'))!.content, _result);
    expect(find.byKey(const ValueKey('history-entry-smart-undo')), findsOne);
  });

  testWidgets('the row is hidden when no Smart Mode run is applied', (
    tester,
  ) async {
    await seed(applied: false);
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) {
            final entry = ref
                .watch(historyDetailProvider('e1'))
                .asData
                ?.value
                .entry;
            if (entry == null) return const SizedBox.shrink();
            return SmartModeUndoRow(entryId: 'e1', fallback: entry);
          },
        ),
      ),
    );
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('history-entry-smart-undo')),
      findsNothing,
    );
  });

  testWidgets('the toast action undoes the dictation', (tester) async {
    await seed();
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) => Center(
            child: TextButton(
              onPressed: () => showSmartModeUndoToast(
                context: context,
                ref: ref,
                entryId: 'e1',
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    // Let the toast finish sliding in before its action can take a tap.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const ValueKey('toast-smart-undo')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect((await db.getEntry('e1'))!.content, _raw);

    // Let the toast's timers run out before the tree is torn down.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the toast undo updates the open detail row at once (DEV-154)', (
    tester,
  ) async {
    await seed();
    final fallback = (await tester.runAsync(() => db.getEntry('e1')))!;
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) => Column(
            children: [
              TextButton(
                onPressed: () => showSmartModeUndoToast(
                  context: context,
                  ref: ref,
                  entryId: 'e1',
                ),
                child: const Text('show'),
              ),
              SmartModeUndoRow(entryId: 'e1', fallback: fallback),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('show'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const ValueKey('toast-smart-undo')));
    // The undo writes to the database and the detail row reloads from it.
    for (var i = 0; i < 5; i++) {
      await _settle(tester);
    }

    expect(find.byKey(const ValueKey('history-entry-smart-restore')), findsOne);
    expect(
      find.byKey(const ValueKey('history-entry-smart-undo')),
      findsNothing,
    );
    await _dismissToast(tester);
  });

  testWidgets('the undo row is disabled while a preset is applied (DEV-155)', (
    tester,
  ) async {
    await seed();
    final fallback = (await tester.runAsync(() => db.getEntry('e1')))!;
    late ProviderContainer container;
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return SmartModeUndoRow(entryId: 'e1', fallback: fallback);
          },
        ),
      ),
    );
    await _settle(tester);
    final notifier = container.read(historyDetailProvider('e1').notifier);
    final current = container.read(historyDetailProvider('e1')).asData!.value;
    notifier.state = AsyncValue.data(current.copyWith(applyingPreset: true));
    await tester.pump();

    final button = tester.widget<WpButton>(find.byType(WpButton));
    expect(button.onPressed, isNull);
    expect((await db.getEntry('e1'))!.content, _result);
  });

  test(
    'undo and preset apply share one busy lock per entry (DEV-155)',
    () async {
      await seed();
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(historyDetailProvider('e1'), (_, _) {});
      addTearDown(sub.close);
      await container.read(historyDetailProvider('e1').future);
      final notifier = container.read(historyDetailProvider('e1').notifier);
      final lock = container.read(smartModeBusyProvider.notifier);

      // A write in flight on the entry: undo is refused, the DB is untouched.
      expect(lock.tryAcquire('e1'), isTrue);
      expect(await notifier.undoSmartMode(), isFalse);
      expect((await db.getEntry('e1'))!.content, _result);
      // A second apply cannot start either.
      final refused = await notifier.applyPreset(SmartModePreset.concise);
      expect(refused, isA<HistoryPresetApplicationBusy>());
      lock.release('e1');

      // Released: undo works again.
      expect(await notifier.undoSmartMode(), isTrue);
      expect((await db.getEntry('e1'))!.content, _raw);
    },
  );

  test(
    'a held lock makes a preset apply report busy, not failed (DEV-175)',
    () async {
      await seed();
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(historyDetailProvider('e1'), (_, _) {});
      addTearDown(sub.close);
      await container.read(historyDetailProvider('e1').future);
      final notifier = container.read(historyDetailProvider('e1').notifier);

      expect(
        container.read(smartModeBusyProvider.notifier).tryAcquire('e1'),
        isTrue,
      );
      final result = await notifier.applyPreset(SmartModePreset.concise);
      expect(result, isA<HistoryPresetApplicationBusy>());
      expect(result, isNot(isA<HistoryPresetApplicationFailure>()));
      container.read(smartModeBusyProvider.notifier).release('e1');
    },
  );

  test('the lock is released when the undo write throws (DEV-175)', () async {
    await seed();
    final failing = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      try {
        await failing.close();
      } on Object catch (_) {
        // Already closed by the test body.
      }
    });
    await failing.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: const Value('e1'),
        content: const Value(_result),
        title: const Value('Titel'),
        timestamp: Value(DateTime(2026, 10, 18)),
        originalTranscript: const Value(_raw),
        smartModeInput: const Value(_raw),
        smartModeApplied: const Value(true),
      ),
    );
    final container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWithValue(failing)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(historyDetailProvider('e1'), (_, _) {});
    addTearDown(sub.close);
    await container.read(historyDetailProvider('e1').future);
    await failing.close();

    await expectLater(
      container.read(historyDetailProvider('e1').notifier).undoSmartMode(),
      throwsA(anything),
    );
    expect(container.read(smartModeBusyProvider), isEmpty);
  });

  testWidgets(
    'a locked undo row is disabled with the busy tooltip and hint (DEV-175)',
    (tester) async {
      await seed();
      final fallback = (await tester.runAsync(() => db.getEntry('e1')))!;
      late ProviderContainer container;
      await tester.pumpWidget(
        host(
          Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return SmartModeUndoRow(entryId: 'e1', fallback: fallback);
            },
          ),
        ),
      );
      await _settle(tester);
      expect(
        container.read(smartModeBusyProvider.notifier).tryAcquire('e1'),
        isTrue,
      );
      await tester.pump();

      final button = tester.widget<WpButton>(find.byType(WpButton));
      expect(button.onPressed, isNull);
      expect(button.disabledTooltip, 'Smart Mode is still running');
      expect(
        find.byKey(const ValueKey<String>('history-entry-smart-busy')),
        findsOne,
      );
      // The reason is announced once: by the live text, not again as a hint.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.hint == 'Smart Mode is still running',
        ),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Smart Mode is still running'), findsOne);
      container.read(smartModeBusyProvider.notifier).release('e1');
    },
  );

  testWidgets(
    'the busy row fits at 2.0 text scale in a narrow column (BIZ-48)',
    (tester) async {
      await seed();
      final fallback = (await tester.runAsync(() => db.getEntry('e1')))!;
      late ProviderContainer container;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: host(
            Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return SizedBox(
                  width: 260,
                  child: SmartModeUndoRow(entryId: 'e1', fallback: fallback),
                );
              },
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        container.read(smartModeBusyProvider.notifier).tryAcquire('e1'),
        isTrue,
      );
      await tester.pump();

      // An overflow would already have failed the test with a RenderFlex error.
      expect(
        find.byKey(const ValueKey<String>('history-entry-smart-busy')),
        findsOne,
      );
      container.read(smartModeBusyProvider.notifier).release('e1');
    },
  );

  testWidgets(
    'the toast undo under a held lock says so and changes nothing (DEV-175)',
    (tester) async {
      await seed();
      late ProviderContainer container;
      await tester.pumpWidget(
        host(
          Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Center(
                child: TextButton(
                  onPressed: () => showSmartModeUndoToast(
                    context: context,
                    ref: ref,
                    entryId: 'e1',
                  ),
                  child: const Text('show'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('show'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        container.read(smartModeBusyProvider.notifier).tryAcquire('e1'),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('toast-smart-undo')));
      for (var i = 0; i < 5; i++) {
        await _settle(tester);
      }

      expect(
        find.text('Smart Mode is still running – please try again in a moment'),
        findsOne,
      );
      expect((await db.getEntry('e1'))!.content, _result);
      container.read(smartModeBusyProvider.notifier).release('e1');
      await _dismissToast(tester);
    },
  );

  testWidgets('the Smart Mode toast is announced to screen readers (A11y)', (
    tester,
  ) async {
    await seed();
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      (message) async {
        final decoded =
            const StandardMessageCodec().decodeMessage(message)
                as Map<Object?, Object?>?;
        final data = decoded?['data'] as Map<Object?, Object?>?;
        final text = data?['message'];
        if (text is String) announcements.add(text);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        SystemChannels.accessibility.name,
        null,
      ),
    );
    await tester.pumpWidget(
      host(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showSmartModeUndoToast(
              context: context,
              ref: ref,
              entryId: 'e1',
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();

    expect(announcements, contains('Smart Mode applied'));
    await _dismissToast(tester);
  });
}

/// Actionable toasts stay at least 10 s (WCAG 2.2.1), so wait a bit longer.
Future<void> _dismissToast(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// The detail state loads from the database, which needs real time.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
}

// BIZ-62: the copied-to-clipboard toast names the paste key of the platform
// that actually receives the paste, and never promises Cmd+Z off macOS.
void _shortcutLabelTests() {
  group('pasteShortcutLabelFor (BIZ-62)', () {
    test('macOS uses Cmd+V in every language', () {
      for (final lang in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
        expect(
          pasteShortcutLabelFor(
            platform: TargetPlatform.macOS,
            languageCode: lang,
          ),
          '⌘V',
        );
      }
    });

    test('Windows and Linux use Strg+V in German and Ctrl+V elsewhere', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect(
          pasteShortcutLabelFor(platform: platform, languageCode: 'de'),
          'Strg+V',
        );
        for (final lang in ['en', 'es', 'pt', 'ru', 'he']) {
          expect(
            pasteShortcutLabelFor(platform: platform, languageCode: lang),
            'Ctrl+V',
          );
        }
      }
    });

    test(
      'the copied toast text carries the platform key and no Cmd+Z',
      () async {
        final en = lookupL10n(const Locale('en'));
        final de = lookupL10n(const Locale('de'));
        final onWindows = en.selectionUndoCopiedToClipboard(
          pasteShortcutLabelFor(
            platform: TargetPlatform.windows,
            languageCode: 'en',
          ),
        );
        final onMac = en.selectionUndoCopiedToClipboard(
          pasteShortcutLabelFor(
            platform: TargetPlatform.macOS,
            languageCode: 'en',
          ),
        );
        final deOnLinux = de.selectionUndoCopiedToClipboard(
          pasteShortcutLabelFor(
            platform: TargetPlatform.linux,
            languageCode: 'de',
          ),
        );
        expect(onWindows, contains('Ctrl+V'));
        expect(onWindows, isNot(contains('⌘')));
        expect(onMac, contains('⌘V'));
        expect(deOnLinux, contains('Strg+V'));
        for (final text in [onWindows, onMac, deOnLinux]) {
          expect(text, isNot(contains('Cmd+Z')));
          expect(text, isNot(contains('⌘Z')));
        }
      },
    );
  });
}
