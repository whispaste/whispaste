/// The detail panel of a failed recording whose audio is still parked shows the
/// same deadline as Settings → Privacy (`history-detail-kept-until`), and the
/// two next steps beside it: retry (`history-detail-kept-retry`) and discard
/// (`history-detail-kept-discard`).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/services/pending_audio/kept_until_format.dart';
import 'package:whispaste/services/pending_audio/pending_audio_providers.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

const _id = 'parked-detail-1';
final _keptUntil = DateTime(2026, 10, 25, 14, 5);
const _keyId = ValueKey('history-detail-kept-until');
const _retryKey = ValueKey('history-detail-kept-retry');
const _discardKey = ValueKey('history-detail-kept-discard');

/// The parked recordings the list provider returns. A discard removes its
/// entry here, so the provider's rebuild after the discard sees the change.
List<PendingRetry> _parked = const [];
final List<String> _discarded = [];

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _FakeQueue extends PendingAudioQueue {
  _FakeQueue()
    : super(
        directory: () => '',
        save: (_) async => throw UnimplementedError(),
        entryExists: (_) async => false,
      );

  @override
  Future<void> discard(String entryId) async {
    _discarded.add(entryId);
    _parked = _parked.where((e) => e.entryId != entryId).toList();
  }
}

Future<void> _pump(
  WidgetTester tester,
  HistoryDatabase db, {
  required List<PendingRetry> parked,
}) async {
  _parked = parked;
  _discarded.clear();
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: _id,
      timestamp: DateTime(2026, 10, 18, 9, 30),
      content: const Value('a failed dictation'),
    ),
  );
  final entry = (await db.select(db.historyEntries).get()).single;

  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    makeTestable(
      Scaffold(
        body: HistoryDetailPanel(
          entry: entry,
          isTrashView: false,
          onClose: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
          onArchive: () {},
          onRestore: () {},
        ),
      ),
      db: db,
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        pendingRetryListProvider.overrideWith((ref) async => _parked),
        pendingAudioQueueProvider.overrideWithValue(_FakeQueue()),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

PendingRetry _entry() => PendingRetry(
  entryId: _id,
  capturedAt: DateTime(2026, 10, 18, 9, 30),
  errorCode: 'stt_server_failed',
  expiresAt: _keptUntil,
);

void main() {
  testWidgets(
    'a parked entry shows the deadline in the same text as Settings',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final l10n = await L10n.delegate.load(const Locale('en'));

      await _pump(tester, db, parked: [_entry()]);

      expect(
        tester.widget<Text>(find.byKey(_keyId)).data,
        l10n.pendingAudioKeptUntil(formatKeptUntil('en', _keptUntil)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a parked entry offers retry and discard beside the deadline', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final l10n = await L10n.delegate.load(const Locale('en'));

    await _pump(tester, db, parked: [_entry()]);

    expect(find.byKey(_retryKey), findsOneWidget);
    expect(find.byKey(_discardKey), findsOneWidget);
    expect(find.text(l10n.actionRetry), findsOneWidget);
    expect(find.text(l10n.recoveryDiscard), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('discard is destructive and asks before it deletes the audio', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final l10n = await L10n.delegate.load(const Locale('en'));

    await _pump(tester, db, parked: [_entry()]);
    expect(
      tester
          .widget<WpButton>(
            find.byWidgetPredicate(
              (w) => w is WpButton && w.testId == 'history-detail-kept-discard',
            ),
          )
          .tone,
      WpButtonTone.danger,
    );

    await tester.tap(find.byKey(_discardKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.recoveryDiscardConfirm), findsOneWidget);
    expect(find.text(l10n.pendingAudioDiscardConfirmMessage), findsOneWidget);
    expect(_discarded, isEmpty);

    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(_discarded, isEmpty);
    expect(find.byKey(_keyId), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('discard drops the kept audio and its deadline', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db, parked: [_entry()]);
    await tester.tap(find.byKey(_discardKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(_discarded, [_id]);
    expect(find.byKey(_keyId), findsNothing);
    expect(find.byKey(_discardKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'an entry without a parked audio shows no deadline and no action',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await _pump(tester, db, parked: const []);

      expect(find.byKey(_keyId), findsNothing);
      expect(find.byKey(_retryKey), findsNothing);
      expect(find.byKey(_discardKey), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
