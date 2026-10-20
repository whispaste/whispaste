/// Tests for the paste-failure toast wired in `recording_behavior.dart`.
///
/// Mirrors the extracted-helper pattern from `recovery_toast_test.dart` /
/// `cpu_fallback_toast_test.dart`: [showPasteFailureToast] is exercised
/// through a minimal harness widget, so no app-shell/overlay bootstrapping
/// is required to prove which message (and action button, if any) a given
/// [PasteOutcome] renders.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _PasteFailureHarness extends StatelessWidget {
  const _PasteFailureHarness(
    this.outcome, {
    this.openAccessibilitySettings,
    this.openAutoPasteSettings,
    this.resetEntryAndGrant,
    this.staleEntry = false,
    this.linuxNoDevice = false,
  });

  final PasteOutcome outcome;
  final VoidCallback? openAccessibilitySettings;
  final VoidCallback? openAutoPasteSettings;
  final VoidCallback? resetEntryAndGrant;
  final bool staleEntry;
  final bool linuxNoDevice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showPasteFailureToast(
          context: context,
          l10n: L10n.of(context),
          outcome: outcome,
          openAccessibilitySettings: openAccessibilitySettings,
          openAutoPasteSettings: openAutoPasteSettings,
          resetEntryAndGrant: resetEntryAndGrant,
          staleEntry: staleEntry,
          linuxNoDevice: linuxNoDevice,
        ),
        child: const Text('fire-paste-failure-toast'),
      ),
    );
  }
}

/// Outlasts every toast here: one with an action stays at least 10 s
/// (`_actionableMinimum` in toast.dart), so no dismiss timer stays pending.
const Duration _toastLifetime = Duration(seconds: 11);

void main() {
  late L10n lDe;
  late L10n lEn;
  setUpAll(() async {
    lDe = await L10n.delegate.load(const Locale('de'));
    lEn = await L10n.delegate.load(const Locale('en'));
  });

  group('showPasteFailureToast — elevationBlocked (Windows UIPI)', () {
    testWidgets('renders a distinct message, no action button (de)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.elevationBlocked),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lDe.pasteFailureElevationBlocked), findsOneWidget);
      // Distinct from the generic bucket — must not fall back to it.
      expect(
        find.text(lDe.pasteFailureGeneric(pasteShortcutLabel(l10n: lDe))),
        findsNothing,
      );
      // No action button: there is no clean way to relaunch WhisPaste
      // elevated from inside the running process, so an honest
      // informational message without a button is correct here.
      expect(find.byType(WpButton), findsNothing);

      await tester.pumpAndSettle(_toastLifetime);
    });

    testWidgets('en locale: English copy matches the ARB entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.elevationBlocked),
          locale: const Locale('en'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lEn.pasteFailureElevationBlocked), findsOneWidget);

      await tester.pumpAndSettle(_toastLifetime);
    });
  });

  // ---------------------------------------------------------------------
  // permissionMissing — the toast must offer the SAME recovery the
  // failed-paste OS notification picks for the same failure. On the
  // live-probe macOS build that recovery clears the stale TCC entry first,
  // because a plain Settings deep-link can land the user on a toggle that is
  // already switched on, which reads as "nothing to do here".
  // ---------------------------------------------------------------------
  group('showPasteFailureToast — permissionMissing recovery', () {
    testWidgets(
      'without the reset seam it keeps the plain Settings action',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAccessibilitySettings: () {},
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        // The Settings path is labelled as a permission check and names the
        // clipboard fallback, so the user knows the text is not lost.
        expect(find.text(lDe.pasteFailureCheckPermission), findsOneWidget);
        expect(find.text(lDe.pasteFailureOpenSettings), findsNothing);
        expect(
          find.text(
            lDe.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: lDe)),
          ),
          findsOneWidget,
        );
        expect(find.text(lDe.pasteCapabilityRepairButton), findsNothing);

        await tester.pumpAndSettle(_toastLifetime);
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'with the reset seam the action becomes the entry reset and firing it '
      'runs that recovery, not the Settings deep-link',
      (tester) async {
        var resetCalls = 0;
        var settingsCalls = 0;
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAccessibilitySettings: () => settingsCalls++,
              resetEntryAndGrant: () => resetCalls++,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.pasteFailureOpenSettings), findsNothing);
        // No in-process proof of a stale entry, so the copy stays generic —
        // a first-time user has no old entry to be told about.
        expect(
          find.text(
            lDe.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: lDe)),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text(lDe.pasteCapabilityRepairButton));
        await tester.pumpAndSettle();
        expect(resetCalls, 1);
        expect(
          settingsCalls,
          0,
          reason:
              'The reset seam must replace the Settings deep-link here, not '
              'run alongside it.',
        );

        await tester.pumpAndSettle(_toastLifetime);
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'staleEntry swaps the copy to the reset hint — this process saw the '
      'grant happen and not take',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              resetEntryAndGrant: () {},
              staleEntry: true,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        // Both statements in the one message: the cause and where the text is.
        expect(
          find.textContaining(lDe.pasteCapabilityRepairHint),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            lDe.pasteFailureClipboardCopy(pasteShortcutLabel(l10n: lDe)),
          ),
          findsOneWidget,
        );

        await tester.pumpAndSettle(_toastLifetime);
      },
      skip: !Platform.isMacOS,
    );
  });

  // ---------------------------------------------------------------------
  group('showPasteFailureToast — permissionMissing on Linux (XP-5-06)', () {
    testWidgets(
      'the action opens the Auto-Paste settings and never overwrites the '
      'clipboard that still holds the transcript',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        final clipboardWrites = <Object?>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        var settingsCalls = 0;
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAutoPasteSettings: () => settingsCalls++,
            ),
            locale: const Locale('en'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        // The sudo command is not what the toast offers: it sits in the
        // Auto-Paste settings, next to its own copy button.
        // The action opens the settings, which hold the command, so the toast
        // names the settings instead of promising a copy button it lacks
        // (PAR-028 follow-up).
        expect(
          find.textContaining(lEn.pasteFailureLinuxUinputSettingsHint),
          findsOneWidget,
        );
        expect(
          find.textContaining(lEn.pasteFailureLinuxUinputHint),
          findsNothing,
        );
        expect(find.text(lEn.pasteFailureLinuxUinputCopy), findsNothing);
        expect(find.text(lEn.pasteFailureOpenSettings), findsOneWidget);

        await tester.tap(find.text(lEn.pasteFailureOpenSettings));
        await tester.pumpAndSettle();

        expect(settingsCalls, 1);
        expect(
          clipboardWrites,
          isEmpty,
          reason:
              'A failed paste leaves the transcript on the clipboard; the '
              'action must not replace it with the setup command.',
        );

        await tester.pumpAndSettle(_toastLifetime);
      },
    );

    testWidgets(
      'without any /dev/uinput node the toast does not ask for the uinput '
      'command, because the udev rule cannot help (PAR-028)',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAutoPasteSettings: () {},
              linuxNoDevice: true,
            ),
            locale: const Locale('en'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(lEn.pasteFailureLinuxNoDeviceHint),
          findsOneWidget,
        );
        expect(
          find.textContaining(lEn.pasteFailureLinuxUinputHint),
          findsNothing,
        );
        expect(find.text(lEn.pasteFailureOpenSettings), findsOneWidget);

        await tester.pumpAndSettle(_toastLifetime);
      },
    );
  });

  group('showPasteFailureToast — targetChanged (criterion 1)', () {
    testWidgets('says the target changed and the text is still copied (de)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.targetChanged),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      // Look while the toast is up; one 6 s step would already dismiss it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(lDe.pasteFailureTargetChanged), findsOneWidget);
      expect(
        find.text(lDe.pasteFailureGeneric(pasteShortcutLabel(l10n: lDe))),
        findsNothing,
      );

      await tester.pumpAndSettle(_toastLifetime);
    });
  });

  group('showPasteFailureToast — unconfirmedNoBridge (Linux)', () {
    testWidgets('shows no warning: no receipt bridge on this platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.unconfirmedNoBridge),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      // Look while the toast is up; one 6 s step would already dismiss it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text(lDe.pasteFailureUnconfirmed(pasteShortcutLabel(l10n: lDe))),
        findsNothing,
      );
      expect(
        find.text(lDe.pasteFailureGeneric(pasteShortcutLabel(l10n: lDe))),
        findsNothing,
      );
    });
  });

  group('showPasteFailureToast — unconfirmed (briefing N12)', () {
    testWidgets(
      'never claims the text was pasted; says it is in the clipboard (de)',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const _PasteFailureHarness(PasteOutcome.unconfirmed),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        // Look while the toast is up; one 6 s step would already dismiss it.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.text(lDe.pasteFailureUnconfirmed(pasteShortcutLabel(l10n: lDe))),
          findsOneWidget,
        );
        expect(
          lDe
              .pasteFailureUnconfirmed(pasteShortcutLabel(l10n: lDe))
              .toLowerCase(),
          isNot(contains('eingefügt')),
        );

        await tester.pumpAndSettle(_toastLifetime);
      },
    );
  });

  // XP-6-05: beside the "Open Settings" button the two-sentence Linux message
  // ran past the toast's line budget and lost its instruction ("braucht
  // einm…"). The message must arrive whole in every app language.
  group('showPasteFailureToast — Linux message is never cut off (XP-6-05)', () {
    // Real font metrics: the test font's square glyphs wrap far earlier than
    // the shipped UI font, which would hide or invent a truncation.
    setUpAll(() async {
      await loadAppFonts();
    });

    for (final locale in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
      testWidgets(
        'the whole message is shown ($locale)',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
          await tester.pumpWidget(
            makeTestable(
              _PasteFailureHarness(
                PasteOutcome.permissionMissing,
                openAutoPasteSettings: () {},
              ),
              locale: Locale(locale),
            ),
          );

          await tester.tap(find.text('fire-paste-failure-toast'));
          await tester.pumpAndSettle();

          final paragraph = tester.renderObject<RenderParagraph>(
            find.byKey(const ValueKey<String>('toast-message')),
          );
          expect(paragraph.didExceedMaxLines, isFalse);

          await tester.pumpAndSettle(_toastLifetime);
        },
      );
    }
  });
}
