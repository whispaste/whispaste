// The custom preset dialog's hand-off (#1685): the instruction limit is
// applied on save, an over-long preset from before the limit is never cut,
// and the example instructions land in the field.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/smart_mode/smart_mode_page.dart';
import 'package:whispaste/widgets/wp_banner.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  const max = kSmartModeCustomInstructionMaxChars;
  final longPreset = SmartModeCustomPreset(
    id: 'old',
    name: 'Old',
    instruction: 'a' * (max + 100),
  );

  /// Opens the dialog for [existing]; the returned getter reads the result
  /// once the dialog closed (`pending` while open).
  Future<Object? Function()> open(
    WidgetTester tester, {
    SmartModeCustomPreset? existing,
  }) async {
    Object? result = 'pending';
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showSmartModeCustomPresetDialog(
                  context: context,
                  existing: existing,
                ),
            child: const Text('Open dialog'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    return () => result;
  }

  Finder field(String id) => find.descendant(
    of: find.byKey(ValueKey('smart-mode-custom-dialog-$id')),
    matching: find.byType(EditableText),
  );

  String instructionText(WidgetTester tester) =>
      tester.widget<EditableText>(field('instruction')).controller.text;

  WpButton button(WidgetTester tester, String testId) => tester.widget(
    find.byWidgetPredicate((w) => w is WpButton && w.testId == testId),
  );

  bool saveEnabled(WidgetTester tester) =>
      button(tester, 'smart-mode-custom-dialog-save').onPressed != null;

  final tooLong = find.byType(WpBanner);

  testWidgets('a new instruction stops at the limit', (tester) async {
    await open(tester);
    await tester.enterText(field('name'), 'Mail');
    await tester.enterText(field('instruction'), 'b' * (max + 50));
    await tester.pump();

    expect(instructionText(tester).length, max);
    expect(saveEnabled(tester), isTrue);
    expect(tooLong, findsNothing);
  });

  testWidgets('an over-long saved preset opens in full and is never cut', (
    tester,
  ) async {
    final result = await open(tester, existing: longPreset);

    expect(instructionText(tester), longPreset.instruction);
    expect(tooLong, findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    // One more keystroke: with the limiter on, Flutter would cut the text to
    // the limit here.
    await tester.enterText(field('instruction'), '${longPreset.instruction}b');
    await tester.pump();
    expect(instructionText(tester).length, max + 101);
    expect(saveEnabled(tester), isFalse);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is WpButton && w.testId == 'smart-mode-custom-dialog-cancel',
      ),
    );
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });

  testWidgets('shortened to the limit, the preset saves under its id', (
    tester,
  ) async {
    final result = await open(tester, existing: longPreset);

    final shortened = 'c' * max;
    await tester.enterText(field('instruction'), shortened);
    await tester.pump();
    expect(tooLong, findsNothing);
    expect(saveEnabled(tester), isTrue);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is WpButton && w.testId == 'smart-mode-custom-dialog-save',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      result(),
      SmartModeCustomPreset(id: 'old', name: 'Old', instruction: shortened),
    );
  });

  testWidgets('an example fills the empty field and the examples leave', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(l10n.smartModeCustomPresetExampleMailLabel), findsOne);

    await tester.tap(find.text(l10n.smartModeCustomPresetExampleBulletsLabel));
    await tester.pump();

    expect(instructionText(tester), l10n.smartModeCustomPresetExampleBullets);
    expect(find.text(l10n.smartModeCustomPresetExampleMailLabel), findsNothing);
  });
}
