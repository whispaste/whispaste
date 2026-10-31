/// Unit tests for the microphone priority decision (ticket, matrix 9.2).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/microphone_priority.dart';

void main() {
  group('resolveMicrophoneChoice', () {
    test('explicit selection that is present wins over the priority list', () {
      final choice = resolveMicrophoneChoice(
        selected: 'USB Headset',
        priority: const ['Studio Mic'],
        available: const ['Built-in', 'USB Headset', 'Studio Mic'],
      );
      expect(choice.label, 'USB Headset');
      expect(choice.source, MicrophoneChoiceSource.explicit);
    });

    test(
      'absent explicit device falls to the first present priority entry',
      () {
        final choice = resolveMicrophoneChoice(
          selected: 'USB Headset',
          priority: const ['USB Headset', 'Studio Mic', 'Built-in'],
          available: const ['Built-in', 'Studio Mic'],
        );
        expect(choice.label, 'Studio Mic');
        expect(choice.source, MicrophoneChoiceSource.priority);
      },
    );

    test('"Default" with a priority list picks the highest present entry', () {
      final choice = resolveMicrophoneChoice(
        selected: 'Default',
        priority: const ['Studio Mic', 'Built-in'],
        available: const ['Built-in', 'Studio Mic'],
      );
      expect(choice.label, 'Studio Mic');
      expect(choice.source, MicrophoneChoiceSource.priority);
    });

    test(
      'virtual or loopback inputs are never picked from the priority list',
      () {
        final choice = resolveMicrophoneChoice(
          selected: 'Default',
          priority: const ['Loopback Audio', 'Built-in'],
          available: const ['Loopback Audio', 'Built-in'],
        );
        expect(choice.label, 'Built-in');
      },
    );

    test('nothing present falls back to the system default', () {
      final choice = resolveMicrophoneChoice(
        selected: 'USB Headset',
        priority: const ['Studio Mic'],
        available: const ['Built-in'],
      );
      expect(choice.label, isNull);
      expect(choice.source, MicrophoneChoiceSource.systemDefault);
    });

    test(
      'empty priority and "Default" keep the old system-default behaviour',
      () {
        final choice = resolveMicrophoneChoice(
          selected: 'Default',
          priority: const [],
          available: const ['Built-in'],
        );
        expect(choice, same(MicrophoneChoice.systemDefault));
      },
    );

    test('empty and sentinel entries in the priority list are skipped', () {
      final choice = resolveMicrophoneChoice(
        selected: 'Default',
        priority: const ['', 'Default', 'Built-in'],
        available: const ['Default', 'Built-in'],
      );
      expect(choice.label, 'Built-in');
    });

    test('an explicitly selected virtual device is still honoured', () {
      final choice = resolveMicrophoneChoice(
        selected: 'Loopback Audio',
        priority: const ['Built-in'],
        available: const ['Loopback Audio', 'Built-in'],
      );
      expect(choice.label, 'Loopback Audio');
      expect(choice.source, MicrophoneChoiceSource.explicit);
    });
  });

  group('isVirtualInputLabel', () {
    test('flags common virtual and monitor inputs case-insensitively', () {
      expect(isVirtualInputLabel('Loopback Audio'), isTrue);
      expect(isVirtualInputLabel('VB-Audio Virtual Cable'), isTrue);
      expect(isVirtualInputLabel('Monitor of Built-in Audio'), isTrue);
      expect(isVirtualInputLabel('Stereo Mix (Realtek)'), isTrue);
    });

    test('does not flag ordinary microphones', () {
      expect(isVirtualInputLabel('MacBook Pro Microphone'), isFalse);
      expect(isVirtualInputLabel('Blue Yeti'), isFalse);
      expect(isVirtualInputLabel('Headset (USB Audio)'), isFalse);
    });
  });

  group('AudioInputSettings.microphonePriority', () {
    test('defaults to an empty list', () {
      expect(AudioInputSettings.defaults.microphonePriority, isEmpty);
    });

    test('round-trips through the string map in order', () {
      const original = AudioInputSettings(
        microphonePriority: ['USB Headset', 'Built-in'],
      );
      final restored = AudioInputSettings.fromMap(original.toMap());
      expect(restored.microphonePriority, ['USB Headset', 'Built-in']);
      expect(restored, original);
    });

    test('a corrupt value reads as an empty list', () {
      final restored = AudioInputSettings.fromMap(const {
        'microphone_priority': '{not json',
      });
      expect(restored.microphonePriority, isEmpty);
    });

    test('non-string entries are dropped', () {
      final restored = AudioInputSettings.fromMap(const {
        'microphone_priority': '["Built-in", 3, null]',
      });
      expect(restored.microphonePriority, ['Built-in']);
    });

    test('equality compares the list contents', () {
      const a = AudioInputSettings(microphonePriority: ['A', 'B']);
      const b = AudioInputSettings(microphonePriority: ['B', 'A']);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });
}
