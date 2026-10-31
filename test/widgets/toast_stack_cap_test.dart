/// UIA-SHL-10: toasts do not pile up. At most two are on screen at normal
/// text size and one from text scale 1.3 on, the size where UX-050 stacks
/// the buttons under the message. Errors outlast other toasts, and a
/// non-error toast is dropped rather than pushing out an error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/toast.dart';

import '../fixtures/test_helpers.dart';

class _Harness extends StatelessWidget {
  const _Harness({required this.onReady, this.textScale = 1.0});

  final void Function(BuildContext) onReady;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Builder(
        builder: (c) {
          onReady(c);
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

void _show(BuildContext c, String message, WpToastType type) {
  WpToast.show(
    c,
    message: message,
    type: type,
    duration: const Duration(seconds: 2),
  );
}

void main() {
  late BuildContext ctx;

  Future<void> pumpAt(WidgetTester tester, {double textScale = 1.0}) {
    return tester.pumpWidget(
      makeTestable(
        _Harness(onReady: (c) => ctx = c, textScale: textScale),
        locale: const Locale('en'),
      ),
    );
  }

  Future<void> drain(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(seconds: 6));

  testWidgets('at most two toasts are on screen at normal text size', (
    tester,
  ) async {
    await pumpAt(tester);
    _show(ctx, 'first-toast', WpToastType.info);
    _show(ctx, 'second-toast', WpToastType.info);
    _show(ctx, 'third-toast', WpToastType.info);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('first-toast'), findsNothing);
    expect(find.text('second-toast'), findsOneWidget);
    expect(find.text('third-toast'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('one toast at large text size, the newest one', (tester) async {
    await pumpAt(tester, textScale: 1.3);
    _show(ctx, 'first-toast', WpToastType.info);
    _show(ctx, 'second-toast', WpToastType.info);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('first-toast'), findsNothing);
    expect(find.text('second-toast'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a new toast evicts a non-error before an error', (tester) async {
    await pumpAt(tester);
    _show(ctx, 'error-toast', WpToastType.error);
    _show(ctx, 'info-toast', WpToastType.info);
    _show(ctx, 'newest-toast', WpToastType.info);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('error-toast'), findsOneWidget);
    expect(find.text('info-toast'), findsNothing);
    expect(find.text('newest-toast'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a non-error toast does not push out two errors', (tester) async {
    await pumpAt(tester);
    _show(ctx, 'error-one', WpToastType.error);
    _show(ctx, 'error-two', WpToastType.error);
    _show(ctx, 'done-toast', WpToastType.success);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('error-one'), findsOneWidget);
    expect(find.text('error-two'), findsOneWidget);
    expect(find.text('done-toast'), findsNothing);
    await drain(tester);
  });

  // A toast evicted in the frame it was raised has no mounted entry yet; it
  // must still leave the overlay instead of hanging below the window edge.
  testWidgets('a toast evicted before its first frame leaves the overlay', (
    tester,
  ) async {
    await pumpAt(tester);
    _show(ctx, 'evicted-toast', WpToastType.info);
    _show(ctx, 'second-toast', WpToastType.warning);
    _show(ctx, 'third-toast', WpToastType.info);
    await tester.pumpAndSettle();

    expect(find.text('evicted-toast'), findsNothing);
    expect(find.text('second-toast'), findsOneWidget);
    expect(find.text('third-toast'), findsOneWidget);
    await drain(tester);
  });
}
