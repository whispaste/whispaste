/// Widget tests for the extracted [showRecordingErrorToast] helper from
/// `recording_behavior.dart`.
///
/// Covers the bug fix where `mic_permission_denied` left the user stuck on
/// a plain dismiss-only toast: once macOS TCC has denied microphone access
/// once, `AVCaptureDevice.requestAccess` (called by `record`'s
/// `hasPermission()`) never shows the system dialog again, so the app must
/// route the user to System Settings itself instead. [openMicrophoneSettings]
/// is the injected test seam — mirrors [showRecoveryToast]'s `openSettings`
/// and [showPasteFailureToast]'s `openAccessibilitySettings`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _RecordingErrorHarness extends StatelessWidget {
  const _RecordingErrorHarness({
    required this.errorCode,
    required this.onDismiss,
    this.openMicrophoneSettings,
  });

  final String errorCode;
  final VoidCallback onDismiss;
  final VoidCallback? openMicrophoneSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showRecordingErrorToast(
          context: context,
          l10n: L10n.of(context),
          errorCode: errorCode,
          onDismiss: onDismiss,
          openMicrophoneSettings: openMicrophoneSettings,
        ),
        child: const Text('fire-recording-error-toast'),
      ),
    );
  }
}

void main() {
  late L10n lDe;
  late L10n lEn;
  setUpAll(() async {
    lDe = await L10n.delegate.load(const Locale('de'));
    lEn = await L10n.delegate.load(const Locale('en'));
  });

  group('showRecordingErrorToast — mic_permission_denied', () {
    testWidgets('macOS: renders "Open Settings" action that calls '
        'openMicrophoneSettings instead of dismissing; other platforms keep '
        'the plain dismiss action', (tester) async {
      var dismissTaps = 0;
      var settingsTaps = 0;

      await tester.pumpWidget(
        makeTestable(
          _RecordingErrorHarness(
            errorCode: 'mic_permission_denied',
            onDismiss: () => dismissTaps++,
            openMicrophoneSettings: () => settingsTaps++,
          ),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-recording-error-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lDe.errorMicPermissionDenied), findsOneWidget);

      if (Platform.isMacOS) {
        expect(find.text(lDe.pasteFailureOpenSettings), findsOneWidget);
        expect(find.text(lDe.actionDismiss), findsNothing);

        await tester.tap(find.text(lDe.pasteFailureOpenSettings));
        await tester.pumpAndSettle();

        expect(
          settingsTaps,
          1,
          reason:
              'Tapping the action must open the Microphone privacy pane, '
              'not just dismiss the toast — the OS will never show the '
              'permission dialog again on its own once denied.',
        );
        expect(dismissTaps, 0);
      } else {
        expect(find.text(lDe.actionDismiss), findsOneWidget);
        expect(find.text(lDe.pasteFailureOpenSettings), findsNothing);

        await tester.tap(find.text(lDe.actionDismiss));
        await tester.pumpAndSettle();

        expect(dismissTaps, 1);
        expect(settingsTaps, 0);
      }

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('en locale: English copy matches the ARB entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          _RecordingErrorHarness(
            errorCode: 'mic_permission_denied',
            onDismiss: () {},
          ),
          locale: const Locale('en'),
        ),
      );

      await tester.tap(find.text('fire-recording-error-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lEn.errorMicPermissionDenied), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  });

  group('showRecordingErrorToast — other error codes unaffected', () {
    testWidgets(
      'transcription_empty keeps the plain dismiss action on every platform',
      (tester) async {
        var dismissTaps = 0;

        await tester.pumpWidget(
          makeTestable(
            _RecordingErrorHarness(
              errorCode: 'transcription_empty',
              onDismiss: () => dismissTaps++,
              openMicrophoneSettings: () =>
                  fail('must not be called for a non-mic error'),
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-recording-error-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.errorTranscriptionEmpty), findsOneWidget);
        expect(find.text(lDe.actionDismiss), findsOneWidget);
        expect(find.text(lDe.pasteFailureOpenSettings), findsNothing);

        await tester.tap(find.text(lDe.actionDismiss));
        await tester.pumpAndSettle();

        expect(dismissTaps, 1);

        await tester.pumpAndSettle(const Duration(seconds: 6));
      },
    );
  });
}
