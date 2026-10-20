/// Journey: a dictation that could not be saved to history shows the
/// pending-audio toast, addressable by its test ID (DEV-147).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/pending_audio/pending_audio_notice.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the save-later notice shows the toast with its test ID and the '
      'localized text', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      makeTestable(
        const WpRecordingBehavior(child: SizedBox.shrink()),
        locale: const Locale('en'),
        db: db,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox).first),
    );

    container
        .read(pendingAudioNoticeProvider.notifier)
        .report(PendingAudioNotice.saveLater);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('pending-audio-toast')), findsOneWidget);
    final message = tester.widget<Text>(
      find.byKey(const ValueKey('toast-message')),
    );
    expect(message.data, l10n.pendingAudioSaveLater);

    // Let the auto-dismiss timer and its reverse animation finish first.
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('pending-audio-toast')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
