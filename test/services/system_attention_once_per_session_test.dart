/// GR-028 (2026-10-25): the native OS notice for a refused paste receipt
/// appears at most once per app session. Other notices are not limited here.
///
/// The slot is claimed before the delivery awaits anything, so two overlapping
/// deliveries cannot both pass. A claim that was not delivered (no notification
/// server yet, or the OS call failed) is released, so the next refused receipt
/// can still show the notice.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/system_attention_service.dart';

void main() {
  group('OS notice once per session (GR-028)', () {
    test('pasteReceiptRefused is shown once, then refused', () {
      final gate = SessionNoticeGate();
      const kind = AttentionKind.pasteReceiptRefused;

      expect(gate.claimOsNotice(kind), isTrue);
      expect(gate.claimOsNotice(kind), isFalse);
      expect(gate.claimOsNotice(kind), isFalse);
    });

    test('an overlapping second delivery is refused while the first is in '
        'flight', () {
      final gate = SessionNoticeGate();
      const kind = AttentionKind.pasteReceiptRefused;

      // Two refusals arrive before the first one has finished its awaits.
      expect(gate.claimOsNotice(kind), isTrue);
      expect(gate.claimOsNotice(kind), isFalse);
    });

    test('a skipped or failed delivery releases the session slot', () {
      final gate = SessionNoticeGate();
      const kind = AttentionKind.pasteReceiptRefused;

      // First refusal: no notification server, the claim is given back.
      expect(gate.claimOsNotice(kind), isTrue);
      gate.releaseOsNotice(kind);
      // Second refusal, server now running: the slot is open again.
      expect(gate.claimOsNotice(kind), isTrue);
      expect(gate.claimOsNotice(kind), isFalse);
    });

    test('other kinds are not limited by the gate', () {
      final gate = SessionNoticeGate();

      for (var i = 0; i < 3; i++) {
        expect(gate.claimOsNotice(AttentionKind.pasteFailedUnknown), isTrue);
        expect(gate.claimOsNotice(AttentionKind.pasteBlockedNoTarget), isTrue);
      }
    });

    test('a new gate (new session) shows the receipt notice again', () {
      const kind = AttentionKind.pasteReceiptRefused;
      expect(SessionNoticeGate().claimOsNotice(kind), isTrue);
      expect(SessionNoticeGate().claimOsNotice(kind), isTrue);
    });
  });
}
