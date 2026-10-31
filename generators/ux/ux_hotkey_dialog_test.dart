/// Focused UX harness for the dictation trigger (cf9c28b81): the "Hotkey
/// ändern" dialog (the recorder with single keys) and the hotkey recorder card
/// (`WpHotkeyRecorderDialog.show`) in two states — a free combination and one
/// that another action already holds. A small keyboard probe writes what Enter,
/// Escape and Tab do to `keyboard-probe.log`. Survey tool, asserts nothing:
/// layout exceptions go to exceptions.log, PNGs to the output dir. Tagged
/// `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_hotkey_dialog_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];
const String _theme = 'navy';

/// Which surface a probe opens on its first frame.
enum _Surface { trigger, recorderFree, recorderHeld }

/// Result of the last opened surface, for the keyboard probe log.
Object? _lastResult;
bool _lastClosed = false;

/// Hosts its own [Navigator] inside the capture boundary, so the dialog route
/// is painted inside the PNG (the shell's navigator sits outside it).
class _DialogProbe extends StatelessWidget {
  const _DialogProbe({required this.surface});

  final _Surface surface;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => _OpenOnFrame(surface: surface)),
  );
}

class _OpenOnFrame extends StatefulWidget {
  const _OpenOnFrame({required this.surface});

  final _Surface surface;

  @override
  State<_OpenOnFrame> createState() => _OpenOnFrameState();
}

class _OpenOnFrameState extends State<_OpenOnFrame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastClosed = false;
      _lastResult = null;
      switch (widget.surface) {
        case _Surface.trigger:
          unawaited(
            WpHotkeyRecorderDialog.show(
              context,
              initialKey: 'D',
              initialModifiers: 'meta+shift',
              singleKeys: ModifierHotkey.values.toSet(),
              initialSingleKey: 'rightMeta',
            ).then((v) {
              _lastResult = v;
              _lastClosed = true;
            }),
          );
        case _Surface.recorderFree:
          unawaited(
            WpHotkeyRecorderDialog.show(
              context,
              initialKey: 'D',
              initialModifiers: 'meta+shift',
              holderOf: (_, _) => null,
            ).then((v) {
              _lastResult = v;
              _lastClosed = true;
            }),
          );
        case _Surface.recorderHeld:
          unawaited(
            WpHotkeyRecorderDialog.show(
              context,
              initialKey: 'D',
              initialModifiers: 'meta+shift',
              holderOf: (_, _) => 'Schnellnotiz',
            ).then((v) {
              _lastResult = v;
              _lastClosed = true;
            }),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _capture(WidgetTester tester, String outDir, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  // The output folder may not exist yet on the first capture (H4).
  Directory(outDir).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey(kUxCaptureKey)),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _logLine(String outDir, String file, String line) {
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$file').writeAsStringSync('$line\n', mode: FileMode.append);
}

Future<void> _open(
  WidgetTester tester,
  HistoryDatabase db,
  Size size,
  double scale,
  String locale,
  _Surface surface,
) async {
  await pumpUxScreen(
    tester,
    screen: UxScreen(
      id: 'hotkey-dialog-${surface.name}',
      activePageId: 'settings',
      build: () => _DialogProbe(surface: surface),
    ),
    db: db,
    size: size,
    scale: scale,
    theme: _theme,
    locale: locale,
  );
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final surface in _Surface.values) {
    for (final size in _sizes) {
      for (final scale in _scales) {
        for (final locale in _locales) {
          final name =
              'hotkey-${surface.name}__${size.width.toInt()}x${size.height.toInt()}'
              '__s${scale.toString()}__${_theme}_$locale';
          testWidgets('ux-hotkey: $name', (tester) async {
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));

            await _open(tester, db, size, scale, locale, surface);
            await _capture(tester, outDir, name);

            final error = tester.takeException();
            if (error != null) {
              _logLine(outDir, 'exceptions.log', '$name: $error');
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
          });
        }
      }
    }
  }

  // Keyboard probe: what the keys do on the trigger dialog and the recorder.
  // Writes one line per check; nothing is asserted.
  testWidgets('ux-hotkey: keyboard probe', (tester) async {
    final db = await openSeededUxDatabase(tester);
    addTearDown(() => tester.runAsync(db.close));
    const log = 'keyboard-probe.log';
    const size = kUxSizeMinimum;

    // 1. Trigger dialog: pick a single key, then press Enter.
    await _open(tester, db, size, 1.0, 'de', _Surface.trigger);
    await tester.pump(const Duration(milliseconds: 600));
    final chips = find.byType(WpFilterChip);
    _logLine(outDir, log, 'trigger: chips=${chips.evaluate().length}');
    if (chips.evaluate().isNotEmpty) {
      await tester.tap(chips.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    _logLine(
      outDir,
      log,
      'trigger: after chip + Enter closed=$_lastClosed result=$_lastResult',
    );
    if (!_lastClosed) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 600));
    }
    _logLine(
      outDir,
      log,
      'trigger: after Escape closed=$_lastClosed result=$_lastResult',
    );

    // 2. Recorder (free): Tab to the next control, then record ctrl+K.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    await _open(tester, db, size, 1.0, 'de', _Surface.recorderFree);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
    final saveAfterTab = tester.widget<Text>(
      find.descendant(
        of: find.byType(WpButton).last,
        matching: find.byType(Text),
      ),
    );
    _logLine(
      outDir,
      log,
      'recorder: after Tab, ctrl+K recorded (save label=${saveAfterTab.data})',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    _logLine(
      outDir,
      log,
      'recorder: after Enter closed=$_lastClosed result=$_lastResult',
    );
    if (!_lastClosed) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 600));
    }
    _logLine(
      outDir,
      log,
      'recorder: after Escape closed=$_lastClosed result=$_lastResult',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    final error = tester.takeException();
    if (error != null) {
      _logLine(outDir, 'exceptions.log', 'keyboard-probe: $error');
    }
  });
}
