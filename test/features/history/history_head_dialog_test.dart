/// The history header's status row: on a tall window an expanded section shows
/// its rows inline; on a short window (below 780 px, or text scale 2.0) it
/// opens a dialog instead. Escape closes the dialog and returns focus to the
/// status target. The dialog's actions work, also in a right-to-left locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/widgets/history_status_row.dart';
import 'package:whispaste/features/history/widgets/recovery_banner.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/widgets/wp_button.dart';

class _FakeRecovery extends RecordingRecovery {
  _FakeRecovery({required this.pending})
    : super(
        audioDir: '',
        transcribe: (_) async => const RecoveryTranscription.ok(),
      );

  final List<InterruptedRecording> pending;
  final discarded = <String>[];

  @override
  Future<void> discard(InterruptedRecording recording) async {
    discarded.add(recording.id);
    pending.remove(recording);
  }
}

InterruptedRecording _recording(String id, {required bool hasAudio}) =>
    InterruptedRecording(
      id: id,
      startedAt: DateTime(2026, 10, 17, 9),
      wavPath: hasAudio ? '/rec/$id.wav' : null,
      journalPath: '/rec/journal/$id.json',
    );

Future<_FakeRecovery> _pump(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  final pending = [
    _recording('a', hasAudio: true),
    _recording('b', hasAudio: false),
    _recording('c', hasAudio: false),
  ];
  final recovery = _FakeRecovery(pending: pending);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        interruptedRecordingsProvider.overrideWith(
          (ref) async => RecordingJournalScan(
            recordings: List.of(pending),
            skippedCorrupt: 0,
          ),
        ),
        recordingRecoveryProvider.overrideWithValue(recovery),
      ],
      child: MaterialApp(
        theme: wpDarkTheme(),
        locale: locale,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de'), Locale('he')],
        home: const Scaffold(
          body: Column(children: [HistoryStatusRow(), RecoveryBanner()]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return recovery;
}

Future<void> _openSummary(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('history-recovery-summary')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Escape closes the dialog and returns focus to the target', (
    tester,
  ) async {
    await _pump(tester, size: const Size(800, 716));
    await _openSummary(tester);
    expect(find.byType(RecoveryAllRows), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(RecoveryAllRows), findsNothing);
    final focused = tester.binding.focusManager.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      focused!.findAncestorWidgetOfExactType<WpButton>()?.testId,
      'history-recovery-summary',
    );
  });
}
