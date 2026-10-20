import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

/// The native pill and button windows reserve only
/// [OverlayDesignSpec.shadowPadding] around the painted shape. A Gaussian
/// shadow stays visible up to about three sigma, so a wider blur ends in a
/// hard edge at the window border.
void main() {
  const offset = OverlayDesignSpec.shadowOffset;
  final shift = offset.dx.abs() > offset.dy.abs()
      ? offset.dx.abs()
      : offset.dy.abs();

  test('soft shadow fades out inside the window padding', () {
    expect(
      3 * OverlayDesignSpec.shadowBlur + shift,
      lessThanOrEqualTo(OverlayDesignSpec.shadowPadding),
    );
  });

  test('contact shadow fades out inside the window padding', () {
    const contact = OverlayDesignSpec.contactShadowOffset;
    expect(
      3 * OverlayDesignSpec.contactShadowBlur + contact.dy.abs(),
      lessThanOrEqualTo(OverlayDesignSpec.shadowPadding),
    );
  });

  test('at full wobble the shadow edge is at most faintly visible', () {
    // The liquid outline bulges outward by up to both amplitudes. Two sigma
    // leaves under 3 % of the 20 % shadow ink, below one 8-bit step.
    const wobble =
        OverlayDesignSpec.liquidWobbleBaseAmplitudePx +
        OverlayDesignSpec.liquidWobbleAudioAmplitudePx;
    expect(
      2 * OverlayDesignSpec.shadowBlur + shift + wobble,
      // The pill is painted 1 px inside its box (overlay_painter deflate).
      lessThanOrEqualTo(OverlayDesignSpec.shadowPadding + 1),
    );
  });
}
