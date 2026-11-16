/// Routing of microphone hints during a recording (#984): with the overlay
/// visible they show only there, an OS notification goes out only without an
/// overlay, and hints that are not terminal never bounce the dock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/floating_overlay/pill_hint.dart';
import 'package:whispaste/services/system_attention_service.dart';

void main() {
  group('overlayShowsHints', () {
    test('floating overlay shows hints', () {
      const s = AppSettings(overlay: OverlaySettings(overlayMode: 'floating'));
      expect(overlayShowsHints(s), isTrue);
    });

    test('overlay off sends hints elsewhere', () {
      const s = AppSettings(overlay: OverlaySettings(overlayMode: 'off'));
      expect(overlayShowsHints(s), isFalse);
    });
  });

  group('attentionWantsDockBounce', () {
    test('a silent microphone never bounces the dock', () {
      expect(attentionWantsDockBounce(AttentionKind.silentMicrophone), isFalse);
    });

    test('a blocked paste still asks for attention', () {
      expect(
        attentionWantsDockBounce(AttentionKind.pasteBlockedPermission),
        isTrue,
      );
    });
  });
}
