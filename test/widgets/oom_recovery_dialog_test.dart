import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/oom_recovery_dialog.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // UX-019: exactly one primary action. The primary choice is computed here;
  // the dialog renders every other offered choice as secondary.
  group('oomRecoveryPrimaryChoice', () {
    test('smaller model is primary when it is offered', () {
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: false,
          hasModel: true,
          hasCloudConfigured: false,
        ),
        WpOomRecoveryChoice.trySmallerModel,
      );
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: false,
          hasModel: true,
          hasCloudConfigured: true,
        ),
        WpOomRecoveryChoice.trySmallerModel,
      );
    });

    test('cloud is primary when no smaller model is offered', () {
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: false,
          hasModel: false,
          hasCloudConfigured: true,
        ),
        WpOomRecoveryChoice.switchToCloud,
      );
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: true,
          hasModel: true,
          hasCloudConfigured: true,
        ),
        WpOomRecoveryChoice.switchToCloud,
      );
    });

    test('settings are primary only when nothing else is offered', () {
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: true,
          hasModel: true,
          hasCloudConfigured: false,
        ),
        WpOomRecoveryChoice.openSettings,
      );
      expect(
        oomRecoveryPrimaryChoice(
          isPermanentFail: false,
          hasModel: false,
          hasCloudConfigured: false,
        ),
        WpOomRecoveryChoice.openSettings,
      );
    });
  });

  group('cloud notice (BIZ-19)', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required bool hasCloudConfigured,
      String? cloudProviderName,
    }) async {
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showWpOomRecoveryDialog(
                context: context,
                l10n: L10n.of(context),
                modelName: 'small',
                hasCloudConfigured: hasCloudConfigured,
                isPermanentFail: false,
                cloudProviderName: cloudProviderName,
              ),
              child: const Text('open'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the configured provider next to the cloud action', (
      tester,
    ) async {
      await openDialog(
        tester,
        hasCloudConfigured: true,
        cloudProviderName: 'Deepgram',
      );
      final en = await L10n.delegate.load(const Locale('en'));

      expect(find.text(en.oomRecoverySwitchCloud), findsOneWidget);
      expect(
        find.byKey(kOomRecoveryCloudNoticeKey),
        findsOneWidget,
        reason: 'the cloud action sends the audio away and must say so',
      );
      expect(find.text(en.oomRecoveryCloudNotice('Deepgram')), findsOneWidget);
    });

    testWidgets('no notice when no cloud action is offered', (tester) async {
      await openDialog(tester, hasCloudConfigured: false);
      final en = await L10n.delegate.load(const Locale('en'));

      expect(find.text(en.oomRecoverySwitchCloud), findsNothing);
      expect(find.byKey(kOomRecoveryCloudNoticeKey), findsNothing);
    });

    test(
      'every supported language fills the provider into the notice',
      () async {
        for (final code in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
          final l10n = await L10n.delegate.load(Locale(code));
          final text = l10n.oomRecoveryCloudNotice('Deepgram');
          expect(text, contains('Deepgram'), reason: code);
          expect(text, isNot(contains('{provider}')), reason: code);
        }
      },
    );
  });
}
