/// Overlay pill sizing tests. Anchor resolution and screen clamping now live
/// natively per platform (see lib/services/floating_overlay/overlay_positioning.dart
/// doc comment) and are covered by their own native test setups, not here.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/overlay_positioning.dart';

void main() {
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
}
