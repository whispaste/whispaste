/// Widget tests for the History PIN dialogs (UX-026, UX-027): the primary
/// action waits for a valid 4–8 digit PIN, the input accepts digits only, Enter
/// submits only a valid entry, and "PIN vergessen?" is a neutral link with its
/// consequence written next to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/history_pin.dart';
import 'package:whispaste/features/history/widgets/history_pin_dialogs.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

// Cheap work factor keeps the test fast; verification reads it from the hash.
final _pin4711 = hashHistoryPin('4711', iterations: 10);

late L10n l10n;

/// Hosts a button that opens a PIN dialog; [open] receives the button's context.
Future<void> _host(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) open,
  String pin = '',
}) async {
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings(history: HistorySettings(historyPin: pin)),
          ),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The primary action's `onPressed`, which is null while it is disabled.
VoidCallback? _primary(WidgetTester tester) =>
    tester.widget<WpButton>(find.byKey(kHistoryPinSubmitKey)).onPressed;

String _fieldText(WidgetTester tester, Key key) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('set dialog (UX-026)', () {
    testWidgets('primary action stays disabled until 4 digits are entered', (
      tester,
    ) async {
      await _host(tester, open: (ctx) => showHistoryPinSetDialog(ctx));

      expect(_primary(tester), isNull, reason: 'empty input');

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '123');
      await tester.pump();
      expect(_primary(tester), isNull, reason: '3 digits');

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '1234');
      await tester.pump();
      expect(_primary(tester), isNotNull, reason: '4 digits');
    });

    testWidgets('letters and symbols are filtered out of the PIN field', (
      tester,
    ) async {
      await _host(tester, open: (ctx) => showHistoryPinSetDialog(ctx));

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '4a-7 b');
      await tester.pump();

      expect(_fieldText(tester, kHistoryPinFieldKey), '47');
    });

    testWidgets('Enter does nothing while the PIN is too short', (
      tester,
    ) async {
      await _host(tester, open: (ctx) => showHistoryPinSetDialog(ctx));

      await tester.enterText(find.byKey(kHistoryPinRepeatFieldKey), '12');
      await tester.showKeyboard(find.byKey(kHistoryPinRepeatFieldKey));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyPinInvalid), findsNothing);
      expect(find.text(l10n.historyPinSetSubtitle), findsOneWidget);
    });
  });

  group('unlock dialog (UX-026, UX-027)', () {
    testWidgets('primary action needs 4 to 8 digits', (tester) async {
      await _host(
        tester,
        pin: _pin4711,
        open: (ctx) => showHistoryPinUnlockDialog(ctx, offerForgot: true),
      );

      expect(_primary(tester), isNull, reason: 'empty input');

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '12');
      await tester.pump();
      expect(_primary(tester), isNull, reason: '2 digits');

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '12345678');
      await tester.pump();
      expect(_primary(tester), isNotNull, reason: '8 digits');
    });

    testWidgets('Enter with an invalid PIN is not checked as an attempt', (
      tester,
    ) async {
      await _host(
        tester,
        pin: _pin4711,
        open: (ctx) => showHistoryPinUnlockDialog(ctx, offerForgot: true),
      );

      await tester.enterText(find.byKey(kHistoryPinFieldKey), '12');
      await tester.showKeyboard(find.byKey(kHistoryPinFieldKey));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyPinWrong), findsNothing);
      expect(find.text(l10n.historyPinDialogSubtitle), findsOneWidget);
    });

    testWidgets(
      '"Forgot PIN?" is a neutral link with its consequence beside it',
      (tester) async {
        await _host(
          tester,
          pin: _pin4711,
          open: (ctx) => showHistoryPinUnlockDialog(ctx, offerForgot: true),
        );

        final forgot = tester.widget<WpButton>(
          find.byKey(kHistoryPinForgotKey),
        );
        expect(forgot.tone, WpButtonTone.neutral);
        expect(forgot.variant, WpButtonVariant.ghost);
        expect(
          find.text(
            'Resetting immediately deletes all transcriptions, saved audio files, notes with their versions, and note images. If a file cannot be deleted, WhisPaste shows a notice.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
