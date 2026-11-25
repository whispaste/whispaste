// The progress screen of a start after an encryption switch (#1022).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/encryption_preference.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/startup/encryption_conversion_screen.dart';
import 'package:whispaste/widgets/wp_progress_bar.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });
  tearDown(() => encryptionConversionProgress.value = null);

  testWidgets('shows the step while a conversion runs, else the idle view', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const EncryptionConversionListener(idle: Text('idle'))),
    );
    expect(find.text('idle'), findsOneWidget);

    encryptionConversionProgress.value = const EncryptionConversionProgress(
      toPlain: true,
      step: EncryptionConversionStep.history,
    );
    await tester.pump();
    expect(find.text(l10n.encryptionConversionTitleOff), findsOneWidget);
    expect(find.text(l10n.encryptionConversionHistory), findsOneWidget);
    expect(
      tester
          .widget<WpProgressBar>(
            find.byKey(const ValueKey('encryption-conversion-progress')),
          )
          .value,
      isNull,
    );

    encryptionConversionProgress.value = const EncryptionConversionProgress(
      toPlain: false,
      step: EncryptionConversionStep.recordings,
      done: 3,
      total: 4,
    );
    await tester.pump();
    expect(find.text(l10n.encryptionConversionTitleOn), findsOneWidget);
    expect(
      find.text(l10n.encryptionConversionRecordings(3, 4)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<WpProgressBar>(
            find.byKey(const ValueKey('encryption-conversion-progress')),
          )
          .value,
      0.75,
    );

    encryptionConversionProgress.value = null;
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);
  });
}
