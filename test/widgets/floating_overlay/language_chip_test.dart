import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/language_cycle.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

void main() {
  group('languageChipLabelFor', () {
    test('shows the uppercase code of a fixed language', () {
      expect(languageChipLabelFor('de'), 'DE');
      expect(languageChipLabelFor(' en '), 'EN');
      expect(languageChipLabelFor('zh'), 'ZH');
    });

    test('shows no chip for auto or an empty code', () {
      expect(languageChipLabelFor('auto'), isNull);
      expect(languageChipLabelFor(''), isNull);
      expect(languageChipLabelFor('   '), isNull);
    });
  });

  group('snapshot', () {
    test('carries the chip label through toMap and fromMap', () {
      const snapshot = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
        languageChip: 'DE',
      );
      final restored = FloatingOverlaySnapshot.fromMap(snapshot.toMap());
      expect(restored.languageChip, 'DE');
    });

    test('defaults to no chip', () {
      const snapshot = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
      );
      expect(snapshot.languageChip, isNull);
      expect(
        FloatingOverlaySnapshot.fromMap(snapshot.toMap()).languageChip,
        isNull,
      );
    });
  });

  group('chip position', () {
    // Normal pill: 330 x 64, placed inside the shadow padding.
    const pill = Rect.fromLTWH(
      OverlayDesignSpec.shadowPadding,
      OverlayDesignSpec.shadowPadding,
      330,
      64,
    );

    test('is horizontally centred on the pill', () {
      final centre = WpOverlayPainter.languageChipCentreFor(pill);
      expect(centre.dx, pill.center.dx);
    });

    test('sits on the top edge, fully inside the pill', () {
      final centre = WpOverlayPainter.languageChipCentreFor(pill);
      const half = OverlayDesignSpec.languageChipFontSize / 2;
      expect(centre.dy - half, greaterThanOrEqualTo(pill.top));
      expect(centre.dy + half, lessThan(pill.center.dy));
    });

    test('stays above the waveform bars', () {
      // Bars span 60 % of the height, centred: they start this far below the
      // top edge.
      final barsTop =
          pill.top +
          pill.height * (1 - OverlayDesignSpec.waveformHeightFactor) / 2;
      final centre = WpOverlayPainter.languageChipCentreFor(pill);
      expect(
        centre.dy + OverlayDesignSpec.languageChipFontSize / 2,
        lessThanOrEqualTo(barsTop),
      );
    });
  });
}
