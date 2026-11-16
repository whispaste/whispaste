import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';

AppSettings _flags({
  bool pushToTalk = true,
  bool holdOrTap = false,
  String singleKey = '',
}) => AppSettings(
  audioInput: AudioInputSettings(pushToTalk: pushToTalk, holdOrTap: holdOrTap),
  hotkey: HotkeySettings(hotkeyDoubleTapKey: singleKey),
);

void main() {
  group('hotkeyOperationOf', () {
    test('reads the two stored flags as one choice', () {
      expect(
        hotkeyOperationOf(_flags(pushToTalk: false), supportsKeyUp: true),
        HotkeyOperation.toggle,
      );
      expect(
        hotkeyOperationOf(_flags(), supportsKeyUp: true),
        HotkeyOperation.hold,
      );
      expect(
        hotkeyOperationOf(_flags(holdOrTap: true), supportsKeyUp: true),
        HotkeyOperation.holdOrTap,
      );
    });

    test('a leftover tap-or-hold flag without push-to-talk stays toggle', () {
      expect(
        hotkeyOperationOf(
          _flags(pushToTalk: false, holdOrTap: true),
          supportsKeyUp: true,
        ),
        HotkeyOperation.toggle,
      );
    });

    test('runs as toggle without key-up', () {
      final hold = _flags(holdOrTap: true);
      expect(
        hotkeyOperationOf(hold, supportsKeyUp: false),
        HotkeyOperation.toggle,
      );
    });

    test('a single key shows hold + double tap, or the double tap alone', () {
      expect(
        hotkeyOperationOf(
          _flags(holdOrTap: true, singleKey: 'rightCtrl'),
          supportsKeyUp: true,
        ),
        HotkeyOperation.hold,
      );
      expect(
        hotkeyOperationOf(
          _flags(pushToTalk: false, singleKey: 'rightCtrl'),
          supportsKeyUp: true,
        ),
        HotkeyOperation.toggle,
      );
      expect(
        hotkeyOperationOf(_flags(singleKey: 'rightCtrl'), supportsKeyUp: false),
        HotkeyOperation.toggle,
      );
    });
  });

  test('withHotkeyOperation round-trips every choice', () {
    for (final operation in HotkeyOperation.values) {
      final written = withHotkeyOperation(_flags(), operation);
      expect(hotkeyOperationOf(written, supportsKeyUp: true), operation);
    }
  });
}
