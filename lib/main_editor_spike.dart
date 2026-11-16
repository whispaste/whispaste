/// Standalone harness for the #642 block editor spike — NOT wired into the
/// production app, following the separate-entrypoint pattern of
/// `main_wp_button_gallery.dart`.
///
/// Run it with (profile mode for timing):
///
///   flutter run --profile -t lib/main_editor_spike.dart \
///     --dart-define=SPIKE_DOC=100k
///
/// `SPIKE_DOC`: `20k`, `100k` (prose with headings) or `para` (one
/// 20,000-word paragraph without blank lines, the dictation case).
/// Every 5 s it prints one `SPIKE_FRAMES` line to stdout (and appends it to
/// `SPIKE_FRAMES_FILE` when set) with build and raster times of the frames
/// since the last line, so a test run on the lab guests can read frame times
/// without a profiler.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/theme.dart';
import 'features/notes/blocks/block_document.dart';
import 'features/editor_spike/block_editor.dart';
import 'features/editor_spike/spike_corpus.dart';

const _doc = String.fromEnvironment('SPIKE_DOC', defaultValue: '20k');

String _source() => switch (_doc) {
  '100k' => germanProse(100000),
  'para' => singleParagraph(20000),
  _ => germanProse(20000),
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'Editor Spike ($_doc)', size: Size(1000, 800)),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  _reportFrames();
  runApp(const _SpikeApp());
}

void _reportFrames() {
  final build = <int>[];
  final raster = <int>[];
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> ts) {
    for (final t in ts) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
  });
  Stream<void>.periodic(const Duration(seconds: 5)).listen((_) {
    if (build.isEmpty) return;
    String stats(List<int> v) {
      final s = [...v]..sort();
      final p95 = s[((s.length - 1) * 0.95).round()];
      return 'median=${s[s.length ~/ 2]}us p95=${p95}us max=${s.last}us';
    }

    final line =
        'SPIKE_FRAMES doc=$_doc n=${build.length} '
        'build[${stats(build)}] raster[${stats(raster)}]';
    stdout.writeln(line);
    // A Windows GUI app has no usable stdout, so a test run can name a file.
    final file = Platform.environment['SPIKE_FRAMES_FILE'];
    if (file != null) {
      File(file).writeAsStringSync('$line\n', mode: FileMode.append);
    }
    build.clear();
    raster.clear();
  });
}

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    final document = BlockDocument.parse(_source());
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpLightTheme(),
      home: Scaffold(
        key: const ValueKey('editor-spike-screen'),
        body: BlockEditor(document: document),
      ),
    );
  }
}
