import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/tray_mic_menu.dart';

void main() {
  group('micMenuKey / micLabelFromMenuKey', () {
    test('round-trips device labels, including ones containing colons', () {
      const label = 'Razer Seiren Mini: USB';
      expect(micLabelFromMenuKey(micMenuKey(label)), label);
    });

    test('round-trips the default sentinel', () {
      expect(micLabelFromMenuKey(micMenuKey(micDefaultLabel)), micDefaultLabel);
    });

    test('returns null for keys outside the mic namespace', () {
      expect(micLabelFromMenuKey('toggle_recording'), isNull);
      expect(micLabelFromMenuKey('quit'), isNull);
    });
  });

  group('buildMicrophoneMenuItems', () {
    const labels = ['Default', 'MacBook Pro Microphone', 'Razer Seiren Mini'];

    test(
      'puts the system-default entry first, then separator, then devices',
      () {
        final items = buildMicrophoneMenuItems(
          deviceLabels: labels,
          selectedLabel: micDefaultLabel,
          systemDefaultLabel: 'System Default',
        );
        expect(items, hasLength(4));
        expect(items[0].key, micMenuKey(micDefaultLabel));
        expect(items[0].label, 'System Default');
        expect(items[1].type, 'separator');
        expect(items[2].label, 'MacBook Pro Microphone');
        expect(items[3].label, 'Razer Seiren Mini');
      },
    );

    test(
      'checks exactly the system-default entry when Default is selected',
      () {
        final items = buildMicrophoneMenuItems(
          deviceLabels: labels,
          selectedLabel: micDefaultLabel,
          systemDefaultLabel: 'System Default',
        );
        final checked = items
            .where((i) => i.checked == true)
            .map((i) => i.key)
            .toList();
        expect(checked, [micMenuKey(micDefaultLabel)]);
      },
    );

    test('checks exactly the selected device (radio behavior)', () {
      final items = buildMicrophoneMenuItems(
        deviceLabels: labels,
        selectedLabel: 'Razer Seiren Mini',
        systemDefaultLabel: 'System Default',
      );
      final checked = items
          .where((i) => i.checked == true)
          .map((i) => i.label)
          .toList();
      expect(checked, ['Razer Seiren Mini']);
      expect(items[0].checked, isFalse);
    });

    test(
      'appends a selected-but-unplugged device so the checkmark survives',
      () {
        final items = buildMicrophoneMenuItems(
          deviceLabels: const ['Default', 'MacBook Pro Microphone'],
          selectedLabel: 'Razer Seiren Mini',
          systemDefaultLabel: 'System Default',
        );
        expect(items.last.label, 'Razer Seiren Mini');
        expect(items.last.checked, isTrue);
      },
    );

    test('omits the separator when no real devices exist', () {
      final items = buildMicrophoneMenuItems(
        deviceLabels: const ['Default'],
        selectedLabel: micDefaultLabel,
        systemDefaultLabel: 'System Default',
      );
      expect(items, hasLength(1));
      expect(items.single.checked, isTrue);
    });

    test('filters empty labels from the enumeration', () {
      final items = buildMicrophoneMenuItems(
        deviceLabels: const ['Default', '', 'MacBook Pro Microphone'],
        selectedLabel: micDefaultLabel,
        systemDefaultLabel: 'System Default',
      );
      expect(items.map((i) => i.label), isNot(contains('')));
    });
  });
}
