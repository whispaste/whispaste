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
        final items = buildMicrophoneCommands(
          deviceLabels: labels,
          selectedLabel: micDefaultLabel,
          systemDefaultLabelKey: 'System Default',
        );
        expect(items, hasLength(4));
        expect(items[0].id, micMenuKey(micDefaultLabel));
        expect(items[0].labelKey, 'System Default');
        expect(items[1].isSeparator, isTrue);
        expect(items[2].labelKey, 'MacBook Pro Microphone');
        expect(items[3].labelKey, 'Razer Seiren Mini');
      },
    );

    test(
      'checks exactly the system-default entry when Default is selected',
      () {
        final items = buildMicrophoneCommands(
          deviceLabels: labels,
          selectedLabel: micDefaultLabel,
          systemDefaultLabelKey: 'System Default',
        );
        final checked = items
            .where((i) => i.checked == true)
            .map((i) => i.id)
            .toList();
        expect(checked, [micMenuKey(micDefaultLabel)]);
      },
    );

    test('checks exactly the selected device (radio behavior)', () {
      final items = buildMicrophoneCommands(
        deviceLabels: labels,
        selectedLabel: 'Razer Seiren Mini',
        systemDefaultLabelKey: 'System Default',
      );
      final checked = items
          .where((i) => i.checked == true)
          .map((i) => i.labelKey)
          .toList();
      expect(checked, ['Razer Seiren Mini']);
      expect(items[0].checked, isFalse);
    });

    test(
      'appends a selected-but-unplugged device so the checkmark survives',
      () {
        final items = buildMicrophoneCommands(
          deviceLabels: const ['Default', 'MacBook Pro Microphone'],
          selectedLabel: 'Razer Seiren Mini',
          systemDefaultLabelKey: 'System Default',
        );
        expect(items.last.labelKey, 'Razer Seiren Mini');
        expect(items.last.checked, isTrue);
      },
    );

    test('omits the separator when no real devices exist', () {
      final items = buildMicrophoneCommands(
        deviceLabels: const ['Default'],
        selectedLabel: micDefaultLabel,
        systemDefaultLabelKey: 'System Default',
      );
      expect(items, hasLength(1));
      expect(items.single.checked, isTrue);
    });

    test('filters empty labels from the enumeration', () {
      final items = buildMicrophoneCommands(
        deviceLabels: const ['Default', '', 'MacBook Pro Microphone'],
        selectedLabel: micDefaultLabel,
        systemDefaultLabelKey: 'System Default',
      );
      expect(
        items.where((i) => !i.isSeparator).map((i) => i.labelKey),
        isNot(contains('')),
      );
    });
  });
}
