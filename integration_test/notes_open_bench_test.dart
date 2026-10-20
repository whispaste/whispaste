// WP-31a acceptance benchmark: notes open, image strip, versions panel
// (target: panel visible within 500 ms) and frame timings of real flings.
//
// Purpose: reproducible evidence for the WP-31a acceptance criterion.
// Run in PROFILE mode on macOS only (debug numbers do not count):
//   flutter drive --profile -d macos \
//     --driver <driver file> --target integration_test/notes_open_bench_test.dart \
//     --dart-define=BENCH_IMAGE=<absolute path to a jpg/png>
// Not part of the normal suite: the test carries the `bench` tag and is
// excluded from ordinary runs. Results: see the WP-31a report (hardware,
// build mode, median and p90 per metric).
//
// Measured items:
// (a) time to first useful content (editor text, then image img0);
// (b) scrolling the image strip to img9;
// (c) versions panel: first frame, first list row, transition end, and the
//     database query on its own;
// (d) real flings over the image strip and over the long editor body,
//     frame timings from binding timings callback (build, raster, total).
// Each run gets its own database and temp folder: makeTestable closes the
// database when the widget tree is disposed.
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_asset_storage.dart';
import 'package:whispaste/core/data/note_version_limits.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_image_strip.dart';
import 'package:whispaste/features/notes/widgets/note_versions_dialog.dart';

import '../test/fixtures/test_helpers.dart';

const _imagePath = String.fromEnvironment('BENCH_IMAGE');
const _imageCount = 20;
const _runs = 5;
const _bodyLines = 400;
const _framesPerGesture = 120;

Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  int timeoutMs = 20000,
}) async {
  final sw = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (sw.elapsedMilliseconds > timeoutMs) {
      throw TestFailure('timeout waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 4));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

Future<void> _untilTrue(
  WidgetTester tester,
  bool Function() condition, {
  int timeoutMs = 20000,
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsedMilliseconds > timeoutMs) {
      throw TestFailure('timeout waiting for condition');
    }
    await tester.pump(const Duration(milliseconds: 4));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

int _pct(List<int> xs, double p) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * p).round()];
}

void _report(String name, List<int> xs) {
  stdout.writeln(
    'BENCH $name ms=$xs p50=${_pct(xs, 0.5)} p90=${_pct(xs, 0.9)}',
  );
}

void _reportFrames(String name, List<FrameTiming> frames) {
  final build = frames
      .map((f) => f.buildDuration.inMicroseconds / 1000)
      .map((v) => v.round())
      .toList();
  final raster = frames
      .map((f) => f.rasterDuration.inMicroseconds / 1000)
      .map((v) => v.round())
      .toList();
  final total = frames
      .map((f) => f.totalSpan.inMicroseconds / 1000)
      .map((v) => v.round())
      .toList();
  final missed = frames.where((f) => f.totalSpan.inMicroseconds > 16700).length;
  stdout.writeln(
    'BENCH $name frames=${frames.length} missed16_7=$missed '
    'build_p50=${_pct(build, 0.5)} build_p90=${_pct(build, 0.9)} '
    'build_p99=${_pct(build, 0.99)} raster_p50=${_pct(raster, 0.5)} '
    'raster_p90=${_pct(raster, 0.9)} raster_p99=${_pct(raster, 0.99)} '
    'total_p50=${_pct(total, 0.5)} total_p90=${_pct(total, 0.9)} '
    'total_p99=${_pct(total, 0.99)}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notes open benchmark', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    final image = File(_imagePath).readAsBytesSync();
    final rnd = Random(7);
    final now = DateTime(2026, 10, 1);
    final textMs = <int>[];
    final img0Ms = <int>[];
    final img9ScrollMs = <int>[];
    final panelFirstMs = <int>[];
    final panelRowMs = <int>[];
    final panelAnimMs = <int>[];
    final queryMs = <int>[];
    final stripFrames = <FrameTiming>[];
    final bodyFrames = <FrameTiming>[];

    for (var run = 0; run < _runs; run++) {
      final tmp = Directory.systemTemp.createTempSync('wp31a-bench-');
      try {
        final store = NoteAssetStore(appDataDirPath: tmp.path);
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final note = await db.createNote();
        String body(int seed, int lines) => List.generate(
          lines,
          (l) => 'Zeile $l Version $seed ${rnd.nextInt(100000)} lorem ipsum',
        ).join('\n');
        await db.updateNoteContent(note.id, body(999, _bodyLines));
        for (var i = 0; i < 50; i++) {
          await db.recordNoteVersionIfChanged(
            note.id,
            title: 'Notiz',
            content: body(i, 60),
            limits: const NoteVersionLimits(maxCount: 50),
            now: now.add(Duration(hours: i)),
          );
        }
        final versions = await db.noteVersionsFor(note.id);
        for (var i = 0; i < _imageCount; i++) {
          final rel = 'note_assets/${note.id}/img$i.jpg';
          await store.write(rel, image);
          await db.insertNoteAssetWithinLimits(
            NoteAssetsCompanion.insert(
              id: 'img$i',
              noteId: note.id,
              relativePath: rel,
              mimeType: 'image/jpeg',
              sizeBytes: image.length,
              width: 1,
              height: 1,
              createdAt: now,
            ),
            const NoteAssetLimits(),
          );
        }

        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.pumpWidget(
          makeTestable(
            Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const Expanded(child: NotesPage()),
                    FilledButton(
                      key: const ValueKey('open-versions'),
                      onPressed: () => showNoteVersionsDialog(
                        context: context,
                        noteId: note.id,
                      ),
                      child: const Text('versions'),
                    ),
                  ],
                ),
              ),
            ),
            size: const Size(1100, 800),
            locale: const Locale('de'),
            db: db,
            liveNoteAssets: true,
            overrides: [noteAssetStoreProvider.overrideWithValue(store)],
          ),
        );
        await tester.pump();
        await _until(tester, find.textContaining('Zeile 0 Version 999'));
        await tester.pumpAndSettle();

        // (a) time to first useful content.
        final editorText = find.descendant(
          of: find.byKey(const ValueKey('notes-editor-body')),
          matching: find.textContaining('Zeile 0 Version 999'),
        );
        final sw = Stopwatch()..start();
        await tester.tap(find.textContaining('Zeile 0 Version 999').first);
        await tester.pump();
        await _until(tester, editorText);
        textMs.add(sw.elapsedMilliseconds);
        await _until(
          tester,
          find.byKey(const ValueKey('notes-editor-image-img0')),
        );
        img0Ms.add(sw.elapsedMilliseconds);

        // (b) scroll the strip to img9 until it is built.
        final strip = find.descendant(
          of: find.byType(NoteImageStrip),
          matching: find.byType(Scrollable),
        );
        final sw2 = Stopwatch()..start();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('notes-editor-image-img9')),
          120,
          scrollable: strip,
        );
        await tester.pump();
        img9ScrollMs.add(sw2.elapsedMilliseconds);
        await tester.pumpAndSettle();

        // (c) versions panel, split. Stopwatch stops before any settle.
        final rowKey = ValueKey('notes-version-row-${versions.first.id}');
        final sw3 = Stopwatch()..start();
        await tester.tap(find.byKey(const ValueKey('open-versions')));
        await tester.pump();
        await _until(
          tester,
          find.byWidgetPredicate(
            (w) =>
                w is CircularProgressIndicator ||
                (w.key is ValueKey &&
                    (w.key! as ValueKey).value == rowKey.value),
          ),
        );
        panelFirstMs.add(sw3.elapsedMilliseconds);
        await _until(tester, find.byKey(rowKey));
        panelRowMs.add(sw3.elapsedMilliseconds);
        final route = ModalRoute.of(tester.element(find.byKey(rowKey)))!;
        await _untilTrue(
          tester,
          () => route.animation!.status == AnimationStatus.completed,
        );
        panelAnimMs.add(sw3.elapsedMilliseconds);
        await tester.pumpAndSettle();
        final sw4 = Stopwatch()..start();
        await tester.runAsync(() => db.watchNoteVersions(note.id).first);
        queryMs.add(sw4.elapsedMilliseconds);
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();

        // (d1) real flings over the image strip, at least 120 frames.
        void collectStrip(List<FrameTiming> t) => stripFrames.addAll(t);
        SchedulerBinding.instance.addTimingsCallback(collectStrip);
        var before = stripFrames.length;
        var gestures = 0;
        while (stripFrames.length - before < _framesPerGesture &&
            gestures < 40) {
          final dx = gestures.isEven ? -600.0 : 600.0;
          await tester.fling(strip, Offset(dx, 0), 2500);
          await tester.pump();
          gestures++;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        SchedulerBinding.instance.removeTimingsCallback(collectStrip);
        stdout.writeln('BENCH strip_gestures=$gestures');

        // (d2) real flings over the long editor body, at least 120 frames.
        final bodyScroll = find.byKey(const ValueKey('notes-editor-body'));
        void collectBody(List<FrameTiming> t) => bodyFrames.addAll(t);
        SchedulerBinding.instance.addTimingsCallback(collectBody);
        before = bodyFrames.length;
        gestures = 0;
        while (bodyFrames.length - before < _framesPerGesture &&
            gestures < 40) {
          final dy = gestures.isEven ? -700.0 : 700.0;
          await tester.fling(bodyScroll, Offset(0, dy), 2500);
          await tester.pump();
          gestures++;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        SchedulerBinding.instance.removeTimingsCallback(collectBody);
        stdout.writeln('BENCH body_gestures=$gestures');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }

    _report('a_text_visible', textMs);
    _report('a_img0_visible', img0Ms);
    _report('b_scroll_to_img9', img9ScrollMs);
    _report('c_panel_first_frame', panelFirstMs);
    _report('c_panel_first_row', panelRowMs);
    _report('c_panel_transition_end', panelAnimMs);
    _report('c_db_query_50_versions', queryMs);
    _reportFrames('d_strip_fling', stripFrames);
    _reportFrames('d_body_fling', bodyFrames);
  }, tags: ['bench']);
}
