/// Focused UX harness for the hotkey fallback toast (XP-5-09): shows the toast
/// over the regular shell and captures it at the sweep sizes, scales and
/// locales. Survey tool, asserts nothing. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_hotkey_toast_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/widgets/hotkey_fallback_toast.dart';

import 'ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// Hosts its own [Overlay] inside the capture boundary: the toast goes into
/// the nearest overlay, and the shell's overlay would sit outside the PNG.
class _FallbackProbe extends StatelessWidget {
  const _FallbackProbe();

  @override
  Widget build(BuildContext context) =>
      Overlay(initialEntries: [OverlayEntry(builder: _entryBuilder)]);

  static Widget _entryBuilder(BuildContext context) => const _FallbackTrigger();
}

/// Shows the fallback toast once the first frame is on screen.
class _FallbackTrigger extends ConsumerStatefulWidget {
  const _FallbackTrigger();

  @override
  ConsumerState<_FallbackTrigger> createState() => _FallbackTriggerState();
}

class _FallbackTriggerState extends ConsumerState<_FallbackTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showHotkeyFallbackToast(context: context, ref: ref);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// Lets the fallback toast run out (10 s, then its exit animation) before the
/// tree is disposed; a still-running toast animation at disposal is reported as
/// a ticker warning. Same teardown as `_teardown` in
/// test/journeys/dictionary_csv_journey_test.dart.
Future<void> _letToastRunOut(WidgetTester tester) async {
  const key = ValueKey('toast-hotkey-fallback');
  for (var i = 0; i < 120; i++) {
    if (find.byKey(key).evaluate().isEmpty) break;
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final locale in _locales) {
        final name =
            'hotkey-fallback-toast__${size.width.toInt()}x${size.height.toInt()}'
            '__s${scale.toString()}__dark_$locale';
        testWidgets('ux-toast: $name', (tester) async {
          final db = await openSeededUxDatabase(tester);
          addTearDown(() => tester.runAsync(db.close));

          final screen = UxScreen(
            id: 'hotkey-fallback-toast',
            activePageId: 'settings',
            build: () => const _FallbackProbe(),
          );
          await pumpUxScreen(
            tester,
            screen: screen,
            db: db,
            size: size,
            scale: scale,
            theme: 'dark',
            locale: locale,
          );
          await tester.pump(const Duration(milliseconds: 400));

          final error = tester.takeException();
          if (error != null) {
            Directory(outDir).createSync(recursive: true);
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
            Directory(outDir).createSync(recursive: true);
            File(
              '$outDir/$name.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });

          await _letToastRunOut(tester);
        });
      }
    }
  }
}
