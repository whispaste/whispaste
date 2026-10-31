import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard: every user-assignable hotkey action of `HotkeyService` is listed in
/// the collision bindings of `hotkey_flow.dart`. A new hotkey missing there
/// could be given a combination another action already holds, on every
/// platform alike. Session keys that only exist while a snippet or a
/// dictation runs are not user-assignable.
void main() {
  test('every assignable hotkey action takes part in collision checks', () {
    final service = File('lib/services/hotkey_service.dart').readAsStringSync();
    final flow = File(
      'lib/features/settings/hotkey_flow.dart',
    ).readAsStringSync();
    const sessionOnly = {'snippetAdvance', 'snippetCancel', 'cancelDictation'};
    final actions = RegExp(r"static const _\w+ActionId = '(\w+)';")
        .allMatches(service)
        .map((m) => m.group(1)!)
        .where((id) => !sessionOnly.contains(id))
        .toSet();
    final bound = RegExp(
      r"actionId: '(\w+)'",
    ).allMatches(flow).map((m) => m.group(1)!).toSet();

    expect(actions, contains('repaste'));
    expect(actions.difference(bound), isEmpty);
  });
}
