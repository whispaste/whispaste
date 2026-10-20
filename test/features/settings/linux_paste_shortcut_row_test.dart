/// V1 Wayland: the Linux "always Ctrl+Shift+V" switch and its status line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show BehaviorSettings;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/linux_paste_shortcut_row.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';

import '../../fixtures/test_helpers.dart';

Widget _row({required bool on, required LinuxFocusStatus status}) =>
    makeTestable(
      Consumer(
        builder: (context, ref, _) => SingleChildScrollView(
          child: LinuxPasteShortcutRow(
            settings: AppSettings(
              behavior: BehaviorSettings(linuxAlwaysShiftPaste: on),
            ),
            status: status,
          ),
        ),
      ),
    );

void main() {
  testWidgets('the switch shows the stored value and carries its id', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _row(on: true, status: LinuxFocusStatus.available),
      );
      await tester.pumpAndSettle();
      final toggle = tester.widget<Switch>(
        find.byKey(const Key('text-linux-always-shift-paste-toggle')),
      );
      expect(toggle.value, isTrue);
      expect(
        find.bySemanticsIdentifier('text-linux-always-shift-paste-toggle'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('text-linux-target-status'),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  for (final status in LinuxFocusStatus.values) {
    testWidgets('the status line names the ${status.name} case', (
      tester,
    ) async {
      await tester.pumpWidget(_row(on: false, status: status));
      await tester.pumpAndSettle();
      final l10n = L10n.of(tester.element(find.byType(LinuxPasteShortcutRow)));
      final text = tester.widget<Text>(
        find.byKey(const Key('text-linux-target-status')),
      );
      expect(text.data, LinuxPasteShortcutRow.statusText(l10n, status));
    });
  }

  test('the three status texts differ in every app language', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(locale);
      final texts = {
        for (final s in LinuxFocusStatus.values)
          LinuxPasteShortcutRow.statusText(l10n, s),
      };
      expect(texts, hasLength(3), reason: locale.toLanguageTag());
    }
  });

  test('defaults to off and round-trips through storage', () {
    expect(const BehaviorSettings().linuxAlwaysShiftPaste, isFalse);
    final restored = BehaviorSettings.fromMap(
      const BehaviorSettings(linuxAlwaysShiftPaste: true).toMap(),
    );
    expect(restored.linuxAlwaysShiftPaste, isTrue);
  });
}
