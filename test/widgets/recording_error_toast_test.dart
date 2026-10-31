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
import 'package:whispaste/core/config/settings_enums.dart';
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

      expect(find.text(lDe.errorNoticeMicCause), findsOneWidget);

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

      await tester.pumpAndSettle(const Duration(seconds: 11));
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

      expect(find.text(lEn.errorNoticeMicCause), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 11));
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

        await tester.pumpAndSettle(const Duration(seconds: 11));
      },
    );
  });

  group(
    'showRecordingErrorToast — recovery actions (UIA-FLW-02, UIA-FLW-03)',
    () {
      testWidgets('quick_note_append_failed offers "Text kopieren" instead of '
          'a success message, and the action copies the transcript', (
        tester,
      ) async {
        var copyCalls = 0;
        var dismissTaps = 0;

        await tester.pumpWidget(
          makeTestable(
            _ErrorActionHarness(
              errorCode: 'quick_note_append_failed',
              onDismiss: () => dismissTaps++,
              copyTranscript: () => copyCalls++,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-recording-error-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.errorQuickNoteAppendFailed), findsOneWidget);
        expect(find.text(lDe.historyCopyText), findsOneWidget);

        await tester.tap(find.text(lDe.historyCopyText));
        await tester.pumpAndSettle();

        expect(copyCalls, 1);
        expect(dismissTaps, 0);

        await tester.pumpAndSettle(const Duration(seconds: 11));
      });

      testWidgets(
        'a repeatable failure offers "Erneut versuchen" (UIA-FLW-01)',
        (tester) async {
          var retryCalls = 0;
          var dismissTaps = 0;

          await tester.pumpWidget(
            makeTestable(
              _ErrorActionHarness(
                errorCode: 'cloud_timeout',
                onDismiss: () => dismissTaps++,
                retry: () => retryCalls++,
              ),
              locale: const Locale('de'),
            ),
          );

          await tester.tap(find.text('fire-recording-error-toast'));
          await tester.pumpAndSettle();

          expect(find.text(lDe.actionRetry), findsOneWidget);
          await tester.tap(find.text(lDe.actionRetry));
          await tester.pumpAndSettle();

          expect(retryCalls, 1);
          expect(dismissTaps, 0);

          await tester.pumpAndSettle(const Duration(seconds: 11));
        },
      );

      for (final code in ['stt_model_not_found', 'cloud_auth_error']) {
        testWidgets('$code offers "Einstellungen öffnen", and the action opens '
            'settings instead of only dismissing', (tester) async {
          var settingsTaps = 0;
          var dismissTaps = 0;

          await tester.pumpWidget(
            makeTestable(
              _ErrorActionHarness(
                errorCode: code,
                onDismiss: () => dismissTaps++,
                openSettings: () => settingsTaps++,
              ),
              locale: const Locale('de'),
            ),
          );

          await tester.tap(find.text('fire-recording-error-toast'));
          await tester.pumpAndSettle();

          expect(find.text(lDe.pasteFailureOpenSettings), findsOneWidget);
          expect(find.text(lDe.actionDismiss), findsNothing);

          await tester.tap(find.text(lDe.pasteFailureOpenSettings));
          await tester.pumpAndSettle();

          expect(settingsTaps, 1);
          expect(dismissTaps, 0);

          await tester.pumpAndSettle(const Duration(seconds: 11));
        });
      }

      test(
        'settingsRowForRecordingError deep-links to the model row for a '
        'missing model and to the key row of the configured cloud provider',
        () {
          expect(
            settingsRowForRecordingError(
              'stt_model_not_found',
              SttProviderType.onDevice,
            ),
            'stt-model',
          );
          expect(
            settingsRowForRecordingError(
              'cloud_auth_error',
              SttProviderType.openAI,
            ),
            'speech-openai-key',
          );
          expect(
            settingsRowForRecordingError(
              'cloud_auth_error',
              SttProviderType.deepgram,
            ),
            'speech-deepgram-key',
          );
          for (final code in [
            'stt_model_corrupted',
            'stt_model_file_missing',
            'stt_model_load_failed',
            'parakeet_model_not_found',
          ]) {
            expect(
              settingsRowForRecordingError(code, SttProviderType.onDevice),
              'stt-model',
              reason: code,
            );
          }
          expect(
            settingsRowForRecordingError(
              'transcription_empty',
              SttProviderType.onDevice,
            ),
            isNull,
          );
        },
      );
    },
  );
}

/// Harness for the recovery actions: only the callbacks under test are wired.
class _ErrorActionHarness extends StatelessWidget {
  const _ErrorActionHarness({
    required this.errorCode,
    required this.onDismiss,
    this.openSettings,
    this.copyTranscript,
    this.retry,
  });

  final String errorCode;
  final VoidCallback onDismiss;
  final VoidCallback? openSettings;
  final VoidCallback? copyTranscript;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showRecordingErrorToast(
          context: context,
          l10n: L10n.of(context),
          errorCode: errorCode,
          onDismiss: onDismiss,
          openSettings: openSettings,
          copyTranscript: copyTranscript,
          retry: retry,
        ),
        child: const Text('fire-recording-error-toast'),
      ),
    );
  }
}
