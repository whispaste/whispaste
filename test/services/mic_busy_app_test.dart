import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/mic_busy_app.dart';

const _root =
    r'HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone';

String _block(String name, String stop) =>
    '\r\n$_root\\$name\r\n'
    '    LastUsedTimeStart    REG_QWORD    0x1dc0000000000000\r\n'
    '    LastUsedTimeStop    REG_QWORD    $stop\r\n';

void main() {
  group('parseMicBusyApp', () {
    test('names the desktop app whose use has not stopped', () {
      final out =
          '$_root\r\n    Value    REG_SZ    Allow\r\n'
          '${_block(r'NonPackaged\C:#Tools#old.exe', '0x1dc1111111111111')}'
          '${_block(r'NonPackaged\C:#Program Files#Zoom#zoom.exe', '0x0')}';
      expect(parseMicBusyApp(out), 'zoom');
    });

    test('names a store app by its short name', () {
      final out = _block('Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe', '0x0');
      expect(parseMicBusyApp(out), 'WindowsSoundRecorder');
    });

    test('is null when nothing holds the microphone', () {
      final out = _block(r'NonPackaged\C:#Tools#old.exe', '0x1dc1111111111111');
      expect(parseMicBusyApp(out), isNull);
      expect(parseMicBusyApp(''), isNull);
    });

    test('never names WhisPaste itself', () {
      final out = _block(r'NonPackaged\C:#Apps#whispaste.exe', '0x0');
      expect(parseMicBusyApp(out), isNull);
    });
  });
}
