/// Cross-platform parity gallery — a dev harness, NOT part of the shipped app.
///
/// Renders every shared floating-surface frame (the 16-cell overlay matrix
/// `4 states × 2 themes × 2 sizes` plus the 6 floating-button states) with the
/// exact same `OverlayPainter` / `FloatingButtonPainter` the native shells host
/// (ADR 0002). It then captures itself to a single PNG via
/// `RepaintBoundary.toImage` and exits.
///
/// Because the identical Dart renderer runs on macOS, Windows and Linux, the
/// three captured PNGs are the visual-parity proof for issue 05: any per-OS
/// drift would show up as a pixel difference between the gallery images.
///
/// Run (writes `OUT`, default `./parity-gallery.png`):
///   flutter run -d macos  -t tool/parity_gallery.dart --dart-define=OUT=/abs/path.png
///   flutter run -d linux  -t tool/parity_gallery.dart --dart-define=OUT=/abs/path.png
///   flutter run -d windows -t tool/parity_gallery.dart --dart-define=OUT=C:\abs\path.png
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

const String _outPath = String.fromEnvironment(
  'OUT',
  defaultValue: 'parity-gallery.png',
);

// Logical size of the whole gallery canvas; the window is sized to match so the
// RepaintBoundary is fully laid out and painted before capture.
const Size _canvas = Size(1360, 860);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: _canvas,
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.setResizable(false);
      await windowManager.show();
    },
  );
  runApp(const _GalleryApp());
}

class _GalleryApp extends StatefulWidget {
  const _GalleryApp();

  @override
  State<_GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<_GalleryApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureWhenReady());
  }

  Future<void> _captureWhenReady() async {
    if (_captured) return;
    _captured = true;
    // Let a couple of frames settle (checkerboard + text layout) before grabbing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(_outPath);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print(
        'PARITY_GALLERY_WRITTEN=${file.absolute.path} '
        '(${image.width}x${image.height})',
      );
    } catch (e) {
      // ignore: avoid_print
      print('PARITY_GALLERY_ERROR=$e');
      exit(2);
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    // Force the captured boundary to the full canvas size regardless of the
    // OS window size. Tiling WMs (e.g. sway on the Linux CI VM) clamp the
    // window to the output resolution; without this the RepaintBoundary would
    // lay out at the clamped size and the capture would be cropped. The
    // RepaintBoundary records its whole subtree into its own layer, so
    // `toImage` captures the full canvas even though only part is on screen.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: OverflowBox(
          minWidth: _canvas.width,
          maxWidth: _canvas.width,
          minHeight: _canvas.height,
          maxHeight: _canvas.height,
          alignment: Alignment.topLeft,
          child: RepaintBoundary(key: _boundaryKey, child: const _Gallery()),
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: _canvas.width,
        height: _canvas.height,
        color: const Color(0xFF8A8F98),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Heading('Overlay — 4 states × 2 themes × 2 sizes'),
            const SizedBox(height: 8),
            for (final state in OverlayVisualState.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _RowLabel(state.name),
                    for (final isDark in const [true, false])
                      for (final compact in const [false, true])
                        _OverlayTile(
                          state: state,
                          isDark: isDark,
                          compact: compact,
                        ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const _Heading('Floating button — 6 states'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in FloatingButtonVisualState.values)
                  _ButtonTile(state: s),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// A single overlay frame painted on a checkerboard so transparency is visible.
class _OverlayTile extends StatelessWidget {
  const _OverlayTile({
    required this.state,
    required this.isDark,
    required this.compact,
  });

  final OverlayVisualState state;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final window = OverlayDesignSpec.windowSize(compact: compact);
    final bars = List<double>.generate(
      OverlayDesignSpec.waveform.barCount,
      (i) => (i % 7) / 7.0,
    );
    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: state,
      isDark: isDark,
      compact: compact,
      label: switch (state) {
        OverlayVisualState.recording => 'Recording',
        OverlayVisualState.transcribing => 'Transcribing…',
        OverlayVisualState.done => 'Pasted',
        OverlayVisualState.error => 'Error',
      },
      elapsed: state == OverlayVisualState.recording ? '1:30' : '',
      errorMessage: state == OverlayVisualState.error
          ? 'Network timeout'
          : null,
      doneMessage: state == OverlayVisualState.done ? 'Pasted' : null,
      progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        children: [
          _Checkerboard(
            size: window,
            child: CustomPaint(
              size: window,
              painter: FloatingOverlayView.painterFor(
                snapshot: snapshot,
                waveformBars: bars,
                dotPulse: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${isDark ? 'dark' : 'light'} · ${compact ? 'compact' : 'normal'}',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ButtonTile extends StatelessWidget {
  const _ButtonTile({required this.state});
  final FloatingButtonVisualState state;

  @override
  Widget build(BuildContext context) {
    const diameter = 56.0;
    final window = OverlayDesignSpec.buttonWindowSize(diameter);
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Column(
        children: [
          _Checkerboard(
            size: window,
            child: CustomPaint(
              size: window,
              painter: FloatingButtonView.painterFor(
                state: state,
                diameter: diameter,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            state.name,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Mid-contrast checkerboard backdrop so the (partly transparent) surfaces read
/// clearly in both themes.
class _Checkerboard extends StatelessWidget {
  const _Checkerboard({required this.size, required this.child});
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerPainter(),
      child: SizedBox(width: size.width, height: size.height, child: child),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  static const double _cell = 8;
  static const Color _a = Color(0xFFB7BCC4);
  static const Color _b = Color(0xFF9AA0A8);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (double y = 0; y < size.height; y += _cell) {
      for (double x = 0; x < size.width; x += _cell) {
        final even = ((x ~/ _cell) + (y ~/ _cell)).isEven;
        paint.color = even ? _a : _b;
        canvas.drawRect(Rect.fromLTWH(x, y, _cell, _cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
