/// The coffee entry of the tray command tree: present only where the build has
/// a coffee route, placed before quit, and labelled in the app language.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';

TrayMenuState _state({required bool coffeeAvailable}) => TrayMenuState(
  isRecording: false,
  micDeviceLabels: const ['default'],
  selectedMic: 'default',
  coffeeAvailable: coffeeAvailable,
);

List<String> _ids(List<AppCommand> commands) => [
  for (final c in commands) c.id,
];

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  test('the coffee id is part of the complete tray id list', () {
    expect(TrayCommandIds.all, contains(TrayCommandIds.coffee));
  });

  test('the coffee entry appears after feedback and before quit', () {
    final commands = buildTrayCommands(
      _state(coffeeAvailable: true),
      trayLabelsFor(l10n),
    );
    final ids = _ids(commands);
    final coffee = ids.indexOf(TrayCommandIds.coffee);
    expect(coffee, greaterThan(ids.indexOf(TrayCommandIds.feedback)));
    expect(coffee, lessThan(ids.indexOf(TrayCommandIds.quit)));
  });

  test('the coffee entry carries the coffee label in the app language', () {
    final labels = trayLabelsFor(l10n);
    final commands = buildTrayCommands(_state(coffeeAvailable: true), labels);
    final entry = commands.firstWhere((c) => c.id == TrayCommandIds.coffee);
    expect(labels[entry.labelKey], l10n.coffeeButtonLabel);
  });

  test('without a coffee route the tray has no coffee entry', () {
    final commands = buildTrayCommands(
      _state(coffeeAvailable: false),
      trayLabelsFor(l10n),
    );
    expect(_ids(commands), isNot(contains(TrayCommandIds.coffee)));
  });
}
