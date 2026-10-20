/// 9.8: the recording error paths show a [WpErrorNotice] with a cause and a
/// next step. Covers the four cases the requirement names: missing model,
/// denied microphone, failed transcription and GPU-to-CPU fallback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';
import 'package:whispaste/widgets/wp_error_notice.dart';

import '../fixtures/test_helpers.dart';

class _Trigger extends StatelessWidget {
  const _Trigger({required this.fire});

  final void Function(BuildContext context, L10n l10n) fire;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => fire(context, L10n.of(context)),
        child: const Text('fire'),
      ),
    );
  }
}

void main() {
  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('recordingErrorNotice mapping', () {
    test('covers the four 9.8 cases and nothing else', () {
      expect(
        recordingErrorNotice(l10n, 'stt_model_not_found')?.cause,
        l10n.errorNoticeNoModelCause,
      );
      expect(
        recordingErrorNotice(l10n, 'mic_permission_denied')?.nextStep,
        l10n.errorNoticeMicNext,
      );
      expect(
        recordingErrorNotice(l10n, 'stt_server_failed')?.cause,
        l10n.errorNoticeTranscribeCause,
      );
      expect(recordingErrorNotice(l10n, 'recording_failed'), isNull);
    });
  });

  Future<void> expectNotice(
    WidgetTester tester,
    void Function(BuildContext context, L10n l10n) fire, {
    required String cause,
    required String nextStep,
  }) async {
    await tester.pumpWidget(
      makeTestable(_Trigger(fire: fire), locale: const Locale('en')),
    );
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WpErrorNotice), findsOneWidget);
    expect(find.text(cause), findsOneWidget);
    expect(find.text(nextStep), findsOneWidget);
    // The toast has an action button, so it stays at least 10 s
    // (_actionableMinimum, WCAG 2.2.1); let that timer and its animation finish.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('missing speech model shows cause and next step', (tester) async {
    await expectNotice(
      tester,
      (ctx, l) => showRecordingErrorToast(
        context: ctx,
        l10n: l,
        errorCode: 'stt_model_not_found',
        onDismiss: () {},
      ),
      cause: l10n.errorNoticeNoModelCause,
      nextStep: l10n.errorNoticeNoModelNext,
    );
  });

  testWidgets('denied microphone shows cause and next step', (tester) async {
    await expectNotice(
      tester,
      (ctx, l) => showRecordingErrorToast(
        context: ctx,
        l10n: l,
        errorCode: 'mic_permission_denied',
        onDismiss: () {},
      ),
      cause: l10n.errorNoticeMicCause,
      nextStep: l10n.errorNoticeMicNext,
    );
  });

  testWidgets('failed transcription shows cause and next step', (tester) async {
    await expectNotice(
      tester,
      (ctx, l) => showRecordingErrorToast(
        context: ctx,
        l10n: l,
        errorCode: 'stt_server_failed',
        onDismiss: () {},
      ),
      cause: l10n.errorNoticeTranscribeCause,
      nextStep: l10n.errorNoticeTranscribeNext,
    );
  });

  testWidgets('GPU fallback to CPU shows cause and next step', (tester) async {
    await expectNotice(
      tester,
      (ctx, l) => showCpuFallbackToast(context: ctx, l10n: l),
      cause: l10n.errorNoticeCpuCause,
      nextStep: l10n.errorNoticeCpuNext,
    );
  });
}
