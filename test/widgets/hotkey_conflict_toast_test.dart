/// UIA-SHL-05: a quick-note or snippet-picker hotkey that another app holds
/// says so on screen, with a way to its settings row. Only a new conflict
/// (a transition into the conflict state) shows the notice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/hotkey_fallback_toast.dart';

import '../fixtures/test_helpers.dart';

class _ConflictHarness extends StatelessWidget {
  const _ConflictHarness({
    required this.onChange,
    this.status = HotkeyRegistrationStatus.conflict,
  });

  final VoidCallback onChange;
  final HotkeyRegistrationStatus status;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showHotkeyConflictToast(
          context: context,
          l10n: L10n.of(context),
          actionName: 'Schnellnotiz',
          status: status,
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

  test('an unknown key is a new failure, and the change between both too', () {
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.success,
        HotkeyRegistrationStatus.unknownKey,
      ),
      isTrue,
    );
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.conflict,
        HotkeyRegistrationStatus.unknownKey,
      ),
      isTrue,
    );
    expect(
      isNewHotkeyConflict(
        HotkeyRegistrationStatus.unknownKey,
        HotkeyRegistrationStatus.unknownKey,
      ),
      isFalse,
    );
  });

  testWidgets('an unknown key does not blame another app', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        _ConflictHarness(
          onChange: () {},
          status: HotkeyRegistrationStatus.unknownKey,
        ),
        locale: const Locale('de'),
        noticeBar: true,
      ),
    );

    await tester.tap(find.text('fire-conflict-toast'));
    await tester.pumpAndSettle();

    final lDe = await L10n.delegate.load(const Locale('de'));
    expect(find.text(lDe.hotkeyConflictActive('Schnellnotiz')), findsNothing);
    expect(
      find.text(lDe.hotkeyUnknownKeyActive('Schnellnotiz')),
      findsOneWidget,
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
        noticeBar: true,
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
