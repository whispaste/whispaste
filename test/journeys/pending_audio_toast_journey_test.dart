/// Journey: a dictation that could not be saved to history shows the
/// pending-audio toast, addressable by its test ID (DEV-147).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/pending_audio/pending_audio_notice.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

Future<ProviderContainer> _pumpNotice(
  WidgetTester tester,
  PendingAudioNotice notice,
) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    makeTestable(
      const WpRecordingBehavior(child: SizedBox.shrink()),
      locale: const Locale('en'),
      db: db,
      // App toasts stay away while onboarding is open; this journey covers
      // a finished setup.
      overrides: [onboardingSurfaceActiveProvider.overrideWithValue(false)],
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SizedBox).first),
  );

  container.read(pendingAudioNoticeProvider.notifier).report(notice);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

Future<void> _dismissNotice(WidgetTester tester) async {
  // Let the auto-dismiss timer and its reverse animation finish first.
  await tester.pump(const Duration(seconds: 15));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the save-later notice raises the notice with its ID and the '
      'localized text', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await _pumpNotice(tester, PendingAudioNotice.saveLater);

    final shown = container.read(dictationNoticeProvider)!;
    expect(shown.id, 'pending-audio-toast');
    expect(shown.message, l10n.pendingAudioSaveLater);

    await _dismissNotice(tester);
  });

  testWidgets('an interrupted recording that had to be deleted raises the '
      'discarded notice with its ID and the localized text', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await _pumpNotice(
      tester,
      PendingAudioNotice.interruptedDiscarded,
    );

    final shown = container.read(dictationNoticeProvider)!;
    expect(shown.id, 'pending-audio-discarded-toast');
    expect(shown.message, l10n.pendingAudioInterruptedDiscarded);

    await _dismissNotice(tester);
  });
}
