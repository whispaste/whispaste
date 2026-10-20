/// Paint-cost micro-benchmark for the WP-95 floating button look.
///
/// PROXY, NOT FIRST-FRAME. The coordinator asked for an overlay first-frame
/// measurement before and after the look options. This file measures only the
/// cost of painting one button frame (the shared [WpFloatingButtonPainter]) for
/// the default look and the new options. It does not measure app start,
/// engine boot or the native window, so it cannot stand in for first-frame
/// time. It shows only whether the new options add paint work.
///
/// Manual tool, skipped in the default `flutter test` sweep:
///
/// ```sh
/// FLOATING_BUTTON_BENCH=1 flutter test test/benchmark/floating_button_paint_bench_test.dart
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

const _frames = 2000;
const _warmup = 200;

double _percentile(List<int> sortedUs, double q) {
  final index = ((sortedUs.length - 1) * q).round();
  return sortedUs[index] / 1000.0;
}

/// Records one frame of the painter and returns its cost in microseconds.
int _paintOnce(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final watch = Stopwatch()..start();
  painter.paint(canvas, size);
  watch.stop();
  recorder.endRecording().dispose();
  return watch.elapsedMicroseconds;
}

void main() {
  final enabled = Platform.environment['FLOATING_BUTTON_BENCH'] == '1';

  final variants = <(String, FloatingButtonVisualState, FloatingButtonLook)>[
    (
      'default: round, idle',
      FloatingButtonVisualState.idle,
      FloatingButtonLook.defaults,
    ),
    (
      'round, recording with ring',
      FloatingButtonVisualState.recording,
      FloatingButtonLook.defaults,
    ),
    (
      'square, recording with ring',
      FloatingButtonVisualState.recording,
      const FloatingButtonLook(square: true),
    ),
    (
      'round, recording without ring',
      FloatingButtonVisualState.recording,
      const FloatingButtonLook(ring: false),
    ),
  ];

  test(
    'floating button paint cost per frame (PROXY, not first frame)',
    () {
      final size = OverlayDesignSpec.buttonWindowSize(56);
      print('');
      print('Floating button paint cost (PROXY, not first-frame time)');
      print('frames per variant: $_frames (after $_warmup warm-up)');
      for (final (name, state, look) in variants) {
        final painter = WpFloatingButtonView.painterFor(
          state: state,
          look: look,
        );
        for (var i = 0; i < _warmup; i++) {
          _paintOnce(painter, size);
        }
        final samples = <int>[
          for (var i = 0; i < _frames; i++) _paintOnce(painter, size),
        ]..sort();
        final median = _percentile(samples, 0.5);
        final p95 = _percentile(samples, 0.95);
        print(
          '  ${name.padRight(34)} median ${median.toStringAsFixed(3)} ms  '
          'p95 ${p95.toStringAsFixed(3)} ms',
        );
      }
    },
    skip: enabled ? false : 'set FLOATING_BUTTON_BENCH=1 to run',
  );
}
