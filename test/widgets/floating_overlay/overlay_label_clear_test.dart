/// While the overlay shows a status label, no level dot crosses the text
/// (#1845): bars whose slot overlaps the label band are not painted.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';
import 'package:whispaste/widgets/level_history/level_history_bars.dart';

void main() {
  test('no dot rect intersects the "Wird verarbeitet…" label', () {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Wird verarbeitet…',
        style: TextStyle(fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const left = 40.0, right = 300.0, textLeft = 40.0, count = 40;
    const barW = (right - left) / count;
    final label = Rect.fromLTWH(textLeft, 0, tp.width, 20);
    const pad = OverlayDesignSpec.transcribingWaveNotchPadPx;
    for (final phase in [0.0, 0.3, 0.7]) {
      final levels = WpOverlayPainter.processingLevels(
        count: count,
        left: left,
        barW: barW,
        glassPhase: phase,
        notchStart: textLeft - pad,
        notchEnd: textLeft + tp.width + pad,
      );
      for (var i = 0; i < count; i++) {
        if (levels[i] < 0) continue;
        final slot = Rect.fromLTWH(left + i * barW, 0, barW, 20);
        expect(
          slot.overlaps(label),
          isFalse,
          reason: 'bar $i is painted under the label',
        );
      }
    }
  });

  test('a hidden level paints nothing', () {
    final recorder = ui.PictureRecorder();
    final canvas = _CountingCanvas(Canvas(recorder));
    WpLevelHistoryBars.paint(
      canvas,
      const Rect.fromLTWH(0, 0, 100, 20),
      [0.5, WpLevelHistoryBars.hidden, 0.5],
      accent: Colors.orange,
      lineStrokeMin: 1,
    );
    expect(canvas.rrects, 2);
    recorder.endRecording();
  });
}

class _CountingCanvas implements Canvas {
  _CountingCanvas(this._inner);
  final Canvas _inner;
  int rrects = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    rrects++;
    _inner.drawRRect(rrect, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
