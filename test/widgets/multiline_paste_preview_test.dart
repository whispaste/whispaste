/// Widget tests for the multiline paste preview (WP-38 / 8.5).
///
/// The harness triggers a request through the real provider, so these tests
/// cover the same path an API call takes: confirm and cancel resolve the
/// request, Escape and the timeout resolve it as cancelled.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/multiline_paste_confirmation.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/multiline_paste_preview.dart';

import '../fixtures/test_helpers.dart';

const _multiline = 'first line\nsecond line\nthird line';

/// Window state the preview consults; each test sets it before pumping.
bool _windowHidden = false;
int _activations = 0;

Widget _app(Widget child) => makeTestable(
  child,
  overrides: [
    mainWindowHiddenProvider.overrideWithValue(() async => _windowHidden),
    windowActivatorProvider.overrideWithValue(() async {
      _activations++;
    }),
  ],
);

class _Harness extends ConsumerWidget {
  const _Harness({required this.results, this.timeout});

  final List<bool> results;
  final Duration? timeout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const WpMultilinePastePreviewHost(),
        ElevatedButton(
          key: const ValueKey('trigger-preview'),
          onPressed: () {
            final notifier = ref.read(
              multilinePasteConfirmationProvider.notifier,
            );
            notifier
                .request(
                  _multiline,
                  timeout: timeout ?? kMultilinePasteConfirmTimeout,
                )
                .then(results.add);
          },
          child: const Text('Trigger'),
        ),
      ],
    );
  }
}

void main() {
  setUp(() {
    _windowHidden = false;
    _activations = 0;
  });

  testWidgets('a hidden main window is shown and focused before the preview', (
    tester,
  ) async {
    _windowHidden = true;
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();

    expect(_activations, 1);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsOne);
  });

  testWidgets('a visible main window is left where it is', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();

    expect(_activations, 0);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsOne);
  });

  testWidgets('shows the text, line count and both actions', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsOne);
    expect(find.text('Insert multiline text?'), findsOne);
    expect(find.text('3 lines'), findsOne);
    expect(find.text(_multiline), findsOne);
    expect(
      find.byKey(const ValueKey('multiline-paste-preview-confirm')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('multiline-paste-preview-cancel')),
      findsOne,
    );
    expect(results, isEmpty);
  });

  testWidgets('confirm resolves true and closes the dialog', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('multiline-paste-preview-confirm')),
    );
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsNothing);
  });

  testWidgets('cancel resolves false and closes the dialog', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('multiline-paste-preview-cancel')),
    );
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsNothing);
  });

  testWidgets('Escape resolves false', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_app(_Harness(results: results)));

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsNothing);
  });

  testWidgets('the timeout closes the dialog and resolves false', (
    tester,
  ) async {
    final results = <bool>[];
    await tester.pumpWidget(
      _app(_Harness(results: results, timeout: const Duration(seconds: 2))),
    );

    await tester.tap(find.byKey(const ValueKey('trigger-preview')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.byKey(const ValueKey('multiline-paste-preview')), findsNothing);
  });
}
