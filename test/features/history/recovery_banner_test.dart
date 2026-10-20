/// The recovery banner above the history list: one row per interrupted
/// recording, restore and discard actions, and the count of damaged entries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/widgets/recovery_banner.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/widgets/wp_button.dart';

/// Records calls. Like the real journal, a recording that was recovered or
/// discarded leaves [pending], so the banner's rescan no longer lists it.
class _FakeRecovery extends RecordingRecovery {
  _FakeRecovery({
    required this.pending,
    this.outcome = RecoveryOutcome.recovered,
  }) : super(audioDir: '', transcribe: (_) async => true);

  final List<InterruptedRecording> pending;
  final RecoveryOutcome outcome;
  final recovered = <String>[];
  final discarded = <String>[];

  @override
  Future<RecoveryOutcome> recover(InterruptedRecording recording) async {
    recovered.add(recording.id);
    if (outcome != RecoveryOutcome.failed) pending.remove(recording);
    return outcome;
  }

  @override
  Future<void> discard(InterruptedRecording recording) async {
    discarded.add(recording.id);
    pending.remove(recording);
  }
}

class _ThrowingDiscardRecovery extends _FakeRecovery {
  _ThrowingDiscardRecovery({required super.pending});

  @override
  Future<void> discard(InterruptedRecording recording) async {
    throw StateError('journal is locked');
  }
}

InterruptedRecording _recording(String id, {required bool hasAudio}) =>
    InterruptedRecording(
      id: id,
      startedAt: DateTime(2026, 10, 17, 9),
      wavPath: hasAudio ? '/rec/$id.wav' : null,
      journalPath: '/rec/journal/$id.json',
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<InterruptedRecording> pending,
  required _FakeRecovery recovery,
  int skippedCorrupt = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        interruptedRecordingsProvider.overrideWith(
          (ref) async => RecordingJournalScan(
            recordings: List.of(pending),
            skippedCorrupt: skippedCorrupt,
          ),
        ),
        recordingRecoveryProvider.overrideWithValue(recovery),
      ],
      child: MaterialApp(
        theme: wpDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: const Scaffold(body: RecoveryBanner()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows nothing when there is nothing to recover', (tester) async {
    final pending = <InterruptedRecording>[];
    await _pump(
      tester,
      pending: pending,
      recovery: _FakeRecovery(pending: pending),
    );

    expect(find.byKey(const ValueKey('recovery-row-a')), findsNothing);
    expect(find.textContaining('damaged'), findsNothing);
  });

  testWidgets('one row per interrupted recording, restore only with audio', (
    tester,
  ) async {
    final pending = [
      _recording('a', hasAudio: true),
      _recording('b', hasAudio: false),
    ];
    await _pump(
      tester,
      pending: pending,
      recovery: _FakeRecovery(pending: pending),
    );

    expect(find.byKey(const ValueKey('recovery-row-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-row-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-restore-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-restore-b')), findsNothing);
    expect(find.byKey(const ValueKey('recovery-discard-b')), findsOneWidget);
  });

  testWidgets('restore hands the recording to recovery and drops its row', (
    tester,
  ) async {
    final pending = [_recording('a', hasAudio: true)];
    final recovery = _FakeRecovery(pending: pending);
    await _pump(tester, pending: pending, recovery: recovery);

    await tester.tap(find.byKey(const ValueKey('recovery-restore-a')));
    await tester.pumpAndSettle();

    expect(recovery.recovered, ['a']);
    expect(find.byKey(const ValueKey('recovery-row-a')), findsNothing);
  });

  testWidgets('a failed restore keeps the row with the retry message', (
    tester,
  ) async {
    final pending = [_recording('a', hasAudio: true)];
    final recovery = _FakeRecovery(
      pending: pending,
      outcome: RecoveryOutcome.failed,
    );
    await _pump(tester, pending: pending, recovery: recovery);

    await tester.tap(find.byKey(const ValueKey('recovery-restore-a')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recovery-row-a')), findsOneWidget);
    expect(find.textContaining('Recovery failed'), findsOneWidget);
  });

  testWidgets('discard removes the recording without importing it', (
    tester,
  ) async {
    final pending = [_recording('b', hasAudio: false)];
    final recovery = _FakeRecovery(pending: pending);
    await _pump(tester, pending: pending, recovery: recovery);

    await tester.tap(find.byKey(const ValueKey('recovery-discard-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(recovery.discarded, ['b']);
    expect(recovery.recovered, isEmpty);
  });

  testWidgets('discard asks first and keeps the recording on cancel '
      '(UIA-HIS-03)', (tester) async {
    final pending = [_recording('b', hasAudio: true)];
    final recovery = _FakeRecovery(pending: pending);
    await _pump(tester, pending: pending, recovery: recovery);

    await tester.tap(find.byKey(const ValueKey('recovery-discard-b')));
    await tester.pumpAndSettle();
    expect(find.text('Discard this recording?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();
    expect(recovery.discarded, isEmpty);
    expect(find.byKey(const ValueKey('recovery-row-b')), findsOneWidget);
  });

  testWidgets('a failed discard reports the error and keeps the row '
      '(UIA-HIS-03)', (tester) async {
    final pending = [_recording('b', hasAudio: true)];
    final recovery = _ThrowingDiscardRecovery(pending: pending);
    await _pump(tester, pending: pending, recovery: recovery);

    await tester.tap(find.byKey(const ValueKey('recovery-discard-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recovery-row-b')), findsOneWidget);
    expect(
      tester
          .widget<WpButton>(find.byKey(const ValueKey('recovery-discard-b')))
          .onPressed,
      isNotNull,
      reason: 'the row is not left busy after the failure',
    );
    // Let the toast dismiss and its animations settle before the test ends.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('reports how many damaged journal entries were skipped', (
    tester,
  ) async {
    final pending = <InterruptedRecording>[];
    await _pump(
      tester,
      pending: pending,
      recovery: _FakeRecovery(pending: pending),
      skippedCorrupt: 2,
    );

    expect(find.textContaining('2 damaged recovery entries'), findsOneWidget);
  });
}
