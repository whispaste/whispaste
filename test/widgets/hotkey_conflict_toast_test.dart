/// UIA-SHL-05: a quick-note or snippet-picker hotkey that another app holds
/// says so on screen, with a way to its settings row. Only a new conflict
/// (a transition into the conflict state) shows the toast.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/hotkey_fallback_toast.dart';

import '../fixtures/test_helpers.dart';

class _ConflictHarness extends StatelessWidget {
  const _ConflictHarness({required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showHotkeyConflictToast(
          context: context,
          l10n: L10n.of(context),
          actionName: 'Schnellnotiz',
          onChange: onChange,
        ),
        child: const Text('fire-conflict-toast'),
      ),
    );
  }
}

void main() {
  test('only a transition into the conflict state counts as new', () {
    expect(
      isNewHotkeyConflict(null, HotkeyRegistrationStatus.conflict),
      isTrue,
    );
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.success,
        HotkeyRegistrationStatus.conflict,
      ),
      isTrue,
    );
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.conflict,
        HotkeyRegistrationStatus.conflict,
      ),
      isFalse,
    );
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.conflict,
        HotkeyRegistrationStatus.success,
      ),
      isFalse,
    );
  });

  testWidgets('names the action and offers the way to its setting', (
    tester,
  ) async {
    var changed = 0;
    await tester.pumpWidget(
      makeTestable(
        _ConflictHarness(onChange: () => changed++),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('fire-conflict-toast'));
    await tester.pumpAndSettle();

    final lDe = await L10n.delegate.load(const Locale('de'));
    expect(find.text(lDe.hotkeyConflictActive('Schnellnotiz')), findsOneWidget);

    await tester.tap(find.text(lDe.settingsChangeHotkey));
    await tester.pumpAndSettle();
    expect(changed, 1);
  });
}
