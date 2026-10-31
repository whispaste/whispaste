import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/language_cycle.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';

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
}
