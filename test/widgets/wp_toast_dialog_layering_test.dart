/// A toast must never cover the actions of an open dialog: toasts sit below
/// modal popup routes, like a snack bar below a dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/dialog.dart';
import 'package:whispaste/widgets/toast.dart';

import '../fixtures/test_helpers.dart';

const _confirm = ValueKey('confirm-dialog-confirm');

/// True when a tap at the centre of [finder] reaches its render object.
bool _reachable(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final path = tester.hitTestOnBinding(tester.getCenter(finder)).path;
  return path.any((entry) => entry.target == target);
}

void main() {
  late BuildContext pageContext;
  late Future<bool> dialogResult;

  Future<void> pumpPage(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          },
        ),
        size: size,
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    dialogResult = showWpConfirmDialog(
      context: pageContext,
      title: 'Import settings?',
      message:
          'This replaces your current settings with the ones in the '
          'file. Settings that are not in the file stay as they are.',
      confirmLabel: 'Import',
      cancelLabel: 'Cancel',
    );
    await tester.pumpAndSettle();
  }

  Future<void> showToast(WidgetTester tester) async {
    WpToast.show(
      pageContext,
      message: 'A long notice that takes up most of the width of a window',
      duration: const Duration(seconds: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  // Small enough that the bottom-right toast overlaps the dialog's buttons.
  const narrow = Size(560, 360);

  testWidgets('a toast shown while a dialog is open leaves its buttons '
      'reachable', (tester) async {
    await pumpPage(tester, narrow);
    await openDialog(tester);
    await showToast(tester);

    expect(find.byKey(_confirm), findsOneWidget);
    expect(_reachable(tester, find.byKey(_confirm)), isTrue);

    await tester.tap(find.byKey(_confirm));
    await tester.pumpAndSettle();
    expect(await dialogResult, isTrue);
    await drain(tester);
  });

  testWidgets('a toast shown before the dialog opens stays below it', (
    tester,
  ) async {
    await pumpPage(tester, narrow);
    await showToast(tester);
    await openDialog(tester);

    expect(_reachable(tester, find.byKey(_confirm)), isTrue);
    await tester.tap(find.byKey(_confirm));
    await tester.pumpAndSettle();
    expect(await dialogResult, isTrue);
    await drain(tester);
  });

  testWidgets('a toast raised from inside a dialog stays visible above it', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));
    late BuildContext dialogContext;
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (context) {
          dialogContext = context;
          return const Dialog(child: SizedBox(width: 200, height: 100));
        },
      ),
    );
    await tester.pumpAndSettle();
    WpToast.show(
      dialogContext,
      message: 'Copied',
      duration: const Duration(seconds: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(_reachable(tester, find.text('Copied')), isTrue);
    await drain(tester);
    Navigator.of(dialogContext).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('without a dialog the toast stays on top of the page', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 800));
    await showToast(tester);

    final text = find.text(
      'A long notice that takes up most of the width of a window',
    );
    expect(_reachable(tester, text), isTrue);
    await drain(tester);
  });
}
