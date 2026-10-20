/// UIA-SHL-15: quitting from the tray during a recording asks first. Cancel
/// keeps the app running; the destructive confirm is the only way out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/widgets/quit_during_dictation_dialog.dart';

import '../fixtures/test_helpers.dart';

class _QuitHarness extends StatefulWidget {
  const _QuitHarness({required this.onResult});

  final void Function(bool) onResult;

  @override
  State<_QuitHarness> createState() => _QuitHarnessState();
}

class _QuitHarnessState extends State<_QuitHarness> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () async {
          final quit = await showWpQuitDuringDictationDialog(
            context: context,
            l10n: L10n.of(context),
          );
          widget.onResult(quit);
        },
        child: const Text('open-quit-dialog'),
      ),
    );
  }
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('de'));
  });

  testWidgets('cancel keeps the app running', (tester) async {
    bool? result;
    await tester.pumpWidget(
      makeTestable(
        _QuitHarness(onResult: (v) => result = v),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('open-quit-dialog'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.quitDuringDictationTitle), findsOneWidget);
    expect(find.text(l10n.quitDuringDictationMessage), findsOneWidget);

    await tester.tap(find.text(l10n.actionCancel));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('the confirm button quits', (tester) async {
    bool? result;
    await tester.pumpWidget(
      makeTestable(
        _QuitHarness(onResult: (v) => result = v),
        locale: const Locale('de'),
      ),
    );

    await tester.tap(find.text('open-quit-dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.trayQuit));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  test('a quit request bumps the request counter once per call', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(quitConfirmRequestProvider), 0);
    container.read(quitConfirmRequestProvider.notifier).request();
    container.read(quitConfirmRequestProvider.notifier).request();
    expect(container.read(quitConfirmRequestProvider), 2);
  });
}
