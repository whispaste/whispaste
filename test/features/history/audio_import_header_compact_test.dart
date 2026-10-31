/// The import header above the history list has two forms (UX-077, compact
/// mode). A tall window below text scale 2.0 keeps the full row: description
/// and "Add files". Compact mode (a window below 780 px, or text scale 2.0)
/// drops that row: the add action becomes an icon in the status line with a
/// 44 px target, and the description moves into the import dialog. Mounts the
/// real history page in the screenshot shell, so the pane is the size the
/// user sees. A RenderFlex overflow fails through `tester.takeException()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';

import '../../ux_audit/ux_fixtures.dart';

final _now = DateTime(2026, 10, 25, 12);

/// One job in the queue, so the header is shown during an import.
final _jobs = <ImportJob>[
  ImportJob(
    id: 'import-whisper',
    fileName: 'Besprechung-Q4.mp3',
    status: ImportStatus.transcribing,
    transcribingSince: _now.subtract(const Duration(seconds: 75)),
  ),
];

class _FixedQueue extends AudioImportQueueNotifier {
  @override
  List<ImportJob> build() => _jobs;
}

/// The German description, matched by its fixed start so the test does not
/// depend on the format list.
const _descriptionStart = 'Audiodateien (';

Future<void> _pump(WidgetTester tester, Size size, double scale) async {
  final db = await openSeededUxDatabase(tester);
  addTearDown(() => tester.runAsync(db.close));
  final screen = UxScreen(
    id: 'history-import-header',
    activePageId: 'history',
    build: () => const HistoryPage(),
  );
  await pumpUxScreen(
    tester,
    screen: screen,
    db: db,
    size: size,
    scale: scale,
    theme: 'dark',
    locale: 'de',
    extraOverrides: [
      audioImportQueueProvider.overrideWith(_FixedQueue.new),
      audioImportClockProvider.overrideWithValue(() => _now),
    ],
  );
}

Future<void> _tearDown(WidgetTester tester) async {
  // The transcribing row runs a one-second ticker. Dropping the tree stops it,
  // as the harness does, before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('compact mode: Escape closes the dialog that shows the text', (
    tester,
  ) async {
    await _pump(tester, kUxSizeMinimum, 1.0);

    // The transcribing row's ticker keeps frames coming, so the dialog is
    // awaited with fixed pumps instead of pumpAndSettle.
    await tester.tap(find.byKey(const ValueKey('history-import-summary')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(_descriptionStart), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(_descriptionStart), findsNothing);
    expect(tester.takeException(), isNull);

    await _tearDown(tester);
  });
}
