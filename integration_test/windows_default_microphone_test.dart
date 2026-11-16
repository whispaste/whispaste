import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_routing_service.dart';
import 'package:whispaste/services/microphone_priority.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows default endpoint matches the recording plugin', (
    _,
  ) async {
    final routing = AudioRoutingService();
    final recorder = AudioRecorder();
    try {
      expect(routing.isSupported, isFalse);
      final id = await routing.getDefaultInputDevice();
      expect(
        id,
        isNotNull,
        reason: 'This hardware smoke needs a capture device',
      );
      final devices = await recorder.listInputDevices();
      final label = await routing.defaultInputLabel(devices);
      expect(label, isNotNull);
      expect(devices.singleWhere((d) => d.id == id).label, label);
      final alternative = suggestAlternativeMicrophone(
        silent: label!,
        available: devices.map((d) => d.label).toList(),
      );
      expect(alternative, isNot(label));
      // ignore: avoid_print
      print('DEFAULT-MIC endpoint=$id label=$label alternative=$alternative');
    } finally {
      await recorder.dispose();
    }
    // Requires the Windows capture-endpoint API and a real microphone.
  }, skip: !Platform.isWindows);
}
