/// Positioning/clamping/anchor tests for the shared overlay math (issue 05
/// AC3). The math is platform-independent and sourced from [OverlayDesignSpec],
/// so a single suite locks the behaviour for macOS, Windows and Linux.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/overlay_positioning.dart';

void main() {
  final margin = OverlayDesignSpec.interaction.screenEdgeMargin;
  // A primary screen at the origin (logical pixels).
  const screen = Rect.fromLTWH(0, 0, 1920, 1080);

  group('overlaySize / constants are spec-sourced', () {
    test('normal & compact sizes match the spec', () {
      expect(
        OverlayPositioning.overlaySize(compact: false),
        Size(
          OverlayDesignSpec.normalSize.width,
          OverlayDesignSpec.normalSize.height,
        ),
      );
      expect(
        OverlayPositioning.overlaySize(compact: true),
        Size(
          OverlayDesignSpec.compactSize.width,
          OverlayDesignSpec.compactSize.height,
        ),
      );
    });

    test('edge margin & drag threshold come from the spec', () {
      expect(OverlayPositioning.edgeMargin, margin);
      expect(
        OverlayPositioning.dragThreshold,
        OverlayDesignSpec.interaction.dragThresholdPx,
      );
    });
  });

  group('anchor resolution', () {
    final size = OverlayPositioning.overlaySize(compact: false);

    test('topCenter centres horizontally, margin from the top', () {
      final p = OverlayPositioning.resolve(
        anchor: OverlayAnchor.topCenter,
        screen: screen,
        size: size,
      );
      expect(p.dx, closeTo((screen.width - size.width) / 2, 1e-9));
      expect(p.dy, closeTo(margin, 1e-9));
    });

    test('bottomCenter centres horizontally, margin from the bottom', () {
      final p = OverlayPositioning.resolve(
        anchor: OverlayAnchor.bottomCenter,
        screen: screen,
        size: size,
      );
      expect(p.dx, closeTo((screen.width - size.width) / 2, 1e-9));
      expect(p.dy, closeTo(screen.height - size.height - margin, 1e-9));
    });

    test('lastPosition uses the supplied point (clamped on-screen)', () {
      final p = OverlayPositioning.resolve(
        anchor: OverlayAnchor.lastPosition,
        screen: screen,
        size: size,
        lastPosition: const Offset(300, 500),
      );
      expect(p, const Offset(300, 500));
    });

    test('lastPosition without a stored point falls back to top-centre', () {
      final p = OverlayPositioning.resolve(
        anchor: OverlayAnchor.lastPosition,
        screen: screen,
        size: size,
      );
      expect(p.dx, closeTo((screen.width - size.width) / 2, 1e-9));
      expect(p.dy, closeTo(margin, 1e-9));
    });
  });

  group('screen clamping (multi-monitor / resolution change)', () {
    final size = OverlayPositioning.overlaySize(compact: false);

    test('an off-screen-right point is pulled back inside the margin', () {
      final p = OverlayPositioning.clampToScreen(
        point: const Offset(5000, 5000),
        size: size,
        screen: screen,
      );
      expect(p.dx, closeTo(screen.width - size.width - margin, 1e-9));
      expect(p.dy, closeTo(screen.height - size.height - margin, 1e-9));
    });

    test('a negative point is pushed to the top-left in-margin corner', () {
      final p = OverlayPositioning.clampToScreen(
        point: const Offset(-300, -300),
        size: size,
        screen: screen,
      );
      expect(p.dx, closeTo(margin, 1e-9));
      expect(p.dy, closeTo(margin, 1e-9));
    });

    test('clamps relative to a secondary monitor offset from the origin', () {
      // A second display to the right of the primary.
      const secondary = Rect.fromLTWH(1920, 0, 1280, 720);
      final p = OverlayPositioning.clampToScreen(
        point: const Offset(0, 0), // far left of the secondary screen
        size: size,
        screen: secondary,
      );
      expect(p.dx, closeTo(secondary.left + margin, 1e-9));
      expect(p.dy, closeTo(margin, 1e-9));
    });

    test('degenerate tiny screen pins to the in-margin corner', () {
      const tiny = Rect.fromLTWH(0, 0, 100, 50);
      final p = OverlayPositioning.clampToScreen(
        point: const Offset(40, 20),
        size: size,
        screen: tiny,
      );
      expect(p.dx, closeTo(margin, 1e-9));
      expect(p.dy, closeTo(margin, 1e-9));
    });
  });
}
