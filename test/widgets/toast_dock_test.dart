/// A visible actionable toast must not cover the controls of a bottom action
/// row or of a dialog footer: the row's button stays clickable (UX-044).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/dialog.dart';
import 'package:whispaste/widgets/toast.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_toast_dock.dart';

import '../fixtures/test_helpers.dart';

const _sizes = <Size>[Size(800, 716), Size(1100, 720), Size(1440, 900)];

const _toastMessage = 'Die Aufnahme konnte nicht eingefügt werden.';

void _showActionableToast(BuildContext context) {
  WpToast.show(
    context,
    message: _toastMessage,
    type: WpToastType.error,
    action: WpToastAction(
      label: 'Erneut versuchen',
      onPressed: () {},
      testId: 'dock-toast-action',
    ),
  );
}

/// Drains the actionable toast's 10 s timer so no timer outlives the test.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  for (final size in _sizes) {
    testWidgets('bottom action row stays clickable with a toast at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var confirmed = 0;

      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              Expanded(
                child: Center(
                  child: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => _showActionableToast(context),
                      child: const Text('show-toast'),
                    ),
                  ),
                ),
              ),
              WpToastDockReserve(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: WpButton(
                      key: const ValueKey('dock-row-confirm'),
                      label: 'Speichern',
                      variant: WpButtonVariant.primary,
                      onPressed: () => confirmed++,
                    ),
                  ),
                ),
              ),
            ],
          ),
          size: size,
        ),
      );

      await tester.tap(find.text('show-toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_toastMessage), findsOneWidget);

      final row = tester.getRect(
        find.byKey(const ValueKey('dock-row-confirm')),
      );
      final action = tester.getRect(
        find.byKey(const ValueKey('dock-toast-action')),
      );
      expect(action.overlaps(row), isFalse);

      await tester.tap(find.byKey(const ValueKey('dock-row-confirm')));
      await tester.pump();
      expect(confirmed, 1);

      await _drainToast(tester);
    });

    testWidgets('dialog footer stays clickable with a toast at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var confirmed = 0;

      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showWpDialog<void>(
                context: context,
                title: 'Dialog',
                content: Builder(
                  builder: (inner) => WpButton(
                    key: const ValueKey('dialog-raise-toast'),
                    label: 'Toast',
                    variant: WpButtonVariant.secondary,
                    onPressed: () => _showActionableToast(inner),
                  ),
                ),
                actions: [
                  WpButton(
                    key: const ValueKey('dialog-footer-confirm'),
                    label: 'OK',
                    variant: WpButtonVariant.primary,
                    onPressed: () => confirmed++,
                  ),
                ],
              ),
              child: const Text('open-dialog'),
            ),
          ),
          size: size,
        ),
      );

      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(const ValueKey('dialog-raise-toast')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_toastMessage), findsOneWidget);

      final footer = tester.getRect(
        find.byKey(const ValueKey('dialog-footer-confirm')),
      );
      final action = tester.getRect(
        find.byKey(const ValueKey('dock-toast-action')),
      );
      expect(action.overlaps(footer), isFalse);

      await tester.tap(find.byKey(const ValueKey('dialog-footer-confirm')));
      await tester.pump();
      expect(confirmed, 1);

      await _drainToast(tester);
    });
  }
}
