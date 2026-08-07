/// Unit tests for the shared microphone-selection logic used by both the
/// tray submenu and the status-bar chip.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:whispaste/services/audio_routing_service.dart';
import 'package:whispaste/services/microphone_selection_service.dart';

class _FakeAudioRouting extends AudioRoutingService {
  _FakeAudioRouting({required this.supported, this.devices = const []});

  final bool supported;
  final List<InputDevice> devices;
  final listCalls = <void>[];
  final setCalls = <String>[];
  bool setResult = true;

  @override
  bool get isSupported => supported;

  @override
  Future<List<InputDevice>> listInputDevices() async {
    listCalls.add(null);
    return devices;
  }

  @override
  Future<bool> setDefaultInputDevice(String uid) async {
    setCalls.add(uid);
    return setResult;
  }
}

void main() {
  const coreAudioDevices = [
    InputDevice(id: 'uid-builtin', label: 'MacBook Pro Microphone'),
    InputDevice(id: 'uid-razer', label: 'Razer Seiren Mini'),
  ];

  group('MicrophoneSelectionService.select', () {
    test('persists the label through the injected persist callback', () async {
      final persisted = <String>[];
      final routing = _FakeAudioRouting(supported: false);
      final service = MicrophoneSelectionService(
        persistLabel: (label) async => persisted.add(label),
        audioRouting: routing,
      );

      await service.select('Razer Seiren Mini');

      expect(persisted, ['Razer Seiren Mini']);
    });

    test('selecting the system default never touches routing', () async {
      final routing = _FakeAudioRouting(
        supported: true,
        devices: coreAudioDevices,
      );
      final service = MicrophoneSelectionService(
        persistLabel: (_) async {},
        audioRouting: routing,
      );

      await service.select(micDefaultLabel);

      expect(routing.listCalls, isEmpty);
      expect(routing.setCalls, isEmpty);
    });

    test('switches the system default input via the CoreAudio uid '
        'matching the label', () async {
      final routing = _FakeAudioRouting(
        supported: true,
        devices: coreAudioDevices,
      );
      final service = MicrophoneSelectionService(
        persistLabel: (_) async {},
        audioRouting: routing,
      );

      await service.select('Razer Seiren Mini');

      expect(routing.setCalls, ['uid-razer']);
    });

    test('leaves routing untouched when the label is missing from the '
        'CoreAudio enumeration', () async {
      final routing = _FakeAudioRouting(
        supported: true,
        devices: coreAudioDevices,
      );
      final service = MicrophoneSelectionService(
        persistLabel: (_) async {},
        audioRouting: routing,
      );

      await service.select('Unplugged USB Mic');

      expect(routing.listCalls, hasLength(1));
      expect(routing.setCalls, isEmpty);
    });

    test('skips routing entirely on unsupported platforms', () async {
      final routing = _FakeAudioRouting(
        supported: false,
        devices: coreAudioDevices,
      );
      final service = MicrophoneSelectionService(
        persistLabel: (_) async {},
        audioRouting: routing,
      );

      await service.select('Razer Seiren Mini');

      expect(routing.listCalls, isEmpty);
      expect(routing.setCalls, isEmpty);
    });

    test('still applies routing when persisting fails', () async {
      final routing = _FakeAudioRouting(
        supported: true,
        devices: coreAudioDevices,
      );
      final service = MicrophoneSelectionService(
        persistLabel: (_) async => throw Exception('db down'),
        audioRouting: routing,
      );

      await service.select('Razer Seiren Mini');

      expect(routing.setCalls, ['uid-razer']);
    });
  });

  group('buildMicrophoneOptions', () {
    test('puts the system-default sentinel first, then the devices', () {
      final options = buildMicrophoneOptions(
        deviceLabels: const [
          'Default',
          'MacBook Pro Microphone',
          'Razer Seiren Mini',
        ],
        selectedLabel: micDefaultLabel,
      );
      expect(options, [
        micDefaultLabel,
        'MacBook Pro Microphone',
        'Razer Seiren Mini',
      ]);
    });

    test('appends a selected-but-unplugged device at the end', () {
      final options = buildMicrophoneOptions(
        deviceLabels: const ['Default', 'MacBook Pro Microphone'],
        selectedLabel: 'Razer Seiren Mini',
      );
      expect(options.last, 'Razer Seiren Mini');
    });

    test('filters empty labels from the enumeration', () {
      final options = buildMicrophoneOptions(
        deviceLabels: const ['Default', '', 'MacBook Pro Microphone'],
        selectedLabel: micDefaultLabel,
      );
      expect(options, isNot(contains('')));
    });

    test('yields only the sentinel when no real devices exist', () {
      final options = buildMicrophoneOptions(
        deviceLabels: const ['Default'],
        selectedLabel: micDefaultLabel,
      );
      expect(options, [micDefaultLabel]);
    });
  });
}
