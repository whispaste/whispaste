/// Unit tests for the microphone priority decision (ticket, matrix 9.2).
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/microphone_priority.dart';

void main() {
  _rankingTests();
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

void _rankingTests() {
  group('classifyMicrophone', () {
    test('reads the kind from the label', () {
      expect(
        classifyMicrophone('MacBook Pro Microphone'),
        MicrophoneKind.builtIn,
      );
      expect(
        classifyMicrophone('Mikrofonarray (Realtek)'),
        MicrophoneKind.builtIn,
      );
      expect(
        classifyMicrophone('Built-in Audio Analog Stereo'),
        MicrophoneKind.builtIn,
      );
      expect(classifyMicrophone('AirPods Pro'), MicrophoneKind.bluetooth);
      expect(
        classifyMicrophone('Headset (WH-1000XM5 Hands-Free)'),
        MicrophoneKind.bluetooth,
      );
      expect(
        classifyMicrophone("Silvio's iPhone Microphone"),
        MicrophoneKind.phone,
      );
      expect(classifyMicrophone('BlackHole 2ch'), MicrophoneKind.virtual);
      expect(
        classifyMicrophone('Monitor of Built-in Audio'),
        MicrophoneKind.virtual,
      );
      expect(classifyMicrophone('Blue Yeti'), MicrophoneKind.external);
      expect(
        classifyMicrophone('Headset (USB Audio)'),
        MicrophoneKind.external,
      );
      expect(classifyMicrophone('WH-1000XM5'), MicrophoneKind.unknown);
    });
  });

  group('rankMicrophones', () {
    const all = [
      'MacBook Pro Microphone',
      'AirPods Pro',
      "Silvio's iPhone Microphone",
      'BlackHole 2ch',
      'Blue Yeti',
    ];

    test('cable, built-in, bluetooth last; phone and virtual excluded', () {
      expect(rankMicrophones(all), [
        'Blue Yeti',
        'MacBook Pro Microphone',
        'AirPods Pro',
      ]);
    });

    test('unnamed kinds come after built-in and before bluetooth', () {
      expect(
        rankMicrophones(const [
          'AirPods Pro',
          'WH-1000XM5',
          'MacBook Pro Microphone',
          'Blue Yeti',
        ]),
        ['Blue Yeti', 'MacBook Pro Microphone', 'WH-1000XM5', 'AirPods Pro'],
      );
    });

    test('ignores the default sentinel, empty and duplicate labels', () {
      expect(rankMicrophones(const ['Default', '', 'Blue Yeti', 'Blue Yeti']), [
        'Blue Yeti',
      ]);
    });
  });

  group('suggestAlternativeMicrophone', () {
    test('offers the best other device when the built-in one is silent', () {
      expect(
        suggestAlternativeMicrophone(
          silent: 'MacBook Pro Microphone',
          available: const ['MacBook Pro Microphone', 'Blue Yeti'],
        ),
        'Blue Yeti',
      );
    });

    test('lid closed: external device is offered, never the silent one', () {
      expect(
        suggestAlternativeMicrophone(
          silent: 'Blue Yeti',
          available: const ['Blue Yeti', 'Built-in Microphone'],
        ),
        'Built-in Microphone',
      );
    });

    test('unknown silent device (system default): no suggestion', () {
      expect(
        suggestAlternativeMicrophone(
          silent: 'Default',
          available: const ['Blue Yeti', 'Built-in Microphone'],
        ),
        isNull,
      );
    });

    test('null when nothing else qualifies', () {
      expect(
        suggestAlternativeMicrophone(
          silent: 'Blue Yeti',
          available: const ['Blue Yeti', "Silvio's iPhone", 'BlackHole 2ch'],
        ),
        isNull,
      );
    });

    test('bluetooth is offered when nothing better is left', () {
      expect(
        suggestAlternativeMicrophone(
          silent: 'Blue Yeti',
          available: const ['Blue Yeti', 'AirPods Pro'],
        ),
        'AirPods Pro',
      );
    });
  });

  group('suggestWithinGrace', () {
    test('returns an answer that arrives inside the grace period', () {
      fakeAsync((async) {
        final lookup = Completer<String?>();
        String? result = 'unset';
        suggestWithinGrace(() => lookup.future).then((v) => result = v);
        async.elapse(const Duration(milliseconds: 250));
        expect(result, 'unset');
        lookup.complete('Blue Yeti');
        async.flushMicrotasks();
        expect(result, 'Blue Yeti');
      });
    });

    test('gives up on a late answer after the grace period', () {
      fakeAsync((async) {
        final lookup = Completer<String?>();
        String? result = 'unset';
        suggestWithinGrace(() => lookup.future).then((v) => result = v);
        async.elapse(const Duration(milliseconds: 299));
        expect(result, 'unset');
        async.elapse(const Duration(milliseconds: 1));
        expect(result, isNull);
        lookup.complete('Blue Yeti');
        async.flushMicrotasks();
        expect(result, isNull, reason: 'a late result cannot replace timeout');
      });
    });

    test('a failing lookup yields no suggestion', () {
      fakeAsync((async) {
        String? result = 'unset';
        suggestWithinGrace(
          () => Future<String?>.error(Exception('boom')),
        ).then((v) => result = v);
        async.flushMicrotasks();
        expect(result, isNull);
      });
    });
  });

  group('closed lid (#846)', () {
    const builtIn = 'MacBook Air-Mikrofon';
    const razer = 'Razer Seiren';

    test('the built-in microphone is neither forced nor suggested', () {
      final choice = resolveMicrophoneChoice(
        selected: builtIn,
        priority: const [],
        available: const [builtIn, razer],
        lidClosed: true,
      );
      expect(choice.label, isNull);
      expect(choice.source, MicrophoneChoiceSource.lidClosedFallback);
      expect(rankMicrophones(const [builtIn, razer], lidClosed: true), [razer]);
      expect(
        suggestAlternativeMicrophone(
          silent: razer,
          available: const [builtIn, razer],
          lidClosed: true,
        ),
        isNull,
      );
    });

    test('an open lid keeps the old behaviour', () {
      final choice = resolveMicrophoneChoice(
        selected: builtIn,
        priority: const [],
        available: const [builtIn, razer],
      );
      expect(choice.label, builtIn);
      expect(
        suggestAlternativeMicrophone(
          silent: razer,
          available: const [builtIn, razer],
        ),
        builtIn,
      );
    });

    test('other explicit devices and the priority list skip the built-in', () {
      expect(
        resolveMicrophoneChoice(
          selected: razer,
          priority: const [],
          available: const [builtIn, razer],
          lidClosed: true,
        ).label,
        razer,
      );
      expect(
        resolveMicrophoneChoice(
          selected: 'Default',
          priority: const [builtIn, razer],
          available: const [builtIn, razer],
          lidClosed: true,
        ).label,
        razer,
      );
    });
  });

  group('real device names (#931)', () {
    // Collected 2026-11-09 on real hardware (macOS, hp840 Windows 11, both
    // German system language) or taken from vendor/driver strings (marked).
    const lab = <String, MicrophoneKind>{
      'MacBook Air-Mikrofon': MicrophoneKind.builtIn,
      'Razer Seiren V3 Mini': MicrophoneKind.external,
      'Mikrofon von „iPhone von Test“': MicrophoneKind.phone,
      'Mikrofonarray (Intel® Smart Sound Technologie für digitale Mikrofone)':
          MicrophoneKind.builtIn,
      'Digitale Audioschnittstelle (USB Audio)': MicrophoneKind.external,
      'Monitor of Dummy Output': MicrophoneKind.virtual,
      'Lab Mic': MicrophoneKind.unknown,
      'CABLE Output (VB-Audio Virtual Cable)': MicrophoneKind.virtual,
    };
    // Other app languages: Windows "Microphone Array" / "Stereo Mix" names.
    const vendorStrings = <String, MicrophoneKind>{
      'Matrice de microphones (Realtek Audio)': MicrophoneKind.builtIn,
      'Matriz de micrófonos (Realtek Audio)': MicrophoneKind.builtIn,
      'Array di microfoni (Realtek Audio)': MicrophoneKind.builtIn,
      'Массив микрофонов (Realtek Audio)': MicrophoneKind.builtIn,
      '麦克风阵列 (Realtek Audio)': MicrophoneKind.builtIn,
      'Stereomix (Realtek Audio)': MicrophoneKind.virtual,
      'Mixage stéréo (Realtek Audio)': MicrophoneKind.virtual,
      'Mains libres (Bluetooth)': MicrophoneKind.bluetooth,
    };

    test('classifies lab names', () {
      lab.forEach((name, kind) {
        expect(classifyMicrophone(name), kind, reason: name);
      });
    });

    test('classifies names of other system languages', () {
      vendorStrings.forEach((name, kind) {
        expect(classifyMicrophone(name), kind, reason: name);
      });
    });
  });
}
