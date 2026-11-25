import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/floating_overlay_render_entrypoint.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice_layout.dart';
import 'package:flutter/widgets.dart';

FloatingOverlaySnapshot _snap({
  OverlaySizeVariant size = OverlaySizeVariant.normal,
  bool showCancel = true,
  bool visible = true,
}) => FloatingOverlaySnapshot(
  visible: visible,
  state: OverlayVisualState.recording,
  label: '',
  size: size,
  appearance: OverlayAppearance(showCancel: showCancel),
);

void main() {
  // The X centre as the painter derives it: pill.left + padH + closeOffset.
  Offset xCenter(OverlaySizeVariant v) {
    final spec = OverlayDesignSpec.sizeFor(v);
    final layout = OverlayDesignSpec.layoutFor(v);
    return Offset(
      OverlayDesignSpec.shadowPadding + layout.padH + layout.closeOffset,
      OverlayDesignSpec.shadowPadding + spec.height / 2,
    );
  }

  group('isCloseTap', () {
    test('a tap on the X centre cancels, on every size with an X', () {
      for (final v in [OverlaySizeVariant.normal, OverlaySizeVariant.compact]) {
        expect(isCloseTap(_snap(size: v), xCenter(v)), isTrue, reason: '$v');
      }
    });

    test('the hit area is at least 32 x 32 around the X', () {
      final c = xCenter(OverlaySizeVariant.compact);
      final s = _snap(size: OverlaySizeVariant.compact);
      expect(isCloseTap(s, c + const Offset(15, 15)), isTrue);
      expect(isCloseTap(s, c + const Offset(-15, -15)), isTrue);
    });

    test('a tap on the pill body or far from the X toggles instead', () {
      final s = _snap();
      final size = OverlayDesignSpec.windowSizeFor(OverlaySizeVariant.normal);
      expect(isCloseTap(s, Offset(size.width / 2, size.height / 2)), isFalse);
      expect(isCloseTap(s, Offset(size.width - 20, size.height / 2)), isFalse);
    });

    test('no X: hidden look, disabled cancel, mini and nano stay toggles', () {
      final c = xCenter(OverlaySizeVariant.normal);
      expect(isCloseTap(_snap(showCancel: false), c), isFalse);
      expect(isCloseTap(_snap(visible: false), c), isFalse);
      for (final v in [OverlaySizeVariant.mini, OverlaySizeVariant.nano]) {
        expect(isCloseTap(_snap(size: v), xCenter(v)), isFalse, reason: '$v');
      }
    });
  });

  group('isNoticeCardTap', () {
    const notice = OverlayNotice(
      kind: OverlayNoticeKind.message,
      tone: OverlayNoticeTone.hint,
      title: 'Draft',
      body: 'Hello',
      actions: [],
    );
    FloatingOverlaySnapshot card({bool visible = true}) =>
        FloatingOverlaySnapshot(
          visible: visible,
          state: OverlayVisualState.transcribing,
          label: '',
          notice: notice,
        );
    const scaler = TextScaler.noScaling;
    final height = overlayNoticeCardHeight(notice, scaler);
    const pad = OverlayDesignSpec.shadowPadding;

    test('a click on the card is the card\'s, not a body click', () {
      expect(
        isNoticeCardTap(card(), const Offset(pad + 1, pad + 1), scaler),
        isTrue,
      );
      expect(
        isNoticeCardTap(card(), Offset(pad + 100, pad + height - 1), scaler),
        isTrue,
      );
    });

    test('the shadow margin, a hidden card and the pill stay body clicks', () {
      expect(isNoticeCardTap(card(), const Offset(2, 2), scaler), isFalse);
      expect(
        isNoticeCardTap(card(), Offset(pad + 100, pad + height + 2), scaler),
        isFalse,
      );
      expect(
        isNoticeCardTap(card(visible: false), const Offset(50, 50), scaler),
        isFalse,
      );
      expect(isNoticeCardTap(_snap(), const Offset(50, 40), scaler), isFalse);
    });
  });
}
