/// Focused UX harness for the import rows of the history page (e736c1e0c):
/// one job per state side by side — copying with a bar, transcribing with a
/// percentage, transcribing without engine progress ("Läuft seit m:ss"), and
/// a queued job. The clock is pinned so the elapsed time is stable. Survey
/// tool, asserts nothing. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_import_progress_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _themes = ['dark', 'navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// Pinned "now" so the elapsed time in the capture is always the same.
final DateTime _now = DateTime(2026, 10, 22, 12);

final List<ImportJob> _jobs = [
  const ImportJob(
    id: 'import-copy',
    fileName: 'Interview-Kopie-mit-langem-Dateinamen-2026.wav',
    status: ImportStatus.copying,
    progress: 0.6,
  ),
  ImportJob(
    id: 'import-whisper',
    fileName: 'Besprechung-Q4.mp3',
    status: ImportStatus.transcribing,
    progress: 0.42,
    transcribingSince: _now.subtract(const Duration(seconds: 75)),
  ),
  ImportJob(
    id: 'import-parakeet',
    fileName: 'Vortrag.m4a',
    status: ImportStatus.transcribing,
    transcribingSince: _now.subtract(const Duration(minutes: 12, seconds: 5)),
  ),
  const ImportJob(id: 'import-queued', fileName: 'Notiz.ogg'),
];

/// Holds the fixed job list; the real queue would start its own work.
class _FixedImportQueue extends AudioImportQueueNotifier {
  @override
  List<ImportJob> build() => _jobs;
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final theme in _themes) {
        for (final locale in _locales) {
          final name =
              'history-import-progress__${size.width.toInt()}x${size.height.toInt()}'
              '__s${scale.toString()}__${theme}_$locale';
          testWidgets('ux-import-progress: $name', (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));

            final screen = UxScreen(
              id: 'history-import-progress',
              activePageId: 'history',
              build: () => const HistoryPage(),
            );
            await pumpUxScreen(
              tester,
              screen: screen,
              db: db,
              size: size,
              scale: scale,
              theme: theme,
              locale: locale,
              extraOverrides: [
                audioImportQueueProvider.overrideWith(_FixedImportQueue.new),
                audioImportClockProvider.overrideWithValue(() => _now),
              ],
            );

            final error = tester.takeException();
            Directory(outDir).createSync(recursive: true);
            if (error != null) {
              File(
                '$outDir/exceptions.log',
              ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
            }

            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey(kUxCaptureKey)),
              );
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '$outDir/$name.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });

            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 5));
            debugDefaultTargetPlatformOverride = null;
          });
        }
      }
    }
  }
}
