// The side panel offers dragging a row out only where the native host starts
// an OS drag (macOS, Windows, Linux); elsewhere the gesture would drop
// nothing.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_render_channel.dart';

void main() {
  test('the desktop hosts offer the drag-out', () {
    expect(sidePanelOffersDragOut(TargetPlatform.macOS), isTrue);
    expect(sidePanelOffersDragOut(TargetPlatform.windows), isTrue);
    expect(sidePanelOffersDragOut(TargetPlatform.linux), isTrue);
    expect(sidePanelOffersDragOut(TargetPlatform.android), isFalse);
  });

  test('the render engine wires the drag through that switch', () {
    final source = File(
      'lib/side_panel_render_entrypoint.dart',
    ).readAsStringSync();
    expect(source, contains('sidePanelOffersDragOut(defaultTargetPlatform)'));
  });
}
