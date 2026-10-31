/// Category gating of native attention notifications (ticket, matrix 9.6).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/system_attention_service.dart';

const _pasteKinds = [
  AttentionKind.pasteBlockedPermission,
  AttentionKind.pasteBlockedNoTarget,
  AttentionKind.pasteFailedUnknown,
  AttentionKind.pasteBlockedElevation,
  AttentionKind.pasteReceiptRefused,
];

void main() {
  group('attentionNotificationAllowed', () {
    test('master switch off suppresses every category', () {
      const settings = InterfaceSettings(showNotifications: false);
      for (final kind in AttentionKind.values) {
        expect(
          attentionNotificationAllowed(kind, settings),
          isFalse,
          reason: '$kind',
        );
      }
    });

    test('paste problems follow notifyPasteProblems only', () {
      const off = InterfaceSettings(notifyPasteProblems: false);
      const on = InterfaceSettings(notifyPasteProblems: true);
      for (final kind in _pasteKinds) {
        expect(
          attentionNotificationAllowed(kind, off),
          isFalse,
          reason: '$kind',
        );
        expect(attentionNotificationAllowed(kind, on), isTrue, reason: '$kind');
      }
    });

    test('Smart Mode fallback follows notifySmartModeFallback only', () {
      const off = InterfaceSettings(notifySmartModeFallback: false);
      expect(
        attentionNotificationAllowed(AttentionKind.smartModeFallback, off),
        isFalse,
      );
      // Turning the Smart Mode category off must not silence paste problems.
      expect(
        attentionNotificationAllowed(AttentionKind.pasteFailedUnknown, off),
        isTrue,
      );
    });

    test('silent microphone follows notifyMicrophoneProblems only', () {
      const off = InterfaceSettings(notifyMicrophoneProblems: false);
      expect(
        attentionNotificationAllowed(AttentionKind.silentMicrophone, off),
        isFalse,
      );
      expect(
        attentionNotificationAllowed(AttentionKind.pasteFailedUnknown, off),
        isTrue,
      );
    });

    test('a taken hotkey follows the master switch only', () {
      // No category switch: without the hotkey nothing works at all.
      const categoriesOff = InterfaceSettings(
        notifyPasteProblems: false,
        notifySmartModeFallback: false,
        notifyMicrophoneProblems: false,
      );
      expect(
        attentionNotificationAllowed(
          AttentionKind.hotkeyFallback,
          categoriesOff,
        ),
        isTrue,
      );
    });

    test('defaults keep every category on, as before', () {
      const defaults = InterfaceSettings();
      for (final kind in AttentionKind.values) {
        expect(
          attentionNotificationAllowed(kind, defaults),
          isTrue,
          reason: '$kind',
        );
      }
    });
  });

  group('InterfaceSettings category switches', () {
    test('round-trip through the string map', () {
      const original = InterfaceSettings(
        notifyPasteProblems: false,
        notifySmartModeFallback: false,
      );
      final restored = InterfaceSettings.fromMap(original.toMap());
      expect(restored.notifyPasteProblems, isFalse);
      expect(restored.notifySmartModeFallback, isFalse);
      expect(restored, original);
    });

    test('missing keys default to on', () {
      final restored = InterfaceSettings.fromMap(const {});
      expect(restored.notifyPasteProblems, isTrue);
      expect(restored.notifySmartModeFallback, isTrue);
    });
  });
}
